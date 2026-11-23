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

## 7. Live-Erkennung der Chess.com-Stellung

Die App liest die Stellung einer geöffneten Chess.com-Partie selbst aus – ohne
manuelles Abfragen, ohne Reload der Seite und ohne private Schnittstelle.

**Datenquelle.** `ChessComPositionScript.source` wird als `WKUserScript`
(`.atDocumentEnd`, Main Frame) in die persistente WebView injiziert und liest
ausschließlich, was die Seite ohnehin anzeigt: die Figurenelemente samt
`square-NN`-Klasse (mit Rechteck-Fallback), die sichtbare Zugliste (`.node`),
den Zugindikator der Uhren, den Partieende-Hinweis und die Partie-ID. Es wird
nichts geschrieben, kein Cookie gelesen und keine Anfrage an Chess.com
gestellt. Ein `MutationObserver` (140 ms entprellt) plus langsames Polling
(1,2 s) melden nur dann einen neuen Stand, wenn sich der Fingerabdruck aus
Stellung, Zugrecht, Zugliste und Status geändert hat.

**Verifikation.** `ChessComPositionDetector` prüft jeden Stand auf zwei Wegen:

1. *Zugliste verifiziert* – die sichtbaren SAN-Züge werden mit der eigenen
   Regel-Engine nachgespielt. Stimmt das Ergebnis mit dem erkannten Brett
   überein, sind FEN, Rochaderechte, En-passant-Feld, Halbzug- und Vollzugzähler
   exakt.
2. *Brett erkannt* (Fallback) – die 64 Felder gelten als Wahrheit, das
   Zugrecht kommt von der Uhr, Rochaderechte werden aus der Stellung von König
   und Türmen abgeleitet. Diese Herkunft wird in der Oberfläche benannt.

Erst danach greift `LivePositionSync.publish(...)`: FEN-Rundreise, Königszahl,
Bauern auf der Grundlinie, Gegner-im-Schach und En-passant-Konsistenz müssen
bestehen, sonst wird die Stellung verworfen und im UI mit Grund angezeigt.

**Ereignisse und Versionen.** Jede übernommene Stellung erhält eine streng
monotone Versionsnummer (Basis der Seite, bei einem Reload auf die interne
Version neu aufgesetzt). Daraus entstehen die Ereignisse *Neue Partie*, *Weiß
am Zug*, *Schwarz am Zug*, *Gegner hat gezogen*, *Partie beendet*,
*Zurückgesetzt* und *Stellung geladen*. Veraltete Messungen (Version ≤ aktuell)
werden verworfen, doppelte Stellungen (gleiche FEN und gleicher Ply) gezählt und
übersprungen – sichtbar als `übernommen · doppelt · veraltet · verworfen`.

**Engine.** Eine neue gültige Stellung wird sofort analysiert: die laufende
Suche wird über den Generationen-Zähler beendet, das Engine-Objekt bleibt
bestehen (`position fen …`, MultiPV aus den Einstellungen). Während der
Chess.com-Tab sichtbar ist, ist die Tiefe auf 12 begrenzt (`liveDepthCap`),
damit die Partie flüssig bleibt; im Stockfish-Tab gilt die volle Tiefe.

**Oberfläche.** Der Stockfish-Tab zeigt Quelle, Ereignis, Versionsnummer,
Ply/Zugrecht, die zuletzt erkannten Züge, den Fortschrittsbalken und die
FEN. Darunter steht die *Natural Move Selection* mit bestem Zug, guter
Alternative und interessanter Variante – jeweils mit Bewertung, Qualität und
einer aus den Zugeigenschaften abgeleiteten Begründung (`StrategicExplainer`).
Die Pfeile der Varianten werden animiert auf das Brett gezeichnet.

**Chess.com-Tab.** Die Seite füllt den Tab ohne Adressleiste und ohne
Browser-Navigation; die App zeigt nur einen Kopf mit Sitzungsstatus, einen
Ladeknopf, fünf Schnellzugriffe (Start, Online spielen, Puzzles, Profil, Login)
und den Live-Streifen. Die WebView wird beim App-Start einmal geladen; ein
Tabwechsel layoutet sie nur neu und lädt sie nie nach, damit Sitzung, Scroll-
position und laufende Partie erhalten bleiben.

