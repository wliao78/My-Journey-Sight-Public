import CoreLocation
import Foundation
import WeatherKit

struct GuideWeatherSnapshot {
    let summary: String
    let symbol: String

    static let unavailable = GuideWeatherSnapshot(summary: String(localized: "天气暂不可用"), symbol: "cloud")
}

struct GuideWeatherService {
    func current(at location: CLLocation) async throws -> GuideWeatherSnapshot {
        let weather = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current)
        let celsius = weather.temperature.converted(to: .celsius).value
        return GuideWeatherSnapshot(
            summary: "\(celsius.formatted(.number.precision(.fractionLength(1))))° · \(PublicLanguage.weather(weather.condition.rawValue))",
            symbol: weather.symbolName
        )
    }
}
