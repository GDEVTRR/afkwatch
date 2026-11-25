import SwiftUI

@main
struct BotRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Theme.cyan)
                .onAppear { store.connect() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.connect()
                        store.reconnectIfNeeded()
                        Task { await store.updateLiveActivity() }
                    }
                }
        }
    }
}
