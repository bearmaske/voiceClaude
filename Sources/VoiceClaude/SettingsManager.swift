import Foundation

enum SpeechEngine: String {
    case apple = "apple"
    case senseVoice = "senseVoice"

    var displayName: String {
        switch self {
        case .apple: return "Apple Speech Recognition"
        case .senseVoice: return "SenseVoice-Small"
        }
    }
}

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    struct LanguageOption {
        let identifier: String
        let displayName: String
    }

    static let languages: [LanguageOption] = [
        LanguageOption(identifier: "en-US", displayName: "English"),
        LanguageOption(identifier: "zh-Hans", displayName: "简体中文"),
        LanguageOption(identifier: "zh-Hant", displayName: "繁體中文"),
        LanguageOption(identifier: "ja-JP", displayName: "日本語"),
        LanguageOption(identifier: "ko-KR", displayName: "한국어"),
    ]

    private enum Keys {
        static let language = "selectedLanguage"
        static let speechEngine = "speechEngine"
        static let llmEnabled = "llmEnabled"
        static let apiBaseURL = "apiBaseURL"
        static let apiKey = "apiKey"
        static let llmModel = "llmModel"
    }

    var speechEngine: SpeechEngine {
        get {
            guard let raw = defaults.string(forKey: Keys.speechEngine),
                  let engine = SpeechEngine(rawValue: raw) else { return .apple }
            return engine
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.speechEngine) }
    }

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? "zh-Hans" }
        set { defaults.set(newValue, forKey: Keys.language) }
    }

    var llmEnabled: Bool {
        get { defaults.bool(forKey: Keys.llmEnabled) }
        set { defaults.set(newValue, forKey: Keys.llmEnabled) }
    }

    var apiBaseURL: String {
        get { defaults.string(forKey: Keys.apiBaseURL) ?? "" }
        set { defaults.set(newValue, forKey: Keys.apiBaseURL) }
    }

    var apiKey: String {
        get { defaults.string(forKey: Keys.apiKey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.apiKey) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Keys.llmModel) ?? "" }
        set { defaults.set(newValue, forKey: Keys.llmModel) }
    }

    var isLLMConfigured: Bool {
        !apiBaseURL.isEmpty && !apiKey.isEmpty && !llmModel.isEmpty
    }

    // MARK: - Model paths

    static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceClaude", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var senseVoiceModelDir: URL {
        appSupportDir.appendingPathComponent("SenseVoice", isDirectory: true)
    }

    static var isSenseVoiceDownloaded: Bool {
        let modelPath = senseVoiceModelDir.appendingPathComponent("model.int8.onnx").path
        let tokensPath = senseVoiceModelDir.appendingPathComponent("tokens.txt").path
        return FileManager.default.fileExists(atPath: modelPath) && FileManager.default.fileExists(atPath: tokensPath)
    }
}
