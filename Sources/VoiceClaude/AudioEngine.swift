import AVFoundation

final class AudioEngine {
    var onRMSLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    private var isRunning = false
    private(set) var currentSampleRate: Double = 48000

    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        currentSampleRate = format.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            let rms = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.onRMSLevel?(rms)
            }

            self.onBuffer?(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        let samples = channelData[0]
        var sumSquares: Float = 0

        for i in 0..<frames {
            let sample = samples[i]
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(frames))
        // Normalize: typical speech RMS is ~0.01-0.1, map to 0-1
        let normalized = min(rms * 8.0, 1.0)
        return normalized
    }
}
