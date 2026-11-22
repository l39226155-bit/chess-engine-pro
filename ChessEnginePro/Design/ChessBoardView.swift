//
//  ChessBoardView.swift
//  CHESS ENGINE PRO
//
//  Premium interactive board: tap to move, legal move hints, last move
//  highlight, check highlight, animated pieces and engine arrows.
//

import SwiftUI

struct ChessBoardView: View {

    var board: Board
    var orientation: PieceColor = .white
    var lastMove: Move?
    var arrows: [BoardArrow] = []
    var theme: BoardTheme = BoardTheme.theme(for: .green)
    var pieceStyle: PieceStyleID = .neo
    var arrowPalette: ArrowPalette = ArrowPalette.palette(for: .classic)
    var showCoordinates: Bool = true
    var showsLegalMoves: Bool = true
    var showArrowLabels: Bool = false
    var interactive: Bool = true
    var animate: Bool = true
    /// Providing this handler switches the board into editing mode.
    var onSquareTap: ((Square) -> Void)?
    var onMove: ((Move) -> Void)?

    @State private var selected: Square?
    @State private var promotionRequest: PromotionRequest?
    @State private var animatedPieces: [AnimatedPiece] = []

    private struct AnimatedPiece: Identifiable, Hashable {
        let id: UUID
        var square: Square
        var piece: Piece
    }

    private struct PromotionRequest: Identifiable {
        let id = UUID()
        let from: Square
        let to: Square
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let squareSize = size / 8

