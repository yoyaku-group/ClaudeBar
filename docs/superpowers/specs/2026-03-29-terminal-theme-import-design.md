# Terminal Theme Import — Design Spec

**Date:** 2026-03-29
**Author:** Benjamin Belaga
**Target:** PR to upstream `tddworks/ClaudeBar`
**Status:** Draft

## Summary

Add the ability to import terminal color schemes (`.itermcolors` files) into ClaudeBar, automatically generating a full `AppThemeProvider` theme from the 16 ANSI colors + background/foreground. This gives every macOS user a one-click way to match ClaudeBar's appearance to their terminal.

## Motivation

ClaudeBar is a tool for developers who live in their terminal. Matching the app's appearance to the terminal theme creates visual coherence. Currently, adding a new theme requires implementing ~25 Swift properties manually. This feature lets users import any `.itermcolors` file and get a fully generated theme.

The `.itermcolors` format is the de facto standard for terminal color schemes on macOS:
- 450+ pre-made schemes exist ([mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes))
- iTerm2 exports to this format in one click
- It's an XML property list — parseable with Foundation's `PropertyListSerialization`, zero dependencies

## Architecture

### Layer Placement

Following ClaudeBar's existing layered architecture:

```
Infrastructure/TerminalImport/
├── TerminalColorScheme.swift           # Canonical color model
├── ITermColorsParser.swift             # .itermcolors XML plist parser
└── TerminalThemeGenerator.swift        # ANSI→AppThemeProvider mapping

App/Theme/
├── ImportedTerminalTheme.swift         # AppThemeProvider backed by TerminalColorScheme
└── (ThemeRegistry.swift — modified)    # Persists/loads imported themes

App/Settings/
└── ThemeImportView.swift               # File picker + live preview
```

### 1. Canonical Model — `TerminalColorScheme`

**Layer:** Infrastructure
**Purpose:** Format-agnostic representation of a terminal color scheme.

```swift
public struct TerminalColorScheme: Codable, Sendable {
    public let name: String

    // Core UI colors
    public let background: RGBColor
    public let foreground: RGBColor
    public let boldText: RGBColor?
    public let cursor: RGBColor?
    public let selection: RGBColor?
    public let selectionText: RGBColor?

    // 16 ANSI colors (indices 0-15)
    public let ansiColors: [RGBColor]  // exactly 16

    public struct RGBColor: Codable, Sendable {
        public let red: Double    // 0.0-1.0
        public let green: Double  // 0.0-1.0
        public let blue: Double   // 0.0-1.0
        public let alpha: Double  // 0.0-1.0, defaults to 1.0
    }
}
```

This model is intentionally decoupled from SwiftUI `Color` to keep it in the Infrastructure layer and make it `Codable` for persistence.

### 2. Parser — `ITermColorsParser`

**Layer:** Infrastructure
**Purpose:** Parse `.itermcolors` XML plist files into `TerminalColorScheme`.

```swift
public struct ITermColorsParser {
    public static func parse(from url: URL) throws -> TerminalColorScheme
    public static func parse(from data: Data) throws -> TerminalColorScheme
}
```

**Format:** `.itermcolors` is an XML property list. Each color key maps to a dict:
```xml
<key>Background Color</key>
<dict>
    <key>Red Component</key><real>0.114</real>
    <key>Green Component</key><real>0.145</real>
    <key>Blue Component</key><real>0.169</real>
    <key>Alpha Component</key><real>1</real>
    <key>Color Space</key><string>sRGB</string>
</dict>
```

**Key mapping:**
| .itermcolors Key | TerminalColorScheme Field |
|---|---|
| `Background Color` | `background` |
| `Foreground Color` | `foreground` |
| `Bold Color` | `boldText` |
| `Cursor Color` | `cursor` |
| `Selection Color` | `selection` |
| `Selected Text Color` | `selectionText` |
| `Ansi 0 Color` — `Ansi 15 Color` | `ansiColors[0]`—`ansiColors[15]` |

**Validation:** Parser throws if background, foreground, or any of the 16 ANSI colors are missing. Optional colors (bold, cursor, selection) default to nil.

**Theme name:** Derived from filename (minus `.itermcolors` extension). User can rename after import.

### 3. Theme Generator — `TerminalThemeGenerator`

