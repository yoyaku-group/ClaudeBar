import SwiftUI

// MARK: - CLI Theme

/// Terminal theme tuned closer to modern iTerm:
/// graphite surfaces, restrained chrome, mono typography,
/// and phosphor-like green accents.
public struct CLITheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "cli"
    public let displayName = "CLI"
    public let icon = "terminal.fill"
    public let subtitle: String? = "Terminal"
    public let statusBarIconName: String? = "terminal.fill"

    // MARK: - CLI-Specific Colors

    // Static definitions for reuse
    static let black = Color(red: 0.1137, green: 0.1490, blue: 0.1647)      // #1D262A
    static let charcoal = Color(red: 0.0900, green: 0.1250, blue: 0.1450)
    static let darkGray = Color(red: 0.2629, green: 0.3562, blue: 0.4025)   // #435B67
    static let gray = Color(red: 0.6310, green: 0.6900, blue: 0.7215)       // #A1B0B8
    static let green = Color(red: 0.3620, green: 0.9439, blue: 0.6204)      // #5CF19E
    static let greenDim = Color(red: 0.6780, green: 0.9690, blue: 0.7450)   // #ADF7BE
    static let blue = Color(red: 0.2157, green: 0.7137, blue: 1.0000)       // #37B6FF
    static let cyan = Color(red: 0.3490, green: 1.0000, blue: 0.8196)       // #59FFD1
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.2)
    static let red = Color(red: 0.96, green: 0.36, blue: 0.36)
    static let white = Color(red: 0.9073, green: 0.9216, blue: 0.9294)      // #E7EBED
    static let whiteDim = Color(red: 0.6310, green: 0.6900, blue: 0.7215)   // #A1B0B8
    static let graphiteEdge = Color(red: 0.2629, green: 0.3562, blue: 0.4025)

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Self.black,
                Color(red: 0.1030, green: 0.1380, blue: 0.1560),
                Color(red: 0.0860, green: 0.1140, blue: 0.1320)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var showBackgroundOrbs: Bool { false }

    // MARK: - Cards & Glass

    public static let cardGradient = LinearGradient(
        colors: [
            Color(red: 0.1170, green: 0.1490, blue: 0.1680),
            Color(red: 0.1020, green: 0.1330, blue: 0.1510),
            Color(red: 0.0920, green: 0.1200, blue: 0.1390)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public var cardGradient: LinearGradient { Self.cardGradient }

    public static let glassBackground = Color(red: 0.1010, green: 0.1290, blue: 0.1470)
    public var glassBackground: Color { Self.glassBackground }

    public static let glassBorder = graphiteEdge
    public var glassBorder: Color { Self.glassBorder }

    public static let glassHighlight = blue.opacity(0.12)
    public var glassHighlight: Color { Self.glassHighlight }

    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 10 }

    // MARK: - Typography

    public var textPrimary: Color { Self.white }
    public var textSecondary: Color { Self.whiteDim }
    public var textTertiary: Color { Self.gray.opacity(0.85) }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.green }
    public var statusWarning: Color { Self.amber }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Color(red: 0.65, green: 0.15, blue: 0.15) }

    // MARK: - Accents

    public var accentPrimary: Color { Self.green }
    public var accentSecondary: Color { Self.blue }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Self.green, Self.cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [Self.green.opacity(0.24), Self.blue.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [Self.amber, Self.amber.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { Self.blue.opacity(0.10) }
    public var pressedOverlay: Color { Self.cyan.opacity(0.10) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Self.darkGray.opacity(0.62) }

    // MARK: - Custom Progress Gradient

    public func progressGradient(for percent: Double) -> LinearGradient {
        let color: Color = switch percent {
        case 0..<20: statusCritical
        case 20..<50: statusWarning
        default: statusHealthy
        }
        return LinearGradient(
            colors: [color, color.opacity(0.84)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Initializer

    public init() {}
}

// MARK: - CLI Glass Card Modifier

struct CLIGlassCardStyle: ViewModifier {
    @Environment(\.themeMode) private var themeMode
    var cornerRadius: CGFloat = 8  // Sharper corners for CLI aesthetic
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base card layer - flat dark background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(themeMode.isCLI ? CLITheme.cardGradient : AppTheme.cardGradient(for: .dark))

                    // Simple border - thin green line for CLI
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            themeMode.isCLI ? CLITheme.glassBorder : AppTheme.glassBorder(for: .dark),
                            lineWidth: 1
                        )
                }
            )
    }
}

extension View {
    func cliGlassCard(cornerRadius: CGFloat = 8, padding: CGFloat = 12) -> some View {
        modifier(CLIGlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
