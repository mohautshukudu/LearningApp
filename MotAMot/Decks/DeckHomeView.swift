import SwiftUI

// MARK: - One course: loads the deck, then shows the home screen

struct DeckHomeView: View {
    let slug: String
    @EnvironmentObject private var library: DeckLibrary
    @State private var store: DeckStore?
    @State private var failed = false

    var body: some View {
        Group {
            if let store = store {
                DeckHomeContent(store: store)
            } else if failed {
                Notice(text: "This course couldn't be loaded.").padding(16)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenBackground()
        .task {
            guard store == nil else { return }
            if let loaded = library.store(for: slug) {
                store = loaded
            } else {
                failed = true
            }
        }
    }
}

struct DeckHomeContent: View {
    @ObservedObject var store: DeckStore
    @EnvironmentObject private var library: DeckLibrary
    @State private var showAllBatches = false

    private var accent: Color { Color(hexString: store.data.theme) }

    private var sessionShowing: Binding<Bool> {
        Binding(
            get: { store.study != nil || store.quiz != nil || store.lastResult != nil },
            set: { shown in
                if !shown { store.closeSession() }
            }
        )
    }

    private var colorScheme: ColorScheme? {
        switch store.state.settings.theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                progressCard
                if !store.dueCards.isEmpty { reviewCard }
                if !store.weakCards.isEmpty { weakCard }
                if let batch = store.currentBatch {
                    batchCard(batch)
                } else {
                    CardBox {
                        Text("All done!").font(.title2.weight(.bold))
                        Text("You've worked through all \(store.total) cards. Keep up your reviews, and use Cards to drill any topic.")
                            .foregroundStyle(Palette.muted)
                    }
                }
                finishedBatches
            }
            .padding(16)
        }
        .navigationTitle(store.data.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    DeckCardsView(store: store)
                } label: {
                    Image(systemName: "list.bullet")
                }
                NavigationLink {
                    DeckSettingsView(store: store)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(colorScheme)
        .fullScreenCover(isPresented: sessionShowing) {
            DeckSessionView(store: store)
                .preferredColorScheme(colorScheme)
                .tint(accent)
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast { ToastView(text: toast) }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .onChange(of: store.toast) { _, message in
            guard let message = message else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if store.toast == message { store.toast = nil }
            }
        }
        .onDisappear {
            store.persist()
            library.refresh()
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        CardBox {
            Text("Cards learned").font(.subheadline).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(store.learnedCount)").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/ \(store.total)").foregroundStyle(Palette.muted)
                Spacer()
                if store.liveStreak > 0 {
                    Chip(text: "\(store.liveStreak) day streak", tint: Palette.warnSoft, ink: Palette.warn)
                }
            }
            ProgressBar(value: store.total == 0 ? 0 : Double(store.learnedCount) / Double(store.total), tint: accent)
            if let stage = store.currentStage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(stage.index + 1)/\(store.data.stages.count) · \(stage.stage.name)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(stage.learned)/\(stage.stage.end - stage.stage.start)").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    ProgressBar(value: Double(stage.learned) / Double(max(1, stage.stage.end - stage.stage.start)), height: 6, tint: accent)
                }
            }
            categoryChips
        }
    }

    private var categoryChips: some View {
        let keys = store.data.catOrder.filter { key in store.data.cards.contains { $0.cat == key } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    let all = store.data.cards.filter { $0.cat == key }
                    let got = all.filter { (store.progress($0.id)?.box ?? 0) > 0 }.count
                    Chip(text: "\(store.data.catName(key)) \(got)/\(all.count)", tint: Palette.rule, ink: Palette.muted)
                }
            }
        }
    }

    // MARK: Review

    private var reviewCard: some View {
        let n = store.dueCards.count
        return CardBox {
            Text("\(n) card\(n == 1 ? "" : "s") to review").font(.headline)
            HStack(spacing: 10) {
                Button("Review") { store.startReview(typing: nil) }
                    .buttonStyle(SmallButtonStyle(filled: true))
                Button("Review by typing") { store.startReview(typing: true) }
                    .buttonStyle(SmallButtonStyle())
            }
        }
    }

    private var weakCard: some View {
        let weak = store.weakCards
        return CardBox {
            HStack {
                Text("Weak spots").font(.headline)
                Spacer()
                Chip(text: "\(weak.count)")
            }
            Text(weak.prefix(5).map { $0.ti }.joined(separator: " · ") + (weak.count > 5 ? " …" : ""))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                Button("Match them") { store.startPractice(weak.map { $0.id }, kind: .match, title: "Weak spots") }
                    .buttonStyle(SmallButtonStyle())
                Button("Type them") { store.startPractice(weak.map { $0.id }, kind: .type, title: "Weak spots") }
                    .buttonStyle(SmallButtonStyle())
            }
        }
    }

    // MARK: Current batch

    private func batchCard(_ b: DeckBatch) -> some View {
        let complete = store.isComplete(b)
        let titles = store.newCards(b).prefix(6).map { $0.ti }.joined(separator: " · ")
        return CardBox {
            Text("Batch \(b.n)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
            HStack {
                Text("Cards \(b.start + 1)–\(b.start + b.size)").font(.title3.weight(.bold))
                Spacer()
                Chip(text: "\(b.size) new" + (b.extras.isEmpty ? "" : " + \(b.extras.count)"))
            }
            Text(titles + (b.size > 6 ? " …" : "")).font(.footnote).foregroundStyle(Palette.muted)
            if !b.extras.isEmpty {
                let extra = store.revisionCards(b).prefix(5).map { $0.ti }.joined(separator: " · ")
                Text("Revision mixed in: " + extra + (b.extras.count > 5 ? " …" : ""))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                ForEach(Array(DeckStore.modes.enumerated()), id: \.element.id) { index, mode in
                    rung(b, mode: mode, index: index)
                }
            }
            if complete {
                Notice(text: "Batch passed with a first-try average of \(store.batchAverage(b) ?? 0)%. Next batch: \(store.nextSize()) cards.", tone: .good)
                HStack(spacing: 10) {
                    Button("Study cards") { store.startStudy(store.batchCards(b).map { $0.id }) }
                        .buttonStyle(PrimaryButtonStyle(tint: accent))
                    Button("Unlock next batch") { store.finishBatch() }
                        .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
                }
            } else {
                let next = DeckStore.modes.enumerated()
                    .first(where: { store.isUnlocked(b, $0.offset) && !b.state($0.element.key).passed })?
                    .element
                HStack(spacing: 10) {
                    Button("Study cards") { store.startStudy(store.batchCards(b).map { $0.id }) }
                        .buttonStyle(PrimaryButtonStyle(tint: accent))
                    if let next = next {
                        Button("Test: \(next.name)") { store.startTest(modeKey: next.key) }
                            .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
                    }
                }
            }
        }
    }

    private func rung(_ b: DeckBatch, mode: DeckMode, index: Int) -> some View {
        let st = b.state(mode.key)
        let unlocked = store.isUnlocked(b, index)
        let label: String
        if st.passed {
            label = "Passed · \(st.best ?? 0)%"
        } else if unlocked {
            label = st.best != nil ? "Best \(st.best ?? 0)% · need \(store.state.settings.passMark)%" : "Ready"
        } else {
            label = "Locked"
        }
        return Button {
            store.startTest(modeKey: mode.key)
        } label: {
            VStack(spacing: 2) {
                Text(mode.level).font(.caption2).foregroundStyle(Palette.muted)
                Text(mode.name).font(.subheadline.weight(.semibold))
                Text(label).font(.caption2).foregroundStyle(st.passed ? Palette.good : Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(st.passed ? Palette.goodSoft : Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.rule, lineWidth: 1))
            .opacity(unlocked ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    // MARK: Finished batches

    @ViewBuilder
    private var finishedBatches: some View {
        let done = store.state.batches.filter { $0.done }.reversed()
        if !done.isEmpty {
            Text("Finished batches").font(.headline).padding(.top, 4)
            CardBox(padding: 4) {
                ForEach(Array((showAllBatches ? Array(done) : Array(done.prefix(6))).enumerated()), id: \.element.id) { index, b in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Batch \(b.n) · cards \(b.start + 1)–\(b.start + b.size)").font(.subheadline.weight(.semibold))
                            if let avg = store.batchAverage(b) {
                                Text("\(avg)% first try").font(.caption).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer()
                        Button("Study") { store.startStudy(store.batchCards(b).map { $0.id }) }
                            .buttonStyle(.bordered)
                        Button("Match") { store.startPractice(store.batchCards(b).map { $0.id }, kind: .match) }
                            .buttonStyle(.bordered)
                        Button("Type") { store.startPractice(store.batchCards(b).map { $0.id }, kind: .type) }
                            .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                    .padding(12)
                }
            }
            if done.count > 6 && !showAllBatches {
                Button("Show all \(done.count)") { showAllBatches = true }
                    .font(.subheadline)
            }
        }
    }
}
