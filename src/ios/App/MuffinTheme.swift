import SwiftUI

extension Color {
    /// Hex string in "#RRGGBB" or "RRGGBB" form. Used only to define MuffinTheme's
    /// tokens below from the app icon's actual brand palette - not a general-purpose
    /// color-parsing utility, so no alpha/3-digit/8-digit support is needed.
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Brand palette lifted directly from muffin-emu-icon.svg (the app icon's source
/// art) - kawaii-bakery: warm cream cards, soft rounded corners, gentle shadows,
/// no translucent dark glass.
enum MuffinTheme {
    // Background gradient (warm orange)
    static let backgroundTop = Color(hex: "#F6A94F")
    static let backgroundBottom = Color(hex: "#E5652E")

    // Muffin-top gradient
    static let muffinTopLight = Color(hex: "#E3A254")
    static let muffinTopDark = Color(hex: "#A8622A")

    // Cream / wrapper
    static let cream = Color(hex: "#FDF6EC")
    static let wrapper = Color(hex: "#F0DFC3")

    // Blueberry navy accent
    static let blueberryNavy = Color(hex: "#453765")

    // Pixel-blue accent (the "EMU" nod)
    static let pixelBlue = Color(hex: "#6C63FF")

    // Blush pink
    static let blushPink = Color(hex: "#F2A6A0")

    // Dark brown (text / line work)
    static let brownDarkest = Color(hex: "#2E1B10")
    static let brownDark = Color(hex: "#5C2E10")
    static let brownMid = Color(hex: "#7A4A22")

    // Sparkle cream
    static let sparkleCream = Color(hex: "#FFF3DD")

    // Shadow
    static let shadow = Color(hex: "#4A2410")

    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let muffinTopGradient = LinearGradient(
        colors: [muffinTopLight, muffinTopDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// A warm cream card with a soft rounded corner and gentle drop shadow - the base
/// surface for library cards, settings sections, and picker rows.
struct MuffinCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var fill: Color = MuffinTheme.cream
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MuffinTheme.wrapper, lineWidth: 1)
            )
            .shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

/// Rounded, friendly primary button (muffin-top gradient fill, cream text).
struct MuffinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(MuffinTheme.sparkleCream)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MuffinTheme.muffinTopGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Rounded pill button for secondary/chrome actions (cream fill, brown text).
struct MuffinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(MuffinTheme.brownDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MuffinTheme.cream.opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MuffinTheme.wrapper, lineWidth: 1)
            )
    }
}
