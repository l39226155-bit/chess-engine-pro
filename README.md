# CHESS ENGINE PRO

Native iOS-App (Swift · SwiftUI · WKWebView) mit eingebetteter **Stockfish**-Engine,
einem Premium-Analysebrett mit MultiPV-Pfeilen, fünf Spielstil-Profilen, einem
Trainingssystem, PGN-Import/-Export und einer integrierten **Chess.com**-Ansicht.

> App-Name: CHESS ENGINE PRO · Bundle-ID: `com.chessenginepro.app` · Minimum: iOS 17.0 · arm64

---

## 1. Funktionsumfang

| Bereich | Umsetzung |
|---|---|
| **Chess.com** | WKWebView mit persistenter Sitzung (`WKWebsiteDataStore.default()`), native Browser-Steuerung, eigene Login-Schaltfläche, Sitzung löschen. Anmeldung ausschließlich über die offizielle Chess.com-Seite. |
| **Stockfish** | Offizielle Stockfish-Quellen (17.1) werden im Build zu einer statischen iOS-Bibliothek kompiliert und **im App-Prozess** über das UCI-Protokoll angesteuert (eigener `std::cin`/`std::cout`-Transport, siehe `StockfishBridge.mm`). |
| **Fallback** | Ist die Bibliothek nicht eingebunden, übernimmt eine vollständige Swift-Engine (Alpha-Beta + Quiescence + MultiPV), damit Analyse, Training und Partien immer funktionieren. |
| **Analysebrett** | Tap-to-move, legale Zugvorschläge, letzter Zug, Schach-Markierung, animierte Figuren, 5 Brettdesigns, 3 Figurenstile, Koordinaten, Brett drehen. |
| **Pfeile** | `ArrowRenderer` (Canvas) mit Grün = bester Zug, Blau = gute Alternative, Gelb = interessant, Rot = kritisch/fehlerhaft. Anzahl, Palette, Labels und einzelne Pfeile per Auge-Symbol schaltbar. |
| **MultiPV** | 1–5 Varianten mit Bewertung, Hauptvariante (SAN), Zugqualität, Stil-Fit, Tags (Gabel, Opfer, offene Linie …). |
| **Spielstile** | SOLID, AGGRESSIVE, POSITIONAL, TACTICAL, BALANCED – transparente Heuristik auf echten Zugmerkmalen, immer durch den objektiven Bewertungsverlust gedeckelt. |
| **Qualität** | Hervorragend / Sehr gut / Gut / Interessant / Ungenauigkeit / Fehler / Patzer – ausschließlich aus dem Engine-Verlust klassifiziert. |
| **Training** | 58 maschinell verifizierte Aufgaben (Matt in 1/2/3, Taktik, Endspiele, Verteidigung), 14 Eröffnungslinien, Partie gegen die Engine. |
| **PGN** | Import über den Datei-Browser, vollständige Partieprüfung mit Bewertungsgraph, Genauigkeit, Fehlerliste, annotierter Export. |
| **Speicherung** | SQLite (`analyses.sqlite3`) für Analysen, `UserDefaults` für Einstellungen/Statistik. Alles lokal. |

### Architektur

```
ChessEnginePro/
├── App/                 AppEnvironment, RootView (Custom-Tabbar), App-Einstieg
├── Core/
│   ├── Chess/           Types, Board (Regeln, FEN), Board+SAN
│   ├── Engine/          EngineTypes, StockfishEngine (UCI), FallbackEngine,
│   │                    Bridge/ (C-Header, ObjC++-Transport, Stub)
│   ├── Analysis/        AnalysisManager, NaturalMoveSelection, MoveQuality, GameReview
│   ├── PGN/             PGN-Parser/-Export, Datei-Import
│   └── Storage/         SettingsStore, AnalysisStore (SQLite)
├── Design/              Theme, Components, ChessBoardView + ArrowRenderer
├── Features/
│   ├── Home/ Play/ Analysis/ Training/ Review/ Profile/
└── Resources/           Assets.xcassets, TrainingPuzzles.json, Openings.json
```

Die im Auftrag genannten Bausteine heißen im Code: `ChessComBrowser`
(WebViewManager), `StockfishEngine` (StockfishManager), `AnalysisManager`,
`ChessBoardView`, `ArrowRenderer`, `PGN`, `SettingsStore`.

---

## 2. Build

### Voraussetzungen
* macOS mit Xcode 16 oder neuer
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
* Internetzugang für den Stockfish-Download (einmalig)

### Lokal

