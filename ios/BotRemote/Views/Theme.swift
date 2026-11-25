
import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0B0F14)
    static let card = Color(hex: 0x111821)
    static let cardHigh = Color(hex: 0x16202B)
    static let line = Color(hex: 0x223041)
    static let cyan = Color(hex: 0x22D3EE)
    static let muted = Color(hex: 0x8AA0B4)
    static let ok = Color(hex: 0x34D399)
    static let warn = Color(hex: 0xFBBF24)
    static let err = Color(hex: 0xF87171)

    static func color(for status: BotStatus) -> Color {
        switch status {
        case .online: return ok
        case .connecting, .reconnecting: return warn
        case .stopped: return Color(hex: 0x56677A)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .fill(Theme.card.opacity(0.55))
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .stroke(
                        Theme.line.opacity(0.85),
                        lineWidth: 1
                    )
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
    }
}

extension View {
    func card() -> some View {
        modifier(CardStyle())
    }
}

struct StatusPill: View {
    let status: BotStatus

    var body: some View {
        Text(
            status == .online ? "Çevrimiçi" :
            status == .connecting ? "Bağlanıyor" :
            status == .reconnecting ? "Yeniden bağlanıyor" :
            "Durduruldu"
        )
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .foregroundColor(Theme.color(for: status))
        .background(Theme.color(for: status).opacity(0.15))
        .clipShape(Capsule())
    }
}

func formatUptime(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    return String(
        format: "%dh %02dm %02ds",
        s / 3600,
        (s % 3600) / 60,
        s % 60
    )
}
