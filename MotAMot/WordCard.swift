import SwiftUI

// MARK: - The card used on study, in search results and in the quiz feedback

struct WordCardView: View {
    let word: Word
    var hideMeaning = false
    var revealed = true
    var onReveal: (() -> Void)?

    private var showsMeaning: Bool { !hideMeaning || revealed }

    var body: some View {
        CardBox {
            VStack(spacing: 12) {
                WordVisual(word: word)
                FrenchHeadword(word: word)
                WordChips(word: word)
                SpeakButton(text: word.fr)

                if showsMeaning {
                    Text(word.en)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                } else {
                    Button {
                        onReveal?()
                    } label: {
                        Text("Tap to show the meaning")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.penSoft)
                            .foregroundStyle(Palette.pen)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                ExampleBlock(word: word, showEnglish: showsMeaning, showDictionaryForm: showsMeaning)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Pieces

struct FrenchHeadword: View {
    let word: Word

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !word.article.isEmpty {
                Text(word.article)
                    .font(.french(22))
                    .foregroundStyle(Palette.genderColour(word.gender).opacity(0.7))
            }
            Text(word.fr)
                .font(.french(34, weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
        .multilineTextAlignment(.center)
    }
}

struct WordChips: View {
    let word: Word

    var body: some View {
        HStack(spacing: 6) {
            if !word.genderLabel.isEmpty {
                Chip(text: word.genderLabel,
                     tint: Palette.genderTint(word.gender),
                     ink: Palette.genderColour(word.gender))
            }
            Chip(text: word.pos, tint: Palette.rule, ink: Palette.muted)
            Chip(text: "#\(word.id + 1)", tint: Palette.rule, ink: Palette.muted)
        }
    }
}

/// Emoji, plus a Wikipedia photo for concrete nouns.
struct WordVisual: View {
    let word: Word
    @EnvironmentObject private var store: Store
    @State private var photo: URL?

    var body: some View {
        VStack(spacing: 8) {
            if !word.emoji.isEmpty {
                Text(word.emoji).font(.system(size: 52))
            }
            if let photo = photo {
                AsyncImage(url: photo) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .task(id: word.id) {
            photo = nil
            guard store.state.settings.photos, !store.state.hiddenPhotos.contains(word.id) else { return }
            let found = await PhotoLoader.shared.photo(for: word)
            guard !Task.isCancelled else { return }
            photo = found
        }
    }
}

struct ExampleBlock: View {
    let word: Word
    var showEnglish = true
    var showDictionaryForm = true

    @State private var showGrammar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SpeakButton(text: word.exFr, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HighlightedSentence(word: word)
                    if showEnglish {
                        Text(word.exEn)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                    if word.formChanged, let form = word.highlightedForm {
                        FormNoteLine(form: form, word: word, showGrammar: $showGrammar)
                    }
                    ContractionLines(text: word.exFr)
                    if showDictionaryForm, !word.dictFr.isEmpty {
                        DictionaryFormBlock(word: word)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .sheet(isPresented: $showGrammar) {
            GrammarSheet()
        }
    }
}

/// The example sentence with the word itself picked out.
struct HighlightedSentence: View {
    let word: Word

    var body: some View {
        if let hl = word.hl,
           let form = Text16.slice(word.exFr, hl.start, hl.end) {
            (
                Text(Text16.prefix(word.exFr, hl.start))
                    .font(.french(17))
                    .foregroundColor(Palette.ink)
                + Text(form)
                    .font(.french(17, weight: .bold))
                    .foregroundColor(Palette.pen)
                + Text(Text16.suffix(word.exFr, hl.end))
                    .font(.french(17))
                    .foregroundColor(Palette.ink)
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(word.exFr)
                .font(.french(17))
                .foregroundStyle(Palette.ink)
        }
    }
}

struct FormNoteLine: View {
    let form: String
    let word: Word
    @Binding var showGrammar: Bool

    private var tag: String { Grammar.shortForm(word.formNote) }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(form.lowercased()) = \(word.fr)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
            if !tag.isEmpty {
                Text("· \(tag)")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Button {
                showGrammar = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.pen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why does the word change?")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Palette.penSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Spells out c'est as ce + est.
struct ContractionLines: View {
    let text: String

    private var list: [Contraction] { Grammar.contractions(in: text) }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(list, id: \.whole) { c in
                    HStack(spacing: 4) {
                        Text(c.whole).font(.french(13, weight: .bold))
                        Text("= \(c.full) + \(c.rest)").font(.caption)
                        if !c.note.isEmpty {
                            Text("(\(c.note))").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Palette.rule.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// A second sentence that uses the plain dictionary form, for verbs that are
/// almost never seen in it.
struct DictionaryFormBlock: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("The word itself")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.muted)
            Text(word.dictFr)
                .font(.french(16))
                .foregroundStyle(Palette.ink)
            Text(word.dictEn)
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Palette.goodSoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Photos

/// Looks a noun up on Wikipedia for a picture, and remembers what it found.
actor PhotoLoader {
    static let shared = PhotoLoader()

    private var cache: [String: String] = UserDefaults.standard
        .dictionary(forKey: "motamot-photos") as? [String: String] ?? [:]

    func photo(for word: Word) async -> URL? {
        guard let term = word.photoTerm else { return nil }
        if let cached = cache[term] {
            return cached.isEmpty ? nil : URL(string: cached)
        }
        let slug = term.replacingOccurrences(of: " ", with: "_")
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("MotAMot/1.0 (personal French study app)", forHTTPHeaderField: "User-Agent")
        // A failed request is not remembered: being offline once shouldn't cost
        // the word its picture for good.
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        var found = ""
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           (json["type"] as? String) == "standard",
           let thumb = json["thumbnail"] as? [String: Any],
           let source = thumb["source"] as? String {
            found = source
        }
        cache[term] = found
        UserDefaults.standard.set(cache, forKey: "motamot-photos")
        return found.isEmpty ? nil : URL(string: found)
    }
}

// MARK: - Grammar explainer

struct GrammarSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("French words change shape depending on how they're used. It isn't about a word being masculine or feminine on its own — it's about what it has to agree with.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)

                    section("Verbs change with who is doing it",
                            french: "je suis · tu es · il est · nous sommes · vous êtes · ils sont",
                            note: "All six are être (to be). English does a little of this too: I am, he is. French does more of it.")

                    section("Past actions use a participle",
                            french: "J'ai mangé. · Il a fini.",
                            note: "After avoir or être, the verb takes a fixed past form, like \"eaten\" or \"finished\".")

                    section("Contractions",
                            french: "c'est = ce + est · j'ai = je + ai · l'eau = la + eau",
                            note: "French dislikes two vowel sounds meeting, so a short word drops its vowel and joins the next one. The apostrophe is where the missing letter was. It's compulsory, not casual — je ai is simply wrong.")

                    section("“Il faut” — an il that isn't “he”",
                            french: "Il faut être patient. · Il pleut.",
                            note: "Here il is a placeholder, like the \"it\" in \"it's raining\". Il faut means \"one must / you have to\" in general. To aim it at a person, use devoir: tu dois être patient.")

                    section("Commands drop the subject",
                            french: "Écoute-moi. · Ferme la porte.",
                            note: "")

                    section("Nouns and adjectives agree",
                            french: "un petit chien · une petite maison",
                            note: "Plural usually adds -s. Adjectives copy the noun they describe, which is where masculine and feminine come in.")

                    Text("Mot à Mot teaches the dictionary form. The label just tells you which shape you're looking at, so nothing feels random.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Why the word looks different")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, french: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(french).font(.french(16)).foregroundStyle(Palette.pen)
            if !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
