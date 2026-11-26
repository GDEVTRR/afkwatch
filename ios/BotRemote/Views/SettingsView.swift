import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var urlText = ""
    @State private var showScanner = false
    @State private var showManual = false
    @State private var manualText = ""
    @State private var pending: PairingPayload?
    @State private var confirmUnpair = false
    @State private var biometricError: String?
    @State private var checkingBiometrics = false

    @AppStorage("appearance") private var appearance = "light"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bağlantı") {
                    HStack {
                        Text("Durum")
                        Spacer()
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(store.connection.label).foregroundColor(Theme.muted)
                    }
                    if store.isPaired {
                        HStack {
                            Text("Bilgisayar")
                            Spacer()
                            Text(store.desktopOnline ? "Çevrimiçi" : "Çevrimdışı")
                                .foregroundColor(store.desktopOnline ? Theme.ok : Theme.err)
                        }
                    }
                }

                Section(header: Text("Bulut sunucusu"), footer: Text("QR kodu okuttuğunda otomatik ayarlanır. HTTPS gereklidir.")) {
                    TextField("https://your-server.onrender.com", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(store.isPaired)
                        .onSubmit { store.saveServerURL(urlText) }
                }

                Section("Cihaz eşleştirme") {
                    if store.isPaired {
                        Button("Yeniden bağlan") {
                            store.disconnectSocket()
                            store.connect()
                        }
                        Button("Bu cihazın bağlantısını kes", role: .destructive) {
                            confirmUnpair = true
                        }
                    } else {
                        Button { showScanner = true } label: {
                            Label("Eşleştirme QR kodunu okut", systemImage: "qrcode.viewfinder")
                        }
                        Button { showManual = true } label: {
                            Label("Eşleştirme metnini gir", systemImage: "keyboard")
                        }
                    }
                    if store.busy { ProgressView() }
                }

                Section("Görünüm") {
                    Picker("Tema", selection: $appearance) {
                        Text("Açık").tag("light")
                        Text("Koyu").tag("dark")
                        Text("Sistem").tag("system")
                    }
                }

                Section {
                    Toggle("\(biometryName) ile kilitle", isOn: Binding(
                        get: { biometricLockEnabled },
                        set: { setBiometricLock($0) }
                    ))
                    .disabled(checkingBiometrics)

                    if checkingBiometrics {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Kimlik doğrulanıyor…")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    if let biometricError {
                        Text(biometricError)
                            .font(.caption)
                            .foregroundStyle(Theme.err)
                    } else {
                        Text("Açıldığında veya uygulamaya geri döndüğünde Face ID / Touch ID ya da cihaz parolası istenir.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("Güvenlik")
                }

                Section("Bildirimler") {
                    Toggle("Bot durum bildirimleri", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { enabled in
                            if enabled { Task { _ = await NotificationService.shared.requestPermission() } }
                        }
                    Text("Bot aktif olduğunda veya bağlantısı kesildiğinde bildirim alırsın.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Section("Kestirmeler ve Siri") {
                    Label("“Botları başlat”", systemImage: "play.fill")
                    Label("“Botları durdur”", systemImage: "stop.fill")
                    Label("“Botları yenile”", systemImage: "arrow.clockwise")
                    Text("Komutları Siri'ye söyleyebilir veya Kestirmeler uygulamasına ekleyebilirsin.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Section("Hakkında") {
                    HStack {
                        Text("Aktif bot sınırı")
                        Spacer()
                        Text(store.maxActive > 0 ? "\(store.maxActive)" : "Limitsiz")
                            .foregroundColor(Theme.muted)
                    }
                    HStack {
                        Text("Sürüm")
                        Spacer()
                        Text("1.2.0").foregroundColor(Theme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Ayarlar")
            .tint(Theme.accent)
            .onAppear { urlText = store.serverURL }
            .onChange(of: store.serverURL) { urlText = $0 }
            .sheet(isPresented: $showScanner) { scannerSheet }
            .sheet(isPresented: $showManual) { manualSheet }
            .alert("Bu sunucu eşleştirilsin mi?", isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            )) {
                Button("İptal", role: .cancel) { pending = nil }
                Button("Eşleştir") {
                    if let payload = pending { Task { await store.pair(with: payload) } }
                    pending = nil
                }
            } message: {
                Text(pending.map { "iPhone şu bilgisayara bağlanacak:\n\($0.u)" } ?? "")
            }
            .confirmationDialog("Cihaz bağlantısı kesilsin mi?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Bağlantıyı kes", role: .destructive) { Task { await store.unpair() } }
            } message: {
                Text("Yeniden eşleştirene kadar bilgisayar bu iPhone’dan komut kabul etmeyecek.")
            }
        }
    }

    private var color: Color {
        switch store.connection {
        case .connected: return Theme.ok
        case .connecting: return Theme.warn
        default: return Theme.err
        }
    }

    private var biometryName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biyometrik kilit"
        }
    }

    private func setBiometricLock(_ enabled: Bool) {
        biometricError = nil
        guard enabled else { biometricLockEnabled = false; return }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            biometricLockEnabled = false
            biometricError = policyError?.localizedDescription ?? "Bu cihazda Face ID veya Touch ID kullanılamıyor."
            return
        }

        checkingBiometrics = true
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Bot Remote uygulamasını kilitlemek için kimliğini doğrula."
        ) { success, error in
            DispatchQueue.main.async {
                checkingBiometrics = false
                biometricLockEnabled = success
                if !success { biometricError = error?.localizedDescription ?? "Kimlik doğrulaması tamamlanamadı." }
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRScannerView { code in
                    showScanner = false
                    handle(code)
                }
                .ignoresSafeArea()
                Text("Kamerayı masaüstü uygulamasındaki QR koduna tut.")
                    .font(.footnote)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding()
            }
            .navigationTitle("QR kodu okut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("İptal") { showScanner = false } } }
        }
    }

    private var manualSheet: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Masaüstü uygulamasında QR kodunun altında görünen metni yapıştır.")) {
                    TextEditor(text: $manualText)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Devam et") {
                    showManual = false
                    handle(manualText)
                    manualText = ""
                }
                .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Eşleştirme metni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("İptal") { showManual = false } } }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            store.errorMessage = "Bu geçerli bir Bot Remote eşleştirme kodu değil."
            return
        }
        pending = payload
    }
}
