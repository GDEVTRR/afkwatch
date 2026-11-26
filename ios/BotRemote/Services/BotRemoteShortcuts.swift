
import AppIntents
import Foundation

struct StartAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Başlat"
    static var description = IntentDescription(
        "Bot Remote uygulamasını botları başlatmak için açar."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct StopAllBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tüm Botları Durdur"
    static var description = IntentDescription(
        "Bot Remote uygulamasını botları durdurmak için açar."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct RefreshBotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Botları Yenile"
    static var description = IntentDescription(
        "Bot Remote uygulamasını botları yenilemek için açar."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct BotRemoteShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: StartAllBotsIntent(),
                phrases: [
                    "Bot Remote ile tüm botları başlat"
                ],
                shortTitle: "Botları Başlat",
                systemImageName: "play.fill"
            ),

            AppShortcut(
                intent: StopAllBotsIntent(),
                phrases: [
                    "Bot Remote ile tüm botları durdur"
                ],
                shortTitle: "Botları Durdur",
                systemImageName: "stop.fill"
            ),

            AppShortcut(
                intent: RefreshBotsIntent(),
                phrases: [
                    "Bot Remote ile botları yenile"
                ],
                shortTitle: "Botları Yenile",
                systemImageName: "arrow.clockwise"
            )
        ]
    }
}
