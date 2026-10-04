import SwiftUI

struct QuizView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        Group {
            if let quiz = store.quiz, let item = quiz.current, let word = item.word {
                content(quiz: quiz, item: item, word: word)
            } else {
                Color.clear
            }
        }
        .screenBackground()
    }

    @ViewBuilder
    private func content(quiz: QuizSession, item: QuizItem, word: Word) -> some View {
        VStack(spacing: 0) {
            SessionHeader(done: quiz.progressCount, total: quiz.total) {
                store.quitQuiz()
            }

            Text(quiz.subtitle)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 14) {
                    QuizPromptCard(item: item, word: word)

                    if item.kind == .match {
                        MatchOptions(item: item, word: word, answered: quiz.answered) { id in
                            answerPick(id)
                        }
                    } else if quiz.answered == nil {
                        TypeAnswerArea(item: item,
                                       word: word,
                                       typed: $typed,
                                       typing: $typing,
                                       onSubmit: submit,
                                       onHint: { store.useHint() },
                                       onGiveUp: { store.giveUp(typed: typed) })
                    } else {
                        TypedAnswerReadout(text: typed, ok: quiz.answered?.ok ?? false)
                    }

                    if let answered = quiz.answered {
                        FeedbackBox(word: word, answered: answered)
                    }
                }
                .padding(16)
                .padding(.bottom, 80)
            }

            if let answered = quiz.answered {
                bottomBar(item: item, answered: answered)
            }
        }
        .onChange(of: item.id) { _, _ in
            typed = ""
            typing = item.kind.isTyping
        }
        .onAppear {
            typing = item.kind.isTyping
        }
    }

    private func bottomBar(item: QuizItem, answered: Answered) -> some View {
        HStack(spacing: 10) {
            if item.kind == .typeEnglish && !answered.ok && !item.hint {
                Button("I was right") { store.overrideRight() }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
            }
            Button("Continue") { store.advance() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(Palette.paper)
    }

    private func answerPick(_ id: Int) {
        store.pick(id)
        speakAnswer()
    }

    private func submit() {
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.submitTyped(typed)
        typing = false
        speakAnswer()
    }

    /// Hearing the word right after answering is where most of the listening
    /// practice now comes from.
    private func speakAnswer() {
        guard let w = store.quiz?.current?.word else { return }
        speech.speak(w.fr, settings: store.state.settings)
    }
}

// MARK: - The question

private struct QuizPromptCard: View {
    let item: QuizItem
    let word: Word

    var body: some View {
        CardBox {
            VStack(spacing: 10) {
                switch item.kind {
                case .match where item.dir == .frenchToEnglish:
                    FrenchHeadword(word: word)
                    WordChips(word: word)
                    SpeakButton(text: word.fr)
                    prompt("What does this mean?")
                case .match:
                    if !word.emoji.isEmpty { Text(word.emoji).font(.system(size: 52)) }
                    Text(word.en)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                    prompt("Which French word is this?")
                case .type:
                    if !word.emoji.isEmpty { Text(word.emoji).font(.system(size: 52)) }
                    Text(word.en)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                    WordChips(word: word)
                    if item.hint {
                        Text(Answers.frenchHint(word))
                            .font(.french(18))
                            .tracking(2)
                            .foregroundStyle(Palette.muted)
                    }
                case .typeEnglish:
                    FrenchHeadword(word: word)
                    WordChips(word: word)
                    SpeakButton(text: word.fr)
                    if item.hint {
                        Text(Answers.englishHint(word))
                            .font(.body)
                            .tracking(2)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Palette.muted)
    }
}

// MARK: - Answering

private struct MatchOptions: View {
    let item: QuizItem
    let word: Word
    let answered: Answered?
    let onPick: (Int) -> Void

    private var showsFrench: Bool { item.dir == .englishToFrench }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array((item.options ?? []).enumerated()), id: \.element) { pair in
                optionButton(index: pair.offset, id: pair.element)
            }
        }
    }

    @ViewBuilder
    private func optionButton(index: Int, id: Int) -> some View {
        if let option = Dataset.word(id) {
            Button {
                onPick(id)
            } label: {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, height: 22)
                        .background(Palette.rule)
                        .clipShape(Circle())
                    Text(showsFrench ? option.withArticle : option.en)
                        .font(showsFrench ? .french(18) : .body)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(14)
                .background(background(for: id))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(border(for: id), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(answered != nil)
        }
    }

    private func background(for id: Int) -> Color {
        guard let answered = answered else { return Palette.card }
        if id == word.id { return Palette.goodSoft }
        if answered.pick == id { return Palette.badSoft }
        return Palette.card
    }

    private func border(for id: Int) -> Color {
        guard let answered = answered else { return Palette.rule }
        if id == word.id { return Palette.good }
        if answered.pick == id { return Palette.bad }
        return Palette.rule
    }
}

private struct TypeAnswerArea: View {
    let item: QuizItem
    let word: Word
    @Binding var typed: String
    @FocusState.Binding var typing: Bool
    let onSubmit: () -> Void
    let onHint: () -> Void
    let onGiveUp: () -> Void

    private let accents = ["é", "è", "ê", "à", "â", "ç", "ù", "û", "ô", "î", "ï", "ë", "œ", "'"]

    var body: some View {
        VStack(spacing: 12) {
            TextField(item.kind == .typeEnglish ? "Type the English…" : "Type the French…",
                      text: $typed)
                .font(item.kind == .typeEnglish ? .title3 : .french(22))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typing)
                .onSubmit(onSubmit)
                .padding(14)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.rule, lineWidth: 1)
                )

            if item.kind == .type {
                accentRow
            }

            HStack(spacing: 10) {
                Button(item.hint ? "Show answer" : "Hint (counts as a miss)") {
                    if item.hint { onGiveUp() } else { onHint() }
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                Button("Check", action: onSubmit)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var accentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(accents, id: \.self) { character in
                    Button {
                        typed += character
                    } label: {
                        Text(character)
                            .font(.french(17))
                            .frame(width: 38, height: 38)
                            .background(Palette.card)
                            .foregroundStyle(Palette.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Palette.rule, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct TypedAnswerReadout: View {
    let text: String
    let ok: Bool

    var body: some View {
        Text(text.isEmpty ? "—" : text)
            .font(.title3)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(ok ? Palette.goodSoft : Palette.badSoft)
            .foregroundStyle(ok ? Palette.good : Palette.bad)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Feedback

private struct FeedbackBox: View {
    let word: Word
    let answered: Answered

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answered.ok ? praiseLines[word.id % praiseLines.count] : "Pas tout à fait…")
                .font(.french(20, weight: .semibold))
                .foregroundStyle(answered.ok ? Palette.good : Palette.bad)

            if !answered.note.isEmpty {
                Text(answered.note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(word.withArticle).font(.french(18, weight: .semibold))
                Text("—").foregroundStyle(Palette.muted)
                Text(word.en).font(.subheadline)
            }
            .foregroundStyle(Palette.ink)

            HighlightedSentence(word: word)
            Text(word.exEn)
                .font(.caption)
                .foregroundStyle(Palette.muted)
            ContractionLines(text: word.exFr)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(answered.ok ? Palette.goodSoft : Palette.badSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Result

struct ResultView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Group {
            if let result = store.lastResult {
                content(result)
            } else {
                Color.clear
            }
        }
        .screenBackground()
    }

    private func content(_ result: QuizResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                CardBox {
                    VStack(spacing: 6) {
                        Text(result.headline)
                            .font(.french(24, weight: .semibold))
                            .foregroundStyle(result.passed || result.isPractice ? Palette.good : Palette.warn)
                        Text("\(result.score)%")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                        Text(result.blurb(passMark: store.state.settings.passMark))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }

                actions(result)

                if !result.missed.isEmpty {
                    MissedList(ids: result.missed)
                    if result.kind == .batch && !result.passed {
                        Button("Study just these \(result.missed.count)") {
                            let ids = result.missed
                            store.lastResult = nil
                            store.startStudy(ids: ids)
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func actions(_ result: QuizResult) -> some View {
        if result.kind == .review || result.isPractice {
            Button("Back to batches") { store.lastResult = nil }
                .buttonStyle(PrimaryButtonStyle())
        } else if !result.passed {
            HStack(spacing: 10) {
                Button("Study again") {
                    let b = store.currentBatch
                    store.lastResult = nil
                    if let b = b { store.startStudy(ids: store.batchWords(b).map { $0.id }) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Try again") {
                    let mode = result.mode
                    store.lastResult = nil
                    if let mode = mode { store.startTest(mode) }
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        } else if result.batchComplete {
            Button("Unlock next batch (\(store.nextSize()) words)") {
                store.finishBatch()
                store.lastResult = nil
                store.show(toast: "New batch unlocked")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if let mode = result.mode, let next = store.nextMode(after: mode) {
            VStack(spacing: 10) {
                Button("Next level: \(next.name)") {
                    store.lastResult = nil
                    store.startTest(next)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back") { store.lastResult = nil }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        } else {
            Button("Back to batches") { store.lastResult = nil }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private struct MissedList: View {
    let ids: [Int]
    @EnvironmentObject private var speech: Speech
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missed first time")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            CardBox(padding: 12) {
                ForEach(ids, id: \.self) { id in
                    if let w = Dataset.word(id) {
                        HStack(spacing: 10) {
                            SpeakButton(text: w.fr, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.withArticle)
                                    .font(.french(17, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text(w.en)
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
