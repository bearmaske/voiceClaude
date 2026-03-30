import Cocoa
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var fnMonitor = FnKeyMonitor()
    private var audioEngine = AudioEngine()
    private var speechRecognizer = SpeechRecognizer()
    private var senseVoiceRecognizer = SenseVoiceRecognizer()
    private var capsulePanel = CapsulePanel()
    private var settingsController = SettingsWindowController()

    private var isRecording = false
    private var lastTranscription = ""
    private var inputSampleRate: Double = 48000

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibilityPermission()
        requestMicrophonePermission()
        SpeechRecognizer.requestAuthorization { _ in }
        setupMenuBar()
        setupFnMonitor()
        setupAudioCallbacks()
        setupSpeechCallbacks()
        setupSenseVoiceCallbacks()
    }

    // MARK: - Permissions

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "VoiceClaude needs Accessibility permission to detect the Fn key globally. Please grant access in System Settings > Privacy & Security > Accessibility, then relaunch the app."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceClaude")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let settings = SettingsManager.shared

        // Speech engine submenu
        let engineSubmenu = NSMenu()
        let currentEngine = settings.speechEngine

        let appleItem = NSMenuItem(title: SpeechEngine.apple.displayName, action: #selector(selectEngine(_:)), keyEquivalent: "")
        appleItem.target = self
        appleItem.representedObject = SpeechEngine.apple
        appleItem.state = currentEngine == .apple ? .on : .off
        engineSubmenu.addItem(appleItem)

        let svTitle: String
        if SettingsManager.isSenseVoiceDownloaded {
            svTitle = SpeechEngine.senseVoice.displayName
        } else {
            svTitle = "\(SpeechEngine.senseVoice.displayName) (Download...)"
        }
        let senseVoiceItem = NSMenuItem(title: svTitle, action: #selector(selectEngine(_:)), keyEquivalent: "")
        senseVoiceItem.target = self
        senseVoiceItem.representedObject = SpeechEngine.senseVoice
        senseVoiceItem.state = currentEngine == .senseVoice ? .on : .off
        engineSubmenu.addItem(senseVoiceItem)

        let engineItem = NSMenuItem(title: "Speech Engine", action: nil, keyEquivalent: "")
        engineItem.submenu = engineSubmenu
        menu.addItem(engineItem)

        // Language submenu
        let langSubmenu = NSMenu()
        let currentLang = settings.language
        for lang in SettingsManager.languages {
            let item = NSMenuItem(title: lang.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.identifier
            item.state = lang.identifier == currentLang ? .on : .off
            langSubmenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        // LLM submenu
        let llmSubmenu = NSMenu()
        let toggleItem = NSMenuItem(
            title: settings.llmEnabled ? "Disable" : "Enable",
            action: #selector(toggleLLM),
            keyEquivalent: ""
        )
        toggleItem.target = self
        llmSubmenu.addItem(toggleItem)
        llmSubmenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        llmSubmenu.addItem(settingsItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        llmItem.submenu = llmSubmenu
        if settings.llmEnabled {
            llmItem.title = "LLM Refinement (On)"
        }
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VoiceClaude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let engine = sender.representedObject as? SpeechEngine else { return }

        if engine == .senseVoice && !SettingsManager.isSenseVoiceDownloaded {
            // Download model first
            ModelDownloader.shared.downloadSenseVoice { [weak self] success in
                if success {
                    SettingsManager.shared.speechEngine = .senseVoice
                    _ = self?.senseVoiceRecognizer.loadModel()
                    self?.rebuildMenu()
                }
            }
            return
        }

        SettingsManager.shared.speechEngine = engine
        if engine == .senseVoice {
            _ = senseVoiceRecognizer.loadModel()
        }
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        SettingsManager.shared.language = identifier
        rebuildMenu()
    }

    @objc private func toggleLLM() {
        SettingsManager.shared.llmEnabled.toggle()
        rebuildMenu()
    }

    @objc private func openSettings() {
        settingsController.showWindow()
    }

    // MARK: - Fn Key

    private func setupFnMonitor() {
        fnMonitor.onFnDown = { [weak self] in
            self?.startRecording()
        }
        fnMonitor.onFnUp = { [weak self] in
            self?.stopRecording()
        }
        fnMonitor.start()
    }

    // MARK: - Audio

    private func setupAudioCallbacks() {
        audioEngine.onRMSLevel = { [weak self] rms in
            self?.capsulePanel.updateRMS(rms)
        }
        audioEngine.onBuffer = { [weak self] buffer in
            guard let self else { return }
            let engine = SettingsManager.shared.speechEngine
            if engine == .apple {
                self.speechRecognizer.appendBuffer(buffer)
            } else {
                self.senseVoiceRecognizer.appendBuffer(buffer, inputSampleRate: self.inputSampleRate)
            }
        }
    }

    // MARK: - Speech

    private func setupSpeechCallbacks() {
        speechRecognizer.onPartialResult = { [weak self] text in
            self?.lastTranscription = text
            self?.capsulePanel.updateText(text)
        }
        speechRecognizer.onFinalResult = { [weak self] text in
            self?.lastTranscription = text
            self?.capsulePanel.updateText(text)
        }
        speechRecognizer.onError = { error in
            NSLog("VoiceClaude: Speech recognition error: \(error)")
        }
    }

    private func setupSenseVoiceCallbacks() {
        senseVoiceRecognizer.onResult = { [weak self] text in
            self?.lastTranscription = text
            self?.capsulePanel.updateText(text)
            self?.finishWithText(text)
        }
        senseVoiceRecognizer.onError = { error in
            NSLog("VoiceClaude: SenseVoice error: \(error)")
        }
    }

    // MARK: - Recording Flow

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        lastTranscription = ""

        // Update icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.waveform", accessibilityDescription: "Recording")
        }

        // Show capsule
        capsulePanel.show()

        let engine = SettingsManager.shared.speechEngine

        if engine == .apple {
            let locale = Locale(identifier: SettingsManager.shared.language)
            speechRecognizer.start(locale: locale)
        } else {
            if !senseVoiceRecognizer.loadModel() {
                isRecording = false
                capsulePanel.dismiss()
                return
            }
            senseVoiceRecognizer.startCollecting()
            capsulePanel.updateText("Listening...")
        }

        // Start audio engine
        do {
            try audioEngine.start()
            // Get the actual input sample rate
            inputSampleRate = audioEngine.currentSampleRate
        } catch {
            NSLog("VoiceClaude: Audio engine error: \(error)")
            isRecording = false
            capsulePanel.dismiss()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        // Update icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceClaude")
        }

        // Stop audio
        audioEngine.stop()

        let engine = SettingsManager.shared.speechEngine

        if engine == .apple {
            speechRecognizer.stop()
            let text = lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                capsulePanel.dismiss()
                return
            }
            finishWithText(text)
        } else {
            // SenseVoice: offline recognition
            capsulePanel.updateText("Recognizing...")
            senseVoiceRecognizer.recognize()
            // Result will come through onResult callback → finishWithText
        }
    }

    private func finishWithText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            capsulePanel.dismiss()
            return
        }

        let settings = SettingsManager.shared
        if settings.llmEnabled && settings.isLLMConfigured {
            capsulePanel.showRefining()
            let config = LLMRefiner.Config(
                baseURL: settings.apiBaseURL,
                apiKey: settings.apiKey,
                model: settings.llmModel
            )
            LLMRefiner.refine(text: trimmed, config: config) { [weak self] result in
                let finalText: String
                switch result {
                case .success(let refined):
                    finalText = refined
                case .failure(let error):
                    NSLog("VoiceClaude: LLM refinement failed: \(error). Using original text.")
                    finalText = trimmed
                }
                self?.capsulePanel.updateText(finalText)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.capsulePanel.dismiss()
                    TextInjector.inject(text: finalText)
                }
            }
        } else {
            capsulePanel.dismiss()
            TextInjector.inject(text: trimmed)
        }
    }
}
