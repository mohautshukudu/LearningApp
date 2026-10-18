import SwiftUI

// MARK: - Cards: search, filter, drill

struct DeckCardsView: View {
    @ObservedObject var store: DeckStore
    @State private var query = ""
    @State private var category = "all"
    @State private var statusFilter = "all"
    @State private var openCard: DeckCard?

    private var accent: Color { Color(hexString: store.data.theme) }

    private static let statuses: [(String, String)] = [
        ("all", "Any"), ("learned", "Learned"), ("due", "Due"), ("current", "Current"), ("new", "New"),
    ]

    private func matches(_ card: DeckCard) -> Bool {
        if category != "all" && card.cat != category { return false }
        if statusFilter != "all" {
            let s: String
            switch store.status(of: card) {
            case .learned: s = "learned"
            case .due: s = "due"
            case .current: s = "current"
            case .new: s = "new"
            }
            if s != statusFilter { return false }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return card.ti.lowercased().contains(q) || card.f.a.lowercased().contains(q)
    }

    private var list: [DeckCard] { store.data.cards.filter(matches) }

    var body: some View {
        let cards = list
        List {
            Section {
                filterRow(title: "Topic", selection: $category,
                          options: [("all", "All")] + store.data.catOrder.map { ($0, store.data.catName($0)) })
                filterRow(title: "Status", selection: $statusFilter, options: Self.statuses)
            }
            if category != "all" {
                Section {
                    Text("Drill \(store.data.catName(category)) using cards you've already learned.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    HStack(spacing: 10) {
                        Button("Match") { drill(.match) }.buttonStyle(.bordered)
                        Button("Type") { drill(.type) }.buttonStyle(.bordered)
                    }
                }
            }
            Section("\(cards.count) card\(cards.count == 1 ? "" : "s")\(cards.count > 150 ? " (first 150 shown)" : "")") {
                ForEach(cards.prefix(150)) { card in
                    Button {
                        openCard = card
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(card.id + 1)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.muted)
                                .frame(width: 34, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.ti).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text(card.f.a).font(.footnote).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Circle().fill(color(for: store.status(of: card))).frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search \(store.total) cards")
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openCard) { card in
            DeckCardSheet(store: store, card: card) {
                openCard = nil
            }
        }
    }

    private func filterRow(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.0) { key, label in
                        Button {
                            selection.wrappedValue = key
                        } label: {
                            Text(label)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selection.wrappedValue == key ? accent : Palette.rule)
                                .foregroundStyle(selection.wrappedValue == key ? Color.white : Palette.ink)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func color(for status: DeckStatus) -> Color {
        switch status {
        case .learned: return Palette.good
        case .due: return Palette.warn
        case .current: return accent
        case .new: return Palette.faint
        }
    }

    private func drill(_ kind: DeckKind) {
        let ids = store.data.cards
            .filter { $0.cat == category && (store.progress($0.id)?.box ?? 0) > 0 }
            .map { $0.id }
        if ids.isEmpty {
            store.show(toast: "Learn some of these first")
        } else {
            store.startPractice(ids, kind: kind)
        }
    }
}

private struct DeckCardSheet: View {
    @ObservedObject var store: DeckStore
    let card: DeckCard
    let close: () -> Void

    private var accent: Color { Color(hexString: store.data.theme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DeckCardFace(data: store.data, theme: store.state.settings.theme, card: card)
                HStack(spacing: 10) {
                    if card.isQuizzable {
                        Button("Quiz me on this") {
                            close()
                            store.startPractice([card.id], kind: .type)
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: accent, filled: false))
                    }
                    Button("Close", action: close)
                        .buttonStyle(PrimaryButtonStyle(tint: accent))
                }
            }
            .padding(16)
        }
        .screenBackground()
        .presentationDetents([.large])
    }
}

// MARK: - Settings

struct DeckSettingsView: View {
    @ObservedObject var store: DeckStore
    @State private var restoreText = ""
    @State private var confirmReset = false

    private var accent: Color { Color(hexString: store.data.theme) }

    var body: some View {
        Form {
            Section("Learning") {
                Picker("Pass mark", selection: setting(\.passMark)) {
                    ForEach([70, 80, 90, 100], id: \.self) { Text("\($0)% right first time").tag($0) }
                }
                Picker("Largest batch", selection: setting(\.maxBatch)) {
                    ForEach([20, 30, 40, 60], id: \.self) { Text("\($0) cards").tag($0) }
                }
                Picker("Revision in each batch", selection: setting(\.revDiv)) {
                    Text("A quarter").tag(4)
                    Text("A third").tag(3)
                    Text("Half").tag(2)
                }
                Picker("Theme", selection: setting(\.theme)) {
                    Text("Match my device").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section {
                Button("Copy backup") {
                    UIPasteboard.general.string = store.backupText()
                    store.show(toast: "Backup copied")
                }
                ShareLink(item: store.backupText()) {
                    Text("Share backup…")
                }
                TextEditor(text: $restoreText)
                    .frame(minHeight: 90)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Restore from pasted backup") {
                    if store.restore(from: restoreText) {
                        restoreText = ""
                        store.show(toast: "Backup restored")
                    } else {
                        store.show(toast: "That backup couldn't be read")
                    }
                }
                .disabled(restoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Backup")
            } footer: {
                Text("Same format as the web app's \"Download backup\", so progress can move either way.")
            }
            Section {
                Button("Reset all progress", role: .destructive) { confirmReset = true }
            } footer: {
                Text("\(store.total) cards · \(store.state.stats.answers) answers given")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
        .confirmationDialog("Reset all progress? This cannot be undone.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
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
    }

    private func setting<T>(_ keyPath: WritableKeyPath<DeckSettings, T>) -> Binding<T> {
        Binding(
            get: { store.state.settings[keyPath: keyPath] },
            set: {
                store.state.settings[keyPath: keyPath] = $0
                store.persist()
            }
        )
    }
}
