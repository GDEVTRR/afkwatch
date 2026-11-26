import SwiftUI

enum Theme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardHigh = Color(uiColor: .tertiarySystemGroupedBackground)
    static let line = Color(uiColor: .separator).opacity(0.35)
    static let accent = Color(hex: 0x1677F9)
    static let cyan = Color(hex: 0x1677F9)
    static let muted = Color(uiColor: .secondaryLabel)
    static let ok = Color(hex: 0x159B62)
    static let warn = Color(hex: 0xD28A13)
    static let err = Color(hex: 0xD94A4A)

    static func color(for status: BotStatus) -> Color {
        switch status {
        case .online: return ok
        case .connecting, .reconnecting: return warn
        case .stopped: return muted
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        Group {
            if #available(iOS 26.0, *) {
                content
                    .padding(16)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(.white.opacity(0.26), lineWidth: 0.8))
            } else {
                content
                    .padding(16)
                    .background(.regularMaterial, in: shape)
                    .overlay(shape.stroke(Theme.line, lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.045), radius: 14, y: 5)
            }
        }
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct StatusPill: View {
    let status: BotStatus

    private var title: String {
        switch status {
        case .online: return "Aktif"
        case .connecting: return "Bağlanıyor"
        case .reconnecting: return "Yeniden bağlanıyor"
        case .stopped: return "Durduruldu"
        }
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.color(for: status))
            .background(Theme.color(for: status).opacity(0.12), in: Capsule())
            .modifier(StatusPillGlass())
    }
}

private struct StatusPillGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
        }
    }
}

func formatUptime(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    return String(format: "%dh %02dm %02ds", s / 3600, (s % 3600) / 60, s % 60)
}
