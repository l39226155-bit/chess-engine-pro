//
//  AnalysisPanelView.swift
//  CHESS ENGINE PRO
//
//  The engine now lives inside the Chess.com screen. This panel is the only
//  place that shows live results: one compact row with the evaluation and the
//  best move, plus an expandable area with the real variants and the verified
//  position data. Every value comes from AnalysisManager, nothing is staged.
//

import SwiftUI

struct AnalysisPanelView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var analysis: AnalysisManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var browser: ChessComBrowser

    @State private var isExpanded = false

    private let detailHeight: CGFloat = 238

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            headerRow
            if isExpanded {
                DividerLine()
                detail
            }
        }
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    // MARK: - Gate

    private var allowsEngine: Bool {
        LiveAnalysisPolicy.allowsSuggestions(in: browser.pageMode,
                                             engineEnabled: settings.settings.engineEnabled)
    }

    private var blockNote: String? {
        if !settings.settings.engineEnabled {
            return "Die Engine ist in den Einstellungen deaktiviert."
        }
        return LiveAnalysisPolicy.blockNote(for: browser.pageMode)
    }

    private var hasEvaluation: Bool { !analysis.candidates.isEmpty }

    // MARK: - Progress

    @ViewBuilder
    private var progressBar: some View {
        if allowsEngine && analysis.isAnalyzing {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.divider)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: max(2, proxy.size.width * min(1, max(0.02, analysis.analysisProgress))))
                }
            }
            .frame(height: 2)
            .animation(.easeOut(duration: 0.2), value: analysis.analysisProgress)
        }
    }

    // MARK: - Compact row

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                evalChip

                VStack(alignment: .leading, spacing: 3) {
                    primaryLine
                    HStack(spacing: 5) {
                        Text(statusLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if allowsEngine, analysis.depth > 0 {
                            Text("T\(analysis.depth)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Analyse zuklappen" : "Analyse aufklappen")
    }

    private var evalChip: some View {
        let whiteAhead = analysis.evaluation.whiteCentipawns >= 0
        return Text(allowsEngine && hasEvaluation ? analysis.evaluation.display : "–")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(allowsEngine && hasEvaluation && whiteAhead ? Color(hex: 0x101113) : Theme.text)
            .frame(minWidth: 54)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(allowsEngine && hasEvaluation && whiteAhead
                          ? Color(hex: 0xE8E8EA)
                          : Theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
            )
            .accessibilityLabel(hasEvaluation ? analysis.evaluation.localizedDescription : "Noch keine Bewertung")
    }

    @ViewBuilder
    private var primaryLine: some View {
        if let note = blockNote {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("Analyse deaktiviert")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        } else if let best = analysis.candidates.first {
            HStack(spacing: 6) {
                Text(best.san)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(best.pvSAN.dropFirst().prefix(4).joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        } else if analysis.isAnalyzing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(Theme.accent)
                Text("Stockfish rechnet …")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else if !analysis.liveValidation.isValid {
            Text(analysis.liveValidation.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
        } else {
            Text("Bereit für die nächste Stellung")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var statusLine: String {
        if blockNote != nil { return "Nur in Analyse, Training und gegen Computer" }
        if analysis.isAnalyzing {
            let percent = Int(min(1, max(0, analysis.analysisProgress)) * 100)
            return "\(npsText) · \(percent) %"
        }
        if hasEvaluation {
            let engine = analysis.engineName.isEmpty ? StockfishBuild.displayName : analysis.engineName
            return "\(npsText) · \(engine)"
        }
        if let snapshot = analysis.liveSnapshot, snapshot.isGameOver {
            return snapshot.statusText
        }
        if analysis.liveSnapshot == nil {
            return "Öffne eine Partie, ein Puzzle oder ein Analysebrett"
        }
        return analysis.statusMessage ?? "Keine Analyse verfügbar"
    }

    /// Real nodes per second only - the placeholder appears until the engine
    /// reports its first update.
    private var npsText: String {
        let nps = analysis.nodesPerSecond
        guard nps > 0 else { return "– n/s" }
        if nps >= 1_000_000 { return String(format: "%.1fM n/s", Double(nps) / 1_000_000) }
        if nps >= 1_000 { return String(format: "%.0fK n/s", Double(nps) / 1_000) }
        return "\(nps) n/s"
    }

    // MARK: - Expanded detail

    private var detail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let note = blockNote {
                    lockedNotice(note)
                } else {
                    variantSection
                }
                positionSection
                actionRow
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(height: detailHeight)
    }

    private var variantSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Varianten")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(analysis.style.localizedTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            if analysis.styleRankedCandidates.isEmpty {
                Text(analysis.isAnalyzing
                     ? "Die Varianten erscheinen mit dem ersten Engine-Update."
                     : "Keine Varianten – Engine starten oder eine Stellung laden.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 6)
            } else {
                let variants = Array(analysis.styleRankedCandidates.prefix(5))
                ForEach(Array(variants.enumerated()), id: \.offset) { item in
                    variationRow(item.element)
                    if item.offset < variants.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
        }
    }

    private func variationRow(_ candidate: CandidateMove) -> some View {
        Button {
            analysis.preview(candidate)
            environment.presentAnalysis()
        } label: {
            HStack(spacing: 8) {
                Text("\(candidate.rank)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(candidate.rank == 1 ? Theme.accent : Theme.secondaryText)
                    .frame(width: 9, alignment: .leading)

                Text(candidate.san)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)

                Text(candidate.pvSAN.dropFirst().prefix(5).joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Circle()
                    .fill(Theme.qualityColor(candidate.quality))
                    .frame(width: 5, height: 5)

                Text(candidate.score.display)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(candidate.rank == 1 ? Theme.accentMuted : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Variante \(candidate.rank): \(candidate.san), \(candidate.score.display)")
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Stellung")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                if let snapshot = analysis.liveSnapshot {
                    Text("Zug \(snapshot.ply) · \(snapshot.source.localizedTitle)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let snapshot = analysis.liveSnapshot {
                    Text("v\(snapshot.version)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let snapshot = analysis.liveSnapshot {
                Text(snapshot.fen)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Image(systemName: analysis.liveValidation.isValid
                          ? "checkmark.seal.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(analysis.liveValidation.isValid ? Theme.accent : Theme.warning)
                    Text(analysis.liveValidation.isValid
                         ? analysis.syncStats.summary
                         : analysis.liveValidation.summary)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                if !snapshot.confidence.isExact {
                    Text(snapshot.confidence.note)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Noch keine Stellung erkannt.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )
        )
    }

    private var actionRow: some View {
        HStack(spacing: 7) {
            panelButton("Brett", icon: "square.grid.3x3.fill") {
                environment.presentAnalysis()
            }
            panelButton("Neu", icon: "arrow.clockwise") {
                analysis.analyze()
            }
            .disabled(!allowsEngine)
            .opacity(allowsEngine ? 1 : 0.45)
            panelButton("Drehen", icon: "arrow.triangle.2.circlepath") {
                analysis.flip()
            }
            Spacer(minLength: 0)
            if analysis.isAnalyzing {
                Text("läuft")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func panelButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.elevated))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func lockedNotice(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Engine-Vorschläge deaktiviert")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.warning.opacity(0.10))
        )
    }
}
