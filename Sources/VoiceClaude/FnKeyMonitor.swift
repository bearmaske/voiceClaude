import Cocoa

final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsDown = false

    func start() {
        // Try CGEvent tap first (can suppress events)
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleCGEvent(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            NSLog("VoiceClaude: CGEvent tap created successfully")
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            NSLog("VoiceClaude: CGEvent tap failed, falling back to NSEvent monitor")
        }

        // Also use NSEvent monitors as backup / supplement
        // Global monitor catches events when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEvent(event)
        }

        // Local monitor catches events when our app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }

        NSLog("VoiceClaude: Fn key monitoring started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
        fnIsDown = false
    }

    // MARK: - CGEvent handler (can suppress)

    private func handleCGEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let fnDown = flags.contains(.maskSecondaryFn)

        if fnDown && !fnIsDown {
            fnIsDown = true
            NSLog("VoiceClaude: Fn DOWN (CGEvent)")
            DispatchQueue.main.async { self.onFnDown?() }
            return nil // suppress to prevent emoji picker
        } else if !fnDown && fnIsDown {
            fnIsDown = false
            NSLog("VoiceClaude: Fn UP (CGEvent)")
            DispatchQueue.main.async { self.onFnUp?() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - NSEvent handler (fallback, cannot suppress)

    private func handleNSEvent(_ event: NSEvent) {
        // Skip if CGEvent tap is handling things
        if eventTap != nil { return }

        let fnDown = event.modifierFlags.contains(.function)

        if fnDown && !fnIsDown {
            fnIsDown = true
            NSLog("VoiceClaude: Fn DOWN (NSEvent)")
            onFnDown?()
        } else if !fnDown && fnIsDown {
            fnIsDown = false
            NSLog("VoiceClaude: Fn UP (NSEvent)")
            onFnUp?()
        }
    }
}
