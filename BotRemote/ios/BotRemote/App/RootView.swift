import SwiftUI
import LocalAuthentication

struct RootView: View {
    @EnvironmentObject var store: RemoteStore
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false
    @State private var authenticating = false
    @State private var authMessage: String?

    var body: some View {
        ZStack {
            TabView {
                DashboardView()
                    .tabItem { Label("Botlar", systemImage: "square.grid.2x2") }
                ConsoleTabView()
                    .tabItem { Label("Konsol", systemImage: "terminal") }
                SettingsView()
                    .tabItem { Label("Ayarlar", systemImage: "gearshape") }
            }
            .disabled(isLocked)
            .blur(radius: isLocked ? 8 : 0)

            if isLocked {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
        .onAppear {
            if biometricLockEnabled { lockAndAuthenticate() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && biometricLockEnabled && !isLocked {
                lockAndAuthenticate()
            }
        }
        .alert("Bot Remote", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Theme.cyan)
            Text("Bot Remote kilitli")
                .font(.title2.bold()).foregroundStyle(Theme.ink)
            Text("Devam etmek için biyometrik doğrulama yap.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button {
                authenticate()
            } label: {
                Label("Kimliğimi doğrula", systemImage: "lock.open")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authenticating)
            if let authMessage {
                Text(authMessage).font(.footnote).foregroundStyle(Theme.err)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.opacity(0.96).ignoresSafeArea())
    }

    private func lockAndAuthenticate() {
        guard biometricLockEnabled else { return }
        isLocked = true
        authenticate()
    }

    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        authMessage = nil
        let context = LAContext()
        context.localizedCancelTitle = "İptal"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticating = false
            authMessage = "Bu cihazda biyometrik doğrulama kullanılamıyor."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Bot Remote uygulamasının kilidini aç") { success, evalError in
            DispatchQueue.main.async {
                authenticating = false
                if success {
                    isLocked = false
                    authMessage = nil
                } else {
                    authMessage = evalError?.localizedDescription ?? "Doğrulama başarısız."
                }
            }
        }
    }
}
