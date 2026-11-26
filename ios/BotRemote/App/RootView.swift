import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: RemoteStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Botlar", systemImage: "square.grid.2x2.fill") }
            GalleryView()
                .tabItem { Label("Galeri", systemImage: "photo.on.rectangle.angled") }
            ConsoleTabView()
                .tabItem { Label("Konsol", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "slider.horizontal.3") }
        }
        .onAppear(perform: syncWidget)
        .onChange(of: store.bots) { _ in syncWidget() }
        .onChange(of: store.desktopOnline) { _ in syncWidget() }
        .onChange(of: store.maxActive) { _ in syncWidget() }
        .onChange(of: store.connection) { _ in syncWidget() }
        .alert("Bot Remote", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func syncWidget() {
        WidgetDataStore.update(from: store)
    }
}