            ZStack {
                squaresLayer(squareSize: squareSize)
                highlightLayer(squareSize: squareSize)
                piecesLayer(squareSize: squareSize)
                if showsLegalMoves, let selected = selected {
                    legalMovesLayer(from: selected, squareSize: squareSize)
                }
                ArrowRenderer(arrows: arrows,
                              orientation: orientation,
                              palette: arrowPalette,
                              squareSize: squareSize,
                              showLabels: showArrowLabels)
                if showCoordinates {
                    coordinatesLayer(squareSize: squareSize)
                }
                tapLayer(squareSize: squareSize)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.24), value: orientation)
        .confirmationDialog("Umwandlung",
                            isPresented: promotionBinding,
                            presenting: promotionRequest) { request in
            ForEach(PieceKind.promotionChoices, id: \.self) { kind in
                Button(kind.localizedName) {
                    if let move = board.legalMoves(from: request.from)
                        .first(where: { $0.to == request.to && $0.promotion == kind }) {
                        commit(move)
                    }
                    promotionRequest = nil
                }
            }
            Button("Abbrechen", role: .cancel) { promotionRequest = nil }
        }
        .onAppear { syncPieces(animated: false) }
        .onChange(of: board.fen) { _, _ in syncPieces(animated: true) }
    }

    private var promotionBinding: Binding<Bool> {
        Binding(get: { promotionRequest != nil }, set: { if !$0 { promotionRequest = nil } })
    }

    // MARK: - Layers

    private func squaresLayer(squareSize: CGFloat) -> some View {
        ZStack {
            ForEach(Square.all, id: \.index) { square in
                Rectangle()
                    .fill(square.isLightSquare ? theme.light : theme.dark)
                    .frame(width: squareSize + 0.4, height: squareSize + 0.4)
                    .position(point(for: square, squareSize: squareSize))
            }
        }
    }

    private func highlightLayer(squareSize: CGFloat) -> some View {
        ZStack {
            if let lastMove = lastMove {
                highlight(square: lastMove.from, color: theme.highlight, squareSize: squareSize)
                highlight(square: lastMove.to, color: theme.highlight, squareSize: squareSize)
            }
            if let selected = selected {
                highlight(square: selected, color: theme.selection, squareSize: squareSize)
            }
            if board.isInCheck(board.sideToMove),
               let king = board.kingSquare(for: board.sideToMove) {
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: 0xE05B5B, opacity: 0.85),
                                                Color(hex: 0xE05B5B, opacity: 0.15)],
                                       center: .center,
                                       startRadius: 1,
                                       endRadius: squareSize * 0.5)
                    )
                    .frame(width: squareSize, height: squareSize)
                    .position(point(for: king, squareSize: squareSize))
                    .allowsHitTesting(false)
            }
        }
    }

    private func highlight(square: Square, color: Color, squareSize: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: squareSize, height: squareSize)
            .position(point(for: square, squareSize: squareSize))
            .allowsHitTesting(false)
    }

    private func piecesLayer(squareSize: CGFloat) -> some View {
        ZStack {
            ForEach(animatedPieces) { item in
                Text(item.piece.glyph(style: pieceStyle))
                    .font(.system(size: squareSize * 0.84, weight: .regular))
                    .foregroundStyle(item.piece.displayColor(style: pieceStyle))
                    .shadow(color: .black.opacity(item.piece.color == .white ? 0.55 : 0.35),
                            radius: 1.6, x: 0, y: 1.2)
                    .shadow(color: item.piece.color == .black ? Color.white.opacity(0.18) : Color.clear,
                            radius: 0.6)
                    .position(point(for: item.square, squareSize: squareSize))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func legalMovesLayer(from origin: Square, squareSize: CGFloat) -> some View {
        let moves = board.legalMoves(from: origin)
        var targets: Set<Int> = []
        for move in moves { targets.insert(move.to.index) }
        return ZStack {
            ForEach(Array(targets).sorted(), id: \.self) { index in
                let square = Square(index: index)
                let isCapture = board.squares[index] != nil
                Group {
                    if isCapture {
                        Circle()
                            .stroke(Theme.accent.opacity(0.85), lineWidth: squareSize * 0.07)
                            .frame(width: squareSize * 0.86, height: squareSize * 0.86)
                    } else {
                        Circle()
                            .fill(Theme.accent.opacity(0.38))
                            .frame(width: squareSize * 0.28, height: squareSize * 0.28)
                    }
                }
                .position(point(for: square, squareSize: squareSize))
                .allowsHitTesting(false)
            }
        }
    }

    private func coordinatesLayer(squareSize: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { file in
                let label = String(Character(UnicodeScalar(UInt8(97 + (orientation == .white ? file : 7 - file)))))
                Text(label)
                    .font(.system(size: max(7, squareSize * 0.19), weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.coordinate)
                    .position(x: (CGFloat(file) + 0.5) * squareSize,
                              y: 8 * squareSize - squareSize * 0.16)
                    .allowsHitTesting(false)
            }
            ForEach(0..<8, id: \.self) { row in
                let rank = orientation == .white ? 8 - row : row + 1
                Text("\(rank)")
                    .font(.system(size: max(7, squareSize * 0.19), weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.coordinate)
                    .position(x: squareSize * 0.16,
                              y: (CGFloat(row) + 0.5) * squareSize)
                    .allowsHitTesting(false)
            }
        }
    }

    private func tapLayer(squareSize: CGFloat) -> some View {
        ZStack {
            ForEach(Square.all, id: \.index) { square in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: squareSize, height: squareSize)
                    .position(point(for: square, squareSize: squareSize))
                    .onTapGesture { handleTap(square) }
            }
        }
    }

    // MARK: - Interaction

    private func handleTap(_ square: Square) {
        guard interactive else { return }
        if let onSquareTap = onSquareTap {
            onSquareTap(square)
            return
        }

        guard let piece = board[square] else {
            if let selected = selected, let move = resolveMove(from: selected, to: square) {
                commit(move)
            } else {
                selected = nil
            }
            return
        }

        if piece.color == board.sideToMove {
            selected = selected == square ? nil : square
            return
        }

        guard let selected = selected else { return }
        if let move = resolveMove(from: selected, to: square) {
            commit(move)
        } else {
            self.selected = nil
        }
    }

    private func resolveMove(from origin: Square, to target: Square) -> Move? {
        let moves = board.legalMoves(from: origin).filter { $0.to == target }
        guard !moves.isEmpty else { return nil }
        if moves.count > 1, moves.allSatisfy({ $0.promotion != nil }) {
            promotionRequest = PromotionRequest(from: origin, to: target)
            return nil
        }
        return moves.first
    }

    private func commit(_ move: Move) {
        selected = nil
        onMove?(move)
    }

    // MARK: - Geometry

    private func point(for square: Square, squareSize: CGFloat) -> CGPoint {
        let file = orientation == .white ? square.file : 7 - square.file
        let rank = orientation == .white ? 7 - square.rank : square.rank
        return CGPoint(x: (CGFloat(file) + 0.5) * squareSize,
                       y: (CGFloat(rank) + 0.5) * squareSize)
    }

    // MARK: - Piece animation identity

    private func syncPieces(animated: Bool) {
        var next: [AnimatedPiece] = []
        var pool = animatedPieces

        for index in 0..<64 {
            guard let piece = board.squares[index] else { continue }
            let square = Square(index: index)

            if let match = pool.firstIndex(where: { $0.square == square && $0.piece == piece }) {
                next.append(pool.remove(at: match))
                continue
            }

            if let lastMove = lastMove, square == lastMove.to,
               let match = pool.firstIndex(where: {
                   $0.square == lastMove.from && $0.piece.kind == piece.kind && $0.piece.color == piece.color
               }) {
                var moved = pool.remove(at: match)
                moved.square = square
                next.append(moved)
                continue
            }

            next.append(AnimatedPiece(id: UUID(), square: square, piece: piece))
        }

        if animated && animate {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                animatedPieces = next
            }
        } else {
            animatedPieces = next
        }
    }
}

// MARK: - Arrow renderer

struct ArrowRenderer: View {
    let arrows: [BoardArrow]
    let orientation: PieceColor
    let palette: ArrowPalette
    let squareSize: CGFloat
    var showLabels: Bool = false

    var body: some View {
        Canvas { context, size in
            for arrow in arrows {
                draw(arrow, context: &context, size: size)
            }
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }

    private func draw(_ arrow: BoardArrow, context: inout GraphicsContext, size: CGSize) {
        let from = point(arrow.from, size: size)
        let to = point(arrow.to, size: size)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let unitX = dx / length
        let unitY = dy / length

        let start = CGPoint(x: from.x + unitX * squareSize * 0.30,
                            y: from.y + unitY * squareSize * 0.30)
        let end = CGPoint(x: to.x - unitX * squareSize * 0.26,
                          y: to.y - unitY * squareSize * 0.26)

        let color = palette.color(for: arrow.kind)
        let lineWidth = squareSize * 0.13

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(shaft,
                       with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        let headLength = squareSize * 0.32
        let headWidth = squareSize * 0.18
        let perpendicular = CGPoint(x: -unitY, y: unitX)
        let base = CGPoint(x: end.x - unitX * headLength, y: end.y - unitY * headLength)

        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: base.x + perpendicular.x * headWidth,
                                 y: base.y + perpendicular.y * headWidth))
        head.addLine(to: CGPoint(x: base.x - perpendicular.x * headWidth,
                                 y: base.y - perpendicular.y * headWidth))
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(0.9)))

        if showLabels, let label = arrow.label, !label.isEmpty {
            let text = Text(label)
                .font(.system(size: squareSize * 0.22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            let midpoint = CGPoint(x: (start.x + end.x) / 2,
                                   y: (start.y + end.y) / 2 - squareSize * 0.16)
            context.draw(text, at: midpoint)
        }
    }

    private func point(_ square: Square, size: CGSize) -> CGPoint {
        let unit = size.width / 8
        let file = orientation == .white ? square.file : 7 - square.file
        let rank = orientation == .white ? 7 - square.rank : square.rank
        return CGPoint(x: (CGFloat(file) + 0.5) * unit, y: (CGFloat(rank) + 0.5) * unit)
    }
}
