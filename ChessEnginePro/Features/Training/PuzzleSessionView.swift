//
//  PuzzleSessionView.swift
//  CHESS ENGINE PRO
//
//  Solves bundled puzzles: the app validates every move against the
//  verified solution and plays the forced replies.
//

import SwiftUI

struct PuzzleSessionView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: TrainingStatsStore

    let puzzles: [TrainingPuzzle]
    let category: PuzzleCategory

    @State private var index: Int = 0
    @State private var board = Board()
    @State private var stepIndex = 0
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var solved = false
    @State private var showHint = false
    @State private var recorded = false
    @State private var lastMove: Move?

    var body: some View {
        NavigationStack {
            Group {
                if puzzles.isEmpty {
                    EmptyStateView(icon: "tray",
                                   title: "Keine Aufgaben",
                                   message: "Für diese Kategorie sind keine Aufgaben hinterlegt.")
                        .padding(24)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(current.map { _ in "\(index + 1)/\(puzzles.count)" } ?? "–")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { load(index: min(index, max(0, puzzles.count - 1))) }
    }

    private var current: TrainingPuzzle? {
        guard puzzles.indices.contains(index) else { return nil }
        return puzzles[index]
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if let puzzle = current {
                    header(puzzle)
                    ChessBoardView(board: board,
                                   orientation: puzzle.sideToMove,
                                   lastMove: lastMove,
                                   arrows: [],
                                   theme: BoardTheme.theme(for: settings.settings.boardTheme),
                                   pieceStyle: settings.settings.pieceStyle,
                                   arrowPalette: ArrowPalette.palette(for: settings.settings.arrowPalette),
                                   showCoordinates: true,
                                   showsLegalMoves: settings.settings.showLegalMoves,
                                   interactive: !solved,
                                   animate: settings.settings.animateMoves,
                                   onMove: { move in handle(move, puzzle: puzzle) })

                    .disabled(solved)

                    feedbackView(puzzle)
                    controls(puzzle)
                }
            }
            .padding(16)
        }
    }

    private func header(_ puzzle: TrainingPuzzle) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(puzzle.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("\(puzzle.sideToMove.localizedName) am Zug · \(puzzle.theme)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Schwierigkeit")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                Text(puzzle.difficultyText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func feedbackView(_ puzzle: TrainingPuzzle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let feedback = feedback {
                HStack(spacing: 8) {
                    Image(systemName: feedbackIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedbackIsError ? Theme.error : Theme.accent)
                    Text(feedback)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(feedbackIsError ? Theme.error.opacity(0.12) : Theme.accent.opacity(0.12))
                )
            }
            if showHint {
                Text("Hinweis: \(puzzle.hint)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func controls(_ puzzle: TrainingPuzzle) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showHint = true
                } label: {
                    Label("Hinweis", systemImage: "lightbulb")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    revealSolution(puzzle)
                } label: {
                    Label("Lösung", systemImage: "eye")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button {
                    advance()
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(IconButtonStyle())
            }

            if solved {
                Button {
                    advance()
                } label: {
                    Label("Nächste Aufgabe", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Logic

    private func load(index newIndex: Int) {
        guard puzzles.indices.contains(newIndex) else { return }
        index = newIndex
        let puzzle = puzzles[newIndex]
        board = Board(fen: puzzle.fen) ?? Board()
        stepIndex = 0
        solved = false
        feedback = nil
        feedbackIsError = false
        showHint = false
        recorded = false
        lastMove = nil
    }

    private func advance() {
        if index + 1 < puzzles.count {
            load(index: index + 1)
        } else {
            load(index: 0)
        }
    }

    private func handle(_ move: Move, puzzle: TrainingPuzzle) {
        guard !solved, stepIndex < puzzle.solution.count else { return }
        guard let expected = Move(uci: puzzle.solution[stepIndex]) else { return }

        guard move == expected else {
            feedback = "Dieser Zug löst die Aufgabe nicht. Versuche es erneut."
            feedbackIsError = true
            if !recorded {
                recorded = true
                stats.recordPuzzle(solved: false)
            }
            return
        }

        lastMove = move
        board.apply(move)
        stepIndex += 1
        feedbackIsError = false

        if stepIndex >= puzzle.solution.count {
            finishSolution(puzzle)
            return
        }

        feedback = "Richtig! Die Antwort folgt …"
        let reply = puzzle.solution[stepIndex]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let replyMove = Move(uci: reply), board.isLegal(replyMove) else { return }
            board.apply(replyMove)
            lastMove = replyMove
            stepIndex += 1
            if stepIndex >= puzzle.solution.count {
                finishSolution(puzzle)
            } else {
                feedback = "Weiter – finde den nächsten Zug."
            }
        }
    }

    private func finishSolution(_ puzzle: TrainingPuzzle) {
        solved = true
        feedback = "Gelöst: \(puzzle.title)"
        feedbackIsError = false
        if !recorded {
            recorded = true
            stats.recordPuzzle(solved: true)
        }
    }

    private func revealSolution(_ puzzle: TrainingPuzzle) {
        guard let start = Board(fen: puzzle.fen) else { return }
        var replay = start
        var last: Move?
        for uci in puzzle.solution {
            guard let move = Move(uci: uci), replay.isLegal(move) else { break }
            replay.apply(move)
            last = move
        }
        board = replay
        lastMove = last
        solved = true
        let solutionSAN = start.sanSequence(fromUCI: puzzle.solution).joined(separator: " ")
        feedback = solutionSAN.isEmpty ? "Lösung angezeigt." : "Lösung: \(solutionSAN)"
        feedbackIsError = false
        if !recorded {
            recorded = true
            stats.recordPuzzle(solved: false)
        }
    }
}