```bash
brew install xcodegen
ALLOW_STUB=0 ./scripts/build-stockfish.sh   # baut Build/Stockfish/<platform>/libstockfish.a
xcodegen generate                          # erzeugt ChessEnginePro.xcodeproj
open ChessEnginePro.xcodeproj
```

Das Xcode-Projekt wird aus `project.yml` generiert (die `.xcodeproj` ist bewusst
nicht eingecheckt). Der Pre-Build-Schritt ruft `scripts/build-stockfish.sh` auf,
sodass ein frischer Checkout direkt baubar ist; ohne Netz entsteht dabei eine
Stub-Bibliothek und die App nutzt automatisch die eingebaute Swift-Engine
(sichtbar in Einstellungen → Engine).

### Tests

```bash
xcodebuild test -project ChessEnginePro.xcodeproj -scheme ChessEnginePro \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Abgedeckt: Perft (Startstellung, Kiwipete, En-passant-/Umwandlungsstellung),
FEN-Rundreise, Rochade (inkl. Rochade durch bedrohtes Feld), En passant,
Umwandlung, Matt/Patt, SAN-Disambiguierung, PGN-Parsing/-Export, Qualitäts- und
Stil-Invarianten, gebündelte Trainingsdaten, Fallback-Engine, SQLite-Store.

### Trainingsdaten neu erzeugen

```bash
pip install python-chess
python scripts/generate_training_data.py
```

Das Skript erzeugt alle Aufgaben per Suche und **verifiziert jede Lösung**
(Zwangsläufe des Gegners, echtes Matt, eindeutiger Verteidigungszug,
eindeutiger Materialgewinn). Aktueller Stand: 58 Aufgaben, 14 Eröffnungen.

---

## 3. GitHub Actions → IPA → GitHub Release

Workflow: [`.github/workflows/ios.yml`](.github/workflows/ios.yml)

1. **Checkout** auf `macos-15`, Xcode via `setup-xcode`.
2. **Stockfish** wird für `iphoneos/arm64` und `iphonesimulator/arm64` kompiliert
   (mit Cache) – inkl. Nachweis, dass das Symbol `stockfish_main` vorhanden ist.
3. **XcodeGen** erzeugt das Projekt.
4. **Unit-Tests** laufen auf dem iOS-Simulator.
5. **Archiv** (`generic/platform=iOS`, ohne Signierung) und **IPA-Packaging**
   (`Payload/ChessEnginePro.app` → ZIP).
6. **Artefakt** `ChessEnginePro-ipa` steht 30 Tage zum Download bereit.
7. **Release-Job** (bei Tag `v*` oder manuellem Start) erstellt automatisch eine
   Versionsnummer, ein GitHub-Release und lädt die IPA als Asset hoch.

IPA herunterladen: *Actions → iOS Build & Release → letzter Lauf → Artifacts*
oder über die Release-Seite. Lokal entstehen die Dateien unter `artifacts/`
(`ChessEnginePro.xcarchive`, `ChessEnginePro.ipa`, Logs).

### Ohne Mac: Repo anlegen und Build starten

Der Workflow läuft auf einem macOS-Runner und braucht keinen Mac vor Ort:

```bash
git init -b main
git add .
git commit -m "CHESS ENGINE PRO 1.0.0"
git remote add origin https://github.com/<DEIN-NAME>/chess-engine-pro.git
git push -u origin main
```

* **Nur IPA bauen:** *Actions → iOS Build & Release → Run workflow*.
* **Release mit IPA:** Tag setzen und pushen:
  ```bash
  git tag v1.0.0
  git push origin v1.0.0
  ```
  Der Release-Job lädt die IPA als Asset an `.../releases/tag/v1.0.0` hoch.

Beim ersten Lauf dauert der Stockfish-Build einige Minuten (danach greift der
Cache). Schlägt der Build fehl, zeigen die Artefakte `build-logs` den vollständigen
Test- und Archiv-Log.

---

## 4. Installation mit Sideloadly

1. [Sideloadly](https://sideloadly.io) für Windows/macOS installieren, iPhone per
   Kabel verbinden und entsperren.
2. `ChessEnginePro.ipa` in Sideloadly ziehen.
3. Apple-ID im Feld **Apple account** eintragen (Sideloadly signiert lokal; das
   Passwort geht nur an Apple, nicht an dieses Projekt).
4. **Start** antippen. Nach der Installation auf dem iPhone:
   *Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwicklerprofil vertrauen.*
5. Mit einer kostenlosen Apple-ID ist die App **7 Tage** gültig und muss danach
   neu signiert werden; ein bezahlter Developer-Account verlängert das auf 1 Jahr.

**Signierung:** Die IPA ist absichtlich **unsigniert**. Es liegen keine
Zertifikate, Provisioning-Profile oder Passwörter im Repository. Sideloadly
(oder AltStore) signiert mit deiner Apple-ID. Alternativ kann der Workflow um
`ExportOptions.plist` + Zertifikats-Secrets für ein eigenes Team erweitert werden.

---

## 5. Rechtliches & Grenzen

* **Chess.com**: Es wird ausschließlich die öffentliche Website im WKWebView
  angezeigt. Es werden keine internen/privaten APIs aufgerufen, keine
  Schutzmechanismen umgangen und keine Zugangsdaten gelesen oder gespeichert.
  Die App steht in keiner offiziellen Verbindung zu Chess.com. Für die Nutzung
  gelten die Chess.com-Nutzungsbedingungen; ein App-Store-Review kann eine reine
  Website-Einbettung ablehnen – der hier dokumentierte Weg ist Sideloading.
* **PGN von Chess.com**: Statt privater Schnittstellen wird der offizielle
  PGN-Export verwendet (Datei importieren). Das ist die von Chess.com
  unterstützte Variante.
* **Stockfish**: GPLv3. Der Quellcode der Engine ist unter
  <https://github.com/official-stockfish/Stockfish> verfügbar; dieses Repository
  enthält den vollständigen App-Quellcode, womit die GPL-Anforderungen für eine
  Weitergabe erfüllt werden können.
* **Engine im Prozess**: Stockfish läuft im App-Prozess (kein `fork/exec` unter
  iOS möglich). Ein Engine-Fehler kann daher die App beenden; die Analyse ist auf
  Threads/Depth begrenzt und über „Akkuoptimierung“ bzw. Thread-Limit zähmbar.
* **Was hier nicht ausgeführt werden konnte**: Dieses Projekt wurde auf einem
  Windows-Rechner erstellt. Swift-/Xcode-Kompilierung, Simulator- und
  Gerätetests, der IPA-Build sowie die Chess.com-Anmeldung konnten hier nicht
  ausgeführt werden – genau dafür ist der CI-Workflow da. Die Schachregeln,
  Trainingsdaten und JSON-/Shell-Artefakte wurden lokal geprüft (Perft-Werte
  sind als Tests hinterlegt, alle Puzzle-Lösungen mit python-chess verifiziert).

---

## 6. Persistente WebView, Tabs und Live-Synchronisation

**Persistente Chess.com-WebView.** Die `WKWebView` gehört `AppEnvironment` und wird
genau einmal erzeugt. `RootView` hält die Chess.com-Ebene dauerhaft im View-Baum
und blendet sie nur aus (`opacity`, `allowsHitTesting`), statt sie zu zerstören.
Dadurch bleiben Seite, Cookies/Sitzung, Scrollposition, laufende Partie und
JavaScript-Zustand über jeden Tabwechsel erhalten; `WebViewContainer.updateUIView`
lädt nie nach. Geladen wird erst beim ersten Besuch des Tabs (`startIfNeeded()`).

**Tabs.** HOME · CHESS.COM · STOCKFISH · TRAINING · SETTINGS (`AppTab`).

**EngineManager.** Zentraler Besitzer der Engine: wählt Backend (Stockfish oder
eingebaute Engine), setzt Threads/Hash/MultiPV und ist der einzige Ort, der
`stop()` aufruft. Bei `scenePhase == .background` werden Berechnungen pausiert,
beim Zurückkehren setzt `AnalysisManager.resumeAfterBackground()` sie fort.

**LivePositionSync.** Jede Brettänderung (Zug, Undo, Reset, Editor, PGN-Import,
Sprung zu Ply) läuft durch `LivePositionSync.publish(...)`. Vor der Übergabe an
Stockfish wird die Stellung validiert: FEN-Rundreise, genau ein König je Seite,
keine Bauern auf der Grundlinie, Gegner nicht im Schach, En-passant-Feld
konsistent. Unveränderte Stellungen werden dedupliziert; erst danach startet die
Engine neu. Der Snapshot enthält FEN, Zugrecht, letzten Zug (SAN), Ply,
Zugfolge, Spielende und die Zugart (Rochade, En passant, Umwandlung, Doppelschritt,
Schlagen) – sichtbar im Stockfish-Tab inkl. Fortschrittsbalken (Tiefe/Zeit).

**Tests:** `ChessEngineProTests/LiveSyncTests.swift` deckt Veröffentlichung,
Deduplizierung, Zugarten, Matt-Erkennung und alle Ablehnungsgründe ab.

---

## 7. Version

`1.1.0` (Build 2) · Marketing-Version in `project.yml` (`MARKETING_VERSION`).
