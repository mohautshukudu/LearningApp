import Foundation

// MARK: - Word

struct Highlight: Hashable, Sendable {
    let start: Int
    let end: Int
}

struct Word: Identifiable, Hashable, Sendable {
    let id: Int
    let fr: String
    let gender: String          // "", "m", "f", "mf"
    let pos: String
    let en: String
    let rawEmoji: String
    let exFr: String
    let exEn: String
    let hl: Highlight?          // range of the word inside exFr, in UTF-16 offsets
    let formNote: String        // raw note from the data, e.g. "«je» form"
    let dictFr: String          // dictionary-form sentence, may be empty
    let dictEn: String

    /// Emoji is suppressed for grammar words, where a picture only confuses.
    var emoji: String {
        if Dataset.noEmojiPOS.contains(pos) { return "" }
        if Dataset.noEmojiWords.contains(fr) { return "" }
        return rawEmoji
    }

    /// The form of the word as it actually appears in the example sentence.
    var highlightedForm: String? {
        guard let hl = hl else { return nil }
        return Text16.slice(exFr, hl.start, hl.end)
    }

    /// True when the example uses a changed form (suis for être, chiens for chien).
    var formChanged: Bool {
        guard let form = highlightedForm else { return false }
        return Text16.normForm(form) != Text16.normForm(fr)
    }

    var genderLabel: String {
        guard pos == "noun" else { return "" }
        switch gender {
        case "m": return "masc."
        case "f": return "fem."
        case "mf": return "masc./fem."
        default: return ""
        }
    }

    /// "le ", "la ", "l'", "les " — only for nouns, so cards teach the gender with the word.
    var article: String {
        guard pos == "noun" else { return "" }
        if Dataset.pluralOnly.contains(fr) { return "les " }
        if startsWithVowelSound { return "l'" }
        return gender == "f" ? "la " : "le "
    }

    var withArticle: String { article + fr }

    private var startsWithVowelSound: Bool {
        guard let first = fr.lowercased().first else { return false }
        if "aeiouyàâäéèêëîïôöùûüœæ".contains(first) { return true }
        if first == "h" { return !Dataset.aspirateH.contains(fr) }
        return false
    }

    /// First meaning only, lowercased — used for matching and for photo search.
    var primaryGloss: String {
        var cut = en
        if let i = en.firstIndex(where: { $0 == "," || $0 == ";" || $0 == "(" }) {
            cut = String(en[en.startIndex..<i])
        }
        return cut.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The English term to look a photo up under, or nil when a photo makes no sense.
    var photoTerm: String? {
        guard pos == "noun" else { return nil }
        guard !en.trimmingCharacters(in: .whitespaces).hasPrefix("(") else { return nil }
        let t = primaryGloss
        guard let f = t.first else { return nil }
        return String(f).uppercased() + String(t.dropFirst())
    }
}

// MARK: - UTF-16 helpers
// The highlight offsets come from the web app, which counts UTF-16 units, so we
// slice the same way rather than by Character.

enum Text16 {
    static func slice(_ s: String, _ from: Int, _ to: Int) -> String? {
        let units = Array(s.utf16)
        guard from >= 0, to <= units.count, from < to else { return nil }
        return String(utf16CodeUnits: Array(units[from..<to]), count: to - from)
    }

    static func prefix(_ s: String, _ to: Int) -> String {
        slice(s, 0, to) ?? ""
    }

    static func suffix(_ s: String, _ from: Int) -> String {
        let units = Array(s.utf16)
        guard from >= 0, from < units.count else { return "" }
        return String(utf16CodeUnits: Array(units[from...]), count: units.count - from)
    }

    /// Lowercase, œ → oe, curly quote → straight. Keeps accents.
    static func normForm(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
}

// MARK: - Dataset

enum Dataset {
    static let noEmojiPOS: Set<String> = ["article", "prep", "conj", "pron", "det"]
    static let noEmojiWords: Set<String> = ["ne", "pas", "plus", "moins", "si", "en", "y"]
    static let pluralOnly: Set<String> = ["gens", "toilettes", "vacances", "lunettes", "pâtes", "félicitations"]
    static let aspirateH: Set<String> = ["haine", "hasard", "héros", "honte", "hâte", "haut"]

    static let words: [Word] = loadWords()
    static var total: Int { words.count }

    /// Every word that shares a first meaning, so "also correct" answers can be spotted.
    static let byGloss: [String: [Int]] = {
        var map: [String: [Int]] = [:]
        for w in words { map[w.primaryGloss, default: []].append(w.id) }
        return map
    }()

    /// Every surface form in French (29k of them) mapped to the word it belongs to.
    static let forms: [String: Int] = loadForms()

    static func word(_ id: Int) -> Word? {
        guard id >= 0, id < words.count else { return nil }
        return words[id]
    }