**Layer:** Infrastructure
**Purpose:** Map a `TerminalColorScheme` to all ~25 `AppThemeProvider` properties.

This is the core value of the feature. The algorithm derives the full theme from the canonical colors:

```swift
public struct TerminalThemeGenerator {
    public static func generate(from scheme: TerminalColorScheme) -> ImportedTerminalTheme
}
```

**Mapping algorithm:**

| AppThemeProvider Property | Source | Logic |
|---|---|---|
| **backgroundGradient** | `background` | Solid color as `LinearGradient` |
| **showBackgroundOrbs** | — | `false` (terminal themes are clean) |
| **overlayView** | — | `nil` |
| **cardGradient** | `background` | Lighten by 8-10% for card contrast |
| **glassBackground** | `background` | Lighten by 5%, 80% opacity |
| **glassBorder** | `ansiColors[0]` (black) | 50% opacity |
| **glassHighlight** | `ansiColors[6]` (cyan) | 15% opacity |
| **textPrimary** | `boldText` ?? `foreground` | Direct use |
| **textSecondary** | `foreground` | Direct use |
| **textTertiary** | `foreground` | 70% opacity |
| **fontDesign** | — | `.monospaced` (terminal = mono) |
| **customFontName** | — | `nil` (use system mono) |
| **statusHealthy** | `ansiColors[2]` (green) | Direct use |
| **statusWarning** | `ansiColors[3]` (yellow) | Direct use |
| **statusCritical** | `ansiColors[1]` (red) | Direct use |
| **statusDepleted** | `ansiColors[1]` (red) | 70% opacity |
| **accentPrimary** | `ansiColors[6]` (cyan) | Direct use |
| **accentSecondary** | `ansiColors[4]` (blue) | Direct use |
| **accentGradient** | cyan → blue | `ansiColors[6]` → `ansiColors[4]` |
| **pillGradient** | cyan, blue | 25% → 15% opacity |
| **shareGradient** | `ansiColors[3]` (yellow) | Yellow → bright yellow |
| **hoverOverlay** | `accentPrimary` | 10% opacity |
| **pressedOverlay** | `accentPrimary` | 15% opacity |
| **progressTrack** | `selection` ?? `background` lightened 15% | |
| **progressGradient** | red/yellow/cyan by % | Same logic as existing themes |
| **statusBarIconName** | — | `nil` (use default status icons) |

**Color utilities needed:**
- `lighten(by:)` — increase brightness by percentage
- `darken(by:)` — decrease brightness by percentage
- `withOpacity(_:)` — apply alpha

These are simple HSB manipulations on `RGBColor`, implemented as extensions.

### 4. Imported Theme — `ImportedTerminalTheme`

**Layer:** App (Theme)
**Purpose:** `AppThemeProvider` implementation backed by generated values.

```swift
public struct ImportedTerminalTheme: AppThemeProvider {
    public let id: String           // "imported-{sanitized-name}"
    public let displayName: String  // User-visible name
    public let icon: String         // "terminal.fill"
    public let subtitle: String?    // "Imported"

    // All properties stored as concrete values (not computed from scheme)
    // Generated once by TerminalThemeGenerator, then frozen
    public let backgroundGradient: LinearGradient
    public let cardGradient: LinearGradient
    // ... all other properties
}
```

The theme stores pre-computed values, not a reference to the scheme. This avoids re-computing on every SwiftUI render.

### 5. Persistence

**Location:** `~/.claudebar/themes/` directory
**Format:** JSON files, one per imported theme

Each file contains:
```json
{
    "name": "Dracula",
    "scheme": { /* TerminalColorScheme, Codable */ },
    "importedAt": "2026-03-29T10:00:00Z"
}
```

On app launch, `ThemeRegistry` scans `~/.claudebar/themes/`, re-generates each `ImportedTerminalTheme` from the stored `TerminalColorScheme`, and registers them.

**Why store the scheme, not the generated theme?** If the mapping algorithm improves in a future version, all imported themes automatically benefit.

### 6. UI — `ThemeImportView`

**Layer:** App (Settings)
**Purpose:** Import button + file picker + live preview.

**Integration point:** Added to the existing `themeCard` section in `SettingsView.swift`, below the theme grid.

