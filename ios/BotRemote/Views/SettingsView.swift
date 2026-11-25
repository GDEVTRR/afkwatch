import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var urlText = ""
    @State private var showScanner = false
    @State private var showManual = false
    @State private var manualText = ""
    @State private var pending: PairingPayload?
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(store.connection.label).foregroundColor(Theme.muted)
                    }
                    if store.isPaired {
                        HStack {
                            Text("PC")
                            Spacer()
                            Text(store.desktopOnline ? "Online" : "Offline")
                                .foregroundColor(store.desktopOnline ? Theme.ok : Theme.err)
                        }
                    }
                }

                Section(header: Text("Cloud server"), footer: Text("Set automatically when you scan the QR code. HTTPS is required.")) {
                    TextField("https://your-server.onrender.com", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(store.isPaired)
                        .onSubmit { store.saveServerURL(urlText) }
                }

                Section("Device pairing") {
                    if store.isPaired {
                        Button("Reconnect") { store.disconnectSocket(); store.connect() }
                        Button("Disconnect this device", role: .destructive) { confirmUnpair = true }
                    } else {
                        Button { showScanner = true } label: { Label("Scan pairing QR code", systemImage: "qrcode.viewfinder") }
                        Button { showManual = true } label: { Label("Enter pairing text", systemImage: "keyboard") }
                    }
                    if store.busy { ProgressView() }
                }

                Section("About") {
                    HStack { Text("Max bots"); Spacer(); Text("\(store.maxActive)").foregroundColor(Theme.muted) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .onAppear { urlText = store.serverURL }
            .onChange(of: store.serverURL) { urlText = $0 }
            .sheet(isPresented: $showScanner) { scannerSheet }
            .sheet(isPresented: $showManual) { manualSheet }
            .alert("Pair with this server?", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Pair") {
                    if let p = pending { Task { await store.pair(with: p) } }
                    pending = nil
                }
            } message: {
                Text(pending.map { "This will link your iPhone to the PC registered on:\n\($0.u)" } ?? "")
            }
            .confirmationDialog("Disconnect this device?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await store.unpair() } }
            } message: {
                Text("Your PC will no longer accept commands from this iPhone until you pair again.")
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
                Text("Point the camera at the QR code in the desktop app")
                    .font(.footnote).padding(10).background(.ultraThinMaterial).clipShape(Capsule()).padding()
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScanner = false } } }
        }
    }

    private var manualSheet: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Paste the pairing text shown under the QR code in the desktop app.")) {
                    TextEditor(text: $manualText).frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Continue") { showManual = false; handle(manualText); manualText = "" }
                    .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Pairing text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showManual = false } } }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            store.errorMessage = "This is not a Bot Remote pairing code."
            return
        }
        pending = payload   // always ask the user to confirm the server before linking
    }
}
