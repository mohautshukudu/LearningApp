import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech

    private var session: StudySession? { store.study }

    var body: some View {
        VStack(spacing: 0) {
            if let session = session, let word = session.word {
                SessionHeader(done: session.index + 1,
                              total: session.count,
                              onQuit: { store.endStudy() })

                ScrollView {
                    VStack(spacing: 14) {
                        WordCardView(word: word,
                                     hideMeaning: session.hideMeanings,
                                     revealed: session.revealed,
                                     onReveal: { store.study?.revealed = true })

                        Toggle("Hide meanings (quiz yourself)", isOn: hideBinding)
                            .font(.subheadline)
                            .padding(14)
                            .background(Palette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(16)
                }
                .gesture(swipe)

                HStack(spacing: 10) {
                    Button("Previous") { back() }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                        .disabled(session.index == 0)
                        .opacity(session.index == 0 ? 0.5 : 1)
                    if session.isLast {
                        Button("Done") { finish() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Next") { forward() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
                .background(Palette.paper)
            } else {
                Color.clear
            }
        }
        .screenBackground()
        .onAppear { speakCurrent() }
    }

    private var hideBinding: Binding<Bool> {
        Binding(
            get: { store.study?.hideMeanings ?? false },
            set: { value in
                store.study?.hideMeanings = value
                store.study?.revealed = false
            }
        )
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.width < -60 {
                    if store.study?.isLast == true { finish() } else { forward() }
                } else if value.translation.width > 60 {
                    back()
                }
            }
    }

    private func forward() {
        guard var session = store.study, !session.isLast else { return }
        session.index += 1
        session.revealed = false
        store.study = session
        speakCurrent()
    }

    private func back() {
        guard var session = store.study, session.index > 0 else { return }
        session.index -= 1
        session.revealed = false
        store.study = session
        speakCurrent()
    }

    /// Finishing the cards leads straight into the level he still owes, like the
    /// web app does.
    private func finish() {
        store.endStudy()
        guard let b = store.currentBatch, let mode = store.pendingMode(b) else { return }
        store.startTest(mode)
    }

    private func speakCurrent() {
        guard store.state.settings.autoplay, let w = store.study?.word else { return }
        speech.speak(w.fr, settings: store.state.settings)
    }
}

/// The bar across the top of study and test screens: quit, progress, count.
struct SessionHeader: View {
    let done: Int
    let total: Int
    var onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuit) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            ProgressBar(value: total > 0 ? Double(done) / Double(total) : 0)

            Text("\(done)/\(total)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.rule, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
