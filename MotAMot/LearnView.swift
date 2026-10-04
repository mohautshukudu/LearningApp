import SwiftUI

struct LearnView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatPills()
                    OverallProgressCard()
                    if !store.dueWords.isEmpty {
                        ReviewCard(due: store.dueWords.count)
                    }
                    if let batch = store.currentBatch {
                        CurrentBatchCard(batch: batch)
                    } else {
                        FinishedEverythingCard()
                    }
                    FinishedBatchesList()
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Mot à Mot")
        }
    }
}

// MARK: - Top of the screen

private struct StatPills: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 8) {
            if store.state.stats.streak > 0 {
                Chip(text: "\(store.state.stats.streak) day streak")
            }
            if !store.dueWords.isEmpty {
                Chip(text: "\(store.dueWords.count) to review",
                     tint: Palette.goodSoft, ink: Palette.good)
            }
            Spacer()
        }
    }
}

private struct OverallProgressCard: View {
    @EnvironmentObject private var store: Store

    private var learned: Int { store.learnedCount }

    var body: some View {
        CardBox {
            Text("Words learned")
                .font(.caption)
                .foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(learned)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("/ \(Dataset.total)")
                    .font(.body)
                    .foregroundStyle(Palette.muted)
            }
            ProgressBar(value: Double(learned) / Double(max(1, Dataset.total)))
            Text("About \(Dataset.coverage(learned))% of everyday speech")
                .font(.caption)
                .foregroundStyle(Palette.muted)

            if learned < 100 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Stage 1 · the first 100 words")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(learned)/100")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    ProgressBar(value: Double(learned) / 100, height: 6)
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct ReviewCard: View {
    let due: Int
    @EnvironmentObject private var store: Store

    var body: some View {
        CardBox {
            Text(due == 1 ? "1 word to review" : "\(due) words to review")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                Button("Review") { store.startReview(style: "mixed") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("By typing") { store.startReview(style: "type") }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        }
    }
}

// MARK: - The batch being learned

private struct CurrentBatchCard: View {
    let batch: Batch
    @EnvironmentObject private var store: Store

    private var words: [Word] { store.batchWords(batch) }
    private var complete: Bool { store.isComplete(batch) }

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 2) {
                Text("Batch \(batch.n)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline) {
                    Text("Words \(batch.start + 1)–\(batch.start + batch.size)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Chip(text: batch.extras.isEmpty
                         ? "\(batch.size) new"
                         : "\(batch.size) new + \(batch.extras.count)")
                }
            }

            Text(words.prefix(8).map { $0.fr }.joined(separator: " · ") + (words.count > 8 ? " …" : ""))
                .font(.french(14))
                .foregroundStyle(Palette.muted)

            if !batch.extras.isEmpty {
                Text("Revision mixed in: " + store.revisionWords(batch).prefix(6).map { $0.fr }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            HStack(spacing: 10) {
                ForEach(TestMode.allCases) { mode in
                    LevelRung(batch: batch, mode: mode)
                }
            }

            if complete {
                Notice(text: "Batch passed with a first-try average of \(store.batchAverage(batch) ?? 0)%. Next batch: \(store.nextSize()) words.", tone: .good)
                HStack(spacing: 10) {
                    Button("Study words") {
                        store.startStudy(ids: words.map { $0.id })
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Unlock next batch") {
                        store.finishBatch()
                        store.show(toast: "New batch unlocked")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                }
            } else {
                HStack(spacing: 10) {
                    Button("Study words") {
                        store.startStudy(ids: words.map { $0.id })
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if let next = store.pendingMode(batch) {
                        Button("Test: \(next.name)") { store.startTest(next) }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                }
            }
        }
    }
}

private struct LevelRung: View {
    let batch: Batch
    let mode: TestMode
    @EnvironmentObject private var store: Store

    private var state: ModeState { batch.state(mode) }
    private var unlocked: Bool { store.isUnlocked(batch, mode) }

    private var label: String {
        if state.passed {
            guard let best = state.best else { return "Skipped" }
            return "Passed · \(best)%"
        }
        if !unlocked { return "Locked" }
        if let best = state.best { return "Best \(best)% · need \(store.state.settings.passMark)%" }
        return "Ready"
    }

    private var background: Color {
        if state.passed { return Palette.goodSoft }
        return Palette.card
    }

    var body: some View {
        Button {
            store.startTest(mode)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.level)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.muted)
                Text(mode.name)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 2)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(state.passed ? Palette.good : Palette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(10)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(unlocked && !state.passed ? Palette.pen : Palette.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .opacity(unlocked ? 1 : 0.55)
    }
}

private struct FinishedEverythingCard: View {
    var body: some View {
        CardBox {
            Text("Félicitations !")
                .font(.french(24, weight: .bold))
                .foregroundStyle(Palette.pen)
            Text("You've worked through all \(Dataset.total) words.")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("Keep up your reviews, and start leaning on films and podcasts.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Finished batches

private struct FinishedBatchesList: View {
    @EnvironmentObject private var store: Store

    private var finished: [Batch] {
        Array(store.state.batches.filter { $0.done }.suffix(6).reversed())
    }

    var body: some View {
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Finished batches")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                CardBox(padding: 12) {
                    ForEach(Array(finished.enumerated()), id: \.element.n) { pair in
                        FinishedBatchRow(batch: pair.element)
                        if pair.offset < finished.count - 1 {
                            Divider().background(Palette.rule)
                        }
                    }
                }
            }
        }
    }
}

private struct FinishedBatchRow: View {
    let batch: Batch
    @EnvironmentObject private var store: Store

    private var ids: [Int] { store.batchWords(batch).map { $0.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Batch \(batch.n) · words \(batch.start + 1)–\(batch.start + batch.size)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let avg = store.batchAverage(batch) {
                    Text("\(avg)% first try")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: 6) {
                Button("Study") { store.startStudy(ids: ids) }
                    .buttonStyle(SmallButtonStyle(filled: true))
                Button("Type French") { store.startPractice(ids: ids, kind: .type) }
                    .buttonStyle(SmallButtonStyle())
                Button("Type English") { store.startPractice(ids: ids, kind: .typeEnglish) }
                    .buttonStyle(SmallButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}