**Engine in Partien.** Jede übernommene Stellung wird analysiert, auch während
einer laufenden Partie. Die App ist für Training und Partien gegen Bots gedacht;
in gewerteten Partien gegen Menschen ist Engine-Hilfe regelwidrig, und die
Verantwortung dafür liegt beim Nutzer.

**Ehrliche FEN.** Der Fallback kennzeichnet in `FenConfidence`, welche Felder
verifiziert sind. Zugrecht ohne Uhr, Rochaderechte, En-passant-Feld,
Halbzugzähler und Zugnummer gelten dort als geschätzt und werden im UI als
„Geschätzt: …" ausgewiesen. Nur die verifizierte Zugliste liefert eine
vollständig geprüfte FEN.

**Grenze.** Die Erkennung hängt an der gerenderten DOM-Struktur von Chess.com.
Ändert Chess.com seine Markup-Klassen oder rendert ein Brett ausschließlich auf
Canvas, findet die Sonde keine Stellung; die App zeigt dann „noch keine gültige
Stellung“ statt einer geratenen FEN. Geprüft ist die Kette durch Unit-Tests
(Payload-Decoding, FEN-Aufbau, Zuglisten-Verifikation, Fallback, Versionen,
Dedupe, Ereignisse); ein Test gegen die echte Chess.com-Seite ist in dieser
Umgebung ohne iPhone nicht möglich.

**Tests:** `ChessEngineProTests/ChessComDetectionTests.swift`,
`LiveSyncVersionTests.swift`, `StrategicExplainerTests.swift` sowie
`LiveSyncTests.swift`.

---

## 8. Version

`2.3.0` (Build 6) · Marketing-Version in `project.yml` (`MARKETING_VERSION`).
---

## 9. Qualitätsprüfung (v2.2)

**Automatisch geprüft (GitHub Actions, iOS-Simulator):**

| Bereich | Test |
| --- | --- |
| FEN-Aufbau, Zuglisten-Verifikation, Halbzug-/Vollzugzähler, En passant, Rochade | `ChessComDetectionTests` |
| Fallback-Markierung als geschätzt (Zugrecht, Rochade, En passant, Zähler) | `ChessComDetectionTests` |
| Plausibilität: Königszahl, Bauern auf der Grundlinie, Figurenzahl, benachbarte Könige, unlesbare FEN | `ChessComDetectionTests`, `LiveSyncTests` |
| Versionierung, schnelle Zugfolgen, veraltete/doppelte Updates, Undo/Import/Reset, Ereignisse | `LiveSyncVersionTests` |
| Jede übernommene Stellung erreicht die Engine, auch während einer laufenden Partie | `AnalysisManagerLiveTests` |
| Nur gültige Stellungen erreichen Brett und Engine; schnelle Züge analysieren nur die letzte Stellung; Reload-Rebase | `AnalysisManagerLiveTests` |
| WebView lädt genau einmal, Tabwechsel/Snapshot/Session-Refresh navigieren nicht | `ChessComBrowserLifecycleTests` |
| Regeln, Perft, SAN/PGN, Engine-Bridge, Speicherung | `ChessCoreTests`, `EngineTests` |

**Nicht geprüft – benötigt ein echtes iPhone:**

* Die DOM-Selektoren auf der echten Chess.com-Seite (`.piece`, `square-NN`,
  `.node`, Uhr-Indikator, Partieende-Banner). Die Erkennung ist **nicht** gegen
  die Live-Seite getestet; sie kann dort fehlschlagen oder eine Stellung
  ablehnen.
* WKWebView-Persistenz über echte Tabwechsel: Login, Cookies, Scrollposition und
  laufende Partie auf dem Gerät.
* Signierung/Sideloading und der Chess.com-Login im WebView.
* Stockfish-Laufzeit auf dem Gerät (CPU-Last, Wärme, Hintergrundverhalten).
* Darstellung der neuen Karten, Pfeile und Animationen auf dem Gerät.

**Bekannte Grenzen:** Canvas-only-Boards oder geänderte Chess.com-Klassen
liefern keine Stellung; virtuelle Zuglisten ohne SAN führen zum Brett-Fallback
mit „geschätzt". Die Engine analysiert auch laufende Partien – die App ist für
Training und Partien gegen Bots gedacht.
