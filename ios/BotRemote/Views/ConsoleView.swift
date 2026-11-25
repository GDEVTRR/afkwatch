import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var store: RemoteStore
    let botId: String
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private var bot: BotInfo? { store.bots.first { $0.id == botId } }
    private var entries: [LogEntry] { store.logs[botId] ?? [] }
    private var canSend: Bool {
        bot?.statusKind == .online && store.connection == .connected && store.desktopOnline
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(entries) { e in
                            LogLine(entry: e).id(e.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
                .background(Theme.card)
                .onChange(of: entries.count) { _ in
                    withAnimation(.none) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            HStack(spacing: 8) {
                TextField(canSend ? "Send chat message" : "Bot must be online to chat", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .focused($focused)
                    .disabled(!canSend)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend || sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .background(Theme.background)
        }
        .background(Theme.background)
        .navigationTitle(bot?.name ?? "Konsol")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Temizle") { store.clearLogs(botId) }
            }
        }
        .task { await store.loadLogs(botId) }
    }

    private func send() {
        let message = text
        guard canSend, !sending else { return }
        sending = true
        Task {
            let ok = await store.sendChat(botId, text: message)
            if ok { text = "" }
            sending = false
        }
    }
}

struct LogLine: View {
    let entry: LogEntry
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        (Text(Self.formatter.string(from: entry.date) + "  ").foregroundColor(Color(hex: 0x4B6073))
         + Text(entry.m).foregroundColor(color))
            .font(.system(size: 12.5, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var color: Color {
        switch entry.k {
        case "error": return Theme.err
        case "system": return Theme.cyan
        case "out": return Theme.ok
        case "info": return Theme.muted
        default: return .white
        }
    }
}

/// Console tab: choose a bot, then show its console.
struct ConsoleTabView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var selected: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.bots.isEmpty {
                    EmptyState(icon: "terminal", title: "Bot yok", text: "Bilgisayarını eşleştir ve masaüstü uygulamasından bot ekle.")
                } else {
                    VStack(spacing: 0) {
                        Picker("Bot", selection: Binding(
                            get: { selected ?? store.bots.first?.id ?? "" },
                            set: { selected = $0 }
                        )) {
                            ForEach(store.bots) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .padding(10)
                        if let id = selected ?? store.bots.first?.id {
                            ConsoleView(botId: id).id(id)
                        }
                    }
                }
            }
            .navigationTitle("Konsol")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
