//
//  OpeningTrainer.swift
//  CHESS ENGINE PRO
//
//  Replay and learn opening lines. The app plays the opponent's moves and
//  validates every move you make against the line.
//

import SwiftUI

struct OpeningTrainerListView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var library = OpeningLibrary.shared
    @State private var selected: OpeningLine?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if library.openings.isEmpty {
                        EmptyStateView(icon: "book.closed",
                                       title: "Keine Eröffnungen",
                                       message: library.loadError ?? "Es sind keine Linien hinterlegt.")
                            .padding(.top, 30)
                    } else {
                        ForEach(library.openings) { line in
                            Button {
                                selected = line
                            } label: {
                                row(line)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Eröffnungstraining")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selected) { line in
            OpeningTrainerSession(line: line)
                .environmentObject(settings)
        }
    }

    private func row(_ line: OpeningLine) -> some View {
        HStack(spacing: 12) {
            Text(line.eco)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(line.moves.prefix(8).joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }
}

struct OpeningTrainerSession: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    let line: OpeningLine

    @State private var board = Board()
    @State private var moveIndex = 0
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var lastMove: Move?
    @State private var finished = false

    private var expectedMoves: [Move] {
        var replay = Board()
        var moves: [Move] = []
        for san in line.moves {
            guard let move = replay.move(matchingSan: san) else { break }
            moves.append(move)
            replay.apply(move)
        }
        return moves
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(line.eco) · \(line.name)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(line.description)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ChessBoardView(board: board,
                                   orientation: .white,
                                   lastMove: lastMove,
                                   arrows: [],
                                   theme: BoardTheme.theme(for: settings.settings.boardTheme),
                                   pieceStyle: settings.settings.pieceStyle,
                                   arrowPalette: ArrowPalette.palette(for: settings.settings.arrowPalette),
                                   showCoordinates: true,
                                   showsLegalMoves: settings.settings.showLegalMoves,
                                   interactive: !finished,
                                   animate: settings.settings.animateMoves,
                                   onMove: { move in handle(move) })

                    HStack(spacing: 8) {
                        ProgressView(value: Double(moveIndex),
                                     total: Double(max(1, expectedMoves.count)))
                            .tint(Theme.accent)
                        Text("\(moveIndex)/\(expectedMoves.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let feedback = feedback {
                        HStack(spacing: 8) {
                            Image(systemName: feedbackIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(feedbackIsError ? Theme.error : Theme.accent)
                            Text(feedback)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill((feedbackIsError ? Theme.error : Theme.accent).opacity(0.12))
                        )
                    }

                    HStack(spacing: 10) {
                        Button("Neustart") { restart() }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Zug zeigen") { playNextAutomatically() }
                            .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button("Schließen") { dismiss() }
                            .buttonStyle(SecondaryButtonStyle())
                    }

                    Text("Du spielst Weiß. Die Gegnerzüge werden automatisch gespielt.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Linie trainieren")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { board = Board() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Logic

    private func restart() {
        board = Board()
        moveIndex = 0
        lastMove = nil
        feedback = nil
        feedbackIsError = false
        finished = false
    }

    private func handle(_ move: Move) {
        let moves = expectedMoves
        guard moves.indices.contains(moveIndex) else { return }
        guard move == moves[moveIndex] else {
            feedback = "Dieser Zug gehört nicht zu \(line.name). Erwartet: \(line.moves[safe: moveIndex] ?? "–")"
            feedbackIsError = true
            return
        }
        apply(move)
    }

    private func apply(_ move: Move) {
        guard board.isLegal(move) else { return }
        lastMove = move
        board.apply(move)
        moveIndex += 1
        feedback = nil
        feedbackIsError = false

        if moveIndex >= expectedMoves.count {
            finish()
            return
        }

        // The opponent replies automatically.
        if board.sideToMove == .black {
            let reply = expectedMoves[moveIndex]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard board.isLegal(reply) else { return }
                lastMove = reply
                board.apply(reply)
                moveIndex += 1
                if moveIndex >= expectedMoves.count {
                    finish()
                }
            }
        }
    }

    private func playNextAutomatically() {
        guard expectedMoves.indices.contains(moveIndex) else { return }
        apply(expectedMoves[moveIndex])
    }

    private func finish() {
        finished = true
        feedback = "Linie abgeschlossen – gut gespielt!"
        feedbackIsError = false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
