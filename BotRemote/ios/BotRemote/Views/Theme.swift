import SwiftUI

enum Theme {
    static let background = Color(hex: 0xF5F7FA)
    static let card = Color.white
    static let cardHigh = Color(hex: 0xFFFFFF)
    static let line = Color(hex: 0xE5E9F0)
    static let cyan = Color(hex: 0x2563EB)
    static let muted = Color(hex: 0x687386)
    static let ok = Color(hex: 0x16A34A)
    static let warn = Color(hex: 0xD97706)
    static let err = Color(hex: 0xDC2626)
    static let ink = Color(hex: 0x172033)

    static func color(for status: BotStatus) -> Color {
        switch status {
        case .online: return ok
        case .connecting, .reconnecting: return warn
        case .stopped: return Color(hex: 0x8490A3)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    }
            }
            .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 5)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }

    @ViewBuilder
    func botRemoteGlass() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        #endif
    }
}

struct StatusPill: View {
    let status: BotStatus
    var body: some View {
        Text(status == .online ? "Çevrimiçi" :
             status == .connecting ? "Bağlanıyor" :
             status == .reconnecting ? "Yeniden bağlanıyor" : "Durduruldu")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundColor(Theme.color(for: status))
            .background(Theme.color(for: status).opacity(0.10))
            .clipShape(Capsule())
    }
}

func formatUptime(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    return String(format: "%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60)
}
