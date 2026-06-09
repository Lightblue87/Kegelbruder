import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Brand blue
    static let kbPrimary      = Color(hex: "#4285f4")
    static let kbPrimaryStrong = Color(hex: "#3367d6")
    static let kbPrimaryTint  = Color(hex: "#e0eaff")
    static let kbPrimaryDeep  = Color(hex: "#1b3a8f")

    // Brass / winner gold
    static let kbBrass400 = Color(hex: "#d8a93e")
    static let kbBrass500 = Color(hex: "#c7922a")
    static let kbBrass600 = Color(hex: "#a6781f")

    // Scoring categories
    static let kbPumpe  = Color(hex: "#e5484d")  // red  – Pumpe / Gutter
    static let kbNeuner = Color(hex: "#4285f4")  // blue – 9er
    static let kbKranz  = Color(hex: "#2e9e5b")  // green – Kranz
    static let kbGast   = Color(hex: "#f5a524")  // orange – Gast

    // Status
    static let kbSuccess    = Color(hex: "#2e9e5b")
    static let kbSuccessBg  = Color(hex: "#d8f1e1")
    static let kbDanger     = Color(hex: "#e5484d")
    static let kbDangerBg   = Color(hex: "#fbdcdd")
    static let kbWarning    = Color(hex: "#f5a524")
    static let kbWarningBg  = Color(hex: "#fde9cc")

    // Text
    static let kbTextSecondary = Color(hex: "#6b7888")
    static let kbTextTertiary  = Color(hex: "#97a3b6")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Glass Button Style

struct KBGlassButton: ButtonStyle {
    var prominent: Bool = false
    var tint: Color = .kbPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, prominent ? 18 : 14)
            .padding(.vertical, prominent ? 10 : 8)
            .foregroundColor(prominent ? .white : tint)
            .background(
                Capsule()
                    .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        Capsule()
                            .stroke(prominent ? Color.clear : Color.white.opacity(0.55), lineWidth: 1)
                    )
            )
            .shadow(
                color: prominent ? tint.opacity(0.30) : Color.black.opacity(0.06),
                radius: prominent ? 8 : 2,
                y: prominent ? 4 : 1
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pill / Badge

struct KBPill: View {
    enum Tone { case primary, success, danger, guest, gold, neutral }

    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    private var fg: Color {
        switch tone {
        case .primary: return .kbPrimaryStrong
        case .success: return Color(hex: "#247a47")
        case .danger:  return Color(hex: "#c13438")
        case .guest:   return Color(hex: "#cf871a")
        case .gold:    return Color(hex: "#7a5a12")
        case .neutral: return .kbTextSecondary
        }
    }

    private var bg: Color {
        switch tone {
        case .primary: return .kbPrimaryTint
        case .success: return .kbSuccessBg
        case .danger:  return .kbDangerBg
        case .guest:   return .kbWarningBg
        case .gold:    return Color(hex: "#f1dca5")
        case .neutral: return Color(UIColor.secondarySystemBackground)
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .cornerRadius(6)
    }
}

// MARK: - Rank Color

extension Color {
    static func kbRank(_ rank: Int) -> Color {
        rank == 1 ? .kbBrass500 : .primary
    }
}

// MARK: - Kassenstand Display

struct KBKassenstandView: View {
    let betrag: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("Kassenstand")
                .font(.system(size: 13))
                .foregroundColor(.kbTextSecondary)
            Text(String(format: "%.2f €", betrag))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(betrag >= 0 ? .primary : .kbDanger)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
