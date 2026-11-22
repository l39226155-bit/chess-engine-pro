//
//  StockfishEngine.swift
//  CHESS ENGINE PRO
//
//  UCI transport for the embedded Stockfish build. All engine work happens on
//  a dedicated serial queue plus one reader thread, so the UI never blocks.
//

import Foundation

enum StockfishBuild {
    /// Keep in sync with STOCKFISH_VERSION in scripts/build-stockfish.sh.
    static let version = "17.1"

    static var isLinked: Bool { sf_available() }

    static var rawName: String {
        if let pointer = sf_engine_name() {
            return String(cString: pointer)
        }
        return "Stockfish"
    }

    static var displayName: String {
        isLinked ? "\(rawName) \(version)" : "Stockfish (nicht eingebunden)"
    }
}

final class StockfishEngine: ChessEngine {

    static let shared = StockfishEngine()

    var displayName: String { StockfishBuild.displayName }
    var isAvailable: Bool { StockfishBuild.isLinked }

    // MARK: - State

    private let ioQueue = DispatchQueue(label: "com.chessenginepro.stockfish.io", qos: .userInitiated)
    private let stateLock = NSLock()

    private var continuation: AsyncStream<EngineUpdate>.Continuation?
    private var readerThread: Thread?
    private var optionsApplied: [String: String] = [:]
    private var bestMoveSignal = DispatchSemaphore(value: 0)

    private var searchActive = false
    /// Incremented for every new search so a late `stop()` from the previous
    /// stream cannot abort the current one.
    private var searchGeneration = 0
    private var linesByRank: [Int: EngineLine] = [:]
    private var depth = 0
    private var seldepth = 0
    private var nodes: UInt64 = 0
    private var elapsedMs = 0
    private var sideSign = 1
    private var multiPV = 3

    private init() {}

    // MARK: - Public API

