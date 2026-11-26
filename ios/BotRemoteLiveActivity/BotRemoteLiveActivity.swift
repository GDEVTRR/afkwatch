import ActivityKit
import SwiftUI
import WidgetKit

struct BotRemoteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var activeBots: Int
        var totalBots: Int
        var pcOnline: Bool
        var updatedAt: Date
    }
    var deviceName: String
}

// MARK: - Live Activity / Dynamic Island

struct BotRemoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotRemoteActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bot Remote").font(.headline)
                    Text(context.state.pcOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(context.state.activeBots)/\(context.state.totalBots)")
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text("Etkin bot")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.04, green: 0.07, blue: 0.12))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "server.rack").foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.activeBots)/\(context.state.totalBots)")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Circle()
                            .fill(context.state.pcOnline ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(context.state.pcOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı")
                        Spacer()
                        Text("Etkin bot").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "server.rack").foregroundStyle(.cyan)
            } compactTrailing: {
                Text("\(context.state.activeBots)").monospacedDigit()
            } minimal: {
                Image(systemName: "server.rack").foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
        }
    }
}

// MARK: - Home Screen and Lock Screen widget

private struct BotRemoteWidgetEntry: TimelineEntry {
    let date: Date
    let activeBots: Int
    let totalBots: Int
    let maxActive: Int
    let pcOnline: Bool
    let isPaired: Bool
}

private struct BotRemoteWidgetProvider: TimelineProvider {
    private let appGroup = "group.com.botremote.shared"

    func placeholder(in context: Context) -> BotRemoteWidgetEntry {
        BotRemoteWidgetEntry(date: .now, activeBots: 2, totalBots: 3, maxActive: 5, pcOnline: true, isPaired: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BotRemoteWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BotRemoteWidgetEntry>) -> Void) {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readEntry() -> BotRemoteWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return BotRemoteWidgetEntry(
            date: .now,
            activeBots: defaults?.integer(forKey: "activeBots") ?? 0,
            totalBots: defaults?.integer(forKey: "totalBots") ?? 0,
            maxActive: max(defaults?.integer(forKey: "maxActive") ?? 5, 1),
            pcOnline: defaults?.bool(forKey: "desktopOnline") ?? false,
            isPaired: defaults?.bool(forKey: "isPaired") ?? false
        )
    }
}

struct BotRemoteStatusWidget: Widget {
    private let kind = "BotRemoteStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BotRemoteWidgetProvider()) { entry in
            BotRemoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Bot Remote")
        .description("Aktif bot sayısını ve bilgisayar bağlantısını gösterir.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct BotRemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BotRemoteWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLockScreen
            case .accessoryRectangular:
                rectangularLockScreen
            case .accessoryInline:
                inlineLockScreen
            case .systemMedium:
                mediumHomeScreen
            default:
                smallHomeScreen
            }
        }
        .widgetURL(URL(string: "botremote://refresh"))
    }

    private var circularLockScreen: some View {
        VStack(spacing: 1) {
            Text(entry.isPaired ? "\(entry.activeBots)" : "—")
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
            Text("BOT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
        }
        .widgetAccentable()
    }

    private var rectangularLockScreen: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.title2)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 2) {
                Text("BOT REMOTE").font(.caption2.weight(.bold))
                Text(entry.isPaired ? "\(entry.activeBots)/\(entry.totalBots) aktif bot" : "Eşleştirme bekleniyor")
                    .font(.caption)
                Text(entry.isPaired ? (entry.pcOnline ? "PC çevrimiçi" : "PC çevrimdışı") : "Uygulamayı aç")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inlineLockScreen: some View {
        Text(entry.isPaired ? "Bot Remote · \(entry.activeBots)/\(entry.totalBots) bot aktif" : "Bot Remote · Eşleştirilmedi")
    }

    private var smallHomeScreen: some View {
        widgetBackground(
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.cyan)
                    Text("BOT REMOTE")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                Text(entry.isPaired ? "\(entry.activeBots)" : "—")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(entry.isPaired ? "aktif / \(entry.totalBots) bot" : "Uygulamadan eşleştir")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label(entry.isPaired ? (entry.pcOnline ? "PC bağlı" : "PC çevrimdışı") : "Bağlantı yok",
                      systemImage: entry.pcOnline ? "checkmark.circle.fill" : "circle.slash")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(entry.pcOnline ? .green : .secondary)
            }
            .padding(3)
        )
    }

    private var mediumHomeScreen: some View {
        widgetBackground(
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("BOT REMOTE", systemImage: "server.rack")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(entry.isPaired ? "\(entry.activeBots)" : "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(entry.isPaired ? "aktif / \(entry.totalBots) bot" : "Uygulamadan eşleştir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 7) {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(entry.pcOnline ? .green : .secondary)
                    Text(entry.isPaired ? (entry.pcOnline ? "PC çevrimiçi" : "PC çevrimdışı") : "Bağlı değil")
                        .font(.caption.weight(.medium))
                    Text("Limit: \(entry.maxActive)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(3)
        )
    }

    @ViewBuilder
    private func widgetBackground<Content: View>(_ content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(red: 0.07, green: 0.09, blue: 0.13)
            }
        } else {
            content.background(Color(red: 0.07, green: 0.09, blue: 0.13))
        }
    }
}

@main
struct BotRemoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        BotRemoteLiveActivity()
        BotRemoteStatusWidget()
    }
}
