import Foundation
import WidgetKit

/// Writes the app's latest bot state into the App Group container for WidgetKit.
@MainActor
enum WidgetDataStore {
    static let appGroup = "group.com.botremote.shared"
    private static let widgetKind = "BotRemoteStatusWidget"

    static func update(from store: RemoteStore) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let paired = store.isPaired
        defaults.set(paired ? store.activeCount : 0, forKey: "activeBots")
        defaults.set(paired ? store.bots.count : 0, forKey: "totalBots")
        defaults.set(store.maxActive, forKey: "maxActive")
        defaults.set(paired && store.desktopOnline, forKey: "desktopOnline")
        defaults.set(paired, forKey: "isPaired")
        defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
