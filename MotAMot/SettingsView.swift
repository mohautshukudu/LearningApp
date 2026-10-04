import AVFoundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech

    @State private var skipTo = ""
    @State private var restoreCode = ""
    @State private var showResetAlert = false
    @State private var showSkipAlert = false

    private var settings: Binding<Settings> {
        Binding(get: { store.state.settings },
                set: { store.state.settings = $0; store.persist() })
    }

    var body: some View {
        NavigationStack {
            Form {
                learningSection
                voiceSection
                appearanceSection
                skipSection
                backupSection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Erase all progress?", isPresented: $showResetAlert) {
                Button("Erase", role: .destructive) {
                    store.resetEverything()
                    store.show(toast: "Progress reset")
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Every batch, streak and review date goes back to the start. This can't be undone.")
            }
            .alert("Skip ahead?", isPresented: $showSkipAlert) {
                Button("Skip ahead", role: .destructive) {
                    let n = Int(skipTo) ?? 0
                    store.skipAhead(to: n)
                    store.show(toast: n > 0 ? "Starting from word #\(n + 1)" : "Starting from the beginning")
                    skipTo = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces your current batches and review dates.")
            }
            .onAppear {
                // land the picker on the best installed voice the first time
                if store.state.settings.voiceId.isEmpty, let best = speech.voices.first {
                    store.state.settings.voiceId = best.identifier
                    store.persist()
                }
            }
        }
    }

    // MARK: Learning

    private var learningSection: some View {
        Section("Learning") {
            Picker("Pass mark", selection: settings.passMark) {
                ForEach([70, 80, 90, 100], id: \.self) { value in
                    Text("\(value)% right first time").tag(value)
                }
            }
            Picker("Largest batch", selection: settings.maxBatch) {
                ForEach([20, 30, 50, 80], id: \.self) { value in
                    Text("\(value) words").tag(value)
                }
            }
            Toggle("Photos on cards", isOn: settings.photos)
            Toggle("Say each word when studying", isOn: settings.autoplay)
            Text("Batches grow with your first-try average, and about a third of each one is revision of words you've struggled with.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section("Voice") {
            if speech.voices.isEmpty {
                Text("No French voice is installed. On your iPhone: Settings → Accessibility → Spoken Content → Voices → French, and download a French (France) voice. Enhanced or Premium sound best.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.warn)
            } else {
                Picker("French voice", selection: settings.voiceId) {
                    ForEach(speech.voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(speech.qualityLabel(voice))")
                            .tag(voice.identifier)
                    }
                }
                if !speech.hasGoodVoice {
                    Text("Only the basic voice is installed. Download an Enhanced or Premium French voice in iPhone Settings → Accessibility → Spoken Content → Voices → French, then come back — unlike the website, this app can use them.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speaking speed")
                    Spacer()
                    Text(String(format: "%.2f×", store.state.settings.rate))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                }
                Slider(value: settings.rate, in: 0.5...1.3, step: 0.05)
            }

            Button("Test: « Bonjour, je m'appelle Bard. »") {
                speech.speak("Bonjour, je m'appelle Bard.", settings: store.state.settings)
            }

            Button("Look for newly downloaded voices") {
                speech.reloadVoices()
                store.show(toast: "\(speech.voices.count) French voices found")
            }
            .font(.subheadline)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: settings.theme) {
                Text("Match my phone").tag("")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        }
    }

    // MARK: Skip ahead

    private var skipSection: some View {
        Section("Skip ahead") {
            HStack {
                TextField("Words already known", text: $skipTo)
                    .keyboardType(.numberPad)
                Button("Apply") { showSkipAlert = true }
                    .disabled(Int(skipTo) == nil)
            }
            Text("Marks the first N words as learned, so you start further down the list. They still come back in review.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section("Backup") {
            Button("Copy my backup code") {
                UIPasteboard.general.string = store.backupCode()
                store.show(toast: "Backup code copied")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Restore from a code")
                    .font(.subheadline)
                TextField("Paste a backup code", text: $restoreCode, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                Button("Restore progress") {
                    if store.restore(from: restoreCode) {
                        restoreCode = ""
                        store.show(toast: "Progress restored")
                    } else {
                        store.show(toast: "That code didn't work")
                    }
                }
                .disabled(restoreCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("The code works both ways with the web version, so you can carry progress between your phone and your laptop.")
                .font(.caption)
                .foregroundStyle(Palette.muted)

            Button("Reset all progress", role: .destructive) { showResetAlert = true }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Words", value: "\(Dataset.total)")
            LabeledContent("Learned", value: "\(store.learnedCount)")
            LabeledContent("Reading index", value: Dataset.forms.isEmpty ? "missing" : "\(Dataset.forms.count) forms")
            Text("Word ranking blends the OpenSubtitles 2018 French frequency list (hermitdave/FrequencyWords, CC BY-SA 4.0) with wordfreq. Photos and reading passages come from Wikipedia. Pronunciation uses the voices on your phone.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }
}
