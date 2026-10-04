import Foundation
import SwiftUI

// MARK: - Decoding helper
// Old saves (and saves made by the web app) can be missing keys, so every field
// falls back to a default rather than failing the whole restore.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Saved shape
// Deliberately identical to the web app's save file, so a backup code copied
// from mohautshukudu.github.io/Mot-a-Mot restores here, and the other way round.

struct ModeState: Codable, Hashable {
    var best: Int?
    var first: Int?
    var passed: Bool

    init(best: Int? = nil, first: Int? = nil, passed: Bool = false) {
        self.best = best
        self.first = first
        self.passed = passed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        best = (try? c.decodeIfPresent(Int.self, forKey: .best)) ?? nil
        first = (try? c.decodeIfPresent(Int.self, forKey: .first)) ?? nil
        passed = c.value(.passed, false)
    }
}

struct Batch: Codable, Identifiable, Hashable {
    var n: Int
    var start: Int
    var size: Int
    var extras: [Int]
    var done: Bool
    var skipped: Bool
    var modes: [String: ModeState]

    var id: Int { n }

    init(n: Int, start: Int, size: Int, extras: [Int] = [], done: Bool = false,
         skipped: Bool = false, modes: [String: ModeState]? = nil) {
        self.n = n
        self.start = start
        self.size = size
        self.extras = extras
        self.done = done
        self.skipped = skipped
        self.modes = modes ?? [
            TestMode.match.key: ModeState(),
            TestMode.type.key: ModeState()
        ]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.value(.n, 1)
        start = c.value(.start, 0)
        size = c.value(.size, 10)
        extras = c.value(.extras, [Int]())
        done = c.value(.done, false)
        skipped = c.value(.skipped, false)
        modes = c.value(.modes, [String: ModeState]())
        if modes[TestMode.match.key] == nil { modes[TestMode.match.key] = ModeState() }
        if modes[TestMode.type.key] == nil { modes[TestMode.type.key] = ModeState() }
    }

    func state(_ mode: TestMode) -> ModeState {
        modes[mode.key] ?? ModeState()
    }
}

struct WordProgress: Codable, Hashable {
    var box: Int
    var due: Int
    var miss: Int?

    init(box: Int, due: Int, miss: Int? = nil) {
        self.box = box
        self.due = due
        self.miss = miss
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = c.value(.box, 0)
        due = c.value(.due, 0)
        miss = (try? c.decodeIfPresent(Int.self, forKey: .miss)) ?? nil
    }
}

struct Settings: Codable {
    var passMark: Int = 80
    var maxBatch: Int = 50
    var rate: Double = 0.9
    var reviewMode: String = "mixed"
    var theme: String = ""
    var photos: Bool = true
    var autoplay: Bool = true
    /// The web app's voice key. Kept so a backup code survives a round trip.
    var voice: String = ""
    /// The iOS voice identifier, which the web app has no use for.
    var voiceId: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passMark = c.value(.passMark, 80)
        maxBatch = c.value(.maxBatch, 50)
        rate = c.value(.rate, 0.9)
        reviewMode = c.value(.reviewMode, "mixed")
        theme = c.value(.theme, "")
        photos = c.value(.photos, true)
        autoplay = c.value(.autoplay, true)
        voice = c.value(.voice, "")
        voiceId = c.value(.voiceId, "")
    }
}

struct Stats: Codable {
    var streak: Int = 0
    var lastDay: Int = -1
    var answers: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = c.value(.streak, 0)
        lastDay = c.value(.lastDay, -1)
        answers = c.value(.answers, 0)
    }
}

struct SaveState: Codable {
    var v: Int = 2
    var batches: [Batch] = []
    var words: [String: WordProgress] = [:]
    var hiddenPhotos: [Int] = []
    var settings = Settings()
    var stats = Stats()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = c.value(.v, 2)
        batches = c.value(.batches, [Batch]())
        words = c.value(.words, [String: WordProgress]())
        hiddenPhotos = c.value(.hiddenPhotos, [Int]())
        settings = c.value(.settings, Settings())
        stats = c.value(.stats, Stats())
    }
}

// MARK: - Test modes

enum TestMode: String, CaseIterable, Identifiable {
    case match
    case type

    var id: String { rawValue }
    var key: String { rawValue }

    var name: String {
        switch self {
        case .match: return "Match"
        case .type: return "Type"
        }
    }

    var level: String {
        switch self {
        case .match: return "Level 1"
        case .type: return "Level 2"
        }
    }

    var blurb: String {
        switch self {
        case .match: return "Pick the right meaning or word from a list."
        case .type: return "See the English and type the French."
        }
    }
}

