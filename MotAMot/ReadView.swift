import SwiftUI

// MARK: - A random French Wikipedia passage, with the words he knows picked out

struct Article: Equatable {
    var title: String
    var extract: String
    var imageURL: URL?
    var pageURL: URL?
}

@MainActor
final class Reader: ObservableObject {
    @Published var article: Article?
    @Published var loading = false
    @Published var error: String?

    nonisolated init() {}

    func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }

        for _ in 0..<3 {
            guard let fetched = await fetchOne() else {
                error = "Couldn't reach Wikipedia just now. Check your connection and try again."
                return
            }
            // very short stubs make poor reading practice
            if fetched.extract.split(separator: " ").count >= 12 {
                article = fetched
                return
            }
        }
        error = "Wikipedia kept handing back very short pages. Try again."
    }

    private func fetchOne() async -> Article? {
        guard let url = URL(string: "https://fr.wikipedia.org/api/rest_v1/page/random/summary") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MotAMot/1.0 (personal French study app)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        var extract = (json["extract"] as? String) ?? ""
        if extract.count > 700 {
            extract = String(extract.prefix(700))
            if let lastSpace = extract.lastIndex(of: " ") {
                extract = String(extract[extract.startIndex..<lastSpace])
            }
            extract += " …"
        }
        guard !extract.isEmpty else { return nil }

        let thumb = (json["thumbnail"] as? [String: Any])?["source"] as? String
        let page = ((json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
        return Article(title: (json["title"] as? String) ?? "",
                       extract: extract,
                       imageURL: thumb.flatMap(URL.init(string:)),
                       pageURL: page.flatMap(URL.init(string:)))
    }
}

struct ReadView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var reader = Reader()
    @State private var openWord: Word?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SentencePracticeCard()

                    HStack {
                        Text("Reading")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button(reader.loading ? "Loading…" : "New article") {
                            Task { await reader.load() }
                        }
                        .buttonStyle(SmallButtonStyle(filled: reader.article == nil))
                        .frame(width: 130)
                        .disabled(reader.loading)
                    }

                    if let error = reader.error {
                        Notice(text: error)
                    }

                    if let article = reader.article {
                        ArticleCard(article: article, onTapWord: { openWord = $0 })
                        KnownShareCard(extract: article.extract)
                    } else if reader.loading {
                        Text("Fetching an article…")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Read")
            .task {
                if reader.article == nil { await reader.load() }
            }
            .sheet(item: $openWord) { word in
                WordSheet(word: word)
            }
        }
    }
}

// MARK: Passage

private struct ArticleCard: View {
    let article: Article
    let onTapWord: (Word) -> Void

    var body: some View {
        CardBox {
            if let image = article.imageURL {
                AsyncImage(url: image) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(article.title)
                .font(.french(22, weight: .semibold))
                .foregroundStyle(Palette.ink)

            TappableFrenchText(text: article.extract, onTapWord: onTapWord)

            ContractionLines(text: article.extract)

            HStack(spacing: 10) {
                SpeakButton(text: article.extract, size: 38)
                if let page = article.pageURL {
                    Link("Full article", destination: page)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
        }
    }
}

/// The passage, with each known word tappable and tinted by how well he knows it.
private struct TappableFrenchText: View {
    let text: String
    let onTapWord: (Word) -> Void
    @EnvironmentObject private var store: Store

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 6) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { pair in
                piece(pair.element)
            }
        }
    }

    private struct Piece {
        let text: String
        let wordId: Int?
    }

    /// Splits the passage into words and the punctuation between them.
    private var pieces: [Piece] {
        let ns = text as NSString
        var out: [Piece] = []
        var cursor = 0
        for token in Grammar.tokens(in: text) {
            if token.range.location > cursor {
                let gap = ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor))
                let trimmed = gap.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(Piece(text: trimmed, wordId: nil)) }
            }
            out.append(Piece(text: token.text, wordId: Dataset.lookupForm(token.text)))
            cursor = token.range.location + token.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { out.append(Piece(text: tail, wordId: nil)) }
        }
        return out
    }

    @ViewBuilder
    private func piece(_ piece: Piece) -> some View {
        if let id = piece.wordId, let word = Dataset.word(id) {
            Button {
                onTapWord(word)
            } label: {
                Text(piece.text)
                    .font(.french(17))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(tint(for: word))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Text(piece.text)
                .font(.french(17))
                .foregroundStyle(Palette.muted)
        }
    }

    private func tint(for word: Word) -> Color {
        switch store.status(of: word) {
        case .learned, .due: return Palette.goodSoft
        case .current: return Palette.penSoft
        case .new: return Palette.rule.opacity(0.5)
        }
    }
}

