import Foundation
import SwiftUI

// MARK: - Saved shape
// Same JSON the web apps keep (batches / cards / settings / stats), so a backup
// from Fret by Fret, Atlas etc. can be pasted into the matching course here.

struct DeckModeState: Codable, Hashable {
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

struct DeckBatch: Codable, Identifiable, Hashable {
    var n: Int
    var start: Int
    var size: Int
    var extras: [Int]
    var done: Bool
    var skipped: Bool?
    var modes: [String: DeckModeState]

    var id: Int { n }

    init(n: Int, start: Int, size: Int, extras: [Int], modes: [String: DeckModeState]) {
        self.n = n
        self.start = start
        self.size = size
        self.extras = extras
        self.done = false
        self.skipped = nil
        self.modes = modes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.value(.n, 1)
        start = c.value(.start, 0)
        size = c.value(.size, 10)
        extras = c.value(.extras, [Int]())
        done = c.value(.done, false)
        skipped = (try? c.decodeIfPresent(Bool.self, forKey: .skipped)) ?? nil
        modes = c.value(.modes, [String: DeckModeState]())
    }

    func state(_ key: String) -> DeckModeState {
        modes[key] ?? DeckModeState()
    }
}

struct DeckCardProgress: Codable, Hashable {
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

struct DeckSettings: Codable {
    var passMark: Int = 80
    var maxBatch: Int = 40
    var revDiv: Int = 3
    var autoplay: Bool = true
    var sfx: Bool = true
    var theme: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passMark = c.value(.passMark, 80)
        maxBatch = c.value(.maxBatch, 40)
        revDiv = c.value(.revDiv, 3)
        autoplay = c.value(.autoplay, true)
        sfx = c.value(.sfx, true)
        theme = c.value(.theme, "")
    }
}

struct DeckStats: Codable {
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

struct DeckSave: Codable {
    var v: Int = 1
    var batches: [DeckBatch] = []
    var cards: [String: DeckCardProgress] = [:]
    var settings = DeckSettings()
    var stats = DeckStats()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = c.value(.v, 1)
        batches = c.value(.batches, [DeckBatch]())
        cards = c.value(.cards, [String: DeckCardProgress]())
        settings = c.value(.settings, DeckSettings())
        stats = c.value(.stats, DeckStats())
    }
}

// MARK: - Session shapes

enum DeckKind: String {
    case match, type
}

struct DeckMode: Identifiable {
    let key: String
    let name: String
    let level: String
    let kind: DeckKind
    var id: String { key }
}

enum DeckQuizKind {
    case batch, review, practice
}

struct DeckItem: Identifiable {
    let id = UUID()
    let cid: Int
    let kind: DeckKind
    let reverse: Bool
    var hint = false
    var retry = false
    var options: [String] = []
}

/// Enough state to undo one answer when the user taps "I was right".
struct DeckSnapshot {
    let cid: Int
    let wasFirst: Bool
    let progress: DeckCardProgress?
    let missedCount: Int
}

struct DeckAnswered {
    let ok: Bool
    var typed = ""
    var note = ""
    var pick: Int?
    let snapshot: DeckSnapshot
}

struct DeckQuiz {
    let kind: DeckQuizKind
    var modeKey: String?
    var title: String
    var queue: [DeckItem]
    let total: Int
    var firstTry: [Int: Bool] = [:]
    var doneIds: Set<Int> = []
    var answered: DeckAnswered?
    var missed: [Int] = []
    var batchNumber: Int?

    var current: DeckItem? { queue.first }
}

struct DeckResult {
    let kind: DeckQuizKind
    let modeKey: String?
    let score: Int
    let missed: [Int]
    let passed: Bool

    var isPractice: Bool { kind == .practice }
}

struct DeckStudy {
    var ids: [Int]
    var index = 0
    var hide = false
    var revealed = false
}

enum DeckStatus {
    case learned, due, current, new
}

// MARK: - Store

final class DeckStore: ObservableObject, Identifiable {

    static let intervals = [0, 1, 3, 7, 14, 30, 60, 120]

    static let modes: [DeckMode] = [
        DeckMode(key: "match", name: "Match", level: "Level 1", kind: .match),
        DeckMode(key: "type", name: "Type", level: "Level 2", kind: .type),
    ]

