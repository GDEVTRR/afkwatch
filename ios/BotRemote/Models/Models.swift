import Foundation

enum Event {
    static let presence = "presence"
    static let snapshot = "bots:snapshot"
    static let status = "bot:status"
    static let log = "bot:log"
    static let chat = "bot:chat"
    static let screenshot = "bot:screenshot"
    static let command = "command"
    static let revoked = "revoked"
}

enum BotStatus: String {
    case stopped, connecting, online, reconnecting
}

struct BotInfo: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var auth: String
    var version: String
    var autoReconnect: Bool
    var reconnectDelaySec: Int
    var status: String
    var connectedAt: Double?
    var serverVersion: String
    var lastError: String

    var statusKind: BotStatus { BotStatus(rawValue: status) ?? .stopped }
    var isActive: Bool { statusKind != .stopped }
    var address: String { "\(host):\(port)" }
    var connectedDate: Date? { connectedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct Snapshot: Codable {
    var bots: [BotInfo]
    var activeCount: Int
    /// Zero means unlimited (the PC's resources are the practical limit).
    var maxActive: Int
}

struct StatusUpdate: Codable {
    var bot: BotInfo
    var activeCount: Int?
}

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var t: Double
    var k: String
    var m: String

    enum CodingKeys: String, CodingKey { case t, k, m }
    var date: Date { Date(timeIntervalSince1970: t / 1000) }
}

struct LogEvent: Codable {
    var botId: String
    var entry: LogEntry
}

struct ScreenSlot: Codable, Identifiable, Equatable {
    var slot: Int
    var name: String
    var itemName: String
    var count: Int
    var id: Int { slot }
}

struct ScreenWindow: Codable, Equatable {
    var title: String
    var type: String
    var slots: [ScreenSlot]
}

struct ScreenScoreRow: Codable, Identifiable, Equatable {
    var name: String
    var value: Int
    var id: String { "\(name)-\(value)" }
}

struct ScreenScoreboard: Codable, Equatable {
    var title: String
    var rows: [ScreenScoreRow]
}

struct BotScreenSnapshot: Codable, Identifiable, Equatable {
    var capturedAt: Double
    var botName: String
    var username: String
    var serverAddress: String
    var status: String
    var window: ScreenWindow?
    var inventory: [ScreenSlot]
    var scoreboard: ScreenScoreboard?

    var id: String { "\(botName)-\(Int(capturedAt))" }
    var date: Date { Date(timeIntervalSince1970: capturedAt / 1000) }
}

struct BotScreenshotEvent: Codable {
    var botId: String
    var screenshot: BotScreenSnapshot
}

struct LogsResponse: Codable {
    var botId: String
    var logs: [LogEntry]
}

struct PairingPayload: Codable {
    var v: Int
    var u: String
    var c: String
}

struct PairResponse: Codable {
    var phoneId: String
    var token: String
}

struct APIErrorBody: Codable {
    struct Inner: Codable { var code: String; var message: String }
    var error: Inner
}

enum ConnectionState: Equatable {
    case notPaired, connecting, connected, disconnected
    var label: String {
        switch self {
        case .notPaired: return "Eşleştirilmedi"
        case .connecting: return "Bağlanıyor…"
        case .connected: return "Bağlı"
        case .disconnected: return "Bağlantı kesildi"
        }
    }
}

struct RemoteError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
