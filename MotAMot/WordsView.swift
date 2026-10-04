import SwiftUI

struct WordsView: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var filter: WordFilter = .all
    @State private var limit = 150
    @State private var selected: Word?

    enum WordFilter: String, CaseIterable, Identifiable {
        case all, current, learned, due, new
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .current: return "This batch"
            case .learned: return "Learned"
            case .due: return "Due"
            case .new: return "Not yet"
            }
        }
    }

    private var matches: [Word] {
        let q = Answers.norm(query)
        var list = Dataset.words
        if filter != .all {
            list = list.filter { w in
                let s = store.status(of: w)
                switch filter {
                case .learned: return s == .learned || s == .due
                case .current: return s == .current
                case .due: return s == .due
                case .new: return s == .new
                case .all: return true
                }
            }
        }
        if !q.isEmpty {
            list = list.filter { Answers.norm($0.fr).contains(q) || $0.en.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        let shown = matches
        return NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(WordFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }

                Section {
                    ForEach(shown.prefix(limit)) { word in
                        Button {
                            selected = word
                        } label: {
                            WordRow(word: word, status: store.status(of: word))
                        }
                        .buttonStyle(.plain)
                    }
                    if shown.count > limit {
                        Button("Show more") { limit += 200 }
                            .font(.subheadline.weight(.semibold))
                    }
                } header: {
                    Text("\(shown.count) words · ranked by how often they come up")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Words")
            .searchable(text: $query, prompt: "Search French or English")
            .onChange(of: query) { _, _ in limit = 150 }
            .onChange(of: filter) { _, _ in limit = 150 }
            .sheet(item: $selected) { word in
                WordSheet(word: word)
            }
        }
    }
}

private struct WordRow: View {
    let word: Word
    let status: WordStatus

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(word.id + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(word.withArticle)
                    .font(.french(17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(word.en)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(dotColour)
                .frame(width: 9, height: 9)
        }
        .padding(.vertical, 2)
    }

    private var dotColour: Color {
        switch status {
        case .learned: return Palette.good
        case .due: return Palette.warn
        case .current: return Palette.pen
        case .new: return Palette.faint
        }
    }
}

/// Tapping a word anywhere in the app opens this.
struct WordSheet: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech

    var body: some View {
        NavigationStack {
            ScrollView {
                WordCardView(word: word)
                    .padding(16)
            }
            .screenBackground()
            .navigationTitle(word.fr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                speech.speak(word.fr, settings: store.state.settings)
            }
        }
        .presentationDetents([.large, .medium])
    }
}
