import SwiftUI

@main
struct AITourGuideApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if let preview = PublicLocalizationQA.screen { preview } else { TourGuideView() }
#else
                TourGuideView()
#endif
            }.environment(\.locale, PublicLanguage.locale)
        }
    }
}