enum WordStatus {
    case learned, due, current, new
}

enum Tab: Hashable {
    case learn, read, words, courses, settings
}

// MARK: - Store

final class Store: ObservableObject {

    static let intervals = [0, 1, 3, 7, 14, 30, 60, 120]

    @Published var state = SaveState()
    @Published var tab: Tab = .learn
    @Published var study: StudySession?
    @Published var quiz: QuizSession?
    @Published var lastResult: QuizResult?
    @Published var builder: SentenceBuilder?
    @Published var toast: String?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("motamot-progress.json")
    }()

    private var builderPool: [Word]?
    private var builderPoolKey: Int?

    init() {
        load()
        if state.batches.isEmpty || (state.batches.last?.done ?? false) {
            newBatch()
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SaveState.self, from: data)
        else { return }
        state = decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Base64 of the save file — the same code the web app makes and accepts.
    func backupCode() -> String {
        guard let data = try? JSONEncoder().encode(state) else { return "" }
        return data.base64EncodedString()
    }

    @discardableResult
    func restore(from code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let decoded = try? JSONDecoder().decode(SaveState.self, from: data),
              !decoded.batches.isEmpty || !decoded.words.isEmpty
        else { return false }
        state = decoded
        if state.batches.isEmpty || (state.batches.last?.done ?? false) { newBatch() }
        persist()
        return true
    }

    func resetEverything() {
        state = SaveState()
        newBatch()
        persist()
    }

    // MARK: Days

    /// Days since 1970 in the user's own timezone, matching the web app.
    static func today() -> Int {
        let offset = Double(TimeZone.current.secondsFromGMT())
        return Int(floor((Date().timeIntervalSince1970 + offset) / 86400))
    }

    // MARK: Progress lookups

    func progress(_ id: Int) -> WordProgress? {
        state.words[String(id)]
    }

    func setProgress(_ id: Int, _ p: WordProgress) {
        state.words[String(id)] = p
    }

    func missCount(_ id: Int) -> Int {
        progress(id)?.miss ?? 0
    }

    var learnedCount: Int {
        state.batches.filter { $0.done }.reduce(0) { $0 + $1.size }
    }

    var currentBatch: Batch? {
        state.batches.last.flatMap { $0.done ? nil : $0 }
    }

    /// The batch in progress, or the last one when everything is finished.
    var latestBatch: Batch? { state.batches.last }

    func newWords(_ b: Batch) -> [Word] {
        let end = min(b.start + b.size, Dataset.total)
        guard b.start >= 0, b.start < end else { return [] }
        return Array(Dataset.words[b.start..<end])
    }

    func revisionWords(_ b: Batch) -> [Word] {
        b.extras.compactMap { Dataset.word($0) }
    }

    func batchWords(_ b: Batch) -> [Word] {
        newWords(b) + revisionWords(b)
    }

    func batchAverage(_ b: Batch) -> Int? {
        let scores = TestMode.allCases.compactMap { b.state($0).first }.filter { $0 >= 0 }
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    func isUnlocked(_ b: Batch, _ mode: TestMode) -> Bool {
        switch mode {
        case .match: return true
        case .type: return b.state(.match).passed
        }
    }

    func isComplete(_ b: Batch) -> Bool {
        TestMode.allCases.allSatisfy { b.state($0).passed }
    }

    func status(of w: Word) -> WordStatus {
        if let p = progress(w.id), p.box > 0 {
            return p.due <= Store.today() ? .due : .learned
        }
        if let b = currentBatch, w.id >= b.start, w.id < b.start + b.size { return .current }
        return .new
    }

    var dueWords: [Word] {
        let d = Store.today()
        return Dataset.words.filter { w in
            guard let p = progress(w.id) else { return false }
            return p.box > 0 && p.due <= d
        }
    }

    // MARK: Batches

    /// Words already learned, worst first, to fold back into a new batch.
    private func pickRevision(_ n: Int, excluding range: Range<Int>) -> [Int] {
        guard n > 0 else { return [] }
        let pool = Dataset.words.filter { w in
            guard let p = progress(w.id), p.box > 0 else { return false }
            return !range.contains(w.id)
        }
        guard !pool.isEmpty else { return [] }
        let scored = pool.map { w -> (Int, Double) in
            let weak = (progress(w.id)?.box ?? 1) <= 1 ? 3.0 : 0.0
            return (w.id, Double(missCount(w.id)) * 10 + Double.random(in: 0..<4) + weak)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(n).map { $0.0 }
    }

    /// How big the next batch should be, given how the last one went.
    func nextSize() -> Int {
        guard let b = state.batches.last else { return 10 }
        if b.skipped { return 10 }
        let scores = TestMode.allCases.compactMap { b.state($0).first }.filter { $0 >= 0 }
        let avg = scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count)
        var size = b.size
        if avg >= 90 { size += 10 }
        else if avg >= 80 { size += 5 }
        else if avg < 65 { size -= 5 }
        return max(10, min(state.settings.maxBatch, size))
    }

    func newBatch() {
        let start = learnedCount
        guard start < Dataset.total else { return }
        let total = min(nextSize(), Dataset.total - start)
        let revisionCount = state.batches.contains(where: { $0.done }) ? Int((Double(total) / 3).rounded()) : 0
        let size = max(1, total - revisionCount)
        let extras = pickRevision(revisionCount, excluding: start..<(start + size))
        state.batches.append(Batch(n: state.batches.count + 1, start: start, size: size, extras: extras))
        persist()
    }

    func finishBatch() {
        guard var b = state.batches.last, !b.done, isComplete(b) else { return }
        b.done = true
        state.batches[state.batches.count - 1] = b
        let d = Store.today()
        for w in newWords(b) {
            var p = progress(w.id) ?? WordProgress(box: 0, due: 0)
            p.box = 1
            p.due = d + 1
            setProgress(w.id, p)
        }
        newBatch()
        persist()
    }

    func skipAhead(to n: Int) {
        let count = max(0, min(Dataset.total, n))
        let d = Store.today()
        state.batches = []
        state.words = [:]
        if count > 0 {
            var modes: [String: ModeState] = [:]
            for m in TestMode.allCases { modes[m.key] = ModeState(best: nil, first: nil, passed: true) }
            state.batches.append(Batch(n: 1, start: 0, size: count, extras: [], done: true, skipped: true, modes: modes))
            for i in 0..<count {
                setProgress(i, WordProgress(box: 2, due: d + 1 + (i % 7)))
            }
        }
        newBatch()
        persist()
    }

    func bumpStreak() {
        let d = Store.today()
        guard state.stats.lastDay != d else { return }
        state.stats.streak = state.stats.lastDay == d - 1 ? state.stats.streak + 1 : 1
        state.stats.lastDay = d
    }

    // MARK: Appearance

    var colorScheme: ColorScheme? {
        switch state.settings.theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    func show(toast message: String) {
        toast = message
    }

    // MARK: Sentence practice

    /// Example sentences made entirely of words he has already learned.
    func eligibleSentences() -> [Word] {
        // Rebuilding this means scanning every example sentence, so it is only
        // redone when the number of learned words has actually changed.
        let key = learnedCount
        if let pool = builderPool, builderPoolKey == key { return pool }
        let pool = Dataset.words.filter { w in
            let tokens = Grammar.tokens(in: w.exFr)
            guard tokens.count >= 3, tokens.count <= 8 else { return false }
            return tokens.allSatisfy { token in
                guard let id = Dataset.lookupForm(token.text), let word = Dataset.word(id) else { return false }
                let s = status(of: word)
                return s == .learned || s == .due
            }
        }
        builderPool = pool
        builderPoolKey = key
        return pool
    }

    func startBuilder() {
        let pool = eligibleSentences()
        guard let w = pool.randomElement() else { return }
        builder = SentenceBuilder(word: w)
    }
}

// MARK: - Sentence builder

struct SentenceBuilder {
    struct Tile: Identifiable, Hashable {
        let id: Int
        let text: String
    }

    let wordId: Int
    let answer: [String]
    var tiles: [Tile]
    var placed: [Tile] = []
    var checked: Bool?

    init(word: Word) {
        wordId = word.id
        let parts = word.exFr.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        answer = parts
        tiles = parts.enumerated().map { Tile(id: $0.offset, text: $0.element) }.shuffled()
    }

    var word: Word? { Dataset.word(wordId) }

    var isFull: Bool { placed.count == answer.count }

    var remaining: [Tile] {
        tiles.filter { tile in !placed.contains(where: { $0.id == tile.id }) }
    }

    mutating func place(_ tile: Tile) {
        guard checked == nil, !placed.contains(where: { $0.id == tile.id }) else { return }
        placed.append(tile)
    }

    mutating func unplace(at index: Int) {
        guard checked == nil, placed.indices.contains(index) else { return }
        placed.remove(at: index)
    }

    mutating func clear() {
        placed = []
        checked = nil
    }

    mutating func check() {
        checked = placed.map { $0.text } == answer
    }

    /// Whether the tile in a given slot is in the right place.
    func slotIsRight(_ index: Int) -> Bool {
        guard placed.indices.contains(index), answer.indices.contains(index) else { return false }
        return placed[index].text == answer[index]
    }
}
