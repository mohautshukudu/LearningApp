import Foundation

// MARK: - Session shapes

enum QuestionKind: String {
    case match          // pick from four
    case type           // see the English, type the French
    case typeEnglish    // see the French, type the English

    var isTyping: Bool { self != .match }

    var practiceName: String {
        switch self {
        case .match: return "Match"
        case .type: return "Type French"
        case .typeEnglish: return "Type English"
        }
    }
}

enum QuizKind {
    case batch, review, practice
}

enum Direction {
    case frenchToEnglish, englishToFrench
}

struct QuizItem: Identifiable {
    let id = UUID()
    let wid: Int
    var kind: QuestionKind
    var dir: Direction
    var hint = false
    var retry = false
    var options: [Int]? = nil

    var word: Word? { Dataset.word(wid) }
}

/// Enough state to undo one answer when he taps "I was right".
struct AnswerSnapshot {
    let wid: Int
    let wasFirstAttempt: Bool
    let progress: WordProgress?
    let missedCount: Int
}

struct Answered {
    let ok: Bool
    var typed: String = ""
    var note: String = ""
    var pick: Int? = nil
    let snapshot: AnswerSnapshot
}

struct QuizSession {
    let kind: QuizKind
    var mode: TestMode? = nil       // which level, when this is a batch test
    var questionKind: QuestionKind  // what the questions look like, when they are all the same
    var mixedKinds = false          // review can mix match and typing
    var queue: [QuizItem]
    let total: Int
    var firstTry: [Int: Bool] = [:]
    var doneIds: Set<Int> = []
    var answered: Answered? = nil
    var missed: [Int] = []
    var batchNumber: Int? = nil

    var current: QuizItem? { queue.first }

    var progressCount: Int { doneIds.count }

    var title: String {
        switch kind {
        case .review: return "Review"
        case .practice: return questionKind.practiceName + " practice"
        case .batch: return mode?.name ?? "Test"
        }
    }

    var subtitle: String {
        var parts: [String] = [title]
        if kind == .batch, let n = batchNumber { parts.append("Batch \(n)") }
        if kind == .practice { parts.append("not scored") }
        if current?.retry == true { parts.append("second go") }
        return parts.joined(separator: " · ")
    }
}

struct QuizResult {
    let kind: QuizKind
    let mode: TestMode?
    let score: Int
    let missed: [Int]
    let passed: Bool
    let batchComplete: Bool

    var isPractice: Bool { kind == .practice }

    var headline: String {
        if isPractice { return "Practice done" }
        if kind == .review { return "Révision terminée" }
        return passed ? "Level passed" : "Presque !"
    }

    func blurb(passMark: Int) -> String {
        if isPractice { return "right first time. Nothing was graded — misses come back in review." }
        if kind == .review { return "right first time. Missed words come back tomorrow." }
        if passed { return "right first time. You needed \(passMark)%." }
        return "right first time. You need \(passMark)% to pass. Missed words are below."
    }
}

struct StudySession {
    var ids: [Int]
    var index: Int = 0
    var hideMeanings = false
    var revealed = false

    var count: Int { ids.count }
    var word: Word? { ids.indices.contains(index) ? Dataset.word(ids[index]) : nil }
    var isLast: Bool { index >= ids.count - 1 }
}

let praiseLines = ["Bravo !", "Très bien !", "Parfait !", "Excellent !", "Super !", "C'est ça !", "Génial !"]

// MARK: - Running a quiz

extension Store {

    // MARK: Starting

    /// A new order every session, but the first 100 words come first — they are
    /// about half of everyday speech.
    private func studyOrder(_ ids: [Int]) -> [Int] {
        let core = ids.filter { $0 < 100 }.shuffled()
        let rest = ids.filter { $0 >= 100 }.shuffled()
        return core + rest
    }

    func startStudy(ids: [Int]) {
        guard !ids.isEmpty else { return }
        study = StudySession(ids: studyOrder(ids))
    }

