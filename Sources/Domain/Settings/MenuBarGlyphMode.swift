import Foundation

/// What the menu-bar glyph shows (Ben, 2026-08-18: RunCat-style).
///
/// `.text` is the classic readout; `.cat` is a running cat whose tint
/// continuously reflects overall quota health; `.catAndText` shows both.
public enum MenuBarGlyphMode: String, Sendable, CaseIterable, Identifiable {
    case text
    case cat
    case catAndText

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: return "Texte"
        case .cat: return "Chat"
        case .catAndText: return "Chat + texte"
        }
    }

    /// Whether the running cat renders at all.
    public var showsCat: Bool { self != .text }

    /// Whether the usage text renders next to the cat.
    public var showsText: Bool { self != .cat }

    /// SF Symbol for the settings choice chip.
    public var choiceIconName: String {
        switch self {
        case .text: return "textformat"
        case .cat: return "hare.fill"
        case .catAndText: return "circle.grid.2x1.left.filled"
        }
    }
}
