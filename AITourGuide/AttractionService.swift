import CoreLocation
import MapKit

struct GuideSearchIntent {
    let mapQuery: String
    let category: MKPointOfInterestCategory?

    static func resolve(_ input: String, using ai: GuideAIClient) async throws -> GuideSearchIntent {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return GuideSearchIntent(mapQuery: "", category: nil) }
        let lowered = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let categories: [(terms: [String], name: String, category: MKPointOfInterestCategory)] = [
            (["博物馆", "museum", "美术馆", "art gallery"], "museum", .museum),
            (["公园", "park"], "park", .park),
            (["海滩", "沙滩", "beach"], "beach", .beach),
            (["动物园", "zoo"], "zoo", .zoo),
            (["水族馆", "aquarium"], "aquarium", .aquarium),
            (["剧院", "剧场", "theater", "theatre"], "theater", .theater)
        ]
        for match in categories where match.terms.contains(where: { lowered.contains($0) }) {
            if match.terms.contains(where: { lowered == $0 }) {
                return GuideSearchIntent(mapQuery: match.name, category: match.category)
            }
            break
        }
        var normalizationError: Error?
        do {
            let output = try await ai.complete(
                instructions: "Convert the user's sightseeing request to one concise English Apple Maps place search query. Preserve the requested place type and specific subject; remove conversational filler and distance/mode instructions. Reply with only the English search phrase, no explanation or punctuation. Equivalent Chinese and English requests should yield the same phrase.",
                input: query)
            let normalized = output.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) ?? ""
            if !normalized.isEmpty, normalized.count <= 100 {
                return GuideSearchIntent(mapQuery: normalized, category: nil)
            }
        } catch { normalizationError = error }
        for match in categories where match.terms.contains(where: { lowered.contains($0) }) {
            return GuideSearchIntent(mapQuery: match.name, category: match.category)
        }
        throw normalizationError ?? GuideAIError.invalidResponse
    }
}

struct GuideAttraction: Identifiable {
    let id: String
    let item: MKMapItem
    let distance: CLLocationDistance
    let reason: String
    let highlight: String

    var name: String { item.name ?? String(localized: "未命名景点") }
    var address: String { item.placemark.title ?? "" }
}

enum GuideTravelMode: String, CaseIterable, Identifiable {
    case walking = "步行"
    case driving = "开车"

    var id: String { rawValue }
    var title: String { NSLocalizedString(rawValue, comment: "Travel mode") }
    var directionsMode: String {
        self == .walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
    }
    var searchRadii: [CLLocationDistance] {
        self == .walking ? [1_500, 3_000, 5_000] : [8_000, 20_000, 40_000]
    }
}

@MainActor
struct AttractionService {
    private let ai = GuideAIClient()

    func recommendations(near location: CLLocation, mode: GuideTravelMode, query: String = "") async throws -> [GuideAttraction] {
        let intent = try await GuideSearchIntent.resolve(query, using: ai)
        var found: [String: MKMapItem] = [:]
        var lastError: Error?
        for radius in mode.searchRadii {
            let request = MKLocalSearch.Request()
            request.region = MKCoordinateRegion(center: location.coordinate,
                                                latitudinalMeters: radius * 2,
                                                longitudinalMeters: radius * 2)
            request.resultTypes = .pointOfInterest
            if intent.mapQuery.isEmpty {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
                    .museum, .park, .nationalPark, .aquarium, .zoo, .beach, .theater
                ])
            } else {
                request.naturalLanguageQuery = intent.mapQuery
                if let category = intent.category {
                    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
                }
            }
            do {
                for item in try await MKLocalSearch(request: request).start().mapItems {
                    guard let name = item.name, let point = item.placemark.location,
                          location.distance(from: point) <= radius else { continue }
                    found["\(name)|\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)"] = item
                }
            } catch { lastError = error }
            if found.count >= 50 { break }
        }
        if found.isEmpty, let lastError { throw lastError }
        let candidates = found.values.compactMap { item -> (MKMapItem, CLLocationDistance)? in
            guard let point = item.placemark.location else { return nil }
            return (item, location.distance(from: point))
        }.sorted { $0.1 < $1.1 }.prefix(50)
        guard !candidates.isEmpty else { return [] }

        let numbered = candidates.enumerated().map { index, candidate in
            "p\(index)|\(candidate.0.name ?? "")|\(candidate.0.pointOfInterestCategory?.rawValue ?? "")|\(Int(candidate.1))m"
        }.joined(separator: "\n")
        let output = try await ai.complete(
            instructions: "你是谨慎的现场导游。只从提供的 Apple 地图候选中挑选最多 4 个有参观价值的景点。若用户提出搜索要求，必须优先严格满足类型、主题等要求；不符合的候选不能凑数。步行模式优先近处且适合步行到达的地点；开车模式可优先更远、值得专程去的地点。每行严格输出 p编号|一句简短的当前应用语言推荐理由|一句该地点独有或明显区别于普通同类地点的具体特色。第三字段优先写可辨认的建筑外观、场馆主题或地形；禁止‘留意周边氛围’‘适合散步’‘看看展品’等任何地点都能套用的空话。不能确定特色时写‘暂缺可靠的特色资料’，不要编造历史、馆藏或设施。不得添加不存在的地点，不得声称已核验营业时间。没有合适候选可返回空文本。",
            input: "用户要求：\(intent.mapQuery.isEmpty ? "自动推荐附近值得看的景点" : intent.mapQuery)。出行方式：\(mode.rawValue)。当前位置坐标：\(location.coordinate.latitude),\(location.coordinate.longitude)。候选：\n\(numbered)"
        )
        var seen: Set<Int> = []
        return output.split(separator: "\n").compactMap { line -> GuideAttraction? in
            let fields = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard fields.count == 3, fields[0].hasPrefix("p"),
                  let index = Int(fields[0].dropFirst()), candidates.indices.contains(index),
                  seen.insert(index).inserted else { return nil }
            let candidate = candidates[index]
            let coordinate = candidate.0.placemark.coordinate
            let stableID = "\(candidate.0.name ?? "")|\(coordinate.latitude)|\(coordinate.longitude)"
            return GuideAttraction(id: stableID, item: candidate.0, distance: candidate.1,
                                   reason: fields[1], highlight: fields[2])
        }.prefix(4).map { $0 }
    }
}
