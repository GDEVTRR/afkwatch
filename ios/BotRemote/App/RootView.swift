import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: RemoteStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            ConsoleTabView()
                .tabItem { Label("Console", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .alert("Bot Remote", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
