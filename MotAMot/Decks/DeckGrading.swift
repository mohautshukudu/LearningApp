import Foundation

// MARK: - Marking typed answers
// A port of the web apps' squash / gradeTyped / gradeMusic.

struct DeckGrade {
    let ok: Bool
    var note: String = ""
}

struct DeckGrader {
    let norm: [[String]]
    let pySquash: Bool

    init(data: DeckData) {
        norm = data.norm
        pySquash = data.pySquash
    }

    // MARK: Regex helpers

    private static func replace(_ s: String, _ pattern: String, _ with: String, ignoreCase: Bool = false) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: with)
    }

    private static let ordinals: [(String, String)] = [
        ("first", "1st"), ("second", "2nd"), ("third", "3rd"), ("fourth", "4th"),
        ("fifth", "5th"), ("sixth", "6th"), ("seventh", "7th"), ("eighth", "8th"),
    ]

    // MARK: Squash

    /// Reduces an answer to something safe to compare: no case, accents, spaces or punctuation.
    func squash(_ input: String) -> String {
        if pySquash {
            var s = Self.replace(input, "\\s+", " ")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            s = Self.replace(s, "[“”\"]", "'")
            return Self.replace(s, "[‘’]", "'")
        }
        var s = input
        for rule in norm where rule.count == 2 {
            s = Self.replace(s, rule[0], rule[1], ignoreCase: true)
        }
        s = s.lowercased().decomposedStringWithCanonicalMapping
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }))
        s = s.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        for (word, short) in Self.ordinals {
            s = Self.replace(s, "\\b\(word)\\b", short)
        }
        s = Self.replace(s, "^(the|a|an)\\s+", "")
        s = Self.replace(s, "[\\s\\-_.,'\"’()+]", "")
        return s
    }

    // MARK: Grading

    func grade(_ spec: DeckSpec, _ raw: String) -> DeckGrade {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch spec.t {
        case "num":
            return DeckGrade(ok: typed == spec.a)
        case "text":
            let accepted = spec.acc ?? [spec.a]
            let ok = accepted.contains { x in
                if x.hasPrefix("=") { return typed == String(x.dropFirst()) }
                return squash(typed) == squash(x)
            }
            return DeckGrade(ok: ok)
        case "note":
            return gradeNote(spec, typed)
        case "tokens":
            return gradeTokens(spec, typed)
        default:
            return DeckGrade(ok: false)
        }
    }

    /// First letter shown, the rest as underscores.
    func hint(for spec: DeckSpec) -> String {
        var out = ""
        for (i, ch) in spec.a.enumerated() {
            if ch.isWhitespace { out.append(ch) } else { out.append(i == 0 ? ch : "_") }
        }
        return Self.replace(out, "_(?=_)", "_ ")
    }

    // MARK: Music

    private static let letterPC: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    /// "F#", "Bb", "E♭" -> pitch class 0...11.
    static func pitchClass(_ name: String) -> Int? {
        guard let first = name.uppercased().first, let base = letterPC[first] else { return nil }
        var pc = base
        for ch in name.dropFirst() {
            if ch == "#" || ch == "♯" { pc += 1 }
            else if ch == "b" || ch == "♭" { pc -= 1 }
        }
        return ((pc % 12) + 12) % 12
    }

    private func gradeNote(_ spec: DeckSpec, _ typed: String) -> DeckGrade {
        guard typed.count >= 1, typed.count <= 2,
              let first = typed.first, "ABCDEFGabcdefg".contains(first),
              typed.dropFirst().allSatisfy({ "#b♯♭".contains($0) })
        else { return DeckGrade(ok: false, note: "Type just a note name, like C, F# or Bb.") }
        let name = first.uppercased() + String(typed.dropFirst())
        let ok: Bool
        if let pc = spec.pc {
            ok = Self.pitchClass(name) == pc
        } else {
            ok = DeckGrader.sameLetters(typed, spec.a)
        }
        var note = ""
        if ok, typed.uppercased() != spec.a.uppercased(), spec.a.count < 3 {
            note = "Same pitch. In this context it's spelled \(spec.a)."
        }
        return DeckGrade(ok: ok, note: note)
    }

    private static func sameLetters(_ a: String, _ b: String) -> Bool {
        let fix = { (s: String) in s.uppercased().replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "B") }
        return fix(a) == fix(b)
    }

    /// "Am", "F#dim", "Bb" -> root and quality.
    private static func chordToken(_ raw: String) -> (root: String, quality: String)? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        t = t.replacingOccurrences(of: "°", with: "dim")
        guard let first = t.first, "ABCDEFGabcdefg".contains(first) else { return nil }
        var rest = t.dropFirst()
        var accidental = ""
        if let a = rest.first, a == "#" || a == "b" {
            accidental = String(a)
            rest = rest.dropFirst()
        }
        var quality = rest.lowercased()
        if ["m", "min", "-", "minor"].contains(quality) { quality = "m" }
        else if ["dim", "o"].contains(quality) { quality = "dim" }
        else if ["", "maj", "major"].contains(quality) { quality = "" }
        return (first.uppercased() + accidental, quality)
    }

    private func gradeTokens(_ spec: DeckSpec, _ typed: String) -> DeckGrade {
        let want = spec.toks ?? []
        if want.first == "none" {
            let squashed = typed.lowercased().filter { !$0.isWhitespace }
            return DeckGrade(ok: ["none", "no", "nothing", "0", "zero", "nosharpsorflats"].contains(squashed))
        }
        let parts = typed
            .components(separatedBy: CharacterSet(charactersIn: " ,;\n\t"))
            .filter { !$0.isEmpty }
        let got = parts.map(Self.chordToken)
        guard got.count == want.count, !got.contains(where: { $0 == nil }) else { return DeckGrade(ok: false) }
        let gotTokens = got.compactMap { $0 }
        let wantTokens = want.compactMap(Self.chordToken)
        guard wantTokens.count == want.count else { return DeckGrade(ok: false) }

        let exact = zip(gotTokens, wantTokens).allSatisfy { $0.root == $1.root && $0.quality == $1.quality }
        if exact { return DeckGrade(ok: true) }
        let samePitches = zip(gotTokens, wantTokens).allSatisfy {
            Self.pitchClass($0.root) == Self.pitchClass($1.root) && $0.quality == $1.quality
        }
        if samePitches { return DeckGrade(ok: true, note: "Same pitches. Spelled properly: \(spec.a)") }
        return DeckGrade(ok: false)
    }
}
