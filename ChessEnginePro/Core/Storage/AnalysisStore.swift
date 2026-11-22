//
//  AnalysisStore.swift
//  CHESS ENGINE PRO
//
//  Local SQLite storage for saved analyses (no network, no account needed).
//

import Foundation
import SQLite3

struct AnalysisRecord: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var fen: String
    var createdAt: Date
    var summary: String
    var pgn: String?
    var moveCount: Int
    var evaluatedBy: String

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: createdAt)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AnalysisStore {

    static let shared = AnalysisStore()

    private var database: OpaquePointer?
    private let lock = NSLock()

    private init() {
        openDatabase()
    }

    deinit {
        if let database = database {
            sqlite3_close(database)
        }
    }

    // MARK: - Setup

    private func openDatabase() {
        let fileManager = FileManager.default
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first else { return }
        let directory = baseURL.appendingPathComponent("ChessEnginePro", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("analyses.sqlite3")

        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            database = nil
            return
        }

        let schema = """
        CREATE TABLE IF NOT EXISTS analyses (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            fen TEXT NOT NULL,
            created_at REAL NOT NULL,
            summary TEXT NOT NULL,
            pgn TEXT,
            move_count INTEGER NOT NULL DEFAULT 0,
            engine TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_analyses_created ON analyses(created_at DESC);
        """
        sqlite3_exec(database, schema, nil, nil, nil)
    }

    // MARK: - Writing

    func save(_ record: AnalysisRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard let database = database else { return }

        let sql = """
        INSERT OR REPLACE INTO analyses
        (id, title, fen, created_at, summary, pgn, move_count, engine)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, record.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, record.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, record.fen, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 5, record.summary, -1, SQLITE_TRANSIENT)
        if let pgn = record.pgn {
            sqlite3_bind_text(statement, 6, pgn, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_int(statement, 7, Int32(record.moveCount))
        sqlite3_bind_text(statement, 8, record.evaluatedBy, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
    }

    func delete(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let database = database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM analyses WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let database = database else { return }
        sqlite3_exec(database, "DELETE FROM analyses;", nil, nil, nil)
    }

    // MARK: - Reading

    func records(limit: Int = 30) -> [AnalysisRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let database = database else { return [] }

        let sql = """
        SELECT id, title, fen, created_at, summary, pgn, move_count, engine
        FROM analyses ORDER BY created_at DESC LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(1, limit)))

        var result: [AnalysisRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(statement, 0),
                  let titleText = sqlite3_column_text(statement, 1),
                  let fenText = sqlite3_column_text(statement, 2),
                  let summaryText = sqlite3_column_text(statement, 4) else { continue }
            let pgn: String?
            if let pgnText = sqlite3_column_text(statement, 5) {
                pgn = String(cString: pgnText)
            } else {
                pgn = nil
            }
            let engineText = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            result.append(AnalysisRecord(id: String(cString: idText),
                                         title: String(cString: titleText),
                                         fen: String(cString: fenText),
                                         createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                                         summary: String(cString: summaryText),
                                         pgn: pgn,
                                         moveCount: Int(sqlite3_column_int(statement, 6)),
                                         evaluatedBy: engineText))
        }
        return result
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let database = database else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM analyses;", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }
}