private struct KnownShareCard: View {
    let extract: String
    @EnvironmentObject private var store: Store

    private var counts: (known: Int, inList: Int) {
        var known = 0, inList = 0
        for token in Grammar.tokens(in: extract) {
            guard let id = Dataset.lookupForm(token.text), let w = Dataset.word(id) else { continue }
            inList += 1
            let s = store.status(of: w)
            if s == .learned || s == .due { known += 1 }
        }
        return (known, inList)
    }

    private var percent: Int {
        let c = counts
        return c.inList > 0 ? Int((Double(c.known) / Double(c.inList) * 100).rounded()) : 0
    }

    var body: some View {
        CardBox {
            HStack {
                Text("**\(percent)%** of this passage is vocabulary you've learned")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Chip(text: "\(counts.known)/\(counts.inList)")
            }
            ProgressBar(value: Double(percent) / 100)
            HStack(spacing: 12) {
                legend("learned", Palette.goodSoft)
                legend("this batch", Palette.penSoft)
                legend("later on", Palette.rule)
            }
        }
    }

    private func legend(_ label: String, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: 14, height: 10)
            Text(label).font(.caption2).foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Sentence practice

private struct SentencePracticeCard: View {
    @EnvironmentObject private var store: Store

    private var pool: [Word] { store.eligibleSentences() }

    var body: some View {
        CardBox {
            if pool.count < 3 {
                Text("Sentence practice")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Unlocks once you've learned enough words to make whole sentences. \(pool.count)/3 ready so far — finish a batch or two and it opens.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            } else if let builder = store.builder, let word = builder.word {
                BuilderBoard(builder: builder, word: word)
            } else {
                HStack {
                    Text("Sentence practice")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Chip(text: "\(pool.count) sentences")
                }
                Text("Put a French sentence in order. Only words you've learned.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Button("Start") { store.startBuilder() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

private struct BuilderBoard: View {
    let builder: SentenceBuilder
    let word: Word
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Put it in order")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Chip(text: "\(store.eligibleSentences().count) available")
            }

            Text(word.exEn)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)

            // the slots
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(builder.placed.enumerated()), id: \.element.id) { pair in
                    Button {
                        store.builder?.unplace(at: pair.offset)
                    } label: {
                        tile(pair.element.text, background: slotColour(pair.offset))
                    }
                    .buttonStyle(.plain)
                    .disabled(builder.checked != nil)
                }
                if builder.placed.isEmpty {
                    Text("tap the words below")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(8)
            .background(Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // the pile
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(builder.remaining) { tileItem in
                    Button {
                        store.builder?.place(tileItem)
                    } label: {
                        tile(tileItem.text, background: Palette.card)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let ok = builder.checked {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ok ? praiseLines[word.id % praiseLines.count] : "Not quite")
                        .font(.french(18, weight: .semibold))
                        .foregroundStyle(ok ? Palette.good : Palette.bad)
                    Text(word.exFr).font(.french(17)).foregroundStyle(Palette.ink)
                    Text(word.exEn).font(.caption).foregroundStyle(Palette.muted)
                    ContractionLines(text: word.exFr)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ok ? Palette.goodSoft : Palette.badSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Next sentence") { store.startBuilder() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button("Clear") { store.builder?.clear() }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    Button("Check") {
                        store.builder?.check()
                        if store.builder?.checked == true {
                            store.bumpStreak()
                            store.persist()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!builder.isFull)
                    .opacity(builder.isFull ? 1 : 0.5)
                }
            }
        }
    }

    private func slotColour(_ index: Int) -> Color {
        guard let ok = builder.checked else { return Palette.penSoft }
        if ok || builder.slotIsRight(index) { return Palette.goodSoft }
        return Palette.badSoft
    }

    private func tile(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.french(17))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.rule, lineWidth: 1)
            )
    }
}

// MARK: - Wrapping row of views

/// Lays children out left to right, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, x - spacing)
        let width = maxWidth == .infinity ? widest : maxWidth
        return CGSize(width: max(0, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                       proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
