import CoreLocation
import MapKit
import SwiftUI

struct AttractionDetailView: View {
    @StateObject private var playback = GuideSpeechPlaybackService()
    let attraction: GuideAttraction
    let travelMode: GuideTravelMode
    let currentLocation: CLLocation?
    @Binding var messages: [GuideMessage]
    @Binding var length: GuideLength
    let onAppear: () -> Void
    let onDisappear: () -> Void
    let onLengthChange: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GuidePlaceImage(item: attraction.item)
                    .frame(height: 260)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(attraction.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(attraction.reason)
                    .font(.body)
                    .foregroundStyle(SightTheme.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "最值得知道"), systemImage: "sparkles")
                        .font(.headline)
                    Text(attraction.highlight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .sightPanel(radius: 14)
                Label(String(format: NSLocalizedString("距当前位置约 %@ 米 · %@", comment: ""), String(describing: Int(attraction.distance)), String(describing: travelMode.title)), systemImage: travelMode == .walking ? "figure.walk" : "car")
                    .font(.headline)
                    .foregroundStyle(SightTheme.accent)

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "地点信息"), systemImage: "mappin.circle")
                        .font(.headline)
                    Text(attraction.address.isEmpty ? String(localized: "地址暂不可用") : attraction.address)
                        .textSelection(.enabled)
                    if let website = attraction.item.url {
                        Link(String(localized: "查看官方网站"), destination: website)
                    }
                    Text(String(localized: "开放时间和现场活动请以场馆公告为准。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .sightPanel(radius: 14)

                if PublicDemo.enabled {
                    Label(PublicDemo.notice, systemImage: "wifi.slash")
                        .padding().frame(maxWidth: .infinity)
                } else {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: attraction.item.placemark.coordinate,
                    latitudinalMeters: 1_400,
                    longitudinalMeters: 1_400
                ))) {
                    Marker(attraction.name, coordinate: attraction.item.placemark.coordinate)
                    if let currentLocation {
                        Marker(String(localized: "我的位置"), systemImage: "location.fill", coordinate: currentLocation.coordinate)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    attraction.item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: travelMode.directionsMode
                    ])
                } label: {
                    Label(String(format: NSLocalizedString("在 Apple 地图中%@导航", comment: ""), String(describing: travelMode.title)), systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                }

                HStack {
                    Text(String(localized: "AI 讲解"))
                        .font(.title2.bold())
                    Spacer()
                    if let narration = messages.first(where: { !$0.isUser && !$0.text.hasPrefix("正在准备") && !$0.text.hasPrefix("讲解暂不可用") }) {
                        Button {
                            playback.toggle(message: narration)
                        } label: {
                            Label(playback.speakingMessageID == narration.id ? String(localized: "停止播放") : String(localized: "播放讲解"),
                                  systemImage: playback.speakingMessageID == narration.id ? "stop.circle.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(playback.speakingMessageID == narration.id ? String(localized: "停止语音讲解") : String(localized: "播放语音讲解"))
                    }
                }
                Picker(String(localized: "讲解长度"), selection: $length) {
                    ForEach(GuideLength.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: length) { _, _ in onLengthChange() }
                ForEach(messages) { message in
                    Text(message.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(message.isUser ? SightTheme.accent.opacity(0.22) : SightTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(String(localized: "AI 讲解尚未经过外部资料核验。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }.defaultScrollAnchor(PublicLanguage.qaScrollBottom ? .bottom : .top)
        .background { SightTheme.background }
        .foregroundStyle(.white)
        .tint(SightTheme.accent)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: onAppear)
        .onDisappear {
            playback.stop()
            onDisappear()
        }
        .onChange(of: messages.first?.id) { _, _ in playback.stop() }
    }
}