    func setOption(_ name: String, value: String) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let already = self.optionsApplied[name] == value
            if !already { self.optionsApplied[name] = value }
            let searching = self.searchActive
            self.stateLock.unlock()
            guard !already, !searching else { return }
            sf_write("setoption name \(name) value \(value)")
        }
    }

    func analyze(fen: String, limits: EngineLimits) -> AsyncStream<EngineUpdate> {
        AsyncStream<EngineUpdate> { continuation in
            stateLock.lock()
            let previous = self.continuation
            self.continuation = continuation
            self.searchGeneration &+= 1
            let generation = self.searchGeneration
            self.linesByRank.removeAll()
            self.depth = 0
            self.seldepth = 0
            self.nodes = 0
            self.elapsedMs = 0
            self.multiPV = max(1, limits.multiPV)
            self.sideSign = (Board(fen: fen)?.sideToMove ?? .white) == .white ? 1 : -1
            stateLock.unlock()

            previous?.finish()

            ioQueue.async { [weak self] in
                self?.beginSearch(fen: fen, limits: limits)
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop(ifCurrent: generation)
            }
        }
    }

    func stop() {
        stop(ifCurrent: nil)
    }

    /// Stops the search. When `generation` is given the request is ignored if a
    /// newer search has already started, which prevents a terminated stream
    /// from killing its successor.
    private func stop(ifCurrent generation: Int?) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            if let generation = generation, generation != self.searchGeneration {
                self.stateLock.unlock()
                return
            }
            let active = self.searchActive
            self.searchActive = false
            self.stateLock.unlock()
            if active { sf_write("stop") }
        }
    }

    // MARK: - Search control

    private func beginSearch(fen: String, limits: EngineLimits) {
        guard sf_available() else { return }
        guard sf_start() else { return }
        startReaderIfNeeded()

        // Finish an older search first; the UCI loop is strictly sequential.
        stateLock.lock()
        let active = searchActive
        if active { searchActive = false }
        stateLock.unlock()
        if active {
            sf_write("stop")
            _ = bestMoveSignal.wait(timeout: .now() + 2.0)
        }
        while bestMoveSignal.wait(timeout: .now()) == .success {
            // drain stale signals
        }

        applyOptionIfNeeded("MultiPV", "\(max(1, limits.multiPV))")
        sf_write("position fen \(fen)")

        var command = "go"
        if let milliseconds = limits.moveTimeMs {
            command += " movetime \(max(50, milliseconds))"
        }
        command += " depth \(max(1, min(limits.depth, 60)))"

        stateLock.lock()
        linesByRank.removeAll()
        depth = 0
        seldepth = 0
        nodes = 0
        elapsedMs = 0
        searchActive = true
        stateLock.unlock()

        sf_write(command)
        NSLog("[SF] start: %@ (engine linked: %d)", command, sf_available() ? 1 : 0)
    }

    private func applyOptionIfNeeded(_ name: String, _ value: String) {
        stateLock.lock()
        let shouldSend = optionsApplied[name] != value
        if shouldSend { optionsApplied[name] = value }
        stateLock.unlock()
        if shouldSend {
            sf_write("setoption name \(name) value \(value)")
        }
    }

    // MARK: - Reading

    private func startReaderIfNeeded() {
        stateLock.lock()
        let existing = readerThread
        stateLock.unlock()
        guard existing == nil else { return }

        let thread = Thread { [weak self] in
            self?.readLoop()
        }
        thread.name = "StockfishReader"
        thread.qualityOfService = .userInitiated
        thread.stackSize = 1 << 20

        stateLock.lock()
        readerThread = thread
        stateLock.unlock()
        thread.start()
    }

    private func readLoop() {
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let length = sf_read_line(buffer, Int32(bufferSize))
            if length < 0 { break }
            if length == 0 { continue }
            handle(line: String(cString: buffer))
        }
        NSLog("[SF] reader loop ended")

        stateLock.lock()
        let completion = continuation
        continuation = nil
        searchActive = false
        stateLock.unlock()

        completion?.finish()
    }

    private func handle(line: String) {
        if line.hasPrefix("bestmove") {
            handleBestMove(line)
            return
        }
        guard line.hasPrefix("info "), line.contains(" pv ") else { return }
        handleInfo(line)
    }

    private func handleInfo(_ line: String) {
        let tokens = line.split(separator: " ").map(String.init)

        stateLock.lock()
        let sign = sideSign
        stateLock.unlock()

        var depthValue = 0
        var seldepthValue = 0
        var rank = 1
        var nodeCount: UInt64 = 0
        var timeValue = 0
        var score: EvalScore?
        var pv: [String] = []

        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "depth":
                index += 1
                if index < tokens.count { depthValue = Int(tokens[index]) ?? depthValue }
            case "seldepth":
                index += 1
                if index < tokens.count { seldepthValue = Int(tokens[index]) ?? seldepthValue }
            case "multipv":
                index += 1
                if index < tokens.count { rank = Int(tokens[index]) ?? rank }
            case "nodes":
                index += 1
                if index < tokens.count { nodeCount = UInt64(tokens[index]) ?? nodeCount }
            case "time":
                index += 1
                if index < tokens.count { timeValue = Int(tokens[index]) ?? timeValue }
            case "score":
                if index + 2 < tokens.count {
                    let kind = tokens[index + 1]
                    if let raw = Int(tokens[index + 2]) {
                        if kind == "cp" {
                            score = .centipawns(raw * sign)
                        } else if kind == "mate" {
                            score = .mate(raw * sign)
                        }
                    }
                    index += 2
                }
            case "pv":
                if index + 1 < tokens.count {
                    pv = Array(tokens[(index + 1)...])
                }
                index = tokens.count
            default:
                break
            }
            index += 1
        }

        guard let value = score, !pv.isEmpty else { return }

        stateLock.lock()
        guard searchActive else {
            stateLock.unlock()
            return
        }
        self.depth = max(self.depth, depthValue)
        self.seldepth = max(self.seldepth, seldepthValue)
        self.nodes = max(self.nodes, nodeCount)
        self.elapsedMs = max(self.elapsedMs, timeValue)
        let line = EngineLine(rank: rank,
                              score: value,
                              depth: depthValue,
                              pv: pv,
                              nodes: nodeCount)
        linesByRank[rank] = line

        let ordered = linesByRank.values
            .filter { $0.rank <= max(1, multiPV) }
            .sorted { $0.rank < $1.rank }
        let update = EngineUpdate(depth: self.depth,
                                  seldepth: self.seldepth,
                                  nodes: self.nodes,
                                  timeMs: self.elapsedMs,
                                  lines: ordered,
                                  bestMove: nil,
                                  isFinal: false)
        let target = continuation
        stateLock.unlock()

        target?.yield(update)
    }

    private func handleBestMove(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        var move: Move?
        if parts.count >= 2, parts[1] != "(none)" {
            move = Move(uci: parts[1])
        }
        NSLog("[SF] raw bestmove: %@ -> %@", line, move?.uci ?? "nil")

        stateLock.lock()
        let wasActive = searchActive
        searchActive = false
        if move == nil, let first = linesByRank.values.min(by: { $0.rank < $1.rank })?.firstMove {
            // Stockfish answers "bestmove (none)" when a search is aborted before
            // it completed a root move; the deepest PV still holds a usable move.
            move = first
        }
        let ordered = linesByRank.values.sorted { $0.rank < $1.rank }
        let update = EngineUpdate(depth: depth,
                                  seldepth: seldepth,
                                  nodes: nodes,
                                  timeMs: elapsedMs,
                                  lines: ordered,
                                  bestMove: move,
                                  isFinal: true)
        let target = wasActive ? continuation : nil
        if wasActive { continuation = nil }
        stateLock.unlock()

        bestMoveSignal.signal()
        if let target = target {
            target.yield(update)
            target.finish()
        }
    }
}
