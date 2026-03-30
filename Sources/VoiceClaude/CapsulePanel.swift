import Cocoa

final class CapsulePanel {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var label: NSTextField?
    private var containerView: NSVisualEffectView?
    private var panelWidthConstraint: NSLayoutConstraint?

    private let capsuleHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let waveformSize = NSSize(width: 44, height: 32)
    private let minLabelWidth: CGFloat = 160
    private let maxLabelWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 20
    private let bottomMargin: CGFloat = 80

    private var isShowing = false

    func show() {
        guard !isShowing else { return }
        isShowing = true

        guard let screen = NSScreen.main else { return }

        // Calculate initial width
        let initialWidth = horizontalPadding + waveformSize.width + 12 + minLabelWidth + horizontalPadding

        // Create panel
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: capsuleHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Visual effect background
        let effectView = NSVisualEffectView(frame: p.contentView!.bounds)
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        p.contentView?.addSubview(effectView)
        containerView = effectView

        // Waveform
        let wv = WaveformView(frame: NSRect(x: 0, y: 0, width: waveformSize.width, height: waveformSize.height))
        wv.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(wv)
        waveformView = wv

        // Label
        let lbl = NSTextField(labelWithString: "")
        lbl.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        lbl.textColor = .white
        lbl.lineBreakMode = .byTruncatingTail
        lbl.maximumNumberOfLines = 1
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        effectView.addSubview(lbl)
        label = lbl

        // Constraints
        let contentView = p.contentView!
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            wv.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: horizontalPadding),
            wv.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            wv.widthAnchor.constraint(equalToConstant: waveformSize.width),
            wv.heightAnchor.constraint(equalToConstant: waveformSize.height),

            lbl.leadingAnchor.constraint(equalTo: wv.trailingAnchor, constant: 12),
            lbl.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -horizontalPadding),
            lbl.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            lbl.widthAnchor.constraint(greaterThanOrEqualToConstant: minLabelWidth),
            lbl.widthAnchor.constraint(lessThanOrEqualToConstant: maxLabelWidth),
        ])

        // Width constraint for animation
        let widthC = contentView.widthAnchor.constraint(equalToConstant: initialWidth)
        widthC.isActive = true
        panelWidthConstraint = widthC

        // Position at bottom center
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - initialWidth / 2
        let y = screenFrame.origin.y + bottomMargin
        p.setFrameOrigin(NSPoint(x: x, y: y))

        // Entrance animation
        p.contentView?.alphaValue = 0
        p.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.5, y: 0.5))
        p.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            p.contentView?.animator().alphaValue = 1
            p.contentView?.layer?.setAffineTransform(.identity)
        }

        panel = p
    }

    func updateText(_ text: String) {
        guard isShowing else { return }
        label?.stringValue = text

        // Calculate needed width
        let textWidth = text.isEmpty ? minLabelWidth : min(maxLabelWidth, max(minLabelWidth, ceil(textSize(text).width + 20)))
        let totalWidth = horizontalPadding + waveformSize.width + 12 + textWidth + horizontalPadding

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true

            panelWidthConstraint?.animator().constant = totalWidth

            let x = screenFrame.midX - totalWidth / 2
            let y = panel?.frame.origin.y ?? (screenFrame.origin.y + bottomMargin)
            panel?.animator().setFrame(NSRect(x: x, y: y, width: totalWidth, height: capsuleHeight), display: true)
        }
    }

    func updateRMS(_ rms: Float) {
        waveformView?.updateRMS(rms)
    }

    func showRefining() {
        label?.stringValue = "Refining..."
        label?.textColor = NSColor.white.withAlphaComponent(0.6)
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel?.contentView?.animator().alphaValue = 0
            panel?.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.waveformView?.removeFromSuperview()
            self?.panel = nil
            self?.waveformView = nil
            self?.label = nil
            self?.containerView = nil
            self?.panelWidthConstraint = nil
        })
    }

    private func textSize(_ text: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attrs)
    }
}
