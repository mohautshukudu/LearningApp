import SwiftUI

/// Study, test and result share one full-screen flow, like Mot à Mot's.
struct DeckSessionView: View {
    @ObservedObject var store: DeckStore

    var body: some View {
        Group {
            if store.study != nil {
                DeckStudyView(store: store)
            } else if store.quiz != nil {
                DeckQuizView(store: store)
            } else if store.lastResult != nil {
                DeckResultView(store: store)
            } else {
                Color.clear
            }
        }
        .screenBackground()
    }
}

// MARK: - Card face

struct DeckCardFace: View {
    let data: DeckData
    let theme: String
    let card: DeckCard
    var showAnswer = true
    var onReveal: () -> Void = {}

    var body: some View {
        CardBox {
            Chip(text: data.catName(card.cat))
            Text(DeckText.attributed(card.f.p))
                .font(.title3)
                .foregroundStyle(Palette.ink)
            if let vis = card.f.vis, !vis.isEmpty {
                DeckRich(html: vis, css: data.css, theme: theme)
            }
            if showAnswer {
                Text(card.f.a)
                    .font(.system(size: card.f.a.count > 22 ? 18 : (card.f.a.count > 9 ? 24 : 32), weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.pen)
                if !card.teach.isEmpty {
                    DeckRich(html: card.teach, css: data.css, theme: theme)
                }
                if let r = card.r, r.isSupported {
                    (Text("Also: ").foregroundStyle(Palette.muted)
                        + Text(DeckText.attributed(r.p))
                        + Text(" ")
                        + Text(r.a).bold())
                        .font(.footnote)
                }
            } else {
                Button("Tap to show the answer", action: onReveal)
                    .buttonStyle(SmallButtonStyle())
            }
        }
    }
}

// MARK: - Study

struct DeckStudyView: View {
    @ObservedObject var store: DeckStore

    private var accent: Color { Color(hexString: store.data.theme) }

