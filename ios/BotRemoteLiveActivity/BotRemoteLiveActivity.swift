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

struct BotRemoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotRemoteActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "server.rack").font(.title2).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bot Remote").font(.headline)
                    Text(context.state.pcOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(context.state.activeBots)/\(context.state.totalBots)").font(.title3.bold()).monospacedDigit()
                    Text("Etkin bot").font(.caption2).foregroundStyle(.secondary)
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
                    Text("\(context.state.activeBots)/\(context.state.totalBots)").font(.title3.bold()).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Circle().fill(context.state.pcOnline ? .green : .red).frame(width: 8, height: 8)
                        Text(context.state.pcOnline ? "Bilgisayar çevrimiçi" : "Bilgisayar çevrimdışı")
                        Spacer()
                        Text("Etkin bot").foregroundStyle(.secondary)
                    }.font(.caption)
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

@main
struct BotRemoteWidgetBundle: WidgetBundle {
    var body: some Widget { BotRemoteLiveActivity() }
}
