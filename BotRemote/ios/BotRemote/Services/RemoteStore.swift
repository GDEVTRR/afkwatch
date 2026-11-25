import Foundation
import SwiftUI
import UIKit
import ActivityKit
import SocketIO

/// Single source of truth: owns the ONE Socket.IO connection and all state shown in the UI.
@MainActor
final class RemoteStore: ObservableObject {
    static weak var shared: RemoteStore?
    @Published var bots: [BotInfo] = []
    @Published var maxActive = 5
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

    /// Connect (idempotent: never creates a second socket).
    func connect() {
        guard let token = KeychainStore.get(Self.tokenKey) else { connection = .notPaired; return }
        guard socket == nil else { reconnectIfNeeded(); return }
        do {
            let origin = try APIClient.normalizedOrigin(serverURL)
            let mgr = SocketManager(socketURL: origin, config: [
                .log(false), .compress, .forceWebsockets(true),
                .reconnects(true), .reconnectWait(2), .reconnectWaitMax(60)
            ])
            let s = mgr.defaultSocket
            manager = mgr; socket = s
            wantConnected = true
            registerHandlers(s)
            connection = .connecting
            s.connect(withPayload: ["role": "phone", "token": token])
        } catch {
            report(error)
        }
    }

    func disconnectSocket() {
        wantConnected = false
        retryTask?.cancel(); retryTask = nil
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
        socket = nil; manager = nil
        desktopOnline = false
        connection = isPaired ? .disconnected : .notPaired
    }

    /// Call when the app returns to the foreground.
    func reconnectIfNeeded() {
        guard wantConnected, let s = socket, s.status != .connected, s.status != .connecting else { return }
        if let token = KeychainStore.get(Self.tokenKey) {
            connection = .connecting
            s.connect(withPayload: ["role": "phone", "token": token])
        }
    }

    private func scheduleRetry() {
        // socket.io only auto-reconnects on transport loss; after a server-side disconnect (cloud redeploy)
        // we retry ourselves, using at most one pending task.
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
        busy = true; defer { busy = false }
        do {
            guard payload.v == 1 else { throw RemoteError(code: "VERSION", message: "Unsupported QR code version") }
            let origin = try APIClient.normalizedOrigin(payload.u)
            let res = try await APIClient.completePairing(origin: origin, code: payload.c, deviceName: Self.deviceName())
            disconnectSocket()
            KeychainStore.set(res.token, for: Self.tokenKey)
            KeychainStore.set(res.phoneId, for: "phoneId")
            serverURL = origin.absoluteString
            UserDefaults.standard.set(serverURL, forKey: Self.urlKey)
            connect()
            await updateLiveActivity()
        } catch {
            report(error)
        }
    }

