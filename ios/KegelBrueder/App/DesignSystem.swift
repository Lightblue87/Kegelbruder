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

// MARK: - UITextField wrappers (stable keyboard type on iPad)
//
// Root cause of the "full keyboard on second tap" bug:
// iOS can reset UITextField.keyboardType to .default between SwiftUI render
// passes. Neither makeUIView nor updateUIView fire at the exact moment
// the keyboard appears, so corrections there are too late.
//
// Fix uses two layers:
//   1. LockedKeyboardTextField subclass — overrides the keyboardType setter
//      to a no-op so nothing can ever change the type after init.
//   2. textFieldDidBeginEditing in the coordinator — fires at the instant
//      UIKit makes the field first responder. If, against all odds, the type
//      was changed, we detect and reload before the keyboard animates in.
//
// The Coordinator holds a plain Binding (not @Binding) refreshed in
// updateUIView — required when the caller creates an inline Binding closure
// that captures a value-type (struct), which becomes stale after each
// parent re-render.

final class LockedKeyboardTextField: UITextField {
    private let lockedType: UIKeyboardType
    init(keyboardType: UIKeyboardType) {
        lockedType = keyboardType
        super.init(frame: .zero)
        super.keyboardType = keyboardType
    }
    required init?(coder: NSCoder) { fatalError() }
    override var keyboardType: UIKeyboardType {
        // Read-through: real internal state is visible so the delegate can
        // detect and fix any drift before the keyboard appears.
        get { super.keyboardType }
        // Redirect every write back to lockedType so nothing — SwiftUI, UIKit
        // internals, or explicit sets — can change the stored type.
        set { super.keyboardType = lockedType }
    }
}

// Shared coordinator used by both String-binding wrappers below.
final class KBInputCoordinator: NSObject, UITextFieldDelegate {
    var binding: Binding<String>
    private let target: UIKeyboardType
    private let allowed: CharacterSet

    init(text: Binding<String>, target: UIKeyboardType) {
        self.binding = text
        self.target  = target
        self.allowed = target == .decimalPad
            ? CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ",."))
            : .decimalDigits
    }

    // Fires before the keyboard animation starts — correct moment to ensure
    // the type is set so iOS picks the right layout from the very first frame.
    func textFieldShouldBeginEditing(_ f: UITextField) -> Bool {
        f.keyboardType = target
        return true
    }

    func textFieldDidBeginEditing(_ f: UITextField) {
        // Belt-and-suspenders: re-assert after focus is confirmed.
        // No reloadInputViews() — calling it during the keyboard animation
        // dismisses the keyboard immediately on iPad.
        f.keyboardType = target
    }

    func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString s: String) -> Bool {
        s.isEmpty || s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    func textFieldDidEndEditing(_ f: UITextField) { binding.wrappedValue = f.text ?? "" }
    func textFieldShouldReturn(_ f: UITextField) -> Bool { f.resignFirstResponder(); return true }
}

/// Number pad, String binding (e.g. Tiebreak point fields).
struct NumberStringInputField: UIViewRepresentable {
    typealias Coordinator = KBInputCoordinator
    var placeholder: String = "0"
    @Binding var text: String

    func makeUIView(context: Context) -> LockedKeyboardTextField {
        let f = LockedKeyboardTextField(keyboardType: .numberPad)
        f.textAlignment = .center
        f.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        f.placeholder = placeholder
        f.autocorrectionType = .no; f.spellCheckingType = .no
        f.delegate = context.coordinator
        return f
    }

    func updateUIView(_ f: LockedKeyboardTextField, context: Context) {
        context.coordinator.binding = $text
        if !f.isFirstResponder { f.text = text }
    }

    func makeCoordinator() -> KBInputCoordinator { KBInputCoordinator(text: $text, target: .numberPad) }
}

/// Decimal pad, String binding (e.g. payment amount fields).
struct DecimalInputField: UIViewRepresentable {
    typealias Coordinator = KBInputCoordinator
    var placeholder: String = "0,00"
    @Binding var text: String

    func makeUIView(context: Context) -> LockedKeyboardTextField {
        let f = LockedKeyboardTextField(keyboardType: .decimalPad)
        f.textAlignment = .right
        f.font = .systemFont(ofSize: 17)
        f.placeholder = placeholder
        f.autocorrectionType = .no; f.spellCheckingType = .no
        f.delegate = context.coordinator
        return f
    }

    func updateUIView(_ f: LockedKeyboardTextField, context: Context) {
        context.coordinator.binding = $text
        if !f.isFirstResponder { f.text = text }
    }

    func makeCoordinator() -> KBInputCoordinator { KBInputCoordinator(text: $text, target: .decimalPad) }
}
