import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: RemoteStore
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if !store.isPaired {
                    EmptyState(icon: "qrcode.viewfinder", title: "Bilgisayarını bağla",
                               text: "Ayarlar sekmesinden masaüstü uygulamasındaki QR kodunu okut.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            overview
                            HStack {
                                Text("BOTLAR").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Theme.muted)
                                Spacer()
                                Text("\(store.bots.count) kayıt").font(.caption).foregroundStyle(Theme.muted)
                            }.padding(.top, 4)
                            if store.bots.isEmpty {
                                EmptyState(icon: "cpu", title: "Henüz bot yok",
                                           text: store.desktopOnline ? "Masaüstü uygulamasından bot ekleyebilirsin." : "Bilgisayar şu anda çevrimdışı.")
                                    .frame(maxWidth: .infinity).card()
                            } else {
                                ForEach(store.bots) { bot in
                                    NavigationLink(value: bot.id) { BotCard(bot: bot) }.buttonStyle(.plain)
                                }
                            }
                        }.padding()
                    }.refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Bot Remote")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in BotDetailView(botId: id) }
            .toolbar {
                if store.isPaired {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { Task { await store.startAll() } } label: { Label("Tüm botları başlat", systemImage: "play.fill") }
                            Button(role: .destructive) { Task { await store.stopAll() } } label: { Label("Tüm botları durdur", systemImage: "stop.fill") }
                            Button { Task { await store.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .disabled(!store.desktopOnline || store.connection != .connected)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack").font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent).frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.desktopOnline ? "Masaüstü bağlı" : "Masaüstü çevrimdışı").font(.headline)
                Text(store.connection.label).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Circle().fill(store.desktopOnline ? Theme.ok : Theme.err).frame(width: 9, height: 9)
        }.padding(.vertical, 4)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AKTİF BOT").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(store.activeCount)").font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("/ \(store.maxActive)").font(.title3.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Image(systemName: "waveform.path").font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
            ProgressView(value: Double(store.activeCount), total: Double(max(store.maxActive, 1)))
                .tint(Theme.accent)
            HStack {
                Label("\(store.bots.filter { $0.statusKind == .online }.count) çevrimiçi", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.ok)
                Spacer()
                Text("En fazla \(store.maxActive) bot").foregroundStyle(Theme.muted)
            }.font(.caption.weight(.medium))
        }.card()
    }
}

struct BotCard: View {
    let bot: BotInfo
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Theme.accent.opacity(0.10)).frame(width: 46, height: 46)
                Image(systemName: "cpu").font(.title3).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bot.name).font(.headline)
                Text("\(bot.username) · \(bot.address)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusPill(status: bot.statusKind)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }.card()
    }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accent)
            Text(title).font(.title3.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.padding(28)
    }
}
