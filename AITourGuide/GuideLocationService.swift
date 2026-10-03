import CoreLocation
import Foundation

@MainActor
final class GuideLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var placeName = String(localized: "正在定位…")
    @Published private(set) var message = String(localized: "正在定位…")

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        guard !PublicDemo.enabled else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted: message = String(localized: "定位未开启；请在系统设置中允许此 App 使用位置。")
        @unknown default: message = String(localized: "暂时无法获取位置。")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !PublicDemo.enabled else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !PublicDemo.enabled else { return }
        guard location == nil else { return }
        guard let latest = locations.last else { return }
        manager.stopUpdatingLocation()
        location = latest
        message = String(localized: "已获取当前位置")
        Task {
            let placemark = try? await geocoder.reverseGeocodeLocation(latest).first
            placeName = placemark?.locality ?? placemark?.subLocality ?? placemark?.name ?? String(localized: "当前位置")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown {
            #if targetEnvironment(simulator)
            message = String(localized: "模拟器尚未提供位置；请在 Xcode 的“模拟位置”中选择测试城市，再点右上角刷新。")
            #else
            message = String(localized: "正在等待设备提供位置…")
            #endif
            return
        }
        message = String(format: NSLocalizedString("定位失败：%@", comment: ""), String(describing: PublicLanguage.errorDescription(error)))
    }
}
