
import AppIntents
import Foundation

struct StartAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Başlat"
    static var description = IntentDescription("Bağlı tüm botları başlatır.")

    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "botremote://start-all") else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct StopAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Durdur"
    static var description = IntentDescription("Bağlı tüm botları durdurur.")

    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "botremote://stop-all") else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct RefreshBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Botları Yenile"
    static var description = IntentDescription("Bot durumlarını yeniler.")

    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "botremote://refresh") else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
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
