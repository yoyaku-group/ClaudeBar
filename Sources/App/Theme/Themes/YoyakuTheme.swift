import SwiftUI

// MARK: - Yoyaku Theme

/// Dark terminal theme matching Benjamin's iTerm2 profile exactly.
/// Background: #1D252B, Accent: #5DF1D1 (cyan), Font: monospaced.
/// Colors extracted from com.googlecode.iterm2.plist.
public struct YoyakuTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "yoyaku"
    public let displayName = "Yoyaku"
    public let icon = "brain.fill"
    public let subtitle: String? = "Terminal"

    // MARK: - iTerm2 Color Palette (exact values from plist)

    // Backgrounds
    static let bgDark = Color(red: 0.114, green: 0.145, blue: 0.169)    // #1D252B (iTerm2 BG)
    static let bgCard = Color(red: 0.16, green: 0.19, blue: 0.22)       // #29313A
    static let bgSelection = Color(red: 0.22, green: 0.26, blue: 0.30)  // #38424D

    // Foreground / Text
    static let fg = Color(red: 0.906, green: 0.922, blue: 0.914)        // #E7EBE9 (iTerm2 FG)
    static let fgBold = Color(red: 0.95, green: 0.96, blue: 0.95)       // #F2F4F2
    static let fgDim = Color(red: 0.70, green: 0.73, blue: 0.72)        // #B3BAB8
    static let gray = Color(red: 0.259, green: 0.231, blue: 0.404)      // #423B67 (ANSI 0/black)

    // ANSI Colors — exact iTerm2 values
    static let cyan = Color(red: 0.365, green: 0.945, blue: 0.820)      // #5DF1D1 (ANSI Cyan — PRIMARY)
    static let cyanDim = Color(red: 0.30, green: 0.78, blue: 0.68)      // dimmed cyan
    static let red = Color(red: 0.988, green: 0.220, blue: 0.424)       // #FC386C (ANSI Red)
    static let redBright = Color(red: 0.988, green: 0.275, blue: 0.420) // #FC466B (ANSI Magenta)
    static let amber = Color(red: 0.996, green: 0.788, blue: 0.290)     // #FEC94A (ANSI Yellow)
    static let amberBright = Color(red: 1.0, green: 0.85, blue: 0.40)   // brighter yellow
    static let blue = Color(red: 0.216, green: 0.475, blue: 0.925)      // #3779EC (ANSI Blue)
    static let green = Color(red: 0.361, green: 0.945, blue: 0.373)     // #5CF15F (ANSI Green)

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
        colors: [bgCard.opacity(0.9), bgCard.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public var cardGradient: LinearGradient { Self.cardGradientValue }
    public var glassBackground: Color { Self.bgCard.opacity(0.8) }
    public var glassBorder: Color { Self.gray.opacity(0.5) }
    public var glassHighlight: Color { Self.cyan.opacity(0.15) }
    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 12 }

    // MARK: - Typography

    public var textPrimary: Color { Self.fgBold }
    public var textSecondary: Color { Self.fg }
    public var textTertiary: Color { Self.fgDim }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.cyan }
    public var statusWarning: Color { Self.amber }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Self.redBright.opacity(0.7) }

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
            colors: [
                Self.cyan.opacity(0.25),
                Self.cyan.opacity(0.15)
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

    public var hoverOverlay: Color { Self.cyan.opacity(0.1) }
    public var pressedOverlay: Color { Self.cyan.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Self.bgSelection }

    // MARK: - Custom Progress Gradient

    public func progressGradient(for percent: Double) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20: [Self.red, Self.redBright]
        case 20..<50: [Self.amber, Self.amberBright]
        default: [Self.cyan, Self.cyanDim]
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
