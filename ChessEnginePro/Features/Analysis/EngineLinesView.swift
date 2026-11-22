//
//  EngineLinesView.swift
//  CHESS ENGINE PRO
//
//  A single engine variant row plus the arrow legend.
//

import SwiftUI

struct CandidateRow: View {

    let candidate: CandidateMove
    let arrowHidden: Bool
    let isPreviewing: Bool
    var onSelect: () -> Void
    var onToggleArrow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(candidate.rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(candidate.rank == 1 ? Theme.accent : Theme.secondaryText)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.san)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    QualityBadge(quality: candidate.quality, compact: true)
                    if candidate.rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(candidate.pvSAN.prefix(6).joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if !candidate.tags.isEmpty {
                    Text(candidate.tags.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(candidate.score.display)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(candidate.score.whiteCentipawns >= 0 ? Theme.text : Theme.secondaryText)
                StyleFitBar(value: candidate.styleFit)
            }
            .frame(width: 54)

            Button(action: onToggleArrow) {
                Image(systemName: arrowHidden ? "eye.slash" : "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(arrowHidden ? Theme.secondaryText : Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.field))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pfeil ein- oder ausblenden")
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPreviewing ? Theme.accent.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct StyleFitBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.field)
                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: max(3, proxy.size.width * value / 100))
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Stilpassung \(Int(value)) Prozent")
    }
}

struct ArrowLegend: View {
    let palette: ArrowPalette

    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: palette.best, title: "Bester Zug")
            legendItem(color: palette.alternative, title: "Alternative")
            legendItem(color: palette.interesting, title: "Interessant")
            legendItem(color: palette.critical, title: "Kritisch")
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
