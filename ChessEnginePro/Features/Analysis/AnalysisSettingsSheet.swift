//
//  AnalysisSettingsSheet.swift
//  CHESS ENGINE PRO
//
//  Engine, variant, board, arrow and performance settings.
//

import SwiftUI

struct AnalysisSettingsSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var analysis: AnalysisManager

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    engineSection
                    variantsSection
                    boardSection
                    arrowSection
                    performanceSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Theme.background)
            .navigationTitle("Analyse-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Engine", subtitle: analysis.engineName)
            DividerLine()
            SettingsRow(title: "Engine aktiv", subtitle: "Analyse automatisch starten", icon: "power") {
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
                Text(StockfishBuild.isLinked
                     ? "Stockfish \(StockfishBuild.version) ist eingebunden und rechnet lokal auf dem Gerät."
                     : "Stockfish ist in diesem Build nicht eingebunden – die eingebaute Swift-Engine übernimmt.")
                    .font(.system(size: 10))
                    .foregroundStyle(StockfishBuild.isLinked ? Theme.secondaryText : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            DividerLine()
            stepperRow(title: "Suchtiefe",
                       subtitle: "Höher = stärker, aber langsamer",
                       icon: "gauge.with.dots.needle.67percent",
                       value: $settings.settings.depth,
                       range: 8...40,
                       step: 1)
            DividerLine()
            stepperRow(title: "Analysezeit",
                       subtitle: settings.settings.useTimeLimit ? "\(settings.settings.moveTimeMs) ms pro Stellung" : "Tiefenlimit aktiv",
                       icon: "timer",
                       value: $settings.settings.moveTimeMs,
                       range: 200...10_000,
                       step: 100,
                       enabled: settings.settings.useTimeLimit)
            SettingsRow(title: "Zeitlimit verwenden", icon: "clock") {
                Toggle("", isOn: $settings.settings.useTimeLimit).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
            stepperRow(title: "Threads",
                       subtitle: "Parallele Suchthreads",
                       icon: "cpu",
                       value: $settings.settings.threads,
                       range: 1...8,
                       step: 1)
            DividerLine()
            stepperRow(title: "Hash",
                       subtitle: "Transpositionstabelle in MB",
                       icon: "memorychip",
                       value: $settings.settings.hashMB,
                       range: 16...1024,
                       step: 32)
        }
        .premiumCard()
    }

    private func stepperRow(title: String,
                            subtitle: String,
                            icon: String,
                            value: Binding<Int>,
                            range: ClosedRange<Int>,
                            step: Int,
                            enabled: Bool = true) -> some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon) {
            HStack(spacing: 6) {
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

    // MARK: - Variants

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Varianten", subtitle: "MultiPV")
            DividerLine()
            SettingsRow(title: "Anzahl Varianten",
                        subtitle: "Wie viele Kandidaten die Engine meldet",
                        icon: "list.number") {
                Stepper("\(settings.settings.multiPV)", value: $settings.settings.multiPV, in: 1...5)
                    .labelsHidden()
                    .fixedSize()
            }
            DividerLine()
            VStack(alignment: .leading, spacing: 8) {
                Text("Spielstil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(MoveStyle.allCases) { style in
                    Button {
                        settings.settings.style = style
                        analysis.apply(style: style)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: style.sfSymbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(analysis.style == style ? Theme.accent : Theme.secondaryText)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(style.title)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Text(style.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if analysis.style == style {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .premiumCard()
    }

    // MARK: - Board

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Darstellung")
            DividerLine()
            VStack(alignment: .leading, spacing: 8) {
                Text("Brettdesign")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BoardThemeID.allCases) { themeID in
                            let boardTheme = BoardTheme.theme(for: themeID)
                            Button {
                                settings.settings.boardTheme = themeID
                            } label: {
                                VStack(spacing: 5) {
                                    HStack(spacing: 0) {
                                        Rectangle().fill(boardTheme.light).frame(width: 14, height: 28)
                                        Rectangle().fill(boardTheme.dark).frame(width: 14, height: 28)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    Text(themeID.localizedTitle)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(settings.settings.boardTheme == themeID ? Theme.accent : Theme.secondaryText)
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(settings.settings.boardTheme == themeID ? Theme.accent.opacity(0.12) : Theme.field)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
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
            DividerLine()
            SettingsRow(title: "Koordinaten", icon: "textformat.abc") {
                Toggle("", isOn: $settings.settings.showCoordinates).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Legale Züge anzeigen", icon: "circle.dotted") {
                Toggle("", isOn: $settings.settings.showLegalMoves).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Animationen", icon: "sparkles") {
                Toggle("", isOn: $settings.settings.animateMoves).labelsHidden().tint(Theme.accent)
            }
        }
        .premiumCard()
    }

    // MARK: - Arrows

    private var arrowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pfeile")
            DividerLine()
            SettingsRow(title: "Pfeile anzeigen", icon: "arrow.up.right") {
                Toggle("", isOn: $settings.settings.showArrows).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Anzahl Pfeile", icon: "number") {
                Stepper("\(settings.settings.arrowCount)", value: $settings.settings.arrowCount, in: 1...5)
                    .labelsHidden()
                    .fixedSize()
            }
            SettingsRow(title: "Bewertung am Pfeil", icon: "text.bubble") {
                Toggle("", isOn: $settings.settings.showArrowLabels).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
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
                ArrowLegend(palette: ArrowPalette.palette(for: settings.settings.arrowPalette))
            }
        }
        .premiumCard()
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Performance")
            DividerLine()
            SettingsRow(title: "Akkuoptimierung",
                        subtitle: "Begrenzt die Engine auf einen Thread",
                        icon: "battery.50percent") {
                Toggle("", isOn: $settings.settings.batterySaver).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Maximale Auslastung",
                        subtitle: "Erlaubt alle konfigurierten Threads",
                        icon: "bolt.fill") {
                Toggle("", isOn: $settings.settings.maxEngineLoad).labelsHidden().tint(Theme.accent)
            }
            SettingsRow(title: "Automatische Analyse",
                        subtitle: "Nach jedem Zug neu rechnen",
                        icon: "arrow.triangle.2.circlepath") {
                Toggle("", isOn: $settings.settings.autoAnalyze).labelsHidden().tint(Theme.accent)
            }
            DividerLine()
            Button {
                analysis.analyze()
            } label: {
                Label("Analyse neu starten", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }
}
