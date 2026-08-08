import SwiftUI

@main
struct LiftKitWatchApp: App {
    @State private var store = WatchStore.shared

    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
    }
}
