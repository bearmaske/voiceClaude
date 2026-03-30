import Cocoa

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var statusLabel: NSTextField!

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "LLM Refinement Settings"
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let contentView = NSView(frame: w.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        w.contentView = contentView

        let settings = SettingsManager.shared
        let labelWidth: CGFloat = 110
        let fieldX: CGFloat = 120
        let fieldWidth: CGFloat = 330
        var y: CGFloat = 220

        // API Base URL
        addLabel("API Base URL:", at: NSPoint(x: 20, y: y), width: labelWidth, to: contentView)
        baseURLField = NSTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 24))
        baseURLField.stringValue = settings.apiBaseURL
        baseURLField.placeholderString = "https://api.openai.com/v1"
        contentView.addSubview(baseURLField)

        y -= 40

        // API Key
        addLabel("API Key:", at: NSPoint(x: 20, y: y), width: labelWidth, to: contentView)
        apiKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 24))
        apiKeyField.stringValue = settings.apiKey
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        y -= 40

        // Model
        addLabel("Model:", at: NSPoint(x: 20, y: y), width: labelWidth, to: contentView)
        modelField = NSTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 24))
        modelField.stringValue = settings.llmModel
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        y -= 50

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: 300, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Buttons
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveBtn.frame = NSRect(x: 370, y: y - 5, width: 80, height: 30)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        let testBtn = NSButton(title: "Test", target: self, action: #selector(testConnection))
        testBtn.frame = NSRect(x: 280, y: y - 5, width: 80, height: 30)
        testBtn.bezelStyle = .rounded
        contentView.addSubview(testBtn)

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private func addLabel(_ text: String, at origin: NSPoint, width: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: origin.x, y: origin.y, width: width, height: 20)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 13)
        view.addSubview(label)
    }

    @objc private func saveSettings() {
        let settings = SettingsManager.shared
        settings.apiBaseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiKey = apiKeyField.stringValue
        settings.llmModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "Settings saved."
    }

    @objc private func testConnection() {
        let config = LLMRefiner.Config(
            baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKeyField.stringValue,
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty, !config.model.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Please fill in all fields."
            return
        }

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Testing..."

        LLMRefiner.testConnection(config: config) { [weak self] result in
            switch result {
            case .success(let response):
                self?.statusLabel.textColor = .systemGreen
                self?.statusLabel.stringValue = "Connected! Response: \(response.prefix(50))"
            case .failure(let error):
                self?.statusLabel.textColor = .systemRed
                self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
