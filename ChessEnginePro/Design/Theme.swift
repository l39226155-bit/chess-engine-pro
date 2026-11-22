//
//  Theme.swift
//  CHESS ENGINE PRO
//
//  Central design tokens: dark premium palette, spacing, typography,
//  board themes, piece glyphs and arrow palettes.
//

import SwiftUI

// MARK: - Color helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Theme

enum Theme {
    static let background = Color(hex: 0x0B0D10)
    static let secondaryBackground = Color(hex: 0x101318)
    static let card = Color(hex: 0x171B22)
    static let panel = Color(hex: 0x1D222B)
    static let field = Color(hex: 0x14181F)
    static let accent = Color(hex: 0x81B64C)
    static let accentMuted = Color(hex: 0x81B64C, opacity: 0.16)
    static let text = Color(hex: 0xF5F5F5)
    static let secondaryText = Color(hex: 0x9299A5)
    static let divider = Color(hex: 0xFFFFFF, opacity: 0.06)
    static let error = Color(hex: 0xE05B5B)
    static let warning = Color(hex: 0xE0A65B)
    static let info = Color(hex: 0x5B9BE0)

    static let cardRadius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let padding: CGFloat = 16

    static func qualityColor(_ quality: MoveQuality) -> Color {
        switch quality {
        case .excellent: return Color(hex: 0x81B64C)
        case .veryGood: return Color(hex: 0x9BC46A)
        case .good: return Color(hex: 0xB8CF95)
        case .interesting: return Color(hex: 0x5B9BE0)
        case .inaccuracy: return Color(hex: 0xE8BE5B)
        case .mistake: return Color(hex: 0xE08A4A)
        case .blunder: return Color(hex: 0xE05B5B)
        }
    }
}

// MARK: - Card styling

struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.padding
    var radius: CGFloat = Theme.cardRadius
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
            )
    }
}

extension View {
    func premiumCard(padding: CGFloat = Theme.padding,
                     radius: CGFloat = Theme.cardRadius,
                     fill: Color = Theme.card) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, fill: fill))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: 0x0B0D10))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
                    .opacity(configuration.isPressed ? 0.65 : 1)
            )
    }
}

// MARK: - Board themes

struct BoardTheme {
    let light: Color
    let dark: Color
    let highlight: Color
    let selection: Color
    let coordinate: Color

    static func theme(for id: BoardThemeID) -> BoardTheme {
        switch id {
        case .green:
            return BoardTheme(light: Color(hex: 0xEBECD0),
                              dark: Color(hex: 0x739552),
                              highlight: Color(hex: 0xF7F769, opacity: 0.45),
                              selection: Color(hex: 0x81B64C, opacity: 0.55),
                              coordinate: Color(hex: 0x1D222B, opacity: 0.55))
        case .blue:
            return BoardTheme(light: Color(hex: 0xDEE3E6),
                              dark: Color(hex: 0x4B7399),
                              highlight: Color(hex: 0xFFE45C, opacity: 0.45),
                              selection: Color(hex: 0x5B9BE0, opacity: 0.55),
                              coordinate: Color(hex: 0x101318, opacity: 0.55))
        case .graphite:
            return BoardTheme(light: Color(hex: 0xB9C0C8),
                              dark: Color(hex: 0x5A6472),
                              highlight: Color(hex: 0xF5F5F5, opacity: 0.35),
                              selection: Color(hex: 0x81B64C, opacity: 0.5),
                              coordinate: Color(hex: 0x101318, opacity: 0.6))
        case .wood:
            return BoardTheme(light: Color(hex: 0xE8D3B0),
                              dark: Color(hex: 0xA97D52),
                              highlight: Color(hex: 0xFFD966, opacity: 0.4),
                              selection: Color(hex: 0x81B64C, opacity: 0.5),
                              coordinate: Color(hex: 0x3B2A1A, opacity: 0.6))
        case .violet:
            return BoardTheme(light: Color(hex: 0xDDD6E8),
                              dark: Color(hex: 0x7A6A9B),
                              highlight: Color(hex: 0xFFE45C, opacity: 0.4),
                              selection: Color(hex: 0xC2A6F0, opacity: 0.55),
                              coordinate: Color(hex: 0x1D1826, opacity: 0.6))
        }
    }
}

// MARK: - Arrow palette

struct ArrowPalette {
    let best: Color
    let alternative: Color
    let interesting: Color
    let critical: Color

    func color(for kind: BoardArrow.Kind) -> Color {
        switch kind {
        case .best: return best
        case .alternative: return alternative
        case .interesting: return interesting
        case .critical: return critical
        }
    }

    static func palette(for id: ArrowPaletteID) -> ArrowPalette {
        switch id {
        case .classic:
            return ArrowPalette(best: Color(hex: 0x81B64C),
                                alternative: Color(hex: 0x4A9BE8),
                                interesting: Color(hex: 0xE8C24A),
                                critical: Color(hex: 0xE05B5B))
        case .vivid:
            return ArrowPalette(best: Color(hex: 0x3DDC84),
                                alternative: Color(hex: 0x35C4F0),
                                interesting: Color(hex: 0xFFB020),
                                critical: Color(hex: 0xFF5E7A))
        case .colorblind:
            return ArrowPalette(best: Color(hex: 0x4C9BE8),
                                alternative: Color(hex: 0xF5A623),
                                interesting: Color(hex: 0x2FBF9B),
                                critical: Color(hex: 0xD55E00))
        }
    }
}

// MARK: - Pieces

extension Piece {
    /// Unicode chess glyph for the piece.
    /// The solid set (U+265A...) and the outline set (U+2654...) are both used;
    /// the colour is applied by the view.
    func glyph(style: PieceStyleID) -> String {
        let base: UInt32 = style.usesOutlineGlyphs ? 0x2654 : 0x265A
        let offset: UInt32
        switch kind {
        case .king: offset = 0
        case .queen: offset = 1
        case .rook: offset = 2
        case .bishop: offset = 3
        case .knight: offset = 4
        case .pawn: offset = 5
        }
        guard let scalar = UnicodeScalar(base + offset) else { return "?" }
        return String(Character(scalar))
    }

    func displayColor(style: PieceStyleID) -> Color {
        if color == .white {
            return Color(hex: 0xF8F8F8)
        }
        return style.usesOutlineGlyphs ? Color(hex: 0x1B1F27) : Color(hex: 0x232830)
    }
}