    private func makeItems(_ words: [Word], kind: @escaping (Word) -> QuestionKind) -> [QuizItem] {
        words.shuffled().map { w in
            let k = kind(w)
            return QuizItem(wid: w.id,
                            kind: k,
                            dir: Bool.random() ? .frenchToEnglish : .englishToFrench,
                            options: k == .match ? choices(for: w) : nil)
        }
    }

    func startTest(_ mode: TestMode) {
        guard let b = currentBatch else { return }
        let words = batchWords(b)
        guard !words.isEmpty else { return }
        let kind: QuestionKind = mode == .match ? .match : .type
        quiz = QuizSession(kind: .batch,
                           mode: mode,
                           questionKind: kind,
                           queue: makeItems(words) { _ in kind },
                           total: words.count,
                           batchNumber: b.n)
    }

    func startPractice(ids: [Int], kind: QuestionKind) {
        let words = ids.compactMap { Dataset.word($0) }
        guard !words.isEmpty else { return }
        quiz = QuizSession(kind: .practice,
                           mode: nil,
                           questionKind: kind,
                           queue: makeItems(words) { _ in kind },
                           total: words.count,
                           batchNumber: nil)
    }

    func startReview(style: String) {
        if !style.isEmpty {
            state.settings.reviewMode = style
            persist()
        }
        let words = Array(dueWords.shuffled().prefix(40))
        guard !words.isEmpty else { return }
        let chosen = state.settings.reviewMode
        let kindFor: (Word) -> QuestionKind = { [weak self] w in
            if chosen == "type" { return .type }
            if chosen == "match" { return .match }
            let box = self?.progress(w.id)?.box ?? 1
            return box <= 1 ? .match : .type
        }
        quiz = QuizSession(kind: .review,
                           mode: nil,
                           questionKind: chosen == "type" ? .type : .match,
                           mixedKinds: chosen == "mixed",
                           queue: makeItems(words, kind: kindFor),
                           total: words.count,
                           batchNumber: nil)
    }

    // MARK: Multiple choice

    /// Three wrong answers that are plausible: same part of speech where
    /// possible, and drawn from words near this one in the list.
    private func choices(for w: Word) -> [Int] {
        let b = latestBatch
        let hi = min(Dataset.total, max((b.map { $0.start + $0.size } ?? 0) + 150, 60))
        let base = Dataset.words[0..<hi].filter {
            $0.id != w.id && $0.primaryGloss != w.primaryGloss && $0.fr != w.fr
        }
        let samePOS = base.filter { $0.pos == w.pos }
        let pool = samePOS.count >= 9 ? samePOS : base
        let near = pool.filter { abs($0.id - w.id) < 120 }
        let source = near.count >= 6 ? near : pool
        let picks = source.shuffled().prefix(3).map { $0.id }
        return ([w.id] + picks).shuffled()
    }

    // MARK: Answering

    private func record(ok: Bool, typed: String = "", note: String = "", pick: Int? = nil) {
        guard var q = quiz, let item = q.current else { return }
        let wid = item.wid
        let snapshot = AnswerSnapshot(wid: wid,
                                      wasFirstAttempt: q.firstTry[wid] == nil,
                                      progress: progress(wid),
                                      missedCount: q.missed.count)

        if q.firstTry[wid] == nil {
            q.firstTry[wid] = ok
            if !ok {
                q.missed.append(wid)
                var p = progress(wid) ?? WordProgress(box: 0, due: 0)
                p.miss = (p.miss ?? 0) + 1
                setProgress(wid, p)
            }
        }

        // Review and practice both feed the spaced schedule; a batch test doesn't,
        // because those words are still being learned.
        if q.kind == .review || q.kind == .practice {
            var p = progress(wid) ?? WordProgress(box: 1, due: Store.today())
            if !item.retry {
                if ok {
                    p.box = min(p.box + 1, Store.intervals.count - 1)
                    p.due = Store.today() + Store.intervals[p.box]
                } else {
                    p.box = 1
                    p.due = Store.today() + 1
                }
            }
            setProgress(wid, p)
        }

        state.stats.answers += 1
        q.answered = Answered(ok: ok, typed: typed, note: note, pick: pick, snapshot: snapshot)
        quiz = q
    }

