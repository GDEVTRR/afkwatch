import SwiftUI

@main
struct BotRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @AppStorage("appearance") private var appearance = "light"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(Theme.accent)
                .onAppear {
                    store.connect()
                    if UserDefaults.standard.object(forKey: "notificationPrompted") == nil {
                        Task {
                            _ = await NotificationService.shared.requestPermission()
                            UserDefaults.standard.set(true, forKey: "notificationPrompted")
                        }
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.connect()
                        store.reconnectIfNeeded()
                        Task { await store.updateLiveActivity() }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "botremote" else { return }
                    switch url.host {
                    case "start-all": Task { await store.startAll() }
                    case "stop-all": Task { await store.stopAll() }
                    case "refresh": Task { await store.refresh() }
                    default: break
                    }
                }
        }
    }
}
