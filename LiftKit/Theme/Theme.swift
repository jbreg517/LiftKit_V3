import SwiftUI

// MARK: - Colours
enum LKColor {
    static let background       = Color(hex: "#000000")
    static let surface          = Color(hex: "#1C1C1E")
    static let surfaceElevated  = Color(hex: "#2C2C2E")
    static let textPrimary      = Color(hex: "#F5F5F5")
    static let textSecondary    = Color(hex: "#9CA3AF")
    static let textMuted        = Color(hex: "#6B7280")
    static let accent           = Color(hex: "#D4A843")
    static let accentMuted      = Color(hex: "#8B7335")
    static let work             = Color(hex: "#22C55E")
    static let rest             = Color(hex: "#3B82F6")
    static let warning          = Color(hex: "#F59E0B")
    static let danger           = Color(hex: "#EF4444")
    static let success          = Color(hex: "#22C55E")
}

// MARK: - Typography
enum LKFont {
    static func timer(_ size: CGFloat = 96) -> Font {
        .system(size: size, weight: .black, design: .monospaced)
    }
    static let title: Font       = .system(size: 28, weight: .bold)
    static let heading: Font     = .system(size: 22, weight: .semibold)
    static let body: Font        = .system(size: 17, weight: .regular)
    static let bodyBold: Font    = .system(size: 17, weight: .semibold)
    static let numeric: Font     = .system(size: 22, weight: .bold, design: .monospaced)
    static let caption: Font     = .system(size: 13, weight: .medium)
    static let phase: Font       = .system(size: 16, weight: .black)
}

// MARK: - Spacing
enum LKSpacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radii
enum LKRadius {
    static let small: CGFloat  = 8
    static let medium: CGFloat = 12
    static let large: CGFloat  = 16
    static let pill: CGFloat   = 999
}

// MARK: - Button Styles

struct LKPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LKFont.bodyBold)
            .foregroundColor(LKColor.background)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LKSpacing.md)
            .padding(.vertical, LKSpacing.md)
            .background(LKColor.accent)
            .cornerRadius(LKRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct LKSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LKFont.bodyBold)
            .foregroundColor(LKColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LKSpacing.md)
            .padding(.vertical, LKSpacing.md)
            .background(LKColor.surfaceElevated)
            .cornerRadius(LKRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Colour hex initialiser
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
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