    var body: some View {
        if let s = store.study, let card = store.data.card(s.ids[s.index]) {
            VStack(spacing: 0) {
                header(s)
                ScrollView {
                    VStack(spacing: 14) {
                        DeckCardFace(data: store.data, theme: store.state.settings.theme, card: card,
                                     showAnswer: !s.hide || s.revealed) {
                            store.study?.revealed = true
                        }
                        Toggle("Hide answers (quiz yourself)", isOn: Binding(
                            get: { store.study?.hide ?? false },
                            set: { store.study?.hide = $0; store.study?.revealed = false }
                        ))
                        .padding(14)
                        .background(Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                }
                .id(card.id)
                footer(s)
            }
        }
    }

    private func header(_ s: DeckStudy) -> some View {
        HStack(spacing: 12) {
            Button {
                store.closeSession()
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Close")
            ProgressBar(value: Double(s.index + 1) / Double(max(1, s.ids.count)), height: 8, tint: accent)
            Text("\(s.index + 1)/\(s.ids.count)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func footer(_ s: DeckStudy) -> some View {
        HStack(spacing: 10) {
            Button("Previous") {
                store.study?.index -= 1
                store.study?.revealed = false
            }
            .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
            .disabled(s.index == 0)
            if s.index < s.ids.count - 1 {
                Button("Next") {
                    store.study?.index += 1
                    store.study?.revealed = false
                }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
            } else {
                Button("Done") { store.closeSession() }
                    .buttonStyle(PrimaryButtonStyle(tint: accent))
            }
        }
        .padding(16)
        .background(Palette.paper)
    }
}

// MARK: - Quiz

struct DeckQuizView: View {
    @ObservedObject var store: DeckStore
    @State private var typed = ""
    @State private var confirmQuit = false
    @FocusState private var focused: Bool

    private static let praise = ["Nice.", "Spot on.", "Clean.", "Exactly.", "Good one.", "Yes!", "Right."]

    private var accent: Color { Color(hexString: store.data.theme) }
    private var theme: String { store.state.settings.theme }

    var body: some View {
        if let q = store.quiz, let item = q.current, let sp = store.spec(for: item),
           let card = store.data.card(item.cid) {
            VStack(spacing: 0) {
                header(q)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        subtitle(q, item)
                        promptCard(card, sp, item)
                        if item.kind == .match {
                            optionList(item, sp, q.answered)
                        } else {
                            typingArea(item, sp, q.answered)
                        }
                        if let a = q.answered { feedback(a, card, sp, item) }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                if let a = q.answered { actions(a, item) }
            }
            .id(item.id)
            .onAppear { typed = "" }
            .confirmationDialog("Quit this test? Progress on it will be lost.", isPresented: $confirmQuit, titleVisibility: .visible) {
                Button("Quit", role: .destructive) { store.closeSession() }
                Button("Keep going", role: .cancel) {}
            }
        }
    }

    // MARK: Pieces

    private func header(_ q: DeckQuiz) -> some View {
        HStack(spacing: 12) {
            Button {
                confirmQuit = true
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Quit test")
            ProgressBar(value: Double(q.doneIds.count) / Double(max(1, q.total)), height: 8, tint: accent)
            Text("\(q.doneIds.count)/\(q.total)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func subtitle(_ q: DeckQuiz, _ item: DeckItem) -> some View {
        var parts = [q.title]
        if q.kind == .batch, let n = q.batchNumber { parts.append("Batch \(n)") }
        if q.kind == .practice { parts.append("not scored") }
        if item.retry { parts.append("second go") }
        return Text(parts.joined(separator: " · ")).font(.footnote).foregroundStyle(Palette.muted)
    }

    private func promptCard(_ card: DeckCard, _ sp: DeckSpec, _ item: DeckItem) -> some View {
        CardBox {
            Chip(text: store.data.catName(card.cat))
            Text(DeckText.attributed(sp.p)).font(.title3).foregroundStyle(Palette.ink)
            if let vis = sp.vis, !vis.isEmpty {
                DeckRich(html: vis, css: store.data.css, theme: theme)
            }
            if let sub = sp.sub, !sub.isEmpty {
                Text(DeckText.attributed(sub)).font(.footnote).foregroundStyle(Palette.muted)
            }
            if item.hint && store.quiz?.answered == nil {
                Text(store.grader.hint(for: sp))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func optionList(_ item: DeckItem, _ sp: DeckSpec, _ answered: DeckAnswered?) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                let isRight = option == sp.a
                let isPick = answered?.pick == index
                let revealed = answered != nil
                let ink: Color = revealed && isRight ? Palette.good : (revealed && isPick ? Palette.bad : Palette.ink)
                let fill: Color = revealed && isRight ? Palette.goodSoft : (revealed && isPick ? Palette.badSoft : Palette.card)
                Button {
                    store.pick(index)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 24, height: 24)
                            .background(Palette.rule)
                            .clipShape(Circle())
                        Text(option)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .foregroundStyle(ink)
                    .background(fill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(answered != nil)
            }
        }
    }

    private func symbolKeys(_ sp: DeckSpec) -> [String] {
        if sp.t == "note" { return ["♯", "♭"] }
        if sp.t == "tokens" { return ["♯", "♭", "°", "m", " "] }
        if let ph = sp.ph {
            if ph.contains("♭") { return ["♯", "♭"] }
            if let k = store.data.keys, ph.hasPrefix(k.prefix) { return k.keys }
        }
        return []
    }

    private func typingArea(_ item: DeckItem, _ sp: DeckSpec, _ answered: DeckAnswered?) -> some View {
        VStack(spacing: 10) {
            TextField(sp.ph ?? "Type your answer…", text: Binding(
                get: { answered?.typed ?? typed },
                set: { if answered == nil { typed = $0 } }
            ))
            .focused($focused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(sp.t == "num" ? .numbersAndPunctuation : .default)
            .submitLabel(.done)
            .onSubmit { store.checkTyped(typed) }
            .disabled(answered != nil)
            .padding(14)
            .background(answered == nil ? Palette.card : (answered?.ok == true ? Palette.goodSoft : Palette.badSoft))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.rule, lineWidth: 1))
            .onAppear { if answered == nil { focused = true } }

            if answered == nil {
                let keys = symbolKeys(sp)
                if !keys.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(keys, id: \.self) { key in
                                Button(key == " " ? "space" : key) { typed += key }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button(item.hint ? "Show answer" : "Hint (counts as a miss)") {
                        if item.hint { store.giveUp() } else { store.useHint() }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
                    Button("Check") { store.checkTyped(typed) }
                        .buttonStyle(PrimaryButtonStyle(tint: accent))
                }
            }
        }
    }

    private func feedback(_ a: DeckAnswered, _ card: DeckCard, _ sp: DeckSpec, _ item: DeckItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(a.ok ? Self.praise[item.cid % Self.praise.count] : "Not quite…")
                .font(.title3.weight(.bold))
                .foregroundStyle(a.ok ? Palette.good : Palette.bad)
            if !a.note.isEmpty {
                Text(a.note).font(.subheadline.weight(.semibold))
            }
            Text(sp.a).font(.headline)
            if !card.why.isEmpty {
                DeckRich(html: card.why, css: store.data.css, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(a.ok ? Palette.goodSoft : Palette.badSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actions(_ a: DeckAnswered, _ item: DeckItem) -> some View {
        HStack(spacing: 10) {
            if item.kind == .type && !a.ok && !item.hint {
                Button("I was right") { store.overrideRight() }
                    .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
            }
            Button("Continue") { store.advance() }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
        }
        .padding(16)
        .background(Palette.paper)
    }
}

// MARK: - Result

struct DeckResultView: View {
    @ObservedObject var store: DeckStore

    private var accent: Color { Color(hexString: store.data.theme) }

    var body: some View {
        if let r = store.lastResult {
            ScrollView {
                VStack(spacing: 14) {
                    CardBox {
                        VStack(spacing: 6) {
                            Text(headline(r)).font(.title2.weight(.bold))
                            Text("\(r.score)%").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(accent)
                            Text(blurb(r)).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    actions(r)
                    if !r.missed.isEmpty {
                        Text("Missed first time").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        CardBox(padding: 4) {
                            ForEach(Array(r.missed.enumerated()), id: \.offset) { index, id in
                                if let card = store.data.card(id) {
                                    if index > 0 { Divider() }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(card.ti).font(.subheadline.weight(.semibold))
                                        Text(card.f.a).font(.footnote).foregroundStyle(Palette.muted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                }
                            }
                        }
                        if r.kind == .batch && !r.passed {
                            Button("Study just these \(r.missed.count)") { store.startStudy(r.missed) }
                                .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func headline(_ r: DeckResult) -> String {
        if r.isPractice { return "Practice done" }
        if r.kind == .review { return "Review done" }
        return r.passed ? "Level passed" : "Almost!"
    }

    private func blurb(_ r: DeckResult) -> String {
        let pass = store.state.settings.passMark
        if r.isPractice { return "right first time. Misses come back in review." }
        if r.kind == .review { return "right first time. Missed cards come back tomorrow." }
        if r.passed { return "right first time. You needed \(pass)%." }
        return "right first time. You need \(pass)% to pass. Missed cards are below."
    }

    @ViewBuilder
    private func actions(_ r: DeckResult) -> some View {
        let batch = store.currentBatch
        let modeIndex = DeckStore.modes.firstIndex(where: { $0.key == r.modeKey })
        if r.kind == .review || r.isPractice {
            Button("Back") { store.closeSession() }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
        } else if !r.passed {
            HStack(spacing: 10) {
                Button("Study again") {
                    if let b = batch { store.startStudy(store.batchCards(b).map { $0.id }) }
                }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
                Button("Try again") {
                    if let key = r.modeKey { store.startTest(modeKey: key) }
                }
                .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
            }
        } else if let b = batch, store.isComplete(b) {
            VStack(spacing: 10) {
                Button("Unlock next batch (\(store.nextSize()) cards)") {
                    store.finishBatch()
                    store.closeSession()
                }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
                Button("Back") { store.closeSession() }
                    .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
            }
        } else if let i = modeIndex, i + 1 < DeckStore.modes.count {
            let next = DeckStore.modes[i + 1]
            VStack(spacing: 10) {
                Button("Next level: \(next.name)") { store.startTest(modeKey: next.key) }
                    .buttonStyle(PrimaryButtonStyle(tint: accent))
                Button("Back") { store.closeSession() }
                    .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
            }
        } else {
            Button("Back") { store.closeSession() }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
        }
    }
}
