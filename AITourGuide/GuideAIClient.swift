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
        guard keyVerification || (!PublicDemo.enabled && PublicAIConsent.granted) else {
            throw NSError(domain: "AIConsent", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "请先在设置中同意向所选 AI 服务商发送资料。")])
        }
        var body = body
        body["instructions"] = (body["instructions"] as? String ?? "") +
            (Locale.current.language.languageCode?.identifier == "zh" ? "\n请用中文回答。" : "\nPlease respond in natural English.")
        let (data, response) = try await PublicAITransport.send(body: body, key: key, provider: provider, timeout: 60)
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

}
