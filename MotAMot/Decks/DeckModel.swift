import Foundation

// MARK: - Deck content
// Decoded from the JSON that tools/export_decks.js writes out of the web apps,
// so every course (Python, Excel, Atlas, guitar...) shares one engine.

struct DeckSpec: Codable, Hashable {
    var p: String                 // prompt, a little HTML (<b>, <code>)
    var a: String                 // the answer
    var t: String                 // text, num, note, tokens (or tap, which isn't playable yet)
    var acc: [String]?            // other accepted typed answers
    var opts: [String]?           // fixed answer options for match
    var pool: [String]?           // wrong answers to draw from
    var ph: String?               // placeholder for the typed answer
    var sub: String?
    var vis: String?              // HTML shown under the prompt (code, table, SVG...)
    var matchOnly: Bool?          // too long to type, so only used in Match
    var pc: Int?                  // pitch class, for note questions
    var toks: [String]?           // expected tokens, for chord/key questions
    var audio: Bool?              // needs sound to answer

    /// Question types the native app can ask today.
    var isSupported: Bool {
        t == "text" || t == "num" || t == "note" || t == "tokens"
    }
}

struct DeckCard: Codable, Identifiable, Hashable {
    let id: Int
    let cat: String
    let grp: String
    let ti: String
    let teach: String
    let why: String
    let f: DeckSpec               // forward question
    let r: DeckSpec?              // reverse question
    let hear: Bool

    /// Cards that need sound or a map tap can still be studied, but not tested yet.
    var isQuizzable: Bool { f.isSupported && f.audio != true }
}

struct DeckStage: Codable, Hashable {
    let name: String
    let start: Int
    let end: Int
}

struct DeckKeys: Codable, Hashable {
    let prefix: String
    let keys: [String]
}

struct DeckData: Codable {
    let slug: String
    let name: String
    let blurb: String
    let theme: String
    let css: String
    let cats: [String: String]
    let catOrder: [String]
    let stages: [DeckStage]
    let cards: [DeckCard]
    let norm: [[String]]          // [pattern, replacement] pairs, applied before comparing
    let pySquash: Bool            // Python answers are case sensitive
    let keys: DeckKeys?

    func card(_ id: Int) -> DeckCard? {
        id >= 0 && id < cards.count ? cards[id] : nil
    }

    func catName(_ key: String) -> String { cats[key] ?? key }
}

struct DeckSummary: Codable, Identifiable, Hashable {
    let slug: String
    let name: String
    let blurb: String
    let theme: String
    let total: Int

    var id: String { slug }

    var symbol: String {
        switch slug {
        case "fret-by-fret": return "music.note"
        case "atlas": return "globe.europe.africa"
        case "py-by-py": return "chevron.left.forwardslash.chevron.right"
        case "slide-by-slide": return "rectangle.on.rectangle"
        case "desk-skills": return "tablecells"
        default: return "square.stack.3d.up"
        }
    }
}

enum DeckCatalog {
    static func summaries() -> [DeckSummary] {
        guard let url = Bundle.main.url(forResource: "decks-index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([DeckSummary].self, from: data)
        else { return [] }
        return list
    }

    static func load(_ slug: String) -> DeckData? {
        guard let url = Bundle.main.url(forResource: slug, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(DeckData.self, from: data)
    }
}

// MARK: - Small HTML to text helper
// Prompts only use <b>, <i> and <code>, so they become styled Text instead of
// a web view. Anything richer (tables, SVG, code blocks) goes through DeckRich.

enum DeckText {
    static func attributed(_ html: String) -> AttributedString {
        var out = AttributedString()
        var buffer = ""
        var bold = false, italic = false, code = false

        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            var intent: InlinePresentationIntent = []
            if bold { intent.insert(.stronglyEmphasized) }
            if italic { intent.insert(.emphasized) }
            if code { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            out.append(piece)
            buffer = ""
        }

        var i = html.startIndex
        while i < html.endIndex {
            let ch = html[i]
            if ch == "<", let close = html[i...].firstIndex(of: ">") {
                let raw = html[html.index(after: i)..<close].lowercased()
                let name = raw.split(whereSeparator: { $0 == " " || $0 == "/" }).first.map(String.init) ?? ""
                let closing = raw.hasPrefix("/")
                flush()
                switch name {
                case "b", "strong": bold = !closing
                case "i", "em": italic = !closing
                case "code": code = !closing
                case "br": buffer = "\n"; flush()
                default: break
                }
                i = html.index(after: close)
            } else if ch == "&", let semi = html[i...].prefix(10).firstIndex(of: ";") {
                let entity = String(html[html.index(after: i)..<semi])
                if let decoded = decode(entity) {
                    buffer += decoded
                    i = html.index(after: semi)
                } else {
                    buffer.append(ch)
                    i = html.index(after: i)
                }
            } else {
                buffer.append(ch)
                i = html.index(after: i)
            }
        }
        flush()
        return out
    }

    /// The same text with every tag removed.
    static func plain(_ html: String) -> String {
        String(attributed(html).characters)
    }

    private static func decode(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        case "hellip": return "…"
        case "ndash": return "–"
        case "mdash": return "—"
        default:
            if entity.hasPrefix("#x"), let n = UInt32(entity.dropFirst(2), radix: 16),
               let s = Unicode.Scalar(n) { return String(Character(s)) }
            if entity.hasPrefix("#"), let n = UInt32(entity.dropFirst()),
               let s = Unicode.Scalar(n) { return String(Character(s)) }
            return nil
        }
    }
}
