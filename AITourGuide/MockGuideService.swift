import Foundation

enum GuideLength: String, CaseIterable, Identifiable {
    case short = "30 秒"
    case medium = "2 分钟"
    case deep = "深度"

    var id: Self { self }
}

enum MockGuideService {
    static func introduction(for subject: String, length: GuideLength) -> String {
        let opening = "这是「\(subject)」的演示讲解。P0 尚未接入真实视觉识别，名称和背景都需要在后续版本核验。"
        switch length {
        case .short:
            return opening + "你可以先观察外形、材质和说明牌，再问我一个具体问题。"
        case .medium:
            return opening + "现场参观时，建议先看整体轮廓，再留意细节与展签。若展签写有年代、作者或馆藏编号，后续版本会把这些线索与馆藏资料交叉核对。现在可以继续追问，我会保持当前对象的对话上下文。"
        case .deep:
            return opening + "深度模式将来会区分可核验的事实、合理解释与未知部分，并给出来源。当前只演示交互流程：从对象外观、材料、时代背景、用途及同类作品的差异逐层探索。请勿将这段演示文字当作该展品的真实资料。"
        }
    }

    static func answer(to question: String, about subject: String) -> String {
        "关于「\(subject)」的提问「\(question)」：当前为 P0 演示，尚未核验资料，因此不会编造具体事实。你可以拍清楚说明牌；真实识别与资料核验将在 P1 接入。"
    }
}

