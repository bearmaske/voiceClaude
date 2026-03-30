import Cocoa

final class WaveformView: NSView {
    private let barCount = 5
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barSpacing: CGFloat = 4.0
    private let barWidth: CGFloat = 4.0
    private let minBarHeight: CGFloat = 4.0

    private var smoothedRMS: CGFloat = 0
    private let attackCoeff: CGFloat = 0.40
    private let releaseCoeff: CGFloat = 0.15

    private var barLayers: [CALayer] = []
    private var displayLink: CVDisplayLink?
    private var currentRMS: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        for i in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
            barLayers.append(bar)
            _ = i // used in layout
        }

        startDisplayLink()
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink else { return }
        CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<WaveformView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async { view.updateBars() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    func updateRMS(_ rms: Float) {
        currentRMS = CGFloat(rms)
    }

    private func updateBars() {
        // Smooth envelope
        let target = currentRMS
        if target > smoothedRMS {
            smoothedRMS += (target - smoothedRMS) * attackCoeff
        } else {
            smoothedRMS += (target - smoothedRMS) * releaseCoeff
        }

        let maxBarHeight = bounds.height
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for i in 0..<barCount {
            let jitter = 1.0 + CGFloat.random(in: -0.04...0.04)
            let height = max(minBarHeight, maxBarHeight * barWeights[i] * smoothedRMS * jitter)
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            barLayers[i].frame = CGRect(x: x, y: y, width: barWidth, height: height)
        }

        CATransaction.commit()
    }

    override func removeFromSuperview() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        super.removeFromSuperview()
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
