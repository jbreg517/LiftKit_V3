import SwiftUI

// MARK: - Colors
enum LKColor {
    static let background      = Color(hex: "#000000")
    static let surface         = Color(hex: "#1C1C1E")
    static let surfaceElevated = Color(hex: "#2C2C2E")
    static let accent          = Color(hex: "#D4A843")
    static let work            = Color(hex: "#22C55E")
    static let success         = Color(hex: "#22C55E")
    static let rest            = Color(hex: "#3B82F6")
    static let danger          = Color(hex: "#EF4444")
    static let textPrimary     = Color.white
    static let textSecondary   = Color(UIColor.secondaryLabel)
    static let textMuted       = Color(UIColor.tertiaryLabel)
}

// MARK: - Fonts
enum LKFont {
    static let title    = Font.system(size: 28, weight: .heavy)
    static let heading  = Font.system(size: 20, weight: .bold)
    static let body     = Font.system(size: 16, weight: .regular)
    static let bodyBold = Font.system(size: 16, weight: .semibold)
    static let caption  = Font.system(size: 12, weight: .regular)
    static let numeric  = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let phase    = Font.system(size: 14, weight: .heavy)

    static func timer(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .black, design: .monospaced)
    }
}

// MARK: - Spacing
enum LKSpacing {
    static let xs: CGFloat =  4
    static let sm: CGFloat =  8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Corner Radius
enum LKRadius {
    static let small:  CGFloat =  8
    static let medium: CGFloat = 12
    static let large:  CGFloat = 16
}

// MARK: - Primary Button Style
struct LKPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LKFont.bodyBold)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(LKSpacing.md)
            .background(LKColor.accent)
            .cornerRadius(LKRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style
struct LKSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LKFont.bodyBold)
            .foregroundColor(LKColor.accent)
            .frame(maxWidth: .infinity)
            .padding(LKSpacing.md)
            .background(LKColor.surfaceElevated)
            .cornerRadius(LKRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Card Modifier
struct LKCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(LKSpacing.md)
            .background(LKColor.surface)
            .cornerRadius(LKRadius.large)
    }
}

extension View {
    func lkCard() -> some View {
        modifier(LKCardModifier())
    }
}

// MARK: - Section Label
struct LKSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LKFont.caption)
            .foregroundColor(LKColor.textMuted)
            .tracking(1.5)
    }
}

// MARK: - Hex Color Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
