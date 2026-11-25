import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: RemoteStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if !store.isPaired {
                    EmptyState(icon: "qrcode.viewfinder", title: "Bilgisayarını eşleştir",
                               text: "Ayarlar bölümünden bilgisayar uygulamasında gösterilen QR kodu okut.")
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryCard
                            if store.bots.isEmpty {
                                EmptyState(icon: "cpu", title: "Henüz bot yok",
                                           text: store.desktopOnline ? "Masaüstü uygulamasından bot ekle." : "Bilgisayarın çevrimdışı.")
                                    .frame(height: 220)
                            } else {
                                ForEach(store.bots) { bot in
                                    NavigationLink(value: bot.id) { BotCard(bot: bot) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Botlar")
            .navigationDestination(for: String.self) { id in BotDetailView(botId: id) }
            .toolbar {
                if store.isPaired {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { Task { await store.startAll() } } label: { Label("Tümünü başlat", systemImage: "play.fill") }
                            Button(role: .destructive) { Task { await store.stopAll() } } label: { Label("Tümünü durdur", systemImage: "stop.fill") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .disabled(!store.desktopOnline || store.connection != .connected)
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(store.desktopOnline ? Theme.ok : Theme.err).frame(width: 10, height: 10)
                Text(store.desktopOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı").font(.headline)
                Spacer()
                Text(store.connection.label).font(.caption).foregroundColor(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(store.activeCount)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(Theme.cyan)
                Text("/ \(store.maxActive) bot sınırı").foregroundColor(Theme.muted)
                Spacer()
            }
            ProgressView(value: Double(store.activeCount), total: Double(max(store.maxActive, 1))).tint(Theme.cyan)
        }
        .card()
    }
}

struct BotCard: View {
    let bot: BotInfo
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.color(for: bot.statusKind)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(bot.name).font(.headline)
                Text("\(bot.username) · \(bot.address)").font(.caption).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer()
            StatusPill(status: bot.statusKind)
            Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.muted)
        }
        .card()
    }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(Theme.cyan)
            Text(title).font(.title3.weight(.semibold))
            Text(text).font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
