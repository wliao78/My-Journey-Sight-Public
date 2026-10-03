import MapKit
import SwiftUI

struct GuidePlaceImage: View {
    let item: MKMapItem
    @State private var snapshot: UIImage?

    var body: some View {
        Group {
            if PublicDemo.enabled {
                GeometryReader { geometry in
                Image("DemoIllustration")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Text(String(localized: "示意图"))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(8)
                    }
                    .accessibilityLabel(String(localized: "离线演示示意图"))
                }
            } else if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(String(localized: "景点实景预览"))
            } else {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: item.placemark.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                ))) {
                    Marker(item.name ?? String(localized: "景点"), coordinate: item.placemark.coordinate)
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
                .accessibilityLabel(String(localized: "景点地图预览"))
            }
        }
        .task(id: "\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)") {
            guard !PublicDemo.enabled else { return }
            guard let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene else { return }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: 900, height: 600)
            snapshot = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        }
    }
}
