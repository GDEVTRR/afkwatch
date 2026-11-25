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
                        Button("Yeniden bağlan") { store.disconnectSocket(); store.connect() }
                        Button("Bu cihazın bağlantısını kes", role: .destructive) { confirmUnpair = true }
                    } else {
                        Button { showScanner = true } label: { Label("Eşleştirme QR kodunu okut", systemImage: "qrcode.viewfinder") }
                        Button { showManual = true } label: { Label("Eşleştirme metnini gir", systemImage: "keyboard") }
                    }
                    if store.busy { ProgressView() }
                }

                Section("Güvenlik") {
                    Toggle(isOn: $biometricLockEnabled) {
                        Label("Biyometrik kilit", systemImage: "faceid")
                    }
                    Text("Uygulama açıldığında Face ID, Touch ID veya cihaz parolası istenir.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }

                Section("Hakkında") {
                    HStack { Text("En fazla bot"); Spacer(); Text("\(store.maxActive)").foregroundColor(Theme.muted) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Ayarlar")
            .onAppear { urlText = store.serverURL }
            .onChange(of: store.serverURL) { urlText = $0 }
            .sheet(isPresented: $showScanner) { scannerSheet }
            .sheet(isPresented: $showManual) { manualSheet }
            .alert("Bu sunucuyla eşleştirilsin mi?", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("İptal", role: .cancel) { pending = nil }
                Button("Eşleştir") {
                    if let p = pending { Task { await store.pair(with: p) } }
                    pending = nil
                }
            } message: {
                Text(pending.map { "Bu iPhone şu bilgisayara bağlanacak:\n\($0.u)" } ?? "")
            }
            .confirmationDialog("Bu cihazın bağlantısı kesilsin mi?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Bağlantıyı kes", role: .destructive) { Task { await store.unpair() } }
            } message: {
                Text("Yeniden eşleştirene kadar bilgisayarın bu iPhone’dan komut kabul etmeyecek.")
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

    private var scannerSheet: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRScannerView { code in
                    showScanner = false
                    handle(code)
                }
                .ignoresSafeArea()
                Text("Kamerayı masaüstü uygulamasındaki QR koduna tut.")
                    .font(.footnote).padding(10).background(.ultraThinMaterial).clipShape(Capsule()).padding()
            }
            .navigationTitle("QR kodu okut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("İptal") { showScanner = false } } }
        }
    }

    private var manualSheet: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Masaüstü uygulamasındaki QR kodunun altındaki eşleştirme metnini yapıştır.")) {
                    TextEditor(text: $manualText).frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Devam et") { showManual = false; handle(manualText); manualText = "" }
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
        pending = payload   // always ask the user to confirm the server before linking
    }
}