    func pick(_ id: Int) {
        guard let q = quiz, q.answered == nil, let item = q.current else { return }
        record(ok: id == item.wid, pick: id)
    }

    func submitTyped(_ text: String) {
        guard let q = quiz, q.answered == nil, let item = q.current, let w = item.word else { return }
        let check: AnswerCheck?
        if item.kind == .typeEnglish {
            check = Answers.checkEnglish(typed: text, word: w, hintUsed: item.hint)
        } else {
            check = Answers.checkFrench(typed: text, word: w, hintUsed: item.hint)
        }
        guard let result = check else { return }   // empty input: nothing happens
        record(ok: result.ok, typed: text.trimmingCharacters(in: .whitespacesAndNewlines), note: result.note)
    }

    func useHint() {
        guard var q = quiz, q.answered == nil, !q.queue.isEmpty else { return }
        q.queue[0].hint = true
        quiz = q
    }

    func giveUp(typed: String) {
        guard let q = quiz, q.answered == nil else { return }
        record(ok: false, typed: typed.isEmpty ? "—" : typed)
    }

    /// English has more synonyms than any list can hold, so he can overrule the
    /// marking. This rewinds the miss, then records the answer as right.
    func overrideRight() {
        guard var q = quiz, let answered = q.answered, !answered.ok else { return }
        let snap = answered.snapshot
        if snap.wasFirstAttempt { q.firstTry[snap.wid] = nil }
        if q.missed.count > snap.missedCount { q.missed.removeLast(q.missed.count - snap.missedCount) }
        if let p = snap.progress { setProgress(snap.wid, p) } else { state.words[String(snap.wid)] = nil }
        state.stats.answers -= 1
        q.answered = nil
        quiz = q
        record(ok: true, typed: answered.typed, note: "Counted as right — your call.")
    }

    // MARK: Moving on

    func advance() {
        guard var q = quiz, let answered = q.answered, !q.queue.isEmpty else { return }
        let item = q.queue.removeFirst()
        if answered.ok {
            q.doneIds.insert(item.wid)
        } else {
            // a missed word comes back later in the same round, the other way round
            var again = QuizItem(wid: item.wid,
                                 kind: item.kind,
                                 dir: item.dir == .frenchToEnglish ? .englishToFrench : .frenchToEnglish,
                                 options: item.options)
            again.retry = true
            q.queue.append(again)
        }
        q.answered = nil
        quiz = q
        if q.queue.isEmpty { finishQuiz() }
    }

    func finishQuiz() {
        guard let q = quiz else { return }
        let answers = q.firstTry
        let score = answers.isEmpty ? 0
            : Int((Double(answers.values.filter { $0 }.count) / Double(answers.count) * 100).rounded())

        var passed = true
        if q.kind == .batch, let mode = q.mode, var b = state.batches.last, !b.done {
            var st = b.state(mode)
            if st.first == nil { st.first = score }
            st.best = max(st.best ?? 0, score)
            if score >= state.settings.passMark { st.passed = true }
            b.modes[mode.key] = st
            state.batches[state.batches.count - 1] = b
            passed = st.passed && score >= state.settings.passMark
        }

        let complete = state.batches.last.map { isComplete($0) } ?? false
        bumpStreak()
        persist()
        lastResult = QuizResult(kind: q.kind,
                                mode: q.mode,
                                score: score,
                                missed: q.missed,
                                passed: passed,
                                batchComplete: complete)
        quiz = nil
    }

    func quitQuiz() {
        quiz = nil
        persist()
    }

    func endStudy() {
        study = nil
    }

    /// After a level is passed, the obvious next thing to do.
    func nextMode(after mode: TestMode) -> TestMode? {
        guard let index = TestMode.allCases.firstIndex(of: mode) else { return nil }
        let next = index + 1
        return next < TestMode.allCases.count ? TestMode.allCases[next] : nil
    }

    /// The level a batch is up to: the first one not yet passed.
    func pendingMode(_ b: Batch) -> TestMode? {
        TestMode.allCases.first { isUnlocked(b, $0) && !b.state($0).passed }
    }
}
