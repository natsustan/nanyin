import SwiftUI

@main
struct NanyinApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Nanyin")
                .frame(minWidth: 800, minHeight: 500)
                .onAppear { _ = PlaybackEngine.shared }
        }
    }
}
