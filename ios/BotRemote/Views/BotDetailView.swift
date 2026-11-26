import SwiftUI

struct BotDetailView: View {
    @EnvironmentObject var store: RemoteStore
    let botId: String

    private var bot: BotInfo? { store.bots.first { $0.id == botId } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let bot {
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { StatusPill(status: bot.statusKind); Spacer() }
                            row("Kullanıcı adı", bot.username)
                            row("Sunucu", bot.address)
                            row("Kimlik doğrulama", bot.auth == "microsoft" ? "Microsoft" : "Çevrimdışı")
                            row("Sürüm", bot.serverVersion.isEmpty ? (bot.version.isEmpty ? "Auto" : bot.version) : bot.serverVersion)
                            HStack {
                                Text("Çalışma süresi").foregroundColor(Theme.muted)
                                Spacer()
                                UptimeText(since: bot.connectedDate)
                            }
                            if !bot.lastError.isEmpty && bot.statusKind != .online {
                                Text(bot.lastError).font(.caption).foregroundColor(Theme.err)
                            }
                        }
                        .card()

                        HStack(spacing: 12) {
                            Button { Task { await store.startBot(bot.id) } } label: {
                                Label("Başlat", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(bot.isActive || !canControl)

                            Button(role: .destructive) { Task { await store.stopBot(bot.id) } } label: {
                                Label("Durdur", systemImage: "stop.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!bot.isActive || !canControl)
                        }
                        .controlSize(.large)

                        NavigationLink {
                            ConsoleView(botId: bot.id)
                        } label: {
                            HStack { Label("Konsolu aç", systemImage: "terminal"); Spacer(); Image(systemName: "chevron.right") }
                                .card()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
                .navigationTitle(bot.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyState(icon: "questionmark.circle", title: "Bot bulunamadı", text: "Bilgisayardan kaldırılmış olabilir.")
            }
        }
    }

    private var canControl: Bool { store.desktopOnline && store.connection == .connected }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundColor(Theme.muted); Spacer(); Text(v).lineLimit(1) }
    }
}

/// Ticks once per second, only while visible (no timers when the view is off-screen).
struct UptimeText: View {
    let since: Date?
    var body: some View {
        if let since {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(formatUptime(ctx.date.timeIntervalSince(since))).monospacedDigit().foregroundColor(Theme.ok)
            }
        } else {
            Text("—").foregroundColor(Theme.muted)
        }
    }
}
