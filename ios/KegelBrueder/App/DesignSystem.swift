import SwiftUI

// MARK: - Adaptive color helpers

private extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: Double(alpha))
    }
}

private func kb(_ light: String, _ dark: String, alpha: CGFloat = 1) -> Color {
    Color(UIColor { tc in
        UIColor(hex: tc.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
    })
}

private func kbA(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat) -> Color {
    Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: dark, alpha: darkAlpha)
            : UIColor(hex: light, alpha: lightAlpha)
    })
}

// MARK: - Color Tokens

extension Color {
    // Brand blue
    static let kbPrimary       = kb("#4285f4", "#4f93ff")
    static let kbPrimaryStrong = kb("#3367d6", "#6ea6ff")
    static let kbPrimaryTint   = kbA(light: "#e0eaff", dark: "#4f93ff", darkAlpha: 0.18)
    static let kbPrimaryDeep   = kb("#1b3a8f", "#6ea6ff")

    // Brass / winner gold
    static let kbBrass400 = kb("#d8a93e", "#e8b84f")
    static let kbBrass500 = kb("#c7922a", "#d8a93e")
    static let kbBrass600 = kb("#a6781f", "#c7922a")

    // Scoring categories
    static let kbPumpe  = kb("#e5484d", "#ff6168")
    static let kbNeuner = kb("#4285f4", "#4f93ff")
    static let kbKranz  = kb("#2e9e5b", "#3ab26a")
    static let kbGast   = kb("#f5a524", "#f7b545")

    // Status
    static let kbSuccess   = kb("#2e9e5b", "#3ab26a")
    static let kbSuccessBg = kbA(light: "#d8f1e1", dark: "#3ab26a", darkAlpha: 0.20)
    static let kbDanger    = kb("#e5484d", "#ff6168")
    static let kbDangerBg  = kbA(light: "#fbdcdd", dark: "#ff6168", darkAlpha: 0.20)
    static let kbWarning   = kb("#f5a524", "#f7b545")
    static let kbWarningBg = kbA(light: "#fde9cc", dark: "#f7b545", darkAlpha: 0.20)

    // Text (semantic — secondary/tertiary adapt automatically)
    static let kbTextSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.922, alpha: 0.60)   // rgba(235,235,245,0.60)
            : UIColor(hex: "#6b7888")
    })
    static let kbTextTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.922, alpha: 0.35)   // rgba(235,235,245,0.35)
            : UIColor(hex: "#97a3b6")
    })

    // Legacy hex init (kept for one-off uses)
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
        case .success: return .kbSuccess
        case .danger:  return .kbDanger
        case .guest:   return .kbGast
        case .gold:    return .kbBrass600
        case .neutral: return .kbTextSecondary
        }
    }

    private var bg: Color {
        switch tone {
        case .primary: return .kbPrimaryTint
        case .success: return .kbSuccessBg
        case .danger:  return .kbDangerBg
        case .guest:   return .kbWarningBg
        case .gold:    return kbA(light: "#d8a93e", dark: "#e8b84f", lightAlpha: 0.18, darkAlpha: 0.22)
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

// MARK: - Double formatting

extension Double {
    var kbMoney: String { String(format: "%.2f €", self) }
}

// MARK: - Page background

struct KBPageBackground: View {
    var body: some View {
        Color(UIColor.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

// MARK: - Screen container (scrollable, centered, max-width)

struct KBScreen<Content: View>: View {
    var maxWidth: CGFloat = 800
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Screen title

struct KBScreenTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)
            if let sub = subtitle {
                Text(sub)
                    .font(.subheadline)
                    .foregroundColor(.kbTextSecondary)
            }
        }
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Group box (card with optional header)

struct KBGroupBox<Content: View>: View {
    var header: String? = nil
    @ViewBuilder let content: () -> Content

    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let h = header {
                Text(h.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.kbTextSecondary)
                    .tracking(0.72)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 7)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.bottom, 20)
    }
}

// MARK: - List row

struct KBRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    init(@ViewBuilder _ leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension KBRow where Trailing == EmptyView {
    init(@ViewBuilder _ leading: @escaping () -> Leading) {
        self.leading = leading
        self.trailing = { EmptyView() }
    }
}

// MARK: - Row divider

struct KBRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}


// MARK: - SwiftUI number pad (popover)
//
// The iPad system keyboard is unreliable for number entry: there is no real
// numberPad layout, the floating/undocked keyboard lives in its own window
// that ignores custom inputViews, and keyboardAppearance can't be themed
// reliably. These fields therefore never touch the UIKit text-input system —
// tapping them opens a self-drawn pad in a popover and edits the binding
// directly on every key press.

struct KBNumPadField: View {
    @Binding var text: String
    var placeholder: String = "0"
    var allowsDecimal: Bool = false
    var alignment: Alignment = .center
    var font: Font = .system(size: 20, weight: .bold).monospacedDigit()

    @State private var showPad = false

    var body: some View {
        Button {
            showPad = true
        } label: {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .foregroundColor(text.isEmpty ? Color(UIColor.placeholderText) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keine feste arrowEdge: iOS wählt selbst die Seite mit genug Platz,
        // sonst wird das Pad bei Feldern am Bildschirmrand abgeschnitten.
        .popover(isPresented: $showPad) {
            KBNumPadGrid(text: $text, allowsDecimal: allowsDecimal) {
                showPad = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct KBNumPadGrid: View {
    @Binding var text: String
    var allowsDecimal: Bool
    var onDone: () -> Void

    private var separator: String { Locale.current.decimalSeparator ?? "," }

    var body: some View {
        VStack(spacing: 8) {
            grid
            Button(action: onDone) {
                Text("Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 248)
    }

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach([["1","2","3"], ["4","5","6"], ["7","8","9"]], id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key(digit: $0) }
                }
            }
            HStack(spacing: 8) {
                if allowsDecimal {
                    padButton(separator, action: insertSeparator)
                } else {
                    Color.clear.frame(width: 72, height: 52)
                }
                key(digit: "0")
                padButton("⌫", role: .action) {
                    if !text.isEmpty { text.removeLast() }
                }
            }
        }
    }

    private func key(digit: String) -> some View {
        padButton(digit) { text += digit }
    }

    private enum PadRole { case digit, action }

    private func padButton(_ label: String, role: PadRole = .digit,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: role == .digit ? 24 : 20, weight: .regular))
                .monospacedDigit()
                .foregroundColor(.primary)
                .frame(width: 72, height: 52)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func insertSeparator() {
        guard !text.contains(",") && !text.contains(".") else { return }
        text += text.isEmpty ? "0\(separator)" : separator
    }
}

/// Number pad, String binding (e.g. Tiebreak point fields).
struct NumberStringInputField: View {
    var placeholder: String = "0"
    @Binding var text: String

    var body: some View {
        KBNumPadField(text: $text, placeholder: placeholder, allowsDecimal: false)
    }
}

/// Decimal pad, String binding (e.g. payment amount fields).
struct DecimalInputField: View {
    var placeholder: String = "0,00"
    @Binding var text: String

    var body: some View {
        KBNumPadField(
            text: $text,
            placeholder: placeholder,
            allowsDecimal: true,
            alignment: .trailing,
            font: .system(size: 17)
        )
    }
}
