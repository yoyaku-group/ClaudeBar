import SwiftUI

// MARK: - YOYAKU Theme

/// Dark theme inspired by YOYAKU's iTerm2 setup.
/// Background: #1D252B, Cyan accent: #5DF1D1, Monospaced font.
/// Designed to match Benjamin's terminal aesthetic.
public struct YoyakuTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "yoyaku"
    public let displayName = "YOYAKU"
    public let icon = "music.note"
    public let subtitle: String? = "Vinyl"
    public let statusBarIconName: String? = "music.note"

    // MARK: - YOYAKU Color Palette (from iTerm2)

    // Background: #1D252B
    static let bgDark = Color(red: 0.113, green: 0.147, blue: 0.166)
    // Slightly lighter for cards
    static let bgCard = Color(red: 0.16, green: 0.19, blue: 0.21)
    // Border
    static let bgBorder = Color(red: 0.22, green: 0.26, blue: 0.29)

    // ANSI Cyan: #5DF1D1 (primary accent)
    static let cyan = Color(red: 0.365, green: 0.945, blue: 0.820)
    static let cyanDim = Color(red: 0.25, green: 0.65, blue: 0.56)

    // ANSI Green: #5CF15F
    static let green = Color(red: 0.361, green: 0.945, blue: 0.373)

    // ANSI Red: #FC386C
    static let red = Color(red: 0.988, green: 0.220, blue: 0.424)

    // ANSI Yellow: #FEC94A
    static let yellow = Color(red: 0.996, green: 0.788, blue: 0.290)

    // ANSI Blue: #3779EC
    static let blue = Color(red: 0.216, green: 0.475, blue: 0.925)

    // ANSI Magenta: #FC466B
    static let magenta = Color(red: 0.988, green: 0.275, blue: 0.420)

    // Foreground: #E7EBE9
    static let fg = Color(red: 0.907, green: 0.921, blue: 0.931)
    static let fgDim = Color(red: 0.627, green: 0.690, blue: 0.631)

    // Bright Black: #A0B0A1
    static let gray = Color(red: 0.627, green: 0.690, blue: 0.631)

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Self.bgDark, Self.bgDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { false }

    // MARK: - Cards & Glass

    public static let cardGradientValue = LinearGradient(
        colors: [bgCard, bgCard.opacity(0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public var cardGradient: LinearGradient { Self.cardGradientValue }
    public var glassBackground: Color { Self.bgCard }
    public var glassBorder: Color { Self.bgBorder }
    public var glassHighlight: Color { Self.cyan.opacity(0.2) }
    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 10 }

    // MARK: - Typography

    public var textPrimary: Color { Self.fg }
    public var textSecondary: Color { Self.fgDim }
    public var textTertiary: Color { Self.gray }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.cyan }
    public var statusWarning: Color { Self.yellow }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Self.magenta }

    // MARK: - Accents

    public var accentPrimary: Color { Self.cyan }
    public var accentSecondary: Color { Self.cyanDim }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Self.cyan, Self.cyanDim],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [Self.cyan.opacity(0.25), Self.cyan.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [Self.yellow, Self.yellow.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { Self.cyan.opacity(0.08) }
    public var pressedOverlay: Color { Self.cyan.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Self.bgBorder }

    // MARK: - Custom Progress Gradient

    public func progressGradient(for percent: Double) -> LinearGradient {
        let color: Color = switch percent {
        case 0..<20: statusCritical
        case 20..<50: statusWarning
        default: statusHealthy
        }
        return LinearGradient(
            colors: [color, color.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Initializer

    public init() {}
}
