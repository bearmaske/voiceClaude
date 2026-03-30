import Foundation
import Cocoa

final class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    static let senseVoiceURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"

    private var isDownloading = false
    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var statusLabel: NSTextField?
    private var downloadProcess: Process?

    func downloadSenseVoice(completion: @escaping (Bool) -> Void) {
        guard !isDownloading else { return }
        isDownloading = true

        showProgressWindow()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("sensevoice-model.tar.bz2")
        // Remove previous temp file
        try? FileManager.default.removeItem(at: tempFile)

        // Use curl to download (handles redirects, no ATS issues)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.downloadWithCurl(to: tempFile) ?? false

            if success {
                DispatchQueue.main.async {
                    self?.statusLabel?.stringValue = "Extracting model..."
                    self?.progressBar?.isIndeterminate = true
                    self?.progressBar?.startAnimation(nil)
                }

                let extracted = self?.extractModel(from: tempFile) ?? false
                try? FileManager.default.removeItem(at: tempFile)

                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.dismissProgressWindow()
                    if extracted {
                        completion(true)
                    } else {
                        self?.showError("Failed to extract the model files.")
                        completion(false)
                    }
                }
            } else {
                try? FileManager.default.removeItem(at: tempFile)
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.dismissProgressWindow()
                    self?.showError("Failed to download the model. Please check your internet connection.")
                    completion(false)
                }
            }
        }
    }

    func cancelDownload() {
        downloadProcess?.terminate()
        downloadProcess = nil
        isDownloading = false
        dismissProgressWindow()
    }

    // MARK: - Download with curl

    private func downloadWithCurl(to destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-L", "-o", destination.path, "--progress-bar", Self.senseVoiceURL]

        // Capture stderr for progress
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = nil
        downloadProcess = process

        do {
            try process.run()
        } catch {
            NSLog("VoiceClaude: curl launch failed: \(error)")
            return false
        }

        // Read progress from curl's stderr
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        // Poll progress in background
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.3)
        timer.setEventHandler { [weak self] in
            let newData = handle.availableData
            if !newData.isEmpty {
                buffer.append(newData)
                // curl progress bar format: "  % Total    % Received..."
                // We look for the percentage
                if let str = String(data: buffer.suffix(200), encoding: .utf8) {
                    // Find the last percentage like "45.2%"
                    let pattern = #"(\d+\.?\d*)\s*%"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.matches(in: str, range: NSRange(str.startIndex..., in: str)).last {
                        let range = Range(match.range(at: 1), in: str)!
                        if let pct = Double(str[range]) {
                            self?.progressBar?.doubleValue = pct
                            self?.statusLabel?.stringValue = String(format: "Downloading... %.0f%%", pct)
                        }
                    }
                }
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()
        downloadProcess = nil

        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path)
    }

    // MARK: - Extraction

    private func extractModel(from tarBz2: URL) -> Bool {
        let destDir = SettingsManager.senseVoiceModelDir
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xjf", tarBz2.path, "-C", tempDir.path]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                NSLog("VoiceClaude: tar extraction failed with status \(process.terminationStatus)")
                return false
            }
        } catch {
            NSLog("VoiceClaude: tar launch failed: \(error)")
            return false
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: nil) else { return false }

        var foundModel = false
        var foundTokens = false

        while let fileURL = enumerator.nextObject() as? URL {
            let name = fileURL.lastPathComponent
            if name == "model.int8.onnx" {
                let dest = destDir.appendingPathComponent(name)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: fileURL, to: dest)
                foundModel = fm.fileExists(atPath: dest.path)
            } else if name == "tokens.txt" {
                let dest = destDir.appendingPathComponent(name)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: fileURL, to: dest)
                foundTokens = fm.fileExists(atPath: dest.path)
            }
        }

        NSLog("VoiceClaude: extraction result - model: \(foundModel), tokens: \(foundTokens)")
        return foundModel && foundTokens
    }

    // MARK: - UI

    private func showProgressWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        w.title = "Downloading SenseVoice-Small"
        w.center()
        w.isReleasedWhenClosed = false

        let content = w.contentView!

        let label = NSTextField(labelWithString: "Preparing download...")
        label.frame = NSRect(x: 20, y: 70, width: 380, height: 20)
        label.font = NSFont.systemFont(ofSize: 13)
        content.addSubview(label)
        statusLabel = label

        let progress = NSProgressIndicator(frame: NSRect(x: 20, y: 40, width: 380, height: 20))
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 0
        content.addSubview(progress)
        progressBar = progress

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindow = w
    }

    private func dismissProgressWindow() {
        progressWindow?.close()
        progressWindow = nil
        progressBar = nil
        statusLabel = nil
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Model Download"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
