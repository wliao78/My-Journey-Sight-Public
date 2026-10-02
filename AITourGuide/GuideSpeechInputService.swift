import AVFoundation
import Foundation
import Speech

@MainActor
final class GuideSpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    private func start() async {
        guard recognizer?.isAvailable == true else {
            errorMessage = "当前设备暂不支持语音识别。"
            return
        }
        let speechAllowed = await Self.requestSpeechAuthorization()
        guard speechAllowed else {
            errorMessage = "请在系统设置中允许语音识别。"
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "请在系统设置中允许使用麦克风。"
            return
        }

        task?.cancel()
        task = nil
        transcript = ""
        errorMessage = nil
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        request = newRequest
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            Self.installTap(on: input, format: format, request: newRequest)
            engine.prepare()
            try engine.start()
            isListening = true
            if let recognizer {
                task = Self.makeTask(recognizer: recognizer, request: newRequest, owner: self)
            }
        } catch {
            errorMessage = "语音输入未能启动：\(error.localizedDescription)"
            stop()
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func stop() {
        guard isListening || request != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    private nonisolated static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        owner: GuideSpeechInputService
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let shouldStop = result?.isFinal == true || error != nil
            Task { @MainActor [weak owner] in
                guard owner?.isListening == true else { return }
                if let text { owner?.transcript = text }
                if shouldStop { owner?.stop() }
            }
        }
    }
}
