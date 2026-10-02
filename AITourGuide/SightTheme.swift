import SwiftUI

enum SightTheme {
    static let accent = Color(red: 0.56, green: 0.91, blue: 0.70)
    static let secondary = Color.white.opacity(0.7)
    static let panel = Color.white.opacity(0.11)
    static let border = Color.white.opacity(0.16)

    static var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.13, blue: 0.13),
                    Color(red: 0.06, green: 0.23, blue: 0.20),
                    Color(red: 0.035, green: 0.12, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.green.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 100)
                .offset(x: 190, y: -300)
            Circle()
                .fill(Color.mint.opacity(0.16))
                .frame(width: 350, height: 350)
                .blur(radius: 100)
                .offset(x: -190, y: 360)
        }
        .ignoresSafeArea()
    }
}

private struct SightPanel: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(SightTheme.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(SightTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func sightPanel(radius: CGFloat = 22) -> some View {
        modifier(SightPanel(radius: radius))
    }
}
