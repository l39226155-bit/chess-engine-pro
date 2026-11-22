//
//  EnginePlayView.swift
//  CHESS ENGINE PRO
//
//  Play a full game against the local engine with adjustable strength.
//

import SwiftUI

@MainActor
final class EnginePlaySession: ObservableObject {

    @Published private(set) var board = Board()
    @Published private(set) var isThinking = false
    @Published private(set) var lastMove: Move?
    @Published private(set) var moveLog: [String] = []
    @Published private(set) var evaluation: EvalScore = .zero
    @Published private(set) var statusText = "Wähle eine Farbe und starte eine Partie."
    @Published private(set) var humanColor: PieceColor = .white
    @Published private(set) var isGameOver = false
    @Published private(set) var depth = 8

    private let engine: ChessEngine
    private var task: Task<Void, Never>?
    private var undoStack: [(board: Board, san: String)] = []

    init(engine: ChessEngine) {
        self.engine = engine
    }

    var canInteract: Bool {
        !isThinking && !isGameOver && board.sideToMove == humanColor
    }

    var engineName: String { engine.displayName }

    func newGame(humanColor: PieceColor, depth: Int) {
        task?.cancel()
        engine.stop()
        engine.setOption("MultiPV", value: "1")
        board = Board()
        lastMove = nil
        moveLog = []
        undoStack = []
        evaluation = .zero
        isGameOver = false
        isThinking = false
        self.humanColor = humanColor
        self.depth = max(1, depth)
        statusText = "Du spielst \(humanColor.localizedName) – viel Erfolg!"

        if humanColor == .black {
            requestEngineMove()
        }
    }

    func play(_ move: Move) {
        guard canInteract, board.isLegal(move) else { return }
        let san = board.san(for: move)
        undoStack.append((board, san))
        moveLog.append(san)
        board.apply(move)
        lastMove = move

        if board.isGameOver {
            isGameOver = true
            statusText = board.status.localizedDescription
            return
        }
        requestEngineMove()
    }

    func undo() {
        guard !isThinking, !undoStack.isEmpty else { return }
        task?.cancel()
        engine.stop()

        var restored: Board?
        var removed = 0
        while removed < 2, let entry = undoStack.popLast() {
            restored = entry.board
            if !moveLog.isEmpty { moveLog.removeLast() }
            removed += 1
            if entry.board.sideToMove == humanColor { break }
        }
        guard let boardValue = restored else { return }
        board = boardValue
        lastMove = nil
        evaluation = .zero
        isGameOver = false
        statusText = "Zug zurückgenommen"
        if board.sideToMove != humanColor, !board.isGameOver {
            requestEngineMove()
        }
    }

    func resign() {
        task?.cancel()
        engine.stop()
        isThinking = false
        isGameOver = true
        statusText = "Partie aufgegeben."
    }

    func stop() {
        task?.cancel()
        engine.stop()
        isThinking = false
    }

    // MARK: - Engine

    private func requestEngineMove() {
        if board.isGameOver {
            isGameOver = true
            statusText = board.status.localizedDescription
            return
        }
        isThinking = true
        statusText = "\(engine.displayName) rechnet …"
        let fen = board.fen
        let limits = EngineLimits.depth(max(1, depth), multiPV: 1)

        task = Task { [weak self] in
            guard let self = self else { return }
            var bestMove: Move?
            for await update in self.engine.analyze(fen: fen, limits: limits) {
                if Task.isCancelled { break }
                if let score = update.lines.first?.score {
                    self.evaluation = score
                }
                if update.isFinal {
                    bestMove = update.bestMove ?? update.lines.first?.firstMove
                    break
                }
            }
            if Task.isCancelled {
                self.isThinking = false
                return
            }
            guard let reply = bestMove, self.board.isLegal(reply) else {
                self.isThinking = false
                self.statusText = "Keine Antwort gefunden."
                return
            }
            let san = self.board.san(for: reply)
            self.undoStack.append((self.board, san))
            self.board.apply(reply)
            self.lastMove = reply
            self.moveLog.append(san)
            self.isThinking = false
            if self.board.isGameOver {
                self.isGameOver = true
                self.statusText = self.board.status.localizedDescription
            } else {
                self.statusText = "Du bist am Zug"
            }
        }
    }
}

// MARK: - View

struct EnginePlayView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var stats: TrainingStatsStore

    @StateObject private var session = EnginePlaySession(
        engine: StockfishBuild.isLinked
            ? (StockfishEngine.shared as ChessEngine)
            : (FallbackEngine() as ChessEngine)
    )

    @State private var selectedColor: PieceColor = .white
    @State private var strength: Int = 8
    @State private var gameStarted = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if gameStarted {
                        gameContent
                    } else {
                        setupContent
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Gegen die Engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { environment.analysis.stop() }
        .onDisappear { session.stop() }
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Partie gegen \(session.engineName)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Die Engine läuft vollständig lokal. Stelle deine Farbe und die Spielstärke ein.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .premiumCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("Deine Farbe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Farbe", selection: $selectedColor) {
                    Text("Weiß").tag(PieceColor.white)
                    Text("Schwarz").tag(PieceColor.black)
                }
                .pickerStyle(.segmented)

                DividerLine()

                SettingsRow(title: "Suchtiefe", subtitle: "Höher = stärkerer Gegner", icon: "gauge.with.dots.needle.67percent") {
                    Stepper("\(strength)", value: $strength, in: 1...20)
                        .labelsHidden()
                        .fixedSize()
                }

                Button {
                    environment.analysis.stop()
                    session.newGame(humanColor: selectedColor, depth: strength)
                    stats.recordGame()
                    gameStarted = true
                } label: {
                    Label("Partie starten", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .premiumCard()
        }
    }

    // MARK: - Game

    private var gameContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isThinking ? Theme.accent : Theme.secondaryText)
                    .frame(width: 6, height: 6)
                Text(session.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer()
                Text(session.evaluation.display)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.panel))
            }

            ChessBoardView(board: session.board,
                           orientation: session.humanColor,
                           lastMove: session.lastMove,
                           arrows: [],
                           theme: BoardTheme.theme(for: settings.settings.boardTheme),
                           pieceStyle: settings.settings.pieceStyle,
                           arrowPalette: ArrowPalette.palette(for: settings.settings.arrowPalette),
                           showCoordinates: true,
                           showsLegalMoves: settings.settings.showLegalMoves,
                           interactive: session.canInteract,
                           animate: settings.settings.animateMoves,
                           onMove: { move in session.play(move) })

            HStack(spacing: 8) {
                Button {
                    session.undo()
                } label: {
                    Label("Zurück", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    session.resign()
                } label: {
                    Label("Aufgeben", systemImage: "flag.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button {
                    gameStarted = false
                    session.stop()
                } label: {
                    Label("Neu", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if session.isGameOver {
                Text(session.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .premiumCard(padding: 12, radius: 12)
            }

            if !session.moveLog.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(session.moveLog.enumerated()), id: \.offset) { index, san in
                            HStack(spacing: 3) {
                                if index % 2 == 0 {
                                    Text("\(index / 2 + 1).")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Text(san)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.field))
                        }
                    }
                }
            }
        }
    }
}
