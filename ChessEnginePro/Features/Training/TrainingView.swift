//
//  TrainingView.swift
//  CHESS ENGINE PRO
//
//  Training hub: tactics, mates, openings, endgames, engine games and
//  game review.
//

import SwiftUI

enum TrainingRoute: Identifiable, Hashable {
    case puzzles(PuzzleCategory)
    case openings
    case playEngine
    case editor
    case review

    var id: String {
        switch self {
        case .puzzles(let category): return "puzzle-\(category.rawValue)"
        case .openings: return "openings"
        case .playEngine: return "play-engine"
        case .editor: return "editor"
        case .review: return "review"
        }
    }
}

struct TrainingView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: TrainingStatsStore

    @StateObject private var puzzles = PuzzleLibrary.shared
    @StateObject private var openings = OpeningLibrary.shared

    @State private var route: TrainingRoute?
    @State private var showImporter = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                streakCard
                section(title: "Matt-Aufgaben", routes: [
                    .puzzles(.mate1), .puzzles(.mate2), .puzzles(.mate3)
                ])
                section(title: "Taktik & Technik", routes: [
                    .puzzles(.tactics), .puzzles(.endgame), .puzzles(.defense)
                ])
                specials
                if let error = puzzles.loadError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .background(Theme.background)
        .sheet(item: $route) { route in
            destination(for: route)
        }
        .pgnImporter(isPresented: $showImporter) { game in
            route = nil
            environment.openInAnalysis(game: game)
        } onError: { message in
            environment.showToast(message)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Training")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Taktik, Eröffnungen, Endspiele und eigene Stellungen")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var streakCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Deine Serie")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text("\(stats.stats.streak) Tage")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("\(stats.stats.puzzlesSolved) von \(stats.stats.puzzlesAttempted) Aufgaben gelöst")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            ZStack {
                Circle().fill(Theme.accent.opacity(0.14)).frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
            }
        }
        .premiumCard()
    }

    private func section(title: String, routes: [TrainingRoute]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(routes) { item in
                    if let category = category(of: item) {
                        Button {
                            route = item
                        } label: {
                            modeCard(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func modeCard(category: PuzzleCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(puzzles.count(in: category))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(category.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(category.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(padding: 14, radius: 16)
    }

    private var specials: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mehr")
            VStack(spacing: 8) {
                specialRow(icon: "book.closed.fill",
                           title: "Eröffnungstraining",
                           subtitle: "\(openings.openings.count) Linien aus dem Repertoire",
                           tint: Theme.info) {
                    route = .openings
                }
                specialRow(icon: "cpu.fill",
                           title: "Gegen die Engine spielen",
                           subtitle: "Partie gegen Stockfish mit einstellbarer Stärke",
                           tint: Theme.accent) {
                    route = .playEngine
                }
                specialRow(icon: "square.and.pencil",
                           title: "Eigene Stellung",
                           subtitle: "Position aufbauen und analysieren",
                           tint: Theme.warning) {
                    route = .editor
                }
                specialRow(icon: "doc.text.magnifyingglass",
                           title: "Partie prüfen",
                           subtitle: "PGN importieren und jeden Zug bewerten",
                           tint: Color(hex: 0xC2A6F0)) {
                    route = .review
                }
            }
        }
    }

    private func specialRow(icon: String,
                            title: String,
                            subtitle: String,
                            tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 10))
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
        .buttonStyle(.plain)
    }

    private func category(of route: TrainingRoute) -> PuzzleCategory? {
        if case .puzzles(let category) = route { return category }
        return nil
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: TrainingRoute) -> some View {
        switch route {
        case .puzzles(let category):
            PuzzleSessionView(puzzles: puzzles.puzzles(in: category), category: category)
                .environmentObject(stats)
                .environmentObject(settings)
        case .openings:
            OpeningTrainerListView()
                .environmentObject(settings)
        case .playEngine:
            EnginePlayView()
                .environmentObject(settings)
                .environmentObject(environment)
                .environmentObject(stats)
        case .editor:
            PositionEditorView(initialBoard: environment.analysis.board) { board in
                route = nil
                environment.openInAnalysis(fen: board.fen)
            }
            .environmentObject(settings)
        case .review:
            GameReviewView()
                .environmentObject(environment)
                .environmentObject(settings)
                .environmentObject(environment.review)
                .environmentObject(environment.analysis)
        }
    }
}
