import Speech

final class SpeechRecognizer {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            print("Speech recognizer not available for locale: \(locale)")
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }

        request.shouldReportPartialResults = true
        if #available(macOS 15, *) {
            request.addsPunctuation = true
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    DispatchQueue.main.async { self.onFinalResult?(text) }
                } else {
                    DispatchQueue.main.async { self.onPartialResult?(text) }
                }
            }

            if let error {
                DispatchQueue.main.async { self.onError?(error) }
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }
}