    private static func loadWords() -> [Word] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]]
        else {
            assertionFailure("words.json is missing from the app bundle")
            return []
        }
        var out: [Word] = []
        out.reserveCapacity(rows.count)
        for (i, row) in rows.enumerated() {
            // Word ids are positions in this file, and the forms index points at
            // them, so a short row must still take its place rather than shift
            // every word after it.
            func field(_ n: Int) -> String { n < row.count ? (row[n] as? String ?? "") : "" }
            let span = row.count > 7 ? ((row[7] as? [NSNumber])?.map { $0.intValue } ?? []) : []
            let dict = row.count > 9 ? ((row[9] as? [String]) ?? []) : []
            out.append(Word(
                id: i,
                fr: field(0),
                gender: field(1),
                pos: field(2),
                en: field(3),
                rawEmoji: field(4),
                exFr: field(5),
                exEn: field(6),
                hl: span.count == 2 ? Highlight(start: span[0], end: span[1]) : nil,
                formNote: field(8),
                dictFr: dict.count == 2 ? dict[0] : "",
                dictEn: dict.count == 2 ? dict[1] : ""
            ))
        }
        return out
    }

    private static func loadForms() -> [String: Int] {
        guard let url = Bundle.main.url(forResource: "forms_index", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        var map: [String: Int] = [:]
        map.reserveCapacity(32000)
        for pair in raw.split(separator: " ") {
            guard let colon = pair.lastIndex(of: ":") else { continue }
            let form = String(pair[pair.startIndex..<colon])
            let idPart = pair[pair.index(after: colon)...]
            guard !form.isEmpty, let id = Int(idPart) else { continue }
            map[form] = id
        }
        return map
    }

    /// Which word a piece of running French text belongs to, or nil.
    static func lookupForm(_ token: String) -> Int? {
        let t = Text16.normForm(token)
        if let id = forms[t] { return id }
        // strip an elided article: l'eau → eau, qu'il → il
        if let apos = t.firstIndex(of: "'") {
            let head = String(t[t.startIndex..<apos])
            if ["l", "d", "j", "n", "m", "t", "s", "c", "qu"].contains(head) {
                let bare = String(t[t.index(after: apos)...])
                if let id = forms[bare] { return id }
            }
        }
        return nil
    }

    /// Rough share of everyday speech covered by the first n words.
    static func coverage(_ n: Int) -> Int {
        if n <= 0 { return 0 }
        let points: [(Int, Int)] = [(10, 25), (50, 45), (100, 53), (250, 63), (500, 71), (1000, 79), (2000, 86)]
        var prev = (0, 0)
        for p in points {
            if n <= p.0 {
                let span = Double(p.0 - prev.0)
                let grow = Double(p.1 - prev.1)
                return Int((Double(prev.1) + grow * Double(n - prev.0) / span).rounded())
            }
            prev = p
        }
        return 86
    }
}

// MARK: - Contractions

struct Contraction: Identifiable {
    let id = UUID()
    let whole: String       // c'est
    let full: String        // ce
    let rest: String        // est
    let note: String        // être, when the rest is a changed form
}

enum Grammar {
    static let elision: [String: String] = [
        "c": "ce", "j": "je", "n": "ne", "d": "de", "qu": "que", "s": "se",
        "t": "te", "m": "me", "l": "le / la", "jusqu": "jusque",
        "lorsqu": "lorsque", "puisqu": "puisque"
    ]

    private static let contractionRE = try? NSRegularExpression(
        pattern: "([A-Za-zÀ-ÿŒœ]+)[\u{2019}']([A-Za-zÀ-ÿŒœ-]+)")

    /// Spells out c'est as ce + est, so contractions stop looking like new words.
    static func contractions(in text: String) -> [Contraction] {
        guard let re = contractionRE else { return [] }
        let ns = text as NSString
        var out: [Contraction] = []
        var seen = Set<String>()
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges == 3 else { continue }
            let whole = ns.substring(with: m.range)
            let head = Text16.normForm(ns.substring(with: m.range(at: 1)))
            let rest = ns.substring(with: m.range(at: 2))
            guard let full = elision[head] else { continue }
            let key = Text16.normForm(whole)
            if seen.contains(key) { continue }
            seen.insert(key)
            var note = ""
            if let id = Dataset.lookupForm(rest), let w = Dataset.word(id),
               Text16.normForm(w.fr) != Text16.normForm(rest) {
                note = w.fr
            }
            out.append(Contraction(whole: whole, full: full, rest: rest, note: note))
        }
        return out
    }

    /// Plain-English label for the form the example uses.
    static func shortForm(_ note: String) -> String {
        let n = Text16.normForm(note)
        if n.isEmpty { return "" }
        if let open = n.firstIndex(of: "«"), let close = n.firstIndex(of: "»"), open < close {
            let inner = String(n[n.index(after: open)..<close])
            return inner + " form"
        }
        if n.contains("past participle") { return "past form" }
        if n.contains("command") { return "command form" }
        if n.contains("feminine plural") { return "feminine plural" }
        if n.contains("feminine") { return "feminine" }
        if n.contains("plural") { return "plural" }
        if n.contains("-ant") { return "-ant form" }
        return "another form"
    }

    private static let tokenRE = try? NSRegularExpression(
        pattern: "[A-Za-zÀ-ÿŒœ]+(?:['\u{2019}-][A-Za-zÀ-ÿŒœ]+)*")

    /// Splits running French text into words, keeping where each one sits.
    static func tokens(in text: String) -> [(text: String, range: NSRange)] {
        guard let re = tokenRE else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { (ns.substring(with: $0.range), $0.range) }
    }
}
