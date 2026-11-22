//
//  GameReviewView.swift
//  CHESS ENGINE PRO
//
//  Import a PGN, evaluate every position, show qualities, accuracy and an
//  evaluation graph.
//

import SwiftUI

struct GameReviewView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var review: GameReviewController
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let game = review.game {
                        summary(game)
                        if review.isReviewing { progressCard }
                        boardSection
                        EvalGraphView(moves: review.moves)
                            .padding(.vertical, 6)
                        moveList
                        actions
                    } else {
                        importCard
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Partie prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        review.cancel()
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .pgnImporter(isPresented: $showImporter) { game in
            environment.analysis.stop()
            review.startReview(of: game,
                               engine: analysis.activeEngine,
                               depth: max(10, min(14, settings.settings.depth)))
        } onError: { message in
            environment.showToast(message)
        }
        .onDisappear { review.cancel() }
    }

    // MARK: - Sections

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PGN importieren")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Wähle eine PGN-Datei. Jede Stellung wird lokal analysiert, Fehler und Ungenauigkeiten werden erkannt und mit der besten Alternative verglichen.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showImporter = true
            } label: {
                Label("PGN-Datei auswählen", systemImage: "doc.badge.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("Tipp: Auf Chess.com kannst du deine Partien als PGN exportieren und hier einlesen.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .premiumCard()
    }

    private func summary(_ game: PGNGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(game.subtitle.isEmpty ? "PGN" : game.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Pill(text: game.result, color: Theme.accent)
            }

            if review.isReviewing {
                Text("Analyse läuft …")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            } else if !review.moves.isEmpty {
                Text(review.summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 10) {
                    accuracyTile(title: "Weiß", value: review.accuracyWhite)
                    accuracyTile(title: "Schwarz", value: review.accuracyBlack)
                }
            }
        }
        .premiumCard()
    }

    private func accuracyTile(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
            Text(value.map { String(format: "%.1f%%", $0) } ?? "–")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
    }

    private var progressCard: some View {
        HStack(spacing: 10) {
            ProgressView(value: review.progress)
                .tint(Theme.accent)
            Text("\(Int(review.progress * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
        }
        .premiumCard(padding: 12, radius: 12)
    }

    private var boardSection: some View {
        VStack(spacing: 10) {
            ChessBoardView(board: review.selectedBoard,
                           orientation: .white,
                           lastMove: review.selectedMove.flatMap { Move(uci: $0.uci) },
                           arrows: [],
                           theme: BoardTheme.theme(for: settings.settings.boardTheme),
                           pieceStyle: settings.settings.pieceStyle,
                           arrowPalette: ArrowPalette.palette(for: settings.settings.arrowPalette),
                           showCoordinates: true,
                           showsLegalMoves: false,
                           interactive: false,
                           animate: settings.settings.animateMoves)

            HStack(spacing: 10) {
                Button { review.select(ply: 0) } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(IconButtonStyle())

                Button { review.select(ply: review.selectedPly - 1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())

                Button { review.select(ply: review.selectedPly + 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(IconButtonStyle())

                Button { review.select(ply: review.boards.count - 1) } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(IconButtonStyle())

                Spacer()

                if let move = review.selectedMove {
                    QualityBadge(quality: move.quality)
                    Text(move.scoreAfter.display)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let move = review.selectedMove, let best = move.bestSAN, move.loss > 50 {
                Text("Besser war: \(best) (\(move.scoreBefore.display))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private var moveList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Züge", subtitle: review.summaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(review.moves) { move in
                        Button {
                            review.select(ply: move.ply + 1)
                        } label: {
                            HStack(spacing: 3) {
                                if move.color == .white {
                                    Text("\(move.number).")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Text(move.san)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Image(systemName: move.quality.sfSymbol)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Theme.qualityColor(move.quality))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(review.selectedPly == move.ply + 1 ? Theme.accent.opacity(0.16) : Theme.field)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !review.mistakes.isEmpty {
                DividerLine()
                Text("Fehler & Patzer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(review.mistakes.prefix(6)) { move in
                    Button {
                        review.select(ply: move.ply + 1)
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(move.number).\(move.color == .white ? "" : "..")\(move.san)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.text)
                            QualityBadge(quality: move.quality, compact: true)
                            Spacer()
                            if let best = move.bestSAN {
                                Text("besser: \(best)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .premiumCard(padding: 14, radius: 16)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                showImporter = true
            } label: {
                Label("Andere Partie", systemImage: "doc.badge.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())

            if review.game != nil {
                ShareLink(item: review.exportAnnotated()) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
                }
            }
            Spacer()
        }
    }
}

// MARK: - Evaluation graph

struct EvalGraphView: View {
    let moves: [GameReviewController.ReviewedMove]

    var body: some View {
        Canvas { context, size in
            var zeroLine = Path()
            zeroLine.move(to: CGPoint(x: 0, y: size.height / 2))
            zeroLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(zeroLine, with: .color(Theme.divider), lineWidth: 1)

            guard !moves.isEmpty else { return }
            let step = size.width / CGFloat(moves.count)
            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height / 2))

            for (index, move) in moves.enumerated() {
                let clamped = max(-800.0, min(800.0, Double(move.scoreAfter.whiteCentipawns)))
                let normalised = clamped / 800.0
                let x = CGFloat(index) * step + step / 2
                let y = size.height / 2 - CGFloat(normalised) * (size.height / 2 - 2)
                if index == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
                area.addLine(to: CGPoint(x: x, y: y))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            area.closeSubpath()
            context.fill(area, with: .color(Theme.accent.opacity(0.12)))
            context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
    }
}
