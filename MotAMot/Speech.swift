import AVFoundation
import SwiftUI

/// Pronunciation, through the system speech engine.
///
/// This is the one thing a website on iOS cannot do: Safari only hands web pages
/// the basic voices, while an app can use any French voice installed on the
/// phone, including the Enhanced and Premium ones.
final class Speech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
        reloadVoices()
    }

    // MARK: Voices

    func reloadVoices() {
        let french = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("fr")
        }
        voices = french.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) > rank(b) }
            return a.name < b.name
        }
    }

    /// Best first: France over other regions, premium over enhanced over basic.
    private func rank(_ v: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        if v.language.lowercased() == "fr-fr" { score += 4 }
        switch v.quality {
        case .premium: score += 3
        case .enhanced: score += 2
        default: break
        }
        return score
    }

    func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    var hasFrenchVoice: Bool { !voices.isEmpty }

    var hasGoodVoice: Bool {
        voices.contains { $0.quality == .premium || $0.quality == .enhanced }
    }

    func voice(id: String) -> AVSpeechSynthesisVoice? {
        if !id.isEmpty, let match = voices.first(where: { $0.identifier == id }) { return match }
        return voices.first
    }

    // MARK: Speaking

    func speak(_ text: String, settings: Settings) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activateSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        if let v = voice(id: settings.voiceId) {
            utterance.voice = v
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        }
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let wanted = base * settings.rate
        utterance.rate = Float(min(max(wanted, Double(AVSpeechUtteranceMinimumSpeechRate)),
                                   Double(AVSpeechUtteranceMaximumSpeechRate)))
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }

    // MARK: Delegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
