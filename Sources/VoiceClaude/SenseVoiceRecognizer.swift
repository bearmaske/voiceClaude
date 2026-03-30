import AVFoundation
import CSherpaOnnx

final class SenseVoiceRecognizer {
    var onResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var recognizer: OpaquePointer?
    private var audioBuffers: [Float] = []
    private let targetSampleRate: Int32 = 16000

    /// Initialize the offline recognizer with SenseVoice model
    func loadModel() -> Bool {
        guard recognizer == nil else { return true }

        let modelDir = SettingsManager.senseVoiceModelDir
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx").path
        let tokensPath = modelDir.appendingPathComponent("tokens.txt").path

        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            onError?("SenseVoice model not found")
            return false
        }

        var config = SherpaOnnxOfflineRecognizerConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineRecognizerConfig>.size)

        config.feat_config.sample_rate = targetSampleRate
        config.feat_config.feature_dim = 80

        // Set SenseVoice model paths using C strings
        modelPath.withCString { model in
            tokensPath.withCString { tokens in
                "auto".withCString { lang in
                    "cpu".withCString { provider in
                        "greedy_search".withCString { decoding in
                            config.model_config.sense_voice.model = model
                            config.model_config.sense_voice.language = lang
                            config.model_config.sense_voice.use_itn = 1
                            config.model_config.tokens = tokens
                            config.model_config.num_threads = 2
                            config.model_config.provider = provider
                            config.decoding_method = decoding

                            recognizer = SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }

        if recognizer == nil {
            onError?("Failed to create SenseVoice recognizer")
            return false
        }

        NSLog("VoiceClaude: SenseVoice model loaded")
        return true
    }

    func startCollecting() {
        audioBuffers.removeAll()
    }

    /// Accumulate audio buffers (will be processed all at once on finish)
    func appendBuffer(_ buffer: AVAudioPCMBuffer, inputSampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let samples = channelData[0]

        // Resample to 16kHz if needed
        if abs(inputSampleRate - Double(targetSampleRate)) < 1.0 {
            // Already 16kHz, just append
            audioBuffers.append(contentsOf: UnsafeBufferPointer(start: samples, count: frames))
        } else {
            // Simple linear resampling
            let ratio = Double(targetSampleRate) / inputSampleRate
            let outputFrames = Int(Double(frames) * ratio)
            for i in 0..<outputFrames {
                let srcIdx = Double(i) / ratio
                let idx0 = Int(srcIdx)
                let frac = Float(srcIdx - Double(idx0))
                let idx1 = min(idx0 + 1, frames - 1)
                let sample = samples[idx0] * (1 - frac) + samples[idx1] * frac
                audioBuffers.append(sample)
            }
        }
    }

    /// Run offline recognition on all accumulated audio
    func recognize() {
        guard let recognizer else {
            onError?("Recognizer not loaded")
            return
        }

        guard !audioBuffers.isEmpty else {
            onResult?("")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let stream = SherpaOnnxCreateOfflineStream(recognizer)
            guard let stream else {
                DispatchQueue.main.async { self.onError?("Failed to create stream") }
                return
            }

            self.audioBuffers.withUnsafeBufferPointer { ptr in
                SherpaOnnxAcceptWaveformOffline(stream, self.targetSampleRate, ptr.baseAddress, Int32(ptr.count))
            }

            SherpaOnnxDecodeOfflineStream(recognizer, stream)

            let result = SherpaOnnxGetOfflineStreamResult(stream)
            var text = ""
            if let result, let cText = result.pointee.text {
                text = String(cString: cText)
            }

            if let result {
                SherpaOnnxDestroyOfflineRecognizerResult(result)
            }
            SherpaOnnxDestroyOfflineStream(stream)

            DispatchQueue.main.async {
                self.onResult?(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func unloadModel() {
        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
        recognizer = nil
        audioBuffers.removeAll()
    }

    deinit {
        unloadModel()
    }
}
