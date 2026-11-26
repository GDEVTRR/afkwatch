import AppIntents

struct StartAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Başlat"
    static var description = IntentDescription("Bot Remote üzerindeki tüm botları başlatır.")
    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://start-all")!))
    }
}

struct StopAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Durdur"
    static var description = IntentDescription("Bot Remote üzerindeki tüm botları durdurur.")
    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://stop-all")!))
    }
}

struct RefreshBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Botları Yenile"
    static var description = IntentDescription("Bot durumlarını yeniler.")
    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://refresh")!))
    }
}

struct BotRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(intent: StartAllBotsIntent(), phrases: ["Bot Remote ile tüm botları başlat", "Bot Remote botları başlat"], shortTitle: "Botları Başlat", systemImageName: "play.fill"),
            AppShortcut(intent: StopAllBotsIntent(), phrases: ["Bot Remote ile tüm botları durdur", "Bot Remote botları durdur"], shortTitle: "Botları Durdur", systemImageName: "stop.fill"),
            AppShortcut(intent: RefreshBotsIntent(), phrases: ["Bot Remote botları yenile"], shortTitle: "Botları Yenile", systemImageName: "arrow.clockwise")
        ]
    }
}
