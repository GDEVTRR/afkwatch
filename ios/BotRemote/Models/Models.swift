import Foundation

/// Wire models. Field names and event names MUST match cloud/services/protocol.js.
enum Event {
    static let presence = "presence"
    static let snapshot = "bots:snapshot"
    static let status = "bot:status"
    static let log = "bot:log"
    static let chat = "bot:chat"
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
    var connectedAt: Double?   // epoch milliseconds, nil unless online
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
    var maxActive: Int
}

struct StatusUpdate: Codable {
    var bot: BotInfo
    var activeCount: Int?
}

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var t: Double      // epoch milliseconds
    var k: String      // info | chat | error | system | out
    var m: String

    enum CodingKeys: String, CodingKey { case t, k, m }
    var date: Date { Date(timeIntervalSince1970: t / 1000) }
}

struct LogEvent: Codable {
    var botId: String
    var entry: LogEntry
}

struct LogsResponse: Codable {
    var botId: String
    var logs: [LogEntry]
}

struct PairingPayload: Codable {
    var v: Int
    var u: String   // cloud server origin
    var c: String   // single-use pairing code
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
        case .notPaired: return "Not paired"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }
}

struct RemoteError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
