//
//  SettingsStore.swift
//  CHESS ENGINE PRO
//
//  Persistent app and engine configuration.
//

import Foundation
import Combine

enum EngineBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case stockfish
    case builtIn

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .auto: return "Automatisch"
        case .stockfish: return "Stockfish"
        case .builtIn: return "Eingebaute Engine"
        }
    }
}

enum BoardThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case green
    case blue
    case graphite
    case wood
    case violet

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .green: return "Turnier Grün"
        case .blue: return "Ozean Blau"
        case .graphite: return "Graphit"
        case .wood: return "Holz"
        case .violet: return "Violett"
        }
    }
}

enum ArrowPaletteID: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case vivid
    case colorblind

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .classic: return "Klassisch"
        case .vivid: return "Kräftig"
        case .colorblind: return "Farbfehlsichtig"
        }
    }
}

enum PieceStyleID: String, Codable, CaseIterable, Identifiable, Sendable {
    case neo
    case classic
    case outline

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .neo: return "Neo"
        case .classic: return "Klassisch"
        case .outline: return "Outline"
        }
    }

    var usesOutlineGlyphs: Bool { self != .neo }
}

struct AppSettings: Codable, Equatable, Sendable {
    // Engine
    var engineEnabled: Bool = true
    var backend: EngineBackend = .auto
    var depth: Int = 18
    var multiPV: Int = 3
    var useTimeLimit: Bool = false
    var moveTimeMs: Int = 2000
    var threads: Int = 2
    var hashMB: Int = 64
    var style: MoveStyle = .balanced

    // Board
    var boardTheme: BoardThemeID = .green
    var pieceStyle: PieceStyleID = .neo
    var showArrows: Bool = true
    var arrowCount: Int = 3
    var arrowPalette: ArrowPaletteID = .classic
    var showArrowLabels: Bool = true
    var animateMoves: Bool = true
    var showLegalMoves: Bool = true
    var showCoordinates: Bool = true
    var autoAnalyze: Bool = true

    // Performance
    var batterySaver: Bool = false
    var maxEngineLoad: Bool = true
    var backgroundAnalysis: Bool = true

    // Profile
    var playerName: String = "Spieler"
    var chessComHandle: String = ""
    var hapticsEnabled: Bool = true

    var limits: EngineLimits {
        let variants = max(1, multiPV)
        if useTimeLimit {
            return EngineLimits.time(max(200, moveTimeMs), multiPV: variants)
        }
        return EngineLimits.depth(max(1, depth), multiPV: variants)
    }

    var effectiveThreads: Int {
        if batterySaver { return 1 }
        let requested = max(1, threads)
        return maxEngineLoad ? requested : min(requested, 2)
    }
}

@MainActor
final class SettingsStore: ObservableObject {

    private static let storageKey = "chess-engine-pro.settings.v1"

    @Published var settings: AppSettings {
        didSet {
            if settings != oldValue { persist() }
        }
    }

    init() {
        settings = SettingsStore.load()
    }

    private static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: SettingsStore.storageKey)
    }

    func resetToDefaults() {
        settings = AppSettings()
    }
}

// MARK: - Local training statistics

@MainActor
final class TrainingStatsStore: ObservableObject {

    private static let storageKey = "chess-engine-pro.stats.v1"

    struct Stats: Codable, Equatable, Sendable {
        var puzzlesSolved: Int = 0
        var puzzlesAttempted: Int = 0
        var gamesPlayed: Int = 0
        var positionsAnalyzed: Int = 0
        var lastTrainingDate: Date?
        var streak: Int = 0
    }

    @Published private(set) var stats: Stats

    init() {
        if let data = UserDefaults.standard.data(forKey: TrainingStatsStore.storageKey),
           let decoded = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = decoded
        } else {
            stats = Stats()
        }
    }

    func recordPuzzle(solved: Bool) {
        stats.puzzlesAttempted += 1
        if solved { stats.puzzlesSolved += 1 }
        touchTraining()
        persist()
    }

    func recordGame() {
        stats.gamesPlayed += 1
        touchTraining()
        persist()
    }

    func recordAnalysis() {
        stats.positionsAnalyzed += 1
        persist()
    }

    private func touchTraining() {
        let calendar = Calendar.current
        if let last = stats.lastTrainingDate, calendar.isDateInToday(last) {
            return
        }
        if let last = stats.lastTrainingDate,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
           calendar.isDate(last, inSameDayAs: yesterday) {
            stats.streak += 1
        } else {
            stats.streak = 1
        }
        stats.lastTrainingDate = Date()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: TrainingStatsStore.storageKey)
    }
}
