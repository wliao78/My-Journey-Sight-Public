import MapKit
import SwiftUI

struct GuidePlaceImage: View {
    let item: MKMapItem
    @State private var snapshot: UIImage?

    var body: some View {
        Group {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("景点实景预览")
            } else {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: item.placemark.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                ))) {
                    Marker(item.name ?? "景点", coordinate: item.placemark.coordinate)
                }
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
                .accessibilityLabel("景点地图预览")
            }
        }
        .task(id: "\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)") {
            guard let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene else { return }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: 900, height: 600)
            snapshot = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        }
    }
}

