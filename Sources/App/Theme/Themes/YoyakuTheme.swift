import SwiftUI

// MARK: - Yoyaku Theme

/// Dark blue-night theme matching the YOYAKU iTerm2 terminal setup.
/// Background: #1C1E2B, Text: #CED3E5, Monospaced font.
/// Accents: blue-violet gradient with lime green status, amber warnings.
public struct YoyakuTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "yoyaku"
    public let displayName = "Yoyaku"
    public let icon = "brain.fill"
    public let subtitle: String? = "Terminal"

    // MARK: - YOYAKU Color Palette (extracted from iTerm2 profile)

    // Backgrounds
    static let bgDark = Color(red: 0.11, green: 0.12, blue: 0.17)       // #1C1E2B
    static let bgCard = Color(red: 0.15, green: 0.16, blue: 0.22)       // #262838 (ANSI 0)
    static let bgSelection = Color(red: 0.20, green: 0.22, blue: 0.30)  // #33384C

    // Foreground / Text
    static let fg = Color(red: 0.81, green: 0.83, blue: 0.90)           // #CED3E5
    static let fgBold = Color(red: 0.90, green: 0.91, blue: 0.96)       // #E5E8F4
    static let fgDim = Color(red: 0.75, green: 0.77, blue: 0.85)        // #BFC4D8
    static let gray = Color(red: 0.30, green: 0.32, blue: 0.40)         // #4C5166 (ANSI 8)

    // ANSI Colors
    static let green = Color(red: 0.60, green: 0.85, blue: 0.45)        // #99D872
    static let greenBright = Color(red: 0.68, green: 0.92, blue: 0.55)  // #ADEA8C
    static let blue = Color(red: 0.45, green: 0.58, blue: 0.98)         // #7293F9
    static let blueBright = Color(red: 0.55, green: 0.68, blue: 1.0)    // #8CADFF
    static let violet = Color(red: 0.75, green: 0.48, blue: 0.95)       // #BF7AF2
    static let violetBright = Color(red: 0.85, green: 0.58, blue: 1.0)  // #D893FF
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.33)        // #F2BF54
    static let amberBright = Color(red: 1.0, green: 0.85, blue: 0.45)   // #FFD872
    static let red = Color(red: 0.94, green: 0.33, blue: 0.38)          // #EF5460
    static let redBright = Color(red: 0.98, green: 0.45, blue: 0.50)    // #F9727F
    static let cyan = Color(red: 0.35, green: 0.82, blue: 0.80)         // #59D1CC
    static let cyanBright = Color(red: 0.45, green: 0.90, blue: 0.88)   // #72E5E0

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Self.bgDark,
                Color(red: 0.13, green: 0.14, blue: 0.20),
                Self.bgDark
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { true }

    // MARK: - Cards & Glass

    public static let cardGradientValue = LinearGradient(
        colors: [bgCard.opacity(0.9), bgCard.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public var cardGradient: LinearGradient { Self.cardGradientValue }
    public var glassBackground: Color { Self.bgCard.opacity(0.8) }
    public var glassBorder: Color { Self.gray.opacity(0.5) }
    public var glassHighlight: Color { Self.blueBright.opacity(0.25) }
    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 12 }

    // MARK: - Typography

    public var textPrimary: Color { Self.fgBold }
    public var textSecondary: Color { Self.fg }
    public var textTertiary: Color { Self.fgDim }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.green }
    public var statusWarning: Color { Self.amber }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Self.redBright.opacity(0.7) }

    // MARK: - Accents

    public var accentPrimary: Color { Self.blue }
    public var accentSecondary: Color { Self.violet }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Self.blue, Self.violet],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Self.blue.opacity(0.3),
                Self.violet.opacity(0.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [Self.amber, Self.amberBright],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { Self.blue.opacity(0.1) }
    public var pressedOverlay: Color { Self.blue.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Self.bgSelection }

    // MARK: - Custom Progress Gradient

    public func progressGradient(for percent: Double) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20: [Self.red, Self.redBright]
        case 20..<50: [Self.amber, Self.amberBright]
        default: [Self.green, Self.greenBright]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Initializer

    public init() {}
}
