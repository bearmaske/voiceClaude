import Foundation

final class LLMRefiner {
    static let systemPrompt = """
    You are a speech-recognition post-processor. Your ONLY job is to fix obvious transcription errors. Rules:
    1. Fix Chinese homophone errors (e.g. wrong tones/characters from speech recognition)
    2. Fix English technical terms that were incorrectly transcribed as Chinese (e.g. "配森"→"Python", "杰森"→"JSON", "瑞科特"→"React", "艾皮艾"→"API", "吉特"→"Git", "哈伯"→"GitHub", "杰爱斯"→"JS", "赛斯"→"CSS", "爱其梯梅尔"→"HTML", "诺德"→"Node", "斯威夫特"→"Swift")
    3. Fix obvious English word boundary errors
    4. DO NOT rewrite, rephrase, polish, or restructure any text
    5. DO NOT add or remove punctuation beyond what's needed for fixes
    6. DO NOT change any text that appears correct
    7. If the entire input appears correct, return it exactly as-is
    8. Return ONLY the corrected text, no explanations
    """

    struct Config {
        let baseURL: String
        let apiKey: String
        let model: String
    }

    static func refine(text: String, config: Config, completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "LLMRefiner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1,
            "max_tokens": 2048
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LLMRefiner", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "LLMRefiner", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])))
                    }
                    return
                }
                DispatchQueue.main.async { completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines))) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    static func testConnection(config: Config, completion: @escaping (Result<String, Error>) -> Void) {
        refine(text: "测试连接 test connection", config: config, completion: completion)
    }
}
