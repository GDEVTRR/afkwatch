import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: RemoteStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if !store.isPaired {
                    EmptyState(icon: "qrcode.viewfinder", title: "Bilgisayarını eşleştir",
                               text: "Ayarlar bölümünden bilgisayar uygulamasındaki QR kodunu okut.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            summaryCard
                            HStack {
                                Text("Botların").font(.title3.bold()).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(store.bots.count) kayıtlı").font(.caption).foregroundStyle(Theme.muted)
                            }
                            if store.bots.isEmpty {
                                EmptyState(icon: "cpu", title: "Henüz bot yok",
                                           text: store.desktopOnline ? "Masaüstü uygulamasından bot ekle." : "Bilgisayarın çevrimdışı.")
                                    .frame(maxWidth: .infinity, minHeight: 180)
                                    .card()
                            } else {
                                ForEach(store.bots) { bot in
                                    NavigationLink(value: bot.id) { BotCard(bot: bot) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Kontrol Merkezi")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in BotDetailView(botId: id) }
            .toolbar {
                if store.isPaired {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { Task { await store.refresh() } } label: { Label("Durumu yenile", systemImage: "arrow.clockwise") }
                            Button { Task { await store.startAll() } } label: { Label("Tüm botları başlat", systemImage: "play.fill") }
                            Button(role: .destructive) { Task { await store.stopAll() } } label: { Label("Tüm botları durdur", systemImage: "stop.fill") }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                        }
                        .disabled(!store.desktopOnline || store.connection != .connected)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(store.desktopOnline ? Theme.ok : Theme.err).frame(width: 8, height: 8)
            Text(store.desktopOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı")
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
            Spacer()
            Text(store.connection.label).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aktif bot").font(.subheadline).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(store.activeCount)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink).monospacedDigit()
                        Text("/ \(store.maxActive)").font(.title3).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 62, height: 62)
                    .background(Theme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            }
            ProgressView(value: Double(store.activeCount), total: Double(max(store.maxActive, 1)))
                .tint(Theme.cyan)
            HStack {
                Label("\(store.bots.filter { $0.statusKind == .online }.count) çevrimiçi", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.ok)
                Spacer()
                Text("En fazla \(store.maxActive) aktif bot")
                    .foregroundStyle(Theme.muted)
            }
            .font(.caption)
        }
        .card()
    }
}

struct BotCard: View {
    let bot: BotInfo
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "bot")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 46, height: 46)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(bot.name).font(.headline).foregroundStyle(Theme.ink)
                Text("\(bot.username) · \(bot.address)")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(status: bot.statusKind)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(Theme.cyan)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(26)
    }
}
