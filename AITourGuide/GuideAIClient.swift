import Foundation

enum GuideAIError: LocalizedError {
    case missingKey, invalidResponse, http(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "请先在设置中填写所选服务商的 API Key。")
        case .invalidResponse: String(localized: "AI 回复无法读取，请重试。")
        case .http(let code): String(format: NSLocalizedString("AI 连接失败（%lld），请检查密钥或网络。", comment: "AI HTTP error"), code)
        }
    }
}

struct GuideAIClient {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-6-luna"

    func testConnection() async throws {
        _ = try await send(body: ["model": model, "store": false,
                                  "max_output_tokens": 20, "instructions": "Reply briefly.",
                                  "input": "ping"], keyVerification: true)
    }

    func complete(instructions: String, input: String) async throws -> String {
        try await send(body: [
            "model": model,
            "store": false,
            "max_output_tokens": 1200,
            "instructions": instructions,
            "input": input
        ])
    }

    func completeImage(instructions: String, input: String, jpegData: Data) async throws -> String {
        try await send(body: [
            "model": model,
            "store": false,
            "max_output_tokens": 1200,
            "instructions": instructions,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": input],
                    ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpegData.base64EncodedString())", "detail": "high"]
                ]
            ]]
        ])
    }

    private func send(body: [String: Any], keyVerification: Bool = false) async throws -> String {
        let provider = PublicAIProvider.selected
        guard let key = APIKeyStore(provider: provider).load() else { throw GuideAIError.missingKey }
        guard keyVerification || PublicAIConsent.granted else {
            throw NSError(domain: "AIConsent", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "请先在设置中同意向所选 AI 服务商发送资料。")])
        }
        var body = body
        body["instructions"] = (body["instructions"] as? String ?? "") +
            (Locale.current.language.languageCode?.identifier == "zh" ? "\n请用中文回答。" : "\nPlease respond in natural English.")
        if provider != .openAI {
            return try await sendAlternative(body: body, provider: provider, key: key)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GuideAIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "completed",
              let output = json["output"] as? [[String: Any]] else { throw GuideAIError.invalidResponse }
        let texts = output.filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
        guard !texts.isEmpty else { throw GuideAIError.invalidResponse }
        return texts.joined(separator: "\n")
    }

    private func sendAlternative(body: [String: Any], provider: PublicAIProvider, key: String) async throws -> String {
        let instruction = (body["instructions"] as? String ?? "") +
            (Locale.current.language.languageCode?.identifier == "zh" ? "\n请用中文回答。" : "\nPlease answer in English.")
        let textInput: String
        var imageData: String?
        if let input = body["input"] as? String {
            textInput = input
        } else if let messages = body["input"] as? [[String: Any]],
                  let content = messages.first?["content"] as? [[String: Any]] {
            textInput = content.first(where: { $0["type"] as? String == "input_text" })?["text"] as? String ?? ""
            imageData = content.first(where: { $0["type"] as? String == "input_image" })?["image_url"] as? String
        } else {
            throw GuideAIError.invalidResponse
        }
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var content: [[String: Any]] = [["type": "text", "text": textInput]]
            if let imageData, let encoded = imageData.components(separatedBy: ",").last {
                content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": encoded]])
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "claude-sonnet-5", "max_tokens": 1200, "system": instruction,
                "messages": [["role": "user", "content": content]]
            ])
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = [["text": textInput]]
            if let imageData, let encoded = imageData.components(separatedBy: ",").last {
                parts.append(["inline_data": ["mime_type": "image/jpeg", "data": encoded]])
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "systemInstruction": ["parts": [["text": instruction]]],
                "contents": [["role": "user", "parts": parts]]
            ])
        case .openAI:
            throw GuideAIError.invalidResponse
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GuideAIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GuideAIError.invalidResponse
        }
        let texts: [String]
        switch provider {
        case .anthropic:
            texts = (json["content"] as? [[String: Any]] ?? [])
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        case .gemini:
            texts = (json["candidates"] as? [[String: Any]] ?? [])
                .flatMap { ($0["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] }
                .compactMap { $0["text"] as? String }
        case .openAI:
            texts = []
        }
        guard !texts.isEmpty else { throw GuideAIError.invalidResponse }
        return texts.joined(separator: "\n")
    }
}
