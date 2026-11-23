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
    var animatesArrows: Bool = true
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
                              showLabels: showArrowLabels,
                              animates: animatesArrows)
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
                PieceGlyph(piece: item.piece, style: pieceStyle, size: squareSize * 0.86)
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

/// Draws the engine arrows with a short draw-in animation, so a new position
/// and its new variants are visually traceable.
struct ArrowRenderer: View {
    let arrows: [BoardArrow]
    let orientation: PieceColor
    let palette: ArrowPalette
    let squareSize: CGFloat
    var showLabels: Bool = false
    var animates: Bool = true

    @State private var reveal: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(arrows) { arrow in
                ArrowBody(arrow: arrow,
                          orientation: orientation,
                          color: palette.color(for: arrow.kind),
                          reveal: reveal)
            }

            if showLabels {
                ForEach(arrows) { arrow in
                    if let label = arrow.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: squareSize * 0.22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            .position(labelPoint(for: arrow))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { restart() }
        .onChange(of: arrows) { _, _ in restart() }
    }

    private func restart() {
        guard animates else {
            reveal = 1
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { reveal = 0 }
        withAnimation(.easeOut(duration: 0.34)) { reveal = 1 }
    }

    private func point(_ square: Square) -> CGPoint {
        let file = orientation == .white ? square.file : 7 - square.file
        let rank = orientation == .white ? 7 - square.rank : square.rank
        return CGPoint(x: (CGFloat(file) + 0.5) * squareSize,
                       y: (CGFloat(rank) + 0.5) * squareSize)
    }

    private func labelPoint(for arrow: BoardArrow) -> CGPoint {
        let from = point(arrow.from)
        let to = point(arrow.to)
        return CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - squareSize * 0.16)
    }
}

private struct ArrowBody: View {
    let arrow: BoardArrow
    let orientation: PieceColor
    let color: Color
    let reveal: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 8
            let geometry = ArrowGeometry(arrow: arrow, orientation: orientation, unit: unit)

            ZStack {
                ArrowShaft(start: geometry.start, end: geometry.end, reveal: reveal)
                    .stroke(color.opacity(0.9),
                            style: StrokeStyle(lineWidth: unit * 0.13, lineCap: .round))

                ArrowHead(tip: geometry.end,
                          base: geometry.base,
                          perpendicular: geometry.perpendicular,
                          halfWidth: unit * 0.18)
                    .fill(color.opacity(0.9))
                    .opacity(Double(min(1, max(0, (reveal - 0.5) / 0.5))))
            }
        }
    }
}

private struct ArrowGeometry {
    var start: CGPoint
    var end: CGPoint
    var base: CGPoint
    var perpendicular: CGPoint

    init(arrow: BoardArrow, orientation: PieceColor, unit: CGFloat) {
        func center(_ square: Square) -> CGPoint {
            let file = orientation == .white ? square.file : 7 - square.file
            let rank = orientation == .white ? 7 - square.rank : square.rank
            return CGPoint(x: (CGFloat(file) + 0.5) * unit,
                           y: (CGFloat(rank) + 0.5) * unit)
        }

        let from = center(arrow.from)
        let to = center(arrow.to)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let unitX = dx / length
        let unitY = dy / length

        start = CGPoint(x: from.x + unitX * unit * 0.30,
                        y: from.y + unitY * unit * 0.30)
        end = CGPoint(x: to.x - unitX * unit * 0.26,
                      y: to.y - unitY * unit * 0.26)
        base = CGPoint(x: end.x - unitX * unit * 0.32,
                       y: end.y - unitY * unit * 0.32)
        perpendicular = CGPoint(x: -unitY, y: unitX)
    }
}

private struct ArrowShaft: Shape {
    var start: CGPoint
    var end: CGPoint
    var reveal: CGFloat

    var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * reveal,
                                 y: start.y + (end.y - start.y) * reveal))
        return path
    }
}

private struct ArrowHead: Shape {
    var tip: CGPoint
    var base: CGPoint
    var perpendicular: CGPoint
    var halfWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + perpendicular.x * halfWidth,
                                 y: base.y + perpendicular.y * halfWidth))
        path.addLine(to: CGPoint(x: base.x - perpendicular.x * halfWidth,
                                 y: base.y - perpendicular.y * halfWidth))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pieces

/// Chess.com style piece rendering.
///
/// The solid Unicode set paints the silhouette, the outline set is stacked on
/// top for the Staunton contour. White pieces are therefore really white (ivory
/// body, dark edge) instead of a grey tint of the same shape, which is what made
/// white pawns look washed out on the green board.
private struct PieceGlyph: View {
    let piece: Piece
    let style: PieceStyleID
    let size: CGFloat

    private var isWhite: Bool { piece.color == .white }

    private var contourColor: Color {
        isWhite ? Color(hex: 0x1B1F27) : Color(hex: 0x5A636F)
    }

    private var flatColor: Color {
        isWhite ? Color(hex: 0xF8F4E9) : Color(hex: 0x1C2026)
    }

    private var bodyStyle: AnyShapeStyle {
        if isWhite {
            return AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xEDE6D6)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
        }
        return AnyShapeStyle(
            LinearGradient(colors: [Color(hex: 0x3B434E), Color(hex: 0x14181D)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
    }

    var body: some View {
        ZStack {
            if style == .outline {
                Text(piece.glyph(style: .outline))
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(isWhite ? Color(hex: 0xF1EADB) : Color(hex: 0x20242B))
            } else {
                Text(piece.glyph(style: .neo))
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(style == .classic ? AnyShapeStyle(flatColor) : bodyStyle)
                Text(piece.glyph(style: .classic))
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(contourColor)
                    .opacity(style == .classic ? 0.95 : 0.85)
            }
        }
        .shadow(color: .black.opacity(isWhite ? 0.45 : 0.3), radius: 1.3, x: 0, y: 1.1)
    }
}
