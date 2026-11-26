import AppIntents
import Foundation

// OpenURLIntent requires iOS 18. Keep the app's deployment target at iOS 16.2;
// these Siri shortcuts are enabled on iOS 18 and newer.
@available(iOS 18.0, *)
struct StartAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Başlat"
    static var description = IntentDescription("Bot Remote üzerindeki tüm botları başlatır.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://start-all")!))
    }
}

@available(iOS 18.0, *)
struct StopAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Durdur"
    static var description = IntentDescription("Bot Remote üzerindeki tüm botları durdurur.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://stop-all")!))
    }
}

@available(iOS 18.0, *)
struct RefreshBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Botları Yenile"
    static var description = IntentDescription("Bot durumlarını yeniler.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "botremote://refresh")!))
    }
}

@available(iOS 18.0, *)
struct BotRemoteShortcuts: AppShortcutsProvider {
    // AppShortcutsBuilder builds the array from individual AppShortcut expressions.
    // Do not wrap these expressions in an array literal.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAllBotsIntent(),
            phrases: [
                "Bot Remote ile tüm botları başlat \(.applicationName)",
                "Bot Remote botları başlat \(.applicationName)"
            ],
            shortTitle: "Botları Başlat",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: StopAllBotsIntent(),
            phrases: [
                "Bot Remote ile tüm botları durdur \(.applicationName)",
                "Bot Remote botları durdur \(.applicationName)"
            ],
            shortTitle: "Botları Durdur",
            systemImageName: "stop.fill"
        )

        AppShortcut(
            intent: RefreshBotsIntent(),
            phrases: [
                "Bot Remote botları yenile \(.applicationName)"
            ],
            shortTitle: "Botları Yenile",
            systemImageName: "arrow.clockwise"
        )
    }
}
