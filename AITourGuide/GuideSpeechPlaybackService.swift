import AVFoundation
import Foundation

@MainActor
final class GuideSpeechPlaybackService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingMessageID: UUID?

    static var chineseVoices: [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(message: GuideMessage) {
        if speakingMessageID == message.id {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // System speech can still work with the current audio session.
        }

        let utterance = AVSpeechUtterance(string: message.text)
        let preferredVoices = Self.chineseVoices.filter {
            let name = $0.name.lowercased().replacingOccurrences(of: "-", with: "")
            return name.contains("tingting") || name.contains("yushu") || name.contains("meijia")
        }
        let selectedIdentifier = UserDefaults.standard.string(forKey: "guideVoiceIdentifier") ?? ""
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        utterance.voice = AVSpeechSynthesisVoice(identifier: selectedIdentifier)
            ?? preferredVoices.sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.language.hasPrefix(language) && !$1.language.hasPrefix(language)
            }.first
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = 0.53
        utterance.pitchMultiplier = 1.02
        utterance.postUtteranceDelay = 0
        speakingMessageID = message.id
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingMessageID = nil
        activeUtteranceID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard activeUtteranceID == identifier else { return }
            speakingMessageID = nil
            activeUtteranceID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard activeUtteranceID == identifier else { return }
            speakingMessageID = nil
            activeUtteranceID = nil
        }
    }
}
