//
//  SettingsView.swift
//  CHESS ENGINE PRO
//
//  Complete settings: engine, display, performance, account and privacy.
//

import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var showDeleteConfirm = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    engineSection
                    displaySection
                    performanceSection
                    accountSection
                    privacySection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Theme.background)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .alert("Alle Analysen löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    environment.store.deleteAll()
                    environment.showToast("Alle Analysen gelöscht")
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Gespeicherte Analysen werden dauerhaft von diesem Gerät entfernt.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Engine", subtitle: analysis.engineName)
            DividerLine()
            SettingsRow(title: "Engine aktiv", icon: "power") {
                Toggle("", isOn: $settings.settings.engineEnabled).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
            VStack(alignment: .leading, spacing: 8) {
                Text("Backend")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Backend", selection: $settings.settings.backend) {
                    ForEach(EngineBackend.allCases) { backend in
                        Text(backend.localizedTitle).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 8)
            DividerLine()
            intStepper(title: "Suchtiefe", icon: "gauge.with.dots.needle.67percent",
                       value: $settings.settings.depth, range: 8...40, step: 1)
            DividerLine()
            intStepper(title: "MultiPV", icon: "list.number",
                       value: $settings.settings.multiPV, range: 1...5, step: 1)
            DividerLine()
            intStepper(title: "Analysezeit (ms)", icon: "timer",
                       value: $settings.settings.moveTimeMs, range: 200...10_000, step: 100,
                       enabled: settings.settings.useTimeLimit)
            SettingsRow(title: "Zeitlimit statt Tiefe", icon: "clock") {
                Toggle("", isOn: $settings.settings.useTimeLimit).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
            intStepper(title: "Threads", icon: "cpu",
                       value: $settings.settings.threads, range: 1...8, step: 1)
            DividerLine()
            intStepper(title: "Hash (MB)", icon: "memorychip",
                       value: $settings.settings.hashMB, range: 16...1024, step: 32)
            DividerLine()
            Button {
                analysis.analyze()
            } label: {
                Label("Engine neu starten", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }

    private func intStepper(title: String, icon: String,
                            value: Binding<Int>, range: ClosedRange<Int>, step: Int,
                            enabled: Bool = true) -> some View {
        SettingsRow(title: title, icon: icon) {
            HStack(spacing: 8) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(enabled ? Theme.text : Theme.secondaryText)
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
                    .disabled(!enabled)
                    .fixedSize()
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Darstellung")
            DividerLine()
            VStack(alignment: .leading, spacing: 8) {
                Text("Brettdesign")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Brettdesign", selection: $settings.settings.boardTheme) {
                    ForEach(BoardThemeID.allCases) { theme in
                        Text(theme.localizedTitle).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 8) {
                Text("Figurenstil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Figurenstil", selection: $settings.settings.pieceStyle) {
                    ForEach(PieceStyleID.allCases) { style in
                        Text(style.localizedTitle).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 6)
            DividerLine()
            SettingsRow(title: "Pfeile anzeigen", icon: "arrow.up.right") {
                Toggle("", isOn: $settings.settings.showArrows).labelsHidden().tint(Theme.accent)
            }
            intStepper(title: "Anzahl Pfeile", icon: "number",
                       value: $settings.settings.arrowCount, range: 1...5, step: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Pfeilfarben")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Pfeilfarben", selection: $settings.settings.arrowPalette) {
                    ForEach(ArrowPaletteID.allCases) { palette in
                        Text(palette.localizedTitle).tag(palette)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 6)
            DividerLine()
            SettingsRow(title: "Koordinaten", icon: "textformat.abc") {
                Toggle("", isOn: $settings.settings.showCoordinates).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Legale Züge", icon: "circle.dotted") {
                Toggle("", isOn: $settings.settings.showLegalMoves).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Animationen", icon: "sparkles") {
                Toggle("", isOn: $settings.settings.animateMoves).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Dunkles Design", subtitle: "CHESS ENGINE PRO nutzt immer Dark Mode", icon: "moon.fill") {
                Toggle("", isOn: .constant(true)).labelsHidden().disabled(true).tint(Theme.accent)
            }
        }
        .premiumCard()
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Performance")
            DividerLine()
            SettingsRow(title: "Akkuoptimierung",
                        subtitle: "Ein Thread, geringere Hitzeentwicklung",
                        icon: "battery.50percent") {
                Toggle("", isOn: $settings.settings.batterySaver).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Maximale Auslastung",
                        subtitle: "Alle Threads erlauben",
                        icon: "bolt.fill") {
                Toggle("", isOn: $settings.settings.maxEngineLoad).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Hintergrundanalyse",
                        subtitle: "Analyse nach Positionswechsel neu starten",
                        icon: "square.stack.3d.up") {
                Toggle("", isOn: $settings.settings.backgroundAnalysis).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Automatische Analyse", icon: "arrow.triangle.2.circlepath") {
                Toggle("", isOn: $settings.settings.autoAnalyze).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
            Button {
                settings.resetToDefaults()
                analysis.apply(style: settings.settings.style)
                environment.showToast("Einstellungen zurückgesetzt")
            } label: {
                Label("Auf Standard zurücksetzen", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Konto")
            DividerLine()
            VStack(alignment: .leading, spacing: 6) {
                Text("Lokaler Anzeigename")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                TextField("Name", text: $settings.settings.playerName)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
            }
            .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Chess.com-Benutzername (nur lokal)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                TextField("Benutzername", text: $settings.settings.chessComHandle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
                Text("Die Anmeldung selbst findet ausschließlich im Chess.com-WebView statt. Die App speichert kein Passwort.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            DividerLine()
            Button {
                dismiss()
                environment.selectedTab = .play
            } label: {
                Label("Chess.com-Sitzung verwalten", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Datenschutz & Daten")
            DividerLine()
            Text("Alle Analysen, Einstellungen und Trainingsdaten bleiben auf diesem Gerät. Es werden keine Zugangsdaten ausgelesen und keine Analyse-Daten an Server gesendet. Die Engine rechnet vollständig offline.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            Text("\(environment.store.count) gespeicherte Analysen")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
            Button {
                showDeleteConfirm = true
            } label: {
                Label("Alle Analysen löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.error)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Über")
            DividerLine()
            infoRow("Version", appVersion)
            infoRow("Engine", StockfishBuild.displayName)
            infoRow("Stockfish-Version", StockfishBuild.version)
            infoRow("Plattform", "iOS · SwiftUI · WKWebView")
            DividerLine()
            Text("Diese App enthält Stockfish (GPLv3). Der Quellcode der Engine ist unter github.com/official-stockfish/Stockfish verfügbar. CHESS ENGINE PRO steht in keiner offiziellen Verbindung zu Chess.com.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .premiumCard()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 3)
    }
}
