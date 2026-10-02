import Foundation

enum PublicAIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        }
    }

    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "publicAIProvider") ?? "openai") ?? .openAI
    }
}
