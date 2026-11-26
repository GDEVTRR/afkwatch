import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var store: RemoteStore
    let botId: String

    @State private var message = ""
    @State private var sending = false
    @State private var filter = "all"
    @FocusState private var inputFocused: Bool

    private var bot: BotInfo? { store.bots.first { $0.id == botId } }
    private var entries: [LogEntry] { store.logs[botId] ?? [] }
    private var visibleEntries: [LogEntry] {
        switch filter {
        case "errors": return entries.filter { $0.k == "error" }
        case "chat": return entries.filter { $0.k == "chat" || $0.k == "out" }
        case "system": return entries.filter { $0.k == "system" || $0.k == "info" }
        default: return entries
        }
    }
    private var canSend: Bool {
        bot?.statusKind == .online && store.connection == .connected && store.desktopOnline
    }

    var body: some View {
        VStack(spacing: 0) {
            consoleHeader
            filterBar
            Divider().overlay(Theme.line)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if visibleEntries.isEmpty {
                            Text(entries.isEmpty ? "Henüz konsol kaydı yok." : "Bu filtrede kayıt bulunamadı.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 180)
                                .multilineTextAlignment(.center)
                        } else {
                            ForEach(visibleEntries) { entry in
                                LogLine(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        Color.clear.frame(height: 2).id("console-bottom")
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                }
                .background(Theme.card.opacity(0.72))
                .onChange(of: visibleEntries.count) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("console-bottom", anchor: .bottom)
                    }
                }
                .onAppear { proxy.scrollTo("console-bottom", anchor: .bottom) }
            }

            messageComposer
        }
        .background(Theme.background)
        .navigationTitle(bot?.name ?? "Konsol")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { Task { await store.loadLogs(botId) } } label: {
                        Label("Kayıtları yenile", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { store.clearLogs(botId) } label: {
                        Label("Görünen kayıtları temizle", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await store.loadLogs(botId) }
    }

    private var consoleHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bot.map { Theme.color(for: $0.statusKind) } ?? Theme.muted)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(bot?.name ?? "Bot")
                    .font(.subheadline.weight(.semibold))
                Text(bot?.address ?? "Bot bilgisi alınamadı")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(entries.count) kayıt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.muted)
            StatusPill(status: bot?.statusKind ?? .stopped)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card)
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            filterButton("Tümü", value: "all")
            filterButton("Sistem", value: "system")
            filterButton("Sohbet", value: "chat")
            filterButton("Hatalar", value: "errors")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.background)
    }

    private func filterButton(_ title: String, value: String) -> some View {
        Button {
            filter = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(filter == value ? Color.white : Theme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(filter == value ? Theme.accent : Theme.cardHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var messageComposer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(canSend ? "Minecraft sohbetine mesaj yaz…" : "Mesaj için bot çevrimiçi olmalı", text: $message, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 16))
                .focused($inputFocused)
                .submitLabel(.send)
                .disabled(!canSend)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: sending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 43, height: 43)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!canSend || sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(11)
        .background(Theme.background)
        .overlay(alignment: .top) { Divider().overlay(Theme.line) }
    }

    private func sendMessage() {
        let outgoing = message
        guard canSend, !sending, !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        Task {
            let sent = await store.sendChat(botId, text: outgoing)
            if sent { message = "" }
            sending = false
        }
    }
}

struct LogLine: View {
    let entry: LogEntry

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.formatter.string(from: entry.date))
                .foregroundStyle(Color(hex: 0x718596))
                .frame(width: 62, alignment: .leading)
            Text(entry.m)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch entry.k {
        case "error": return Theme.err
        case "system": return Theme.cyan
        case "out": return Theme.ok
        case "info": return Theme.muted
        default: return Color.primary
        }
    }
}

/// The bot switcher is a menu instead of a segmented picker, so it remains usable with many bots.
struct ConsoleTabView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var selectedBotID: String?

    private var selectedBot: BotInfo? {
        if let selectedBotID, let match = store.bots.first(where: { $0.id == selectedBotID }) { return match }
        return store.bots.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.bots.isEmpty {
                    EmptyState(icon: "terminal", title: "Bot yok", text: "Bilgisayarını eşleştir ve masaüstü uygulamasından bot ekle.")
                } else if let bot = selectedBot {
                    VStack(spacing: 0) {
                        Menu {
                            ForEach(store.bots) { item in
                                Button {
                                    selectedBotID = item.id
                                } label: {
                                    if item.id == bot.id {
                                        Label(item.name, systemImage: "checkmark")
                                    } else {
                                        Text(item.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                ServerIconView(bot: bot)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bot.name).font(.subheadline.weight(.semibold))
                                    Text("\(store.bots.count) bot arasından seç")
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                StatusPill(status: bot.statusKind)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                            }
                            .padding(11)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)

                        ConsoleView(botId: bot.id).id(bot.id)
                    }
                }
            }
            .navigationTitle("Konsol")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: store.bots) { bots in
                if let selectedBotID, !bots.contains(where: { $0.id == selectedBotID }) {
                    self.selectedBotID = bots.first?.id
                }
            }
            .onAppear {
                if selectedBotID == nil { selectedBotID = store.bots.first?.id }
            }
        }
    }
}
