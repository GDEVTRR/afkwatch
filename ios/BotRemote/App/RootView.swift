import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: RemoteStore
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Botlar", systemImage: "square.grid.2x2.fill") }
            ConsoleTabView().tabItem { Label("Konsol", systemImage: "terminal") }
            SettingsView().tabItem { Label("Ayarlar", systemImage: "slider.horizontal.3") }
        }
        .toolbarBackground(.regularMaterial, for: .tabBar)
        .alert("Bot Remote", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
    }
}
