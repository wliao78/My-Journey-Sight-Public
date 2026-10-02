import Foundation

enum GuideLength: String, CaseIterable, Identifiable {
    case short = "30 秒"
    case medium = "2 分钟"
    case deep = "深度"

    var id: Self { self }
}

enum MockGuideService {
    static func introduction(for subject: String, length: GuideLength) -> String {
        let opening = String(format: NSLocalizedString("这是「%@」的演示讲解，不代表已核实的地点或展品。", comment: "Demo guide disclaimer"), subject)
        switch length {
        case .short:
            return opening + String(localized: "你可以先观察外形、材质和说明牌，再问一个具体问题。")
        case .medium:
            return opening + String(localized: "先看整体轮廓，再留意细节与展签。具体年代、作者和馆藏资料，请以现场说明或官方资料为准。")
        case .deep:
            return opening + String(localized: "这段示例仅演示如何从外观、材料、背景与用途逐层观察。它不包含真实展品的已核实资料；参观时请查阅官方来源。")
        }
    }

    static func answer(to question: String, about subject: String) -> String {
        String(format: NSLocalizedString("关于「%@」的提问「%@」：当前是演示场景，没有经过资料核验。请拍摄清晰展签或查阅官方说明。", comment: "Demo guide answer"), subject, question)
    }
}
