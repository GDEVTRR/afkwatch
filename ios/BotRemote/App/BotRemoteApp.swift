import SwiftUI
import LocalAuthentication

@main
struct BotRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked = true
    @State private var isAuthenticating = false
    @State private var authenticationError: String?

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)

                if biometricLockEnabled && !isUnlocked {
                    AppLockOverlay(
                        isAuthenticating: isAuthenticating,
                        errorMessage: authenticationError,
                        unlock: authenticate
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .tint(Theme.accent)
            .onAppear {
                if biometricLockEnabled {
                    isUnlocked = false
                    authenticate()
                }
                store.connect()
                if UserDefaults.standard.object(forKey: "notificationPrompted") == nil {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        UserDefaults.standard.set(true, forKey: "notificationPrompted")
                    }
                }
            }
            .onChange(of: biometricLockEnabled) { enabled in
                if !enabled {
                    isUnlocked = true
                    authenticationError = nil
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    if biometricLockEnabled {
                        isUnlocked = false
                        authenticationError = nil
                    }
                } else if phase == .active {
                    store.connect()
                    store.reconnectIfNeeded()
                    Task { await store.updateLiveActivity() }
                    if biometricLockEnabled && !isUnlocked {
                        authenticate()
                    }
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

    private func authenticate() {
        guard biometricLockEnabled, !isUnlocked, !isAuthenticating else { return }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            authenticationError = policyError?.localizedDescription ?? "Bu cihazda kimlik doğrulaması kullanılamıyor."
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Bot Remote içeriğine erişmek için kimliğini doğrula."
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    isUnlocked = true
                    authenticationError = nil
                } else {
                    authenticationError = error?.localizedDescription ?? "Kimlik doğrulaması tamamlanamadı."
                }
            }
        }
    }
}

private struct AppLockOverlay: View {
    let isAuthenticating: Bool
    let errorMessage: String?
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 88, height: 88)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))

                Text("Bot Remote kilitli")
                    .font(.title2.weight(.bold))
                Text("Devam etmek için Face ID, Touch ID veya cihaz parolanla kimliğini doğrula.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                if isAuthenticating {
                    ProgressView("Doğrulanıyor…")
                        .padding(.top, 4)
                } else {
                    Button(action: unlock) {
                        Label("Yeniden dene", systemImage: "lock.open.fill")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.err)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            .padding(28)
        }
        .accessibilityAddTraits(.isModal)
    }
}
