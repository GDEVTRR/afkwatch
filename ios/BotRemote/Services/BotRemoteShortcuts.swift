
import AppIntents

struct StartAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Başlat"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct StopAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Durdur"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct RefreshBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Botları Yenile"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct BotRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAllBotsIntent(),
            phrases: ["Bot Remote ile tüm botları başlat"],
            shortTitle: "Botları Başlat",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: StopAllBotsIntent(),
            phrases: ["Bot Remote ile tüm botları durdur"],
            shortTitle: "Botları Durdur",
            systemImageName: "stop.fill"
        )

        AppShortcut(
            intent: RefreshBotsIntent(),
            phrases: ["Bot Remote ile botları yenile"],
            shortTitle: "Botları Yenile",
            systemImageName: "arrow.clockwise"
        )
    }
}
