import SwiftUI

// MARK: - Colors
enum LKColor {
    // Surfaces adapt to light/dark; brand + status colors stay constant.
    static let background      = dynamic(light: "#F2F2F7", dark: "#000000")
    static let surface         = dynamic(light: "#FFFFFF", dark: "#1C1C1E")
    static let surfaceElevated = dynamic(light: "#E6E6EB", dark: "#2C2C2E")
    // Gold accent. In light mode a deeper amber-gold reads clearly as text on
    // light surfaces (the pale gold below is reserved for dark mode).
    static let accent          = dynamic(light: "#A16207", dark: "#D4A843")
    static let work            = Color(hex: "#22C55E")
    static let success         = Color(hex: "#22C55E")
    static let rest            = Color(hex: "#3B82F6")
    static let danger          = Color(hex: "#EF4444")
    static let textPrimary     = Color(uiColor: .label)        // black in light, white in dark
    static let textSecondary   = Color(UIColor.secondaryLabel)
    /// Muted captions/labels. The system tertiaryLabel is too faint on light
    /// backgrounds, so light mode uses a readable medium gray; dark mode keeps
    /// the original light-gray tertiary.
    static let textMuted       = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? .tertiaryLabel : UIColor(white: 0.42, alpha: 1.0)
    })
    /// Dark text/icons placed on the gold accent — readable in both modes.
    static let onAccent        = Color.black

    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Fonts
// Built on Dynamic Type text styles (rather than fixed point sizes) so all
// text scales with the user's accessibility text-size setting. The chosen
// styles match the previous fixed sizes at the default setting:
//   title 28 → .title · heading 20 → .title3 · body 16/17 → .body
//   caption 12 → .caption · phase 14/15 → .subheadline · numeric 28 → .title
enum LKFont {
    static let title    = Font.system(.title,       design: .default,    weight: .heavy)
    static let heading  = Font.system(.title3,      design: .default,    weight: .bold)
    static let body     = Font.system(.body,        design: .default,    weight: .regular)
    static let bodyBold = Font.system(.body,        design: .default,    weight: .semibold)
    static let caption  = Font.system(.caption,     design: .default,    weight: .regular)
    static let numeric  = Font.system(.title,       design: .monospaced, weight: .bold)
    static let phase    = Font.system(.subheadline, design: .default,    weight: .heavy)

    /// Large stopwatch numerals. Intentionally a fixed display size (like the
    /// system Clock app) — it's sized to fit the screen, not to be read as text.
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

    /// Caps content to a comfortable reading width and centers it. On iPhone the
    /// width is already under the cap so this is a no-op; on iPad it keeps the
    /// single-column content from stretching edge-to-edge.
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
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

// MARK: - Equipment Icon
/// Equipment glyphs. Free weights are custom-drawn because SF Symbols lack
/// distinct barbell / dumbbell / kettlebell / band shapes; everything else
/// uses its SF Symbol. The shapes fill with the inherited foreground color and
/// scale to `size`. NOTE: custom glyphs render only in normal views — dropdown
/// menu rows must keep the SF Symbol name (SwiftUI menus only show system images).
struct EquipmentIcon: View {
    let equipment: Equipment
    var size: CGFloat = 16

    private var lineW: CGFloat { max(1.5, size * 0.12) }

    var body: some View {
        switch equipment {
        case .barbell:        barbell
        case .dumbbell:       dumbbell
        case .kettlebell:     kettlebell
        case .resistanceBand: band
        default:
            Image(systemName: equipment.sfSymbol).font(.system(size: size))
        }
    }

    // Long thin bar with two plates per side.
    private var barbell: some View {
        ZStack {
            Capsule().frame(width: size * 0.98, height: size * 0.12)
            RoundedRectangle(cornerRadius: size * 0.05).frame(width: size * 0.10, height: size * 0.55).offset(x: -size * 0.30)
            RoundedRectangle(cornerRadius: size * 0.05).frame(width: size * 0.10, height: size * 0.40).offset(x: -size * 0.42)
            RoundedRectangle(cornerRadius: size * 0.05).frame(width: size * 0.10, height: size * 0.55).offset(x: size * 0.30)
            RoundedRectangle(cornerRadius: size * 0.05).frame(width: size * 0.10, height: size * 0.40).offset(x: size * 0.42)
        }
        .frame(width: size, height: size)
    }

    // Short solid bar with chunky endcaps.
    private var dumbbell: some View {
        ZStack {
            Capsule().frame(width: size * 0.60, height: size * 0.14)
            RoundedRectangle(cornerRadius: size * 0.08).frame(width: size * 0.20, height: size * 0.50).offset(x: -size * 0.32)
            RoundedRectangle(cornerRadius: size * 0.08).frame(width: size * 0.20, height: size * 0.50).offset(x: size * 0.32)
        }
        .frame(width: size, height: size)
    }

    // Round bell with a loop handle on top.
    private var kettlebell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14)
                .stroke(lineWidth: lineW)
                .frame(width: size * 0.42, height: size * 0.36)
                .offset(y: -size * 0.30)
            Circle()
                .frame(width: size * 0.66, height: size * 0.66)
                .offset(y: size * 0.13)
        }
        .frame(width: size, height: size)
    }

    // Resistance loop band.
    private var band: some View {
        Capsule()
            .stroke(lineWidth: lineW)
            .frame(width: size * 0.92, height: size * 0.50)
            .frame(width: size, height: size)
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
