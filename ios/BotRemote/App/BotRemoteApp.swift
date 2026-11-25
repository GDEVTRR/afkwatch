import SwiftUI

@main
struct BotRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
                .onAppear { store.connect() }
                .onChange(of: scenePhase) { phase in
                    // Keep the single socket alive across foreground/background transitions.
                    if phase == .active { store.connect(); store.reconnectIfNeeded(); Task { await store.updateLiveActivity() } }
                }
        }
    }
}
