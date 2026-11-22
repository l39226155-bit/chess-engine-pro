//
//  PositionEditorView.swift
//  CHESS ENGINE PRO
//
//  Build custom positions by tapping squares, or paste a FEN.
//

import SwiftUI
import UIKit

struct PositionEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var board: Board
    @State private var selectedPiece: Piece?
    @State private var fenText: String
    @State private var errorMessage: String?

    var onApply: (Board) -> Void

    init(initialBoard: Board, onApply: @escaping (Board) -> Void) {
        _board = State(initialValue: initialBoard)
        _fenText = State(initialValue: initialBoard.fen)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ChessBoardView(board: board,
                                   orientation: .white,
                                   lastMove: nil,
                                   arrows: [],
                                   theme: BoardTheme.theme(for: settings.settings.boardTheme),
                                   pieceStyle: settings.settings.pieceStyle,
                                   arrowPalette: ArrowPalette.palette(for: settings.settings.arrowPalette),
                                   showCoordinates: true,
                                   showsLegalMoves: false,
                                   interactive: true,
                                   animate: false,
                                   onSquareTap: { square in edit(square) })

                    paletteCard
                    sideToMoveCard
                    fenCard

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.error)
                    }

                    HStack(spacing: 10) {
                        Button {
                            apply()
                        } label: {
                            Label("Stellung übernehmen", systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            board = Board.empty
                            board.castling = .none
                            selectedPiece = nil
                            syncFEN()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(IconButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Stellung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        board = Board()
                        selectedPiece = nil
                        syncFEN()
                    } label: {
                        Text("Startposition").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var paletteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Figur auswählen")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                paletteButton(nil)
                ForEach(PieceKind.allCases, id: \.self) { kind in
                    paletteButton(Piece(color: .white, kind: kind))
                }
            }
            HStack(spacing: 6) {
                Spacer().frame(width: 40)
                ForEach(PieceKind.allCases, id: \.self) { kind in
                    paletteButton(Piece(color: .black, kind: kind))
                }
            }
            Text("Auswahl: \(selectedPiece?.kind.localizedName ?? "Löschen")")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .premiumCard(padding: 14, radius: 16)
    }

    private func paletteButton(_ piece: Piece?) -> some View {
        let isSelected = selectedPiece?.color == piece?.color && selectedPiece?.kind == piece?.kind
        return Button {
            selectedPiece = piece
        } label: {
            Group {
                if let piece = piece {
                    Text(piece.glyph(style: settings.settings.pieceStyle))
                        .font(.system(size: 21))
                        .foregroundStyle(piece.displayColor(style: settings.settings.pieceStyle))
                } else {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 33, height: 33)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.25) : Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sideToMoveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Am Zug")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Picker("Am Zug", selection: Binding(
                get: { board.sideToMove },
                set: { board.sideToMove = $0; syncFEN() }
            )) {
                Text("Weiß").tag(PieceColor.white)
                Text("Schwarz").tag(PieceColor.black)
            }
            .pickerStyle(.segmented)
        }
        .premiumCard(padding: 14, radius: 16)
    }

    private var fenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FEN")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            TextField("FEN", text: $fenText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
            HStack(spacing: 8) {
                Button("FEN laden") {
                    guard let parsed = Board(fen: fenText) else {
                        errorMessage = "Ungültige FEN."
                        return
                    }
                    board = parsed
                    errorMessage = nil
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("FEN kopieren") {
                    UIPasteboard.general.string = board.fen
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .premiumCard(padding: 14, radius: 16)
    }

    // MARK: - Editing

    private func edit(_ square: Square) {
        if let piece = selectedPiece {
            board[square] = piece
        } else {
            board[square] = nil
        }
        board.castling = .none
        board.enPassant = nil
        board.halfmoveClock = 0
        errorMessage = nil
        syncFEN()
    }

    private func syncFEN() {
        fenText = board.fen
    }

    private func apply() {
        guard board.kingSquare(for: .white) != nil, board.kingSquare(for: .black) != nil else {
            errorMessage = "Beide Könige müssen auf dem Brett stehen."
            return
        }
        // Ensure the side that is not to move is not already in check.
        if board.isInCheck(board.sideToMove.opponent) {
            errorMessage = "Die Seite, die nicht am Zug ist, darf nicht im Schach stehen."
            return
        }
        onApply(board)
        dismiss()
    }
}
