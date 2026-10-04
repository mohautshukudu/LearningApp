import Foundation

struct AnswerCheck {
    let ok: Bool
    let note: String
}

/// Marking typed answers. French is strict about the word but forgiving about
/// accents; English has to accept every listed meaning, plurals, UK/US spelling
/// and small typos, because there is rarely one single right translation.
enum Answers {

    // MARK: - Shared text helpers

    /// Lowercase, accents removed, punctuation out. "Être" and "etre" land together.
    static func norm(_ s: String) -> String {
        let folded = s.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        for c in folded {
            if ("a"..."z").contains(c) || c == "'" || c == "-" || c == " " {
                out.append(c)
            } else {
                out.append(" ")
            }
        }
        return collapse(out)
    }

    /// Lowercase and punctuation out, but accents kept — this is what decides
    /// whether an answer was spelled perfectly.
    static func soft(_ s: String) -> String {
        let base = s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "`", with: "'")
        var out = ""
        for c in base {
            if c.isLetter || c == "'" || c == "-" || c == " " {
                out.append(c)
            } else {
                out.append(" ")
            }
        }
        return collapse(out)
    }

    static func collapse(_ s: String) -> String {
        s.split(separator: " ").joined(separator: " ")
    }

    /// Drops a leading article so "le chien" is accepted for "chien".
    static func stripArticle(_ s: String) -> String {
        for a in ["le ", "la ", "les ", "un ", "une ", "des ", "se "] where s.hasPrefix(a) {
            let rest = String(s.dropFirst(a.count))
            if !rest.isEmpty { return rest }
        }
        for a in ["l'", "s'"] where s.hasPrefix(a) {
            let rest = String(s.dropFirst(a.count))
            if !rest.isEmpty { return rest }
        }
        return s
    }

    // MARK: - French

    /// Spellings that count as the word: the word itself, plus an irregular
    /// plural when the meaning names one.
    static func acceptedForms(_ w: Word) -> [String] {
        var forms = [w.fr]
        if let r = w.en.range(of: "pl. ") {
            let tail = w.en[r.upperBound...]
            if let close = tail.firstIndex(of: ")") {
                let plural = tail[tail.startIndex..<close].trimmingCharacters(in: .whitespaces)
                if !plural.isEmpty { forms.append(plural) }
            }
        }
        if w.fr == "œil" { forms.append("yeux") }
        return forms
    }

    static func frenchHint(_ w: Word) -> String {
        maskAfterFirst(w.fr)
    }

    static func checkFrench(typed raw: String, word w: Word, hintUsed: Bool) -> AnswerCheck? {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return nil }

        let softTyped = soft(typed)
        let normTyped = norm(typed)
        let softSet = [softTyped, stripArticle(softTyped)]
        let normSet = [normTyped, stripArticle(normTyped)]
        let forms = acceptedForms(w)

        var ok = false
        var note = ""

        if forms.contains(where: { softSet.contains(soft($0)) }) {
            ok = true
        } else if forms.contains(where: { normSet.contains(norm($0)) }) {
            ok = true
            note = "Right word, watch the accents: \(w.fr)"
        } else if let alt = otherWordWithSameMeaning(w, normSet: normSet) {
            ok = true
            note = "“\(alt.fr)” also works. The word we're drilling is “\(w.fr)”."
        }

        if hintUsed && ok {
            ok = false
            if note.isEmpty { note = "Correct, but a hint was used, so it goes back in the pile." }
        }
        return AnswerCheck(ok: ok, note: note)
    }

    private static func otherWordWithSameMeaning(_ w: Word, normSet: [String]) -> Word? {
        guard !w.primaryGloss.isEmpty, let ids = Dataset.byGloss[w.primaryGloss] else { return nil }
        for id in ids where id != w.id {
            guard let other = Dataset.word(id) else { continue }
            if normSet.contains(norm(other.fr)) { return other }
        }
        return nil
    }

    // MARK: - English

    /// One meaning, reduced to a comparable key: lowercase, no punctuation, no
    /// leading "to"/"a"/"the".
    static func enKey(_ s: String) -> String {
        var out = ""
        for c in s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") {
            if ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "'" || c == " " {
                out.append(c)
            } else {
                out.append(" ")
            }
        }
        var key = collapse(out)
        for lead in ["to ", "a ", "an ", "the "] where key.hasPrefix(lead) {
            let rest = String(key.dropFirst(lead.count))
            if !rest.isEmpty { key = rest }
            break
        }
        return key
    }

    private static var altCache: [Int: [String]] = [:]

    /// Every English answer that should count for a word.
    static func enAlts(_ w: Word) -> [String] {
        if let cached = altCache[w.id] { return cached }
        var out: [String] = []
        func add(_ s: String) {
            let k = enKey(s)
            guard !k.isEmpty else { return }
            if !out.contains(k) { out.append(k) }
            // "be able to" should also answer as "be able"
            for tail in [" to", " of"] where k.hasSuffix(tail) {
                let shorter = String(k.dropLast(tail.count))
                if !shorter.isEmpty && !out.contains(shorter) { out.append(shorter) }
            }
        }
        let withoutBrackets = removeBrackets(w.en)
        for rawPart in withoutBrackets.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            add(part)
            // "to him/her" also means "to him" and "to her"
            if part.contains("/") {
                let words = part.split(separator: " ").map(String.init)
                for (i, token) in words.enumerated() where token.contains("/") {
                    let options = token.split(separator: "/").map(String.init)
                    for option in options {
                        var copy = words
                        copy[i] = option
                        add(copy.joined(separator: " "))
                    }
                }
            }
        }
        if out.isEmpty {
            // e.g. est-ce que, whose whole meaning is "(question marker)"
            add(w.en.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " "))
        }
        altCache[w.id] = out
        return out
    }

    private static func removeBrackets(_ s: String) -> String {
        var out = ""
        var depth = 0
        for c in s {
            if c == "(" { depth += 1; out.append(" ") }
            else if c == ")" { depth = max(0, depth - 1); out.append(" ") }
            else if depth == 0 { out.append(c) }
        }
        return out
    }

    /// Every meaning in the whole list, so a real word belonging to a different
    /// card is never waved through as a typo.
    private static let allEnglishKeys: Set<String> = {
        var set = Set<String>()
        for w in Dataset.words { for k in enAlts(w) { set.insert(k) } }
        return set
    }()

    private static let irregularPlurals: [String: String] = [
        "man": "men", "woman": "women", "child": "children", "person": "people",
        "foot": "feet", "tooth": "teeth", "mouse": "mice", "wife": "wives",
        "life": "lives", "knife": "knives", "leaf": "leaves", "half": "halves",
        "wolf": "wolves", "shelf": "shelves", "thief": "thieves"
    ]

    static func isPluralPair(_ a: String, _ b: String) -> Bool {
        func oneWay(_ x: String, _ y: String) -> Bool {
            if x + "s" == y { return true }
            if x + "es" == y { return true }
            if x.hasSuffix("y") && String(x.dropLast()) + "ies" == y { return true }
            if irregularPlurals[x] == y { return true }
            // "bank card" → "bank cards", "young man" → "young men"
            if let space = x.lastIndex(of: " ") {
                let head = String(x[x.startIndex...space])
                let tail = String(x[x.index(after: space)...])
                if let irr = irregularPlurals[tail], head + irr == y { return true }
            }
            return false
        }
        return oneWay(a, b) || oneWay(b, a)
    }

    private static let spellingRules: [(NSRegularExpression, String)] = {
        let raw: [(String, String)] = [
            ("ization", "isation"),
            ("([a-z])iz(e|es|ed|ing|er|ers)\\b", "$1is$2"),
            ("yz(e|es|ed|ing)\\b", "ys$1"),
            ("\\b(col|fav|hon|neighb|behavi|lab|flav|hum|harb|rum|arm|vap|savi|rig|endeav)or(s|ed|ing|ite|ites|ful)?\\b", "$1our$2"),
            ("\\b(cent|theat|met|lit|fib|kilomet)er(s)?\\b", "$1re$2"),
            ("\\bgray\\b", "grey"),
            ("\\bprogram(s)?\\b", "programme$1"),
            ("\\btravel(ed|ing|er)\\b", "travell$1"),
            ("\\bdefense\\b", "defence"),
            ("\\blicense\\b", "licence"),
            ("\\bmom\\b", "mum")
        ]
        return raw.compactMap { pattern, template in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (re, template)
        }
    }()

    /// Folds US spelling into UK spelling so "color" and "colour" are one word.
    static func ukSpelling(_ s: String) -> String {
        var out = s
        for (re, template) in spellingRules {
            let range = NSRange(location: 0, length: (out as NSString).length)
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: template)
        }
        return out
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[y.count]
    }

    enum MatchKind { case exact, typo }
    struct EnglishMatch { let kind: MatchKind; let alt: String }

    static func englishMatch(_ typedKey: String, alts: [String]) -> EnglishMatch? {
        func squash(_ s: String) -> String {
            ukSpelling(s).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
        }
        let typedSquashed = squash(typedKey)
        let typedUK = ukSpelling(typedKey)
        for a in alts {
            if squash(a) == typedSquashed { return EnglishMatch(kind: .exact, alt: a) }
            if isPluralPair(ukSpelling(a), typedUK) { return EnglishMatch(kind: .exact, alt: a) }
        }
        // a real English word from another card is a wrong answer, not a typo
        if allEnglishKeys.contains(typedKey) { return nil }
        for a in alts {
            let n = squash(a).count
            let limit = n >= 9 ? 2 : (n >= 5 ? 1 : 0)
            if limit > 0 && levenshtein(squash(a), typedSquashed) <= limit {
                return EnglishMatch(kind: .typo, alt: a)
            }
        }
        return nil
    }

    static func englishHint(_ w: Word) -> String {
        let cleaned = removeBrackets(w.en)
        let first = cleaned.split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
            ?? w.en.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
        if first.lowercased().hasPrefix("to ") {
            return "to " + maskAfterFirst(String(first.dropFirst(3)))
        }
        return maskAfterFirst(first)
    }

    /// "environment" → "e _ _ _ _ _ _ _ _ _ _"
    private static func maskAfterFirst(_ s: String) -> String {
        guard let first = s.first else { return "" }
        var out = String(first)
        for c in s.dropFirst() {
            if c == " " || c == "'" || c == "-" { out.append(c) } else { out.append(" _") }
        }
        return out
    }

    static func checkEnglish(typed raw: String, word w: Word, hintUsed: Bool) -> AnswerCheck? {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return nil }
        let alts = enAlts(w)

        let whole = enKey(typed)
        if whole.isEmpty { return nil }

        var ok = false
        var note = ""

        if let m = englishMatch(whole, alts: alts) {
            ok = true
            if m.kind == .typo { note = "Close enough — it's spelled “\(m.alt)”." }
        } else {
            // they may have given several meanings: all of them must be right
            let parts = typed.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" })
                .map { enKey(String($0)) }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                let hits = parts.map { englishMatch($0, alts: alts) }
                if hits.allSatisfy({ $0 != nil }) {
                    ok = true
                    if let typo = hits.compactMap({ $0 }).first(where: { $0.kind == .typo }) {
                        note = "Close enough — it's spelled “\(typo.alt)”."
                    }
                }
            }
            // the same French spelling can be a second word with its own meaning
            if !ok, parts.count <= 1, let twin = homograph(of: w, answering: whole) {
                ok = true
                note = "That's the other meaning of “\(w.fr)” (\(twin.pos)). This card is the \(w.pos)."
            }
        }

        if hintUsed && ok {
            ok = false
            if note.isEmpty { note = "Correct, but a hint was used, so it goes back in the pile." }
        }
        return AnswerCheck(ok: ok, note: note)
    }

    private static func homograph(of w: Word, answering key: String) -> Word? {
        for other in Dataset.words where other.id != w.id && other.fr == w.fr {
            if englishMatch(key, alts: enAlts(other)) != nil { return other }
        }
        return nil
    }
}
