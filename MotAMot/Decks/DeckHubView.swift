import SwiftUI

// MARK: - Helpers

extension Color {
    /// "#0F766E" -> Color. Falls back to the app's indigo.
    init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if let value = UInt32(digits, radix: 16) {
            self.init(hex: value)
        } else {
            self.init(hex: 0x2F3BD4)
        }
    }
}

// MARK: - Course list
// The "Courses" tab: Fret by Fret, Atlas, Py by Py, Slide by Slide and Desk Skills.

struct DeckHubView: View {
    @StateObject private var library = DeckLibrary()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if library.summaries.isEmpty {
                        Notice(text: "No courses were found in the app bundle.")
                    }
                    ForEach(library.summaries) { summary in
                        NavigationLink(value: summary.slug) {
                            DeckRow(summary: summary, learned: library.learned(summary.slug))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .onAppear { library.refresh() }
            .screenBackground()
            .navigationTitle("Courses")
            .navigationDestination(for: String.self) { slug in
                DeckHomeView(slug: slug)
                    .environmentObject(library)
            }
        }
    }
}

private struct DeckRow: View {
    let summary: DeckSummary
    let learned: Int

    var body: some View {
        let accent = Color(hexString: summary.theme)
        CardBox {
            HStack(spacing: 14) {
                Image(systemName: summary.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.name).font(.headline).foregroundStyle(Palette.ink)
                    Text("\(learned) of \(summary.total) cards learned")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.faint)
            }
            ProgressBar(value: summary.total == 0 ? 0 : Double(learned) / Double(summary.total), height: 6, tint: accent)
            Text(summary.blurb)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.leading)
        }
    }
}
