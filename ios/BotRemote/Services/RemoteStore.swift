import Foundation
import SwiftUI
import UIKit
import ActivityKit
import SocketIO

/// Single source of truth: owns the ONE Socket.IO connection and all state shown in the UI.
@MainActor
final class RemoteStore: ObservableObject {
    @Published var bots: [BotInfo] = []
    /// Zero means that the desktop has no application-defined active bot limit.
    @Published var maxActive = 0
    @Published var desktopOnline = false
    @Published var connection: ConnectionState = .notPaired
    @Published var logs: [String: [LogEntry]] = [:]
    @Published var serverURL: String
    @Published var errorMessage: String?
    @Published var busy = false

    var activeCount: Int { bots.filter { $0.isActive }.count }
    var isPaired: Bool { KeychainStore.get(Self.tokenKey) != nil }

    private static let tokenKey = "phoneToken"
    private static let urlKey = "serverURL"
    private static let maxLogLines = 500

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var wantConnected = false
    private var retryTask: Task<Void, Never>?
    private var liveActivity: Activity<BotRemoteActivityAttributes>?

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        connection = isPaired ? .disconnected : .notPaired
        Task { await updateLiveActivity() }
    }

    // MARK: - Connection lifecycle

    func connect() {
        guard let token = KeychainStore.get(Self.tokenKey) else {
            connection = .notPaired
            return
        }
        guard socket == nil else { reconnectIfNeeded(); return }
        do {
            let origin = try APIClient.normalizedOrigin(serverURL)
            let newManager = SocketManager(socketURL: origin, config: [
                .log(false), .compress, .forceWebsockets(true),
                .reconnects(true), .reconnectWait(2), .reconnectWaitMax(60)
            ])
            let newSocket = newManager.defaultSocket
            manager = newManager
            socket = newSocket
            wantConnected = true
            registerHandlers(newSocket)
            connection = .connecting
            newSocket.connect(withPayload: ["role": "phone", "token": token])
        } catch {
            report(error)
        }
    }

    func disconnectSocket() {
        wantConnected = false
        retryTask?.cancel()
        retryTask = nil
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
        desktopOnline = false
        connection = isPaired ? .disconnected : .notPaired
    }

    func reconnectIfNeeded() {
        guard wantConnected, let currentSocket = socket,
              currentSocket.status != .connected, currentSocket.status != .connecting else { return }
        if let token = KeychainStore.get(Self.tokenKey) {
            connection = .connecting
            currentSocket.connect(withPayload: ["role": "phone", "token": token])
        }
    }

    private func scheduleRetry() {
        guard wantConnected, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.reconnectIfNeeded()
        }
    }

    // MARK: - Pairing

    func pair(with payload: PairingPayload) async {
        busy = true
        defer { busy = false }
        do {
            guard payload.v == 1 else {
                throw RemoteError(code: "VERSION", message: "Unsupported QR code version")
            }
            let origin = try APIClient.normalizedOrigin(payload.u)
            let response = try await APIClient.completePairing(
                origin: origin,
                code: payload.c,
                deviceName: Self.deviceName()
            )
            disconnectSocket()
            KeychainStore.set(response.token, for: Self.tokenKey)
            KeychainStore.set(response.phoneId, for: "phoneId")
            serverURL = origin.absoluteString
            UserDefaults.standard.set(serverURL, forKey: Self.urlKey)
            connect()
            await updateLiveActivity()
        } catch {
            report(error)
        }
    }

    func pair(withText text: String) async {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            report(RemoteError(code: "BAD_QR", message: "This is not a Bot Remote pairing code"))
            return
        }
        await pair(with: payload)
    }

    func unpair() async {
        busy = true
        defer { busy = false }
        if let token = KeychainStore.get(Self.tokenKey),
           let origin = try? APIClient.normalizedOrigin(serverURL) {
            do { try await APIClient.unpair(origin: origin, token: token) }
            catch { /* Still clear local credentials if the server is unreachable. */ }
        }
        wipeCredentials()
    }

    private func wipeCredentials() {
        disconnectSocket()
        KeychainStore.remove(Self.tokenKey)
        KeychainStore.remove("phoneId")
        bots = []
        logs = [:]
        maxActive = 0
        connection = .notPaired
        Task { await updateLiveActivity() }
    }

    func saveServerURL(_ raw: String) {
        serverURL = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(serverURL, forKey: Self.urlKey)
    }

    private static func deviceName() -> String {
        String(UIDevice.current.name.prefix(40))
    }

    // MARK: - Socket handlers

    private func registerHandlers(_ newSocket: SocketIOClient) {
        newSocket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.connection = .connected
                self?.retryTask?.cancel()
                self?.retryTask = nil
            }
        }
        newSocket.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.wantConnected else { return }
                self.connection = .connecting
                self.desktopOnline = false
                Task { await self.updateLiveActivity() }
                self.scheduleRetry()
            }
        }
        newSocket.on(clientEvent: .error) { [weak self] data, _ in
            let message = String(describing: data)
            Task { @MainActor in self?.handleSocketError(message) }
        }

        listen(Event.presence) { [weak self] object in
            guard let payload = object as? [String: Any] else { return }
            if let online = payload["desktopOnline"] as? Bool {
                self?.desktopOnline = online
                Task { await self?.updateLiveActivity() }
            }
        }
        listen(Event.snapshot) { [weak self] object in
            guard let snapshot: Snapshot = Self.decode(object) else { return }
            self?.bots = snapshot.bots
            self?.maxActive = snapshot.maxActive
            Task { await self?.updateLiveActivity() }
        }
        listen(Event.status) { [weak self] object in
            guard let update: StatusUpdate = Self.decode(object), let self else { return }
            if let index = self.bots.firstIndex(where: { $0.id == update.bot.id }) {
                self.bots[index] = update.bot
            } else {
                self.bots.append(update.bot)
            }
            Task { await self.updateLiveActivity() }
        }

        let onLog: @MainActor (Any?) -> Void = { [weak self] object in
            guard let event: LogEvent = Self.decode(object) else { return }
            self?.append(event.entry, to: event.botId)
        }
        listen(Event.log, onLog)
        listen(Event.chat, onLog)

        listen(Event.screenshot) { object in
            guard let event: BotScreenshotEvent = Self.decode(object) else { return }
            ScreenshotArchive.shared.store(event.screenshot, botId: event.botId)
        }

        listen(Event.revoked) { [weak self] _ in
            self?.errorMessage = "This device was removed from your PC."
            self?.wipeCredentials()
        }
    }

    private func handleSocketError(_ message: String) {
        if message.lowercased().contains("unauthorized") {
            errorMessage = "This device is no longer authorized. Please pair again."
            wipeCredentials()
        } else {
            connection = .connecting
            scheduleRetry()
        }
    }

    private func listen(_ event: String, _ handler: @escaping @MainActor (Any?) -> Void) {
        socket?.on(event) { data, _ in
            let first = data.first
            Task { @MainActor in handler(first) }
        }
    }

    private static func decode<T: Decodable>(_ object: Any?) -> T? {
        guard let object,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func append(_ entry: LogEntry, to botId: String) {
        var list = logs[botId] ?? []
        list.append(entry)
        if list.count > Self.maxLogLines { list.removeFirst(list.count - Self.maxLogLines) }
        logs[botId] = list
    }

    // MARK: - Commands

    private func send(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let currentSocket = socket, currentSocket.status == .connected else {
            throw RemoteError(code: "OFFLINE", message: "Not connected to the cloud")
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            currentSocket.emitWithAck(Event.command, payload).timingOut(after: 20) { data in
                guard let response = data.first as? [String: Any] else {
                    continuation.resume(throwing: RemoteError(code: "TIMEOUT", message: "No answer from your PC"))
                    return
                }
                if (response["ok"] as? Bool) == true {
                    continuation.resume(returning: (response["data"] as? [String: Any]) ?? [:])
                } else {
                    let error = response["error"] as? [String: Any]
                    continuation.resume(throwing: RemoteError(
                        code: error?["code"] as? String ?? "ERROR",
                        message: error?["message"] as? String ?? "Command failed"
                    ))
                }
            }
        }
    }

    private func run(_ payload: [String: Any]) async {
        do { _ = try await send(payload) }
        catch { report(error) }
    }

    func startBot(_ id: String) async { await run(["action": "bot.start", "botId": id]) }
    func stopBot(_ id: String) async { await run(["action": "bot.stop", "botId": id]) }
    func startAll() async { await run(["action": "bots.startAll"]) }
    func stopAll() async { await run(["action": "bots.stopAll"]) }

    func sendChat(_ botId: String, text: String) async -> Bool {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 256 else {
            report(RemoteError(code: "BAD_REQUEST", message: "Message must be 1–256 characters"))
            return false
        }
        do {
            _ = try await send(["action": "bot.chat", "botId": botId, "message": message])
            return true
        } catch {
            report(error)
            return false
        }
    }

    func loadLogs(_ botId: String) async {
        do {
            let response = try await send(["action": "bot.logs", "botId": botId, "limit": 200])
            if let parsed: LogsResponse = Self.decode(response) { logs[botId] = parsed.logs }
        } catch { /* Live log streaming remains available. */ }
    }

    func refresh() async {
        do {
            let response = try await send(["action": "snapshot"])
            if let snapshot: Snapshot = Self.decode(response) {
                bots = snapshot.bots
                maxActive = snapshot.maxActive
                await updateLiveActivity()
            }
        } catch { report(error) }
    }

    func clearLogs(_ botId: String) { logs[botId] = [] }

    // MARK: - Live Activity

    func updateLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard isPaired else {
            if let activity = liveActivity {
                await activity.end(nil, dismissalPolicy: .immediate)
                liveActivity = nil
            }
            return
        }
        let state = BotRemoteActivityAttributes.ContentState(
            activeBots: activeCount,
            totalBots: bots.count,
            pcOnline: desktopOnline,
            updatedAt: Date()
        )
        if let activity = liveActivity {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(900)))
        } else if Activity<BotRemoteActivityAttributes>.activities.isEmpty {
            do {
                liveActivity = try Activity.request(
                    attributes: BotRemoteActivityAttributes(deviceName: UIDevice.current.name),
                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(900)),
                    pushType: nil
                )
            } catch {
                // Live Activities are optional.
            }
        } else {
            liveActivity = Activity<BotRemoteActivityAttributes>.activities.first
            if let activity = liveActivity {
                await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(900)))
            }
        }
    }

    func report(_ error: Error) {
        errorMessage = (error as? RemoteError)?.message ?? error.localizedDescription
    }
}