**Flow:**
1. User clicks "Import from Terminal" button (below the theme picker grid)
2. `NSOpenPanel` file picker opens, filtered to `.itermcolors` files
3. File is parsed → scheme is generated → live preview card shows the result
4. User confirms → theme is saved to `~/.claudebar/themes/` and registered
5. Theme appears in the picker grid alongside built-in themes

**Preview card:** Shows background color swatch, text colors, ANSI palette strip (16 small colored squares), and accent color.

**Delete:** Imported themes can be deleted via a context menu (right-click) or a small "x" button in the theme picker. Built-in themes cannot be deleted.

### 7. ThemeMode Evolution

Currently `ThemeMode` is a hardcoded enum. To support imported themes:

**Option A (recommended):** Keep `ThemeMode` enum for built-ins, use the string-based `settings.themeMode` for imported theme IDs. `ThemeRegistry.resolveTheme(for:)` already handles arbitrary string IDs — it falls back to `themes[id]`. The theme picker grid uses `ThemeRegistry.allThemes` instead of `ThemeMode.allCases`.

This is the least invasive change — the enum stays for type safety on built-ins, but the picker becomes dynamic.

**Changes to `ThemeEnvironment.swift`:** The `effectiveColorScheme` logic needs to handle imported themes. Imported terminal themes are always `.dark` or `.light` based on the background luminance (dark bg → `.dark` scheme, light bg → `.light` scheme).

### 8. What Stays Out of Scope

- **Auto-detect from running iTerm2/Terminal.app** — future enhancement, different sandboxing concerns
- **Other formats** (Ghostty, Warp, Base16) — architecture supports them via new parsers, but not in v1
- **Theme editing UI** — users import, they don't tweak individual colors in-app
- **Font import** — `.itermcolors` doesn't include font info; imported themes use system monospace

## Testing Strategy

### Infrastructure Tests
- `ITermColorsParserTests` — parse valid files, handle missing colors, handle malformed XML
- `TerminalThemeGeneratorTests` — verify mapping produces correct colors for known schemes
- `TerminalColorSchemeTests` — Codable round-trip, validation

### App Tests
- `ImportedTerminalThemeTests` — verify all `AppThemeProvider` properties are non-nil
- `ThemeRegistryTests` — imported themes register, persist, load on restart, delete

### Test Data
Bundle 2-3 `.itermcolors` files as test fixtures:
- A dark scheme (e.g., Dracula or Solarized Dark)
- A light scheme (e.g., Solarized Light)
- A minimal scheme (only required keys, no optionals)

## PR Strategy for Upstream

**Branch:** `feature/terminal-theme-import`
**Commits:** Atomic, one per component (parser, generator, theme, UI, tests)
**Scope:** Generic feature — no YOYAKU-specific code. The YoyakuTheme stays in the fork only.

**PR description should emphasize:**
- Zero new dependencies (Foundation `PropertyListSerialization`)
- 450+ compatible schemes via mbadolato/iTerm2-Color-Schemes
- Follows existing architecture patterns (protocol-based, layered, TDD)
- Extensible to other formats via new parser implementations

## File Summary

| Action | File | Layer |
|--------|------|-------|
| **Create** | `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift` | Infrastructure |
| **Create** | `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift` | Infrastructure |
| **Create** | `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift` | Infrastructure |
| **Create** | `Sources/App/Theme/ImportedTerminalTheme.swift` | App |
| **Create** | `Sources/App/Settings/ThemeImportView.swift` | App |
| **Modify** | `Sources/App/Theme/ThemeRegistry.swift` | App |
| **Modify** | `Sources/App/Theme/ThemeEnvironment.swift` | App |
| **Modify** | `Sources/App/Views/SettingsView.swift` | App |
| **Create** | `Tests/InfrastructureTests/TerminalImport/ITermColorsParserTests.swift` | Tests |
| **Create** | `Tests/InfrastructureTests/TerminalImport/TerminalThemeGeneratorTests.swift` | Tests |
| **Create** | `Tests/InfrastructureTests/TerminalImport/TerminalColorSchemeTests.swift` | Tests |
| **Create** | `Tests/InfrastructureTests/TerminalImport/Fixtures/*.itermcolors` | Tests |
| **Modify** | `docs/architecture/THEME_DESIGN.md` | Docs |
| **Modify** | `README.md` | Docs |
