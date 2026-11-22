//
//  AnalysisView.swift
//  CHESS ENGINE PRO
//
//  Board, evaluation, engine variants, arrows, variation playback and tools.
//

import SwiftUI
import UIKit

struct AnalysisView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var showSettings = false
    @State private var showEditor = false
    @State private var showImporter = false
    @State private var showSaveConfirmation = false

    private var theme: BoardTheme { BoardTheme.theme(for: settings.settings.boardTheme) }
    private var palette: ArrowPalette { ArrowPalette.palette(for: settings.settings.arrowPalette) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                liveStatusCard
                boardSection
                annotationRow
                boardToolbar
                engineVariantsCard
                if analysis.isPreviewing { previewCard }
                moveListCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .background(Theme.background)
        .onChange(of: settings.settings) { _, newValue in
            analysis.apply(style: newValue.style)
            analysis.analyze(debounce: true)
        }
        .sheet(isPresented: $showSettings) {
            AnalysisSettingsSheet()
                .environmentObject(settings)
                .environmentObject(analysis)
        }
        .sheet(isPresented: $showEditor) {
            PositionEditorView(initialBoard: analysis.board) { newBoard in
                analysis.setBoard(newBoard)
                environment.showToast("Stellung übernommen")
            }
            .environmentObject(settings)
        }
        .pgnImporter(isPresented: $showImporter) { game in
            analysis.load(game: game)
            environment.showToast("Partie geladen")
        } onError: { message in
            environment.showToast(message)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(analysis.turnText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(analysis.isAnalyzing ? Theme.accent : Theme.secondaryText)
                        .frame(width: 5, height: 5)
                    Text(analysis.engineName.isEmpty ? StockfishBuild.displayName : analysis.engineName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    if analysis.depth > 0 {
                        Text("T\(analysis.depth) · \(nodeText)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Spacer()
            EvalBadge(score: analysis.evaluation)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    // MARK: - Live synchronisation

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(analysis.isAnalyzing ? Theme.accent : Theme.secondaryText)
                    .frame(width: 6, height: 6)
                Text(analysis.isAnalyzing ? "Live-Analyse läuft" : "Live-Position")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                if let snapshot = analysis.liveSnapshot {
                    Pill(text: "Zug \(snapshot.ply)", icon: "number")
                    if let kind = snapshot.moveKind {
                        Pill(text: kind.localizedTitle, color: Theme.info)
                    }
                }
                Spacer(minLength: 0)
                if let snapshot = analysis.liveSnapshot {
                    Text(snapshot.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            if analysis.isAnalyzing {
                ProgressView(value: max(0.02, analysis.analysisProgress))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            HStack(spacing: 6) {
                Image(systemName: analysis.liveValidation.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(analysis.liveValidation.isValid ? Theme.accent : Theme.warning)
                Text(analysis.liveValidation.isValid
                     ? "FEN validiert · \(analysis.liveChangeCount) Stellungswechsel"
                     : analysis.liveValidation.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let fen = analysis.liveSnapshot?.fen {
                    Text(fen)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            }
        }
        .premiumCard(padding: 12, radius: 14)
    }

    private var nodeText: String {
        let nodes = analysis.nodes
        if nodes >= 1_000_000 { return String(format: "%.1fM", Double(nodes) / 1_000_000) }
        if nodes >= 1_000 { return String(format: "%.0fK", Double(nodes) / 1_000) }
        return "\(nodes)"
    }

    // MARK: - Board

    private var boardSection: some View {
        HStack(alignment: .top, spacing: 8) {
            EvaluationBar(score: analysis.evaluation,
                          orientation: analysis.boardOrientation)
                .frame(width: 8, height: boardHeight)

            ChessBoardView(board: analysis.displayBoard,
                           orientation: analysis.boardOrientation,
                           lastMove: analysis.displayLastMove,
                           arrows: analysis.arrows,
                           theme: theme,
                           pieceStyle: settings.settings.pieceStyle,
                           arrowPalette: palette,
                           showCoordinates: settings.settings.showCoordinates,
                           showsLegalMoves: settings.settings.showLegalMoves,
                           showArrowLabels: settings.settings.showArrowLabels,
                           interactive: !analysis.isPreviewing,
                           animate: settings.settings.animateMoves,
                           onMove: { move in analysis.play(move) })
        }
    }

    /// The board is square and fills the available width minus the eval bar.
    private var boardHeight: CGFloat { UIScreen.main.bounds.width - 48 }

    private var annotationRow: some View {
        HStack(spacing: 8) {
            if let best = analysis.candidates.first {
                QualityBadge(quality: best.quality)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bester Zug: \(best.san)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(best.pvSAN.prefix(5).joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            } else if analysis.isAnalyzing {
                ProgressView().scaleEffect(0.7)
                Text("Engine denkt …")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(analysis.statusMessage ?? "Keine Varianten")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            if analysis.isPreviewing {
                HStack(spacing: 6) {
                    Button { analysis.previewStep(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(!analysis.canPreviewBack)

                    Button { analysis.previewStep(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(!analysis.canPreviewForward)

                    Button { analysis.clearPreview() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle())
                }
            }
        }
    }

    private var boardToolbar: some View {
        HStack(spacing: 8) {
            toolButton("arrow.uturn.backward", label: "Zug zurück") { analysis.undo() }
            toolButton("trash", label: "Neu starten") { analysis.reset() }
            toolButton("arrow.triangle.2.circlepath", label: "Brett drehen") { analysis.flip() }
            toolButton("square.and.pencil", label: "Stellung bearbeiten") { showEditor = true }
            toolButton("doc.badge.arrow.up", label: "PGN importieren") { showImporter = true }

            Spacer()

            Button {
                analysis.saveCurrentAnalysis(into: environment.store)
                environment.showToast("Analyse gespeichert")
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(IconButtonStyle())

            ShareLink(item: analysis.currentPGN) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Theme.divider, lineWidth: 1))
                    )
            }
        }
    }

    private func toolButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Engine variants

    private var engineVariantsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Engine-Varianten",
                          subtitle: "\(settings.settings.multiPV) Varianten · \(analysis.style.localizedTitle)")
            DividerLine()
            if analysis.styleRankedCandidates.isEmpty {
                EmptyStateView(icon: "cpu",
                               title: "Keine Varianten",
                               message: "Engine aktivieren oder eine andere Stellung laden.")
            } else {
                VStack(spacing: 4) {
                    ForEach(analysis.styleRankedCandidates) { candidate in
                        CandidateRow(candidate: candidate,
                                     arrowHidden: analysis.hiddenArrowIDs.contains(
                                        BoardArrow(from: candidate.move.from,
                                                   to: candidate.move.to,
                                                   kind: candidate.arrowKind).id),
                                     isPreviewing: analysis.previewCandidate == candidate,
                                     onSelect: {
                                         if analysis.previewCandidate == candidate {
                                             analysis.clearPreview()
                                         } else {
                                             analysis.preview(candidate)
                                         }
                                     },
                                     onToggleArrow: {
                                         analysis.toggleArrow(BoardArrow(from: candidate.move.from,
                                                                         to: candidate.move.to,
                                                                         kind: candidate.arrowKind))
                                     })
                    }
                }
            }
            DividerLine()
            stylePicker
        }
        .premiumCard()
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spielstil für die Variantenauswahl")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MoveStyle.allCases) { style in
                        Button {
                            analysis.apply(style: style)
                            settings.settings.style = style
                        } label: {
                            Text(style.title)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(analysis.style == style ? Color(hex: 0x0B0D10) : Theme.secondaryText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(analysis.style == style ? Theme.accent : Theme.field)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Variante")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let candidate = analysis.previewCandidate {
                    Pill(text: candidate.score.display, color: Theme.accent)
                    Pill(text: "\(analysis.previewPly)/\(max(0, analysis.previewBoards.count - 1))",
                         color: Theme.secondaryText)
                }
            }
            if let candidate = analysis.previewCandidate {
                Text(previewLineText(candidate))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Anfang") { analysis.previewStep(-analysis.previewPly) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Ende") { analysis.previewToEnd() }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Variante spielen") { analysis.clearPreview() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .premiumCard(padding: 14, radius: 16)
    }

    private func previewLineText(_ candidate: CandidateMove) -> String {
        candidate.pvSAN.enumerated().map { index, san in
            index == analysis.previewPly ? "[\(san)]" : san
        }.joined(separator: " ")
    }

    // MARK: - Move list

    private var moveListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Zugliste",
                          subtitle: analysis.sessionMoves.isEmpty ? "Noch keine Züge gespielt" : nil)
            if !analysis.moveLog.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(analysis.moveLog.enumerated()), id: \.offset) { index, san in
                            Button {
                                analysis.jump(toPly: index + 1)
                            } label: {
                                HStack(spacing: 3) {
                                    if index % 2 == 0 {
                                        Text("\(index / 2 + 1).")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Text(san)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(index + 1 == analysis.moveLog.count ? Theme.accentMuted : Theme.field)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("Spiele Züge auf dem Brett oder importiere eine PGN-Datei.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .premiumCard(padding: 14, radius: 16)
    }
}

// MARK: - Evaluation bar

struct EvaluationBar: View {
    let score: EvalScore
    var orientation: PieceColor = .white

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let whiteShare = score.whiteWinProbability
            let whiteHeight = max(2, min(height - 2, height * whiteShare))

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x24272E))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0xE9EBEF))
                    .frame(height: whiteHeight)
            }
            .rotationEffect(.degrees(orientation == .white ? 0 : 180))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
        }
        .accessibilityLabel(score.localizedDescription)
    }
}

struct EvalBadge: View {
    let score: EvalScore

    var body: some View {
        Text(score.display)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(hex: 0x0B0D10))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(score.whiteCentipawns >= 0 ? Theme.accent : Color(hex: 0xB9C0C8))
            )
    }
}
