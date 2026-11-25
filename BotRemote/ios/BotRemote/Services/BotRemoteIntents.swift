import AppIntents

struct BotRemoteStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Bot Remote durumunu öğren"
    static var description = IntentDescription("Botların ve bilgisayar bağlantısının durumunu söyler.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run {
            RemoteStore.shared?.siriStatusSummary() ?? "Bot Remote henüz hazır değil."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct BotRemoteStartAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Bot Remote botlarını başlat"
    static var description = IntentDescription("Bilgisayardaki tüm botları başlatma komutu gönderir.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run {
            "Bot Remote hazır değil."
        }
        guard let store = await MainActor.run(body: { RemoteStore.shared }) else {
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        let result = await store.siriStartAll()
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct BotRemoteStopAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Bot Remote botlarını durdur"
    static var description = IntentDescription("Bilgisayardaki tüm botları durdurma komutu gönderir.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = await MainActor.run(body: { RemoteStore.shared }) else {
            return .result(dialog: "Bot Remote henüz hazır değil.")
        }
        let result = await store.siriStopAll()
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct BotRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BotRemoteStatusIntent(),
            phrases: ["Bot Remote botlarımı kontrol et", "Bot Remote durumunu söyle"],
            shortTitle: "Bot durumunu öğren",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: BotRemoteStartAllIntent(),
            phrases: ["Bot Remote tüm botları başlat"],
            shortTitle: "Tüm botları başlat",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: BotRemoteStopAllIntent(),
            phrases: ["Bot Remote tüm botları durdur"],
            shortTitle: "Tüm botları durdur",
            systemImageName: "stop.fill"
        )
    }
}
