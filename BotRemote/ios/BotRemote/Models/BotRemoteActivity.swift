import ActivityKit
import Foundation

struct BotRemoteActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeBots: Int
        var totalBots: Int
        var pcOnline: Bool
        var updatedAt: Date
    }
    var deviceName: String
}