    /// Accepts the JSON text shown on the desktop (manual pairing without a camera).
    func pair(withText text: String) async {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            report(RemoteError(code: "BAD_QR", message: "This is not a Bot Remote pairing code"))
            return
        }
        await pair(with: payload)
    }

    /// Revoke this phone on the server and wipe local credentials.
    func unpair() async {
        busy = true; defer { busy = false }
        if let token = KeychainStore.get(Self.tokenKey), let origin = try? APIClient.normalizedOrigin(serverURL) {
            do { try await APIClient.unpair(origin: origin, token: token) }
            catch { /* server unreachable or token already revoked: still wipe locally */ }
        }
        wipeCredentials()
    }

    private func wipeCredentials() {
        disconnectSocket()
        KeychainStore.remove(Self.tokenKey)
        KeychainStore.remove("phoneId")
        bots = []; logs = [:]
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

    private func registerHandlers(_ s: SocketIOClient) {
        s.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.connection = .connected
                self?.retryTask?.cancel(); self?.retryTask = nil
            }
        }
        s.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.wantConnected else { return }
                self.connection = .connecting
                self.desktopOnline = false
                self.scheduleRetry()
            }
        }
        s.on(clientEvent: .error) { [weak self] data, _ in
            let text = String(describing: data)
            Task { @MainActor in self?.handleSocketError(text) }
        }
        listen(Event.presence) { [weak self] obj in
            guard let d = obj as? [String: Any] else { return }
            if let online = d["desktopOnline"] as? Bool { self?.desktopOnline = online; Task { await self?.updateLiveActivity() } }
        }
        listen(Event.snapshot) { [weak self] obj in
            guard let snap: Snapshot = Self.decode(obj) else { return }
            self?.bots = snap.bots
            self?.maxActive = snap.maxActive
            Task { await self?.updateLiveActivity() }
        }
        listen(Event.status) { [weak self] obj in
            guard let upd: StatusUpdate = Self.decode(obj), let self else { return }
            if let i = self.bots.firstIndex(where: { $0.id == upd.bot.id }) { self.bots[i] = upd.bot } else { self.bots.append(upd.bot) }
            Task { await self.updateLiveActivity() }
        }
        let onLog: @MainActor (Any?) -> Void = { [weak self] obj in
            guard let ev: LogEvent = Self.decode(obj) else { return }
            self?.append(ev.entry, to: ev.botId)
        }
        listen(Event.log, onLog)
        listen(Event.chat, onLog)
        listen(Event.revoked) { [weak self] _ in
            self?.errorMessage = "This device was removed from your PC."
            self?.wipeCredentials()
        }
    }

    private func handleSocketError(_ text: String) {
        if text.lowercased().contains("unauthorized") {
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

    private static func decode<T: Decodable>(_ obj: Any?) -> T? {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func append(_ entry: LogEntry, to botId: String) {
        var list = logs[botId] ?? []
        list.append(entry)
        if list.count > Self.maxLogLines { list.removeFirst(list.count - Self.maxLogLines) }
        logs[botId] = list
    }

    // MARK: - Commands (each is acknowledged by the PC)

    private func send(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let s = socket, s.status == .connected else {
            throw RemoteError(code: "OFFLINE", message: "Not connected to the cloud")
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            s.emitWithAck(Event.command, payload).timingOut(after: 20) { data in
                guard let res = data.first as? [String: Any] else {
                    cont.resume(throwing: RemoteError(code: "TIMEOUT", message: "No answer from your PC"))
                    return
                }
                if (res["ok"] as? Bool) == true {
                    cont.resume(returning: (res["data"] as? [String: Any]) ?? [:])
                } else {
                    let err = res["error"] as? [String: Any]
                    cont.resume(throwing: RemoteError(code: err?["code"] as? String ?? "ERROR",
                                                      message: err?["message"] as? String ?? "Command failed"))
                }
            }
        }
    }

    private func run(_ payload: [String: Any]) async {
        do { _ = try await send(payload) } catch { report(error) }
    }

    func startBot(_ id: String) async { await run(["action": "bot.start", "botId": id]) }
    func stopBot(_ id: String) async { await run(["action": "bot.stop", "botId": id]) }
    func startAll() async { await run(["action": "bots.startAll"]) }
    func stopAll() async { await run(["action": "bots.stopAll"]) }

    func sendChat(_ botId: String, text: String) async -> Bool {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, msg.count <= 256 else {
            report(RemoteError(code: "BAD_REQUEST", message: "Message must be 1–256 characters")); return false
        }
        do { _ = try await send(["action": "bot.chat", "botId": botId, "message": msg]); return true }
        catch { report(error); return false }
    }

    func loadLogs(_ botId: String) async {
        do {
            let res = try await send(["action": "bot.logs", "botId": botId, "limit": 200])
            if let parsed: LogsResponse = Self.decode(res) { logs[botId] = parsed.logs }
        } catch { /* history is optional; live stream continues */ }
    }

    func refresh() async {
        do {
            let res = try await send(["action": "snapshot"])
            if let snap: Snapshot = Self.decode(res) { bots = snap.bots; maxActive = snap.maxActive; await updateLiveActivity() }
        } catch { report(error) }
    }

    /// Clears only what is displayed on this phone.
    func clearLogs(_ botId: String) { logs[botId] = [] }

    // MARK: - Live Activity

    func updateLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard isPaired else {
            if let activity = liveActivity { await activity.end(nil, dismissalPolicy: .immediate); liveActivity = nil }
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
                // Live Activities are optional; the main app remains fully functional.
            }
        } else {
            liveActivity = Activity<BotRemoteActivityAttributes>.activities.first
            if let activity = liveActivity {
                await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(900)))
            }
        }
    }

    func siriStatusSummary() -> String {
        let total = bots.count
        let active = activeCount
        if !isPaired { return "Bot Remote henüz bir bilgisayarla eşleştirilmemiş." }
        if !desktopOnline { return "Bilgisayar çevrimdışı. Son bilinen durumda \\(active) bot aktifti." }
        return "Toplam \\(total) bottan \\(active) tanesi aktif."
    }

    func siriStartAll() async -> String {
        guard isPaired else { return "Önce Bot Remote uygulamasını bilgisayarınla eşleştir." }
        await startAll()
        return "Tüm botları başlatma komutu gönderildi."
    }

    func siriStopAll() async -> String {
        guard isPaired else { return "Önce Bot Remote uygulamasını bilgisayarınla eşleştir." }
        await stopAll()
        return "Tüm botları durdurma komutu gönderildi."
    }

    func report(_ error: Error) {
        errorMessage = (error as? RemoteError)?.message ?? error.localizedDescription
    }
}