    static let noteLabels = ["C", "C♯/D♭", "D", "D♯/E♭", "E", "F", "F♯/G♭", "G", "G♯/A♭", "A", "A♯/B♭", "B"]

    let data: DeckData
    let grader: DeckGrader
    var id: String { data.slug }

    @Published var state = DeckSave()
    @Published var study: DeckStudy?
    @Published var quiz: DeckQuiz?
    @Published var lastResult: DeckResult?
    @Published var toast: String?

    private let fileURL: URL

    init(data: DeckData) {
        self.data = data
        self.grader = DeckGrader(data: data)
        self.fileURL = DeckStore.saveURL(for: data.slug)
        load()
        if state.batches.isEmpty || (state.batches.last?.done ?? false) {
            newBatch()
        }
    }

    // MARK: Persistence

    private static func saveURL(for slug: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("deck-\(slug)-progress.json")
    }

    /// Cards learned so far, read straight off disk for the course list.
    static func learnedCount(slug: String) -> Int {
        guard let data = try? Data(contentsOf: saveURL(for: slug)),
              let save = try? JSONDecoder().decode(DeckSave.self, from: data)
        else { return 0 }
        return save.batches.filter { $0.done }.reduce(0) { $0 + $1.size }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(DeckSave.self, from: data)
        else { return }
        state = decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The save file as text. Same format as the web app's "Download backup".
    func backupText() -> String {
        guard let data = try? JSONEncoder().encode(state) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    func restore(from text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["batches"] is [Any], object["cards"] is [String: Any],
              let decoded = try? JSONDecoder().decode(DeckSave.self, from: data)
        else { return false }
        state = decoded
        if state.batches.isEmpty || (state.batches.last?.done ?? false) { newBatch() }
        persist()
        return true
    }

    func resetEverything() {
        state = DeckSave()
        newBatch()
        persist()
    }

    func show(toast message: String) {
        toast = message
    }

    // MARK: Days

    static func today() -> Int {
        let offset = Double(TimeZone.current.secondsFromGMT())
        return Int(floor((Date().timeIntervalSince1970 + offset) / 86400))
    }

    // MARK: Progress lookups

    var total: Int { data.cards.count }

    func progress(_ id: Int) -> DeckCardProgress? { state.cards[String(id)] }

    func missCount(_ id: Int) -> Int { progress(id)?.miss ?? 0 }

    var learnedCount: Int {
        state.batches.filter { $0.done }.reduce(0) { $0 + $1.size }
    }

    var currentBatch: DeckBatch? { state.batches.last(where: { !$0.done }) }

    func newCards(_ b: DeckBatch) -> [DeckCard] {
        let end = min(b.start + b.size, data.cards.count)
        guard b.start < end else { return [] }
        return Array(data.cards[b.start..<end])
    }

    func revisionCards(_ b: DeckBatch) -> [DeckCard] {
        b.extras.compactMap { data.card($0) }
    }

    func batchCards(_ b: DeckBatch) -> [DeckCard] {
        newCards(b) + revisionCards(b)
    }

    func batchAverage(_ b: DeckBatch) -> Int? {
        let scores = DeckStore.modes.compactMap { b.state($0.key).first }.filter { $0 >= 0 }
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    func isUnlocked(_ b: DeckBatch, _ index: Int) -> Bool {
        index == 0 || b.state(DeckStore.modes[index - 1].key).passed
    }

    func isComplete(_ b: DeckBatch) -> Bool {
        DeckStore.modes.allSatisfy { b.state($0.key).passed }
    }

    func status(of card: DeckCard) -> DeckStatus {
        if let p = progress(card.id), p.box > 0 {
            return p.due <= DeckStore.today() ? .due : .learned
        }
        if let b = currentBatch, card.id >= b.start, card.id < b.start + b.size { return .current }
        return .new
    }

    var dueCards: [DeckCard] {
        let day = DeckStore.today()
        return data.cards.filter { c in
            guard let p = progress(c.id) else { return false }
            return p.box > 0 && p.due <= day
        }
    }

    var weakCards: [DeckCard] {
        Array(data.cards
            .filter { missCount($0.id) >= 2 }
            .sorted { missCount($0.id) > missCount($1.id) }
            .prefix(12))
    }

    var liveStreak: Int {
        let day = DeckStore.today()
        let s = state.stats
        return (s.lastDay == day || s.lastDay == day - 1) ? s.streak : 0
    }

    var currentStage: (index: Int, stage: DeckStage, learned: Int)? {
        for (i, stage) in data.stages.enumerated() {
            var learned = 0
            var allLearned = true
            for id in stage.start..<stage.end {
                if (progress(id)?.box ?? 0) > 0 { learned += 1 } else { allLearned = false }
            }
            if !allLearned { return (i, stage, learned) }
        }
        return nil
    }

    // MARK: Batches

    private func pickRevision(_ n: Int, excluding range: Range<Int>) -> [Int] {
        guard n > 0 else { return [] }
        let pool = data.cards.filter { c in
            guard let p = progress(c.id), p.box > 0 else { return false }
            return !range.contains(c.id)
        }
        let scored = pool.map { c -> (Int, Double) in
            let box = progress(c.id)?.box ?? 0
            return (c.id, Double(missCount(c.id)) * 10 + Double.random(in: 0..<4) + (box <= 1 ? 3 : 0))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(n).map { $0.0 }
    }

    func nextSize() -> Int {
        guard let b = state.batches.last else { return 10 }
        if b.skipped == true { return 10 }
        let scores = DeckStore.modes.compactMap { b.state($0.key).first }.filter { $0 >= 0 }
        let avg = scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count)
        var size = b.size
        if avg >= 90 { size += 10 } else if avg >= 80 { size += 5 } else if avg < 65 { size -= 5 }
        return max(10, min(state.settings.maxBatch, size))
    }

    func newBatch() {
        let start = learnedCount
        guard start < total else { return }
        let count = min(nextSize(), total - start)
        let hasDone = state.batches.contains { $0.done }
        let revision = hasDone ? Int((Double(count) / Double(max(1, state.settings.revDiv))).rounded()) : 0
        let size = max(1, count - revision)
        let extras = pickRevision(revision, excluding: start..<(start + size))
        var modes: [String: DeckModeState] = [:]
        for m in DeckStore.modes { modes[m.key] = DeckModeState() }
        state.batches.append(DeckBatch(n: state.batches.count + 1, start: start, size: size, extras: extras, modes: modes))
        persist()
    }

    func finishBatch() {
        guard let index = state.batches.indices.last,
              !state.batches[index].done, isComplete(state.batches[index])
        else { return }
        state.batches[index].done = true
        let day = DeckStore.today()
        for c in newCards(state.batches[index]) {
            var p = progress(c.id) ?? DeckCardProgress(box: 0, due: 0)
            p.box = 1
            p.due = day + 1
            state.cards[String(c.id)] = p
        }
        newBatch()
        persist()
    }

    func bumpStreak() {
        let day = DeckStore.today()
        guard state.stats.lastDay != day else { return }
        state.stats.streak = state.stats.lastDay == day - 1 ? state.stats.streak + 1 : 1
        state.stats.lastDay = day
    }

    // MARK: Starting sessions

    func startStudy(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        quiz = nil
        lastResult = nil
        study = DeckStudy(ids: ids.shuffled())
    }

    func startTest(modeKey: String) {
        guard let b = currentBatch, let mode = DeckStore.modes.first(where: { $0.key == modeKey }) else { return }
        let cards = batchCards(b).filter { $0.isQuizzable }
        if cards.isEmpty {
            // Nothing in this batch can be asked yet (sound or map only), so don't block the course.
            if let i = state.batches.indices.last {
                state.batches[i].modes[modeKey] = DeckModeState(best: 100, first: 100, passed: true)
                persist()
            }
            show(toast: "These cards can't be tested in the app yet — marked as passed")
            return
        }
        study = nil
        lastResult = nil
        quiz = DeckQuiz(kind: .batch, modeKey: modeKey, title: mode.name,
                        queue: cards.shuffled().map { makeItem($0, kind: mode.kind) },
                        total: cards.count, batchNumber: b.n)
    }

    func startPractice(_ ids: [Int], kind: DeckKind, title: String? = nil) {
        let cards = ids.compactMap { data.card($0) }.filter { $0.isQuizzable }
        guard !cards.isEmpty else {
            show(toast: "Nothing to practise yet")
            return
        }
        study = nil
        lastResult = nil
        quiz = DeckQuiz(kind: .practice, modeKey: nil,
                        title: title ?? (kind == .match ? "Match practice" : "Type practice"),
                        queue: cards.shuffled().map { makeItem($0, kind: kind) },
                        total: cards.count)
    }

    func startReview(typing: Bool?) {
        let cards = Array(dueCards.filter { $0.isQuizzable }.shuffled().prefix(40))
        guard !cards.isEmpty else { return }
        study = nil
        lastResult = nil
        let items = cards.map { c -> DeckItem in
            let kind: DeckKind
            switch typing {
            case .some(true): kind = .type
            case .some(false): kind = .match
            case .none: kind = (progress(c.id)?.box ?? 1) <= 1 ? .match : .type
            }
            return makeItem(c, kind: kind)
        }
        quiz = DeckQuiz(kind: .review, modeKey: nil, title: "Review", queue: items, total: cards.count)
    }

    func closeSession() {
        study = nil
        quiz = nil
        lastResult = nil
    }

    // MARK: Building questions

    func spec(for item: DeckItem) -> DeckSpec? {
        guard let card = data.card(item.cid) else { return nil }
        return item.reverse ? (card.r ?? card.f) : card.f
    }

    private func canReverse(_ card: DeckCard, kind: DeckKind) -> Bool {
        guard let r = card.r, r.isSupported, r.audio != true else { return false }
        if kind == .type && r.matchOnly == true { return false }
        return true
    }

    private func makeItem(_ card: DeckCard, kind: DeckKind, forceReverse: Bool? = nil) -> DeckItem {
        let reverse = forceReverse ?? (canReverse(card, kind: kind) && Bool.random())
        var item = DeckItem(cid: card.id, kind: kind, reverse: reverse)
        if kind == .match {
            item.options = options(for: card, reverse: reverse)
        }
        return item
    }

    private func answer(of card: DeckCard, reverse: Bool) -> String? {
        let sp = (reverse ? card.r : nil) ?? card.f
        return sp.isSupported ? sp.a : nil
    }

    private func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// The correct answer plus three wrong ones, in random order.
    private func options(for card: DeckCard, reverse: Bool) -> [String] {
        let sp = (reverse ? card.r : nil) ?? card.f
        let a = sp.a
        var pool: [String]
        if let o = sp.opts {
            pool = o
        } else if let p = sp.pool {
            pool = p
        } else if sp.t == "num", let n = Int(a) {
            pool = Array(max(0, n - 4)...(n + 4)).map { String($0) }
        } else if sp.t == "note" {
            pool = DeckStore.noteLabels
        } else {
            pool = data.cards
                .filter { $0.grp == card.grp && $0.id != card.id }
                .compactMap { answer(of: $0, reverse: reverse) }
        }
        pool = unique(pool).filter { $0 != a }
        if pool.count < 3 {
            let more = data.cards
                .filter { $0.cat == card.cat && $0.id != card.id }
                .compactMap { answer(of: $0, reverse: reverse) }
            pool = unique(pool + more).filter { $0 != a }
        }
        if pool.count < 3 {
            let more = data.cards
                .filter { $0.id != card.id }
                .compactMap { answer(of: $0, reverse: reverse) }
            pool = unique(pool + more).filter { $0 != a }
        }
        return ([a] + pool.shuffled().prefix(3)).shuffled()
    }

    // MARK: Answering

    func pick(_ index: Int) {
        guard let q = quiz, q.answered == nil, let item = q.current,
              item.options.indices.contains(index), let sp = spec(for: item)
        else { return }
        record(ok: item.options[index] == sp.a, pick: index)
    }

    func checkTyped(_ raw: String) {
        guard let q = quiz, q.answered == nil, let item = q.current, let sp = spec(for: item),
              !raw.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        var result = grader.grade(sp, raw)
        if item.hint && result.ok {
            result = DeckGrade(ok: false, note: "Correct, but a hint was used, so it goes back in the pile.")
        }
        record(ok: result.ok, typed: raw, note: result.note)
    }

    func giveUp() {
        record(ok: false)
    }

    func useHint() {
        guard var q = quiz, q.answered == nil, !q.queue.isEmpty else { return }
        q.queue[0].hint = true
        quiz = q
    }

    private func record(ok: Bool, typed: String = "", note: String = "", pick: Int? = nil) {
        guard var q = quiz, let item = q.current else { return }
        let key = String(item.cid)
        let snapshot = DeckSnapshot(cid: item.cid, wasFirst: q.firstTry[item.cid] == nil,
                                    progress: state.cards[key], missedCount: q.missed.count)
        if q.firstTry[item.cid] == nil {
            q.firstTry[item.cid] = ok
            if !ok {
                q.missed.append(item.cid)
                var p = state.cards[key] ?? DeckCardProgress(box: 0, due: 0)
                p.miss = (p.miss ?? 0) + 1
                state.cards[key] = p
            }
        }
        if q.kind == .review || q.kind == .practice {
            var p = state.cards[key] ?? DeckCardProgress(box: 1, due: DeckStore.today())
            if !item.retry {
                if ok {
                    p.box = min(max(p.box, 1) + 1, DeckStore.intervals.count - 1)
                    p.due = DeckStore.today() + DeckStore.intervals[p.box]
                } else {
                    p.box = 1
                    p.due = DeckStore.today() + 1
                }
            }
            state.cards[key] = p
        }
        state.stats.answers += 1
        q.answered = DeckAnswered(ok: ok, typed: typed, note: note, pick: pick, snapshot: snapshot)
        quiz = q
    }

    /// "I was right": undo the miss and count it as correct.
    func overrideRight() {
        guard var q = quiz, let a = q.answered, !a.ok else { return }
        let s = a.snapshot
        if s.wasFirst { q.firstTry[s.cid] = nil }
        if q.missed.count > s.missedCount { q.missed.removeLast(q.missed.count - s.missedCount) }
        if let p = s.progress { state.cards[String(s.cid)] = p } else { state.cards[String(s.cid)] = nil }
        state.stats.answers -= 1
        q.answered = nil
        quiz = q
        record(ok: true, typed: a.typed, note: "Counted as right — your call.")
    }

    func advance() {
        guard var q = quiz, !q.queue.isEmpty else { return }
        let item = q.queue.removeFirst()
        if q.answered?.ok == true {
            q.doneIds.insert(item.cid)
        } else if let card = data.card(item.cid) {
            q.queue.append(retry(of: item, card: card))
        }
        q.answered = nil
        quiz = q
        if q.queue.isEmpty { finishQuiz() }
    }

    private func retry(of item: DeckItem, card: DeckCard) -> DeckItem {
        let reverse = canReverse(card, kind: item.kind) ? !item.reverse : item.reverse
        var next = makeItem(card, kind: item.kind, forceReverse: reverse)
        next.retry = true
        return next
    }

    private func finishQuiz() {
        guard let q = quiz else { return }
        let results = q.firstTry
        let right = results.values.filter { $0 }.count
        let score = results.isEmpty ? 0 : Int((Double(right) / Double(results.count) * 100).rounded())
        var passed = true
        if q.kind == .batch, let key = q.modeKey, let i = state.batches.indices.last {
            var st = state.batches[i].state(key)
            if st.first == nil { st.first = score }
            st.best = max(st.best ?? 0, score)
            if score >= state.settings.passMark { st.passed = true }
            state.batches[i].modes[key] = st
            passed = st.passed && score >= state.settings.passMark
        }
        bumpStreak()
        persist()
        lastResult = DeckResult(kind: q.kind, modeKey: q.modeKey, score: score, missed: q.missed, passed: passed)
        quiz = nil
    }
}

// MARK: - Library
// Opens courses on demand and keeps them, so progress isn't reloaded each visit.

final class DeckLibrary: ObservableObject {
    let summaries: [DeckSummary]
    private var stores: [String: DeckStore] = [:]
    @Published var revision = 0

    init() {
        summaries = DeckCatalog.summaries()
    }

    func store(for slug: String) -> DeckStore? {
        if let existing = stores[slug] { return existing }
        guard let data = DeckCatalog.load(slug) else { return nil }
        let store = DeckStore(data: data)
        stores[slug] = store
        return store
    }

    func learned(_ slug: String) -> Int {
        if let s = stores[slug] { return s.learnedCount }
        return DeckStore.learnedCount(slug: slug)
    }

    func refresh() { revision += 1 }
}
