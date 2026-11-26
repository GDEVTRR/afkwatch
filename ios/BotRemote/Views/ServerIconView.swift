import SwiftUI
import UIKit

@MainActor
private final class ServerIconLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    func load(from url: URL?) async {
        guard let url else { return }
        let key = url.absoluteString as NSString

        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("BotRemote iOS server icon client", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else { return }

            Self.cache.setObject(decoded, forKey: key)
            image = decoded
        } catch is CancellationError {
            // A different bot card appeared; the old request can be discarded.
        } catch {
            // Keep the built-in Minecraft/server placeholder when the API is unavailable.
        }
    }
}

struct ServerIconView: View {
    let bot: BotInfo
    @StateObject private var loader = ServerIconLoader()

    private var iconURL: URL? {
        let address = bot.host.contains(":") ? "[\(bot.host)]:\(bot.port)" : "\(bot.host):\(bot.port)"
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let escaped = address.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://api.mcsrvstat.us/icon/\(escaped)")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .task(id: iconURL?.absoluteString ?? "") {
            await loader.load(from: iconURL)
        }
        .accessibilityLabel("\(bot.name) Minecraft sunucu ikonu")
    }
}
