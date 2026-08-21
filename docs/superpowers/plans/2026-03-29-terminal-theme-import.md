# Terminal Theme Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to import `.itermcolors` files into ClaudeBar, automatically generating a full theme from terminal color schemes.

**Architecture:** Infrastructure layer parses `.itermcolors` XML plists into a canonical `TerminalColorScheme` model, then a generator maps 16 ANSI colors + bg/fg to all ~25 `AppThemeProvider` properties. Imported themes persist as JSON in `~/.claudebar/themes/` and register in `ThemeRegistry` on launch.

**Tech Stack:** Swift 6.2, Foundation `PropertyListSerialization`, SwiftUI, Apple Testing framework, Tuist

**Spec:** `docs/superpowers/specs/2026-03-29-terminal-theme-import-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift` | Canonical color model (Codable, Sendable) |
| Create | `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift` | Parse `.itermcolors` XML plist → TerminalColorScheme |
| Create | `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift` | Map TerminalColorScheme → theme property values |
| Create | `Sources/App/Theme/ImportedTerminalTheme.swift` | AppThemeProvider backed by generated values |
| Create | `Sources/App/Theme/ImportedThemeStore.swift` | Persist/load imported themes from ~/.claudebar/themes/ |
| Modify | `Sources/App/Theme/ThemeRegistry.swift` | Load imported themes on init, register/unregister |
| Modify | `Sources/App/Theme/ThemeEnvironment.swift` | Handle imported themes in effectiveColorScheme |
| Create | `Sources/App/Settings/ThemeImportView.swift` | Import button + file picker + preview |
| Modify | `Sources/App/Views/SettingsView.swift` | Add import button to themeCard section |
| Create | `Tests/InfrastructureTests/TerminalImport/ITermColorsParserTests.swift` | Parser tests |
| Create | `Tests/InfrastructureTests/TerminalImport/TerminalThemeGeneratorTests.swift` | Generator mapping tests |
| Create | `Tests/InfrastructureTests/TerminalImport/TerminalColorSchemeTests.swift` | Model Codable round-trip tests |

---

## Task 1: TerminalColorScheme Model

**Files:**
- Create: `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift`
- Create: `Tests/InfrastructureTests/TerminalImport/TerminalColorSchemeTests.swift`

- [ ] **Step 1: Write the failing test for RGBColor Codable round-trip**

```swift
// Tests/InfrastructureTests/TerminalImport/TerminalColorSchemeTests.swift
import Testing
import Foundation
@testable import Infrastructure

@Suite
struct TerminalColorSchemeTests {

    @Test func `RGBColor encodes and decodes correctly`() throws {
        let color = TerminalColorScheme.RGBColor(red: 0.114, green: 0.145, blue: 0.169, alpha: 1.0)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(TerminalColorScheme.RGBColor.self, from: data)
        #expect(decoded.red == 0.114)
        #expect(decoded.green == 0.145)
        #expect(decoded.blue == 0.169)
        #expect(decoded.alpha == 1.0)
    }

    @Test func `TerminalColorScheme encodes and decodes with all fields`() throws {
        let scheme = TerminalColorScheme(
            name: "Test",
            background: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0),
            foreground: .init(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
            boldText: .init(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
            cursor: nil,
            selection: nil,
            selectionText: nil,
            ansiColors: (0..<16).map { i in
                TerminalColorScheme.RGBColor(
                    red: Double(i) / 15.0,
                    green: Double(i) / 15.0,
                    blue: Double(i) / 15.0,
                    alpha: 1.0
                )
            }
        )
        let data = try JSONEncoder().encode(scheme)
        let decoded = try JSONDecoder().decode(TerminalColorScheme.self, from: data)
        #expect(decoded.name == "Test")
        #expect(decoded.ansiColors.count == 16)
        #expect(decoded.boldText != nil)
        #expect(decoded.cursor == nil)
    }

    @Test func `TerminalColorScheme requires exactly 16 ANSI colors`() {
        let scheme = TerminalColorScheme(
            name: "Bad",
            background: .init(red: 0, green: 0, blue: 0, alpha: 1),
            foreground: .init(red: 1, green: 1, blue: 1, alpha: 1),
            boldText: nil,
            cursor: nil,
            selection: nil,
            selectionText: nil,
            ansiColors: [.init(red: 0, green: 0, blue: 0, alpha: 1)]  // only 1
        )
        #expect(scheme.isValid == false)
    }

    @Test func `RGBColor luminance calculation`() {
        let white = TerminalColorScheme.RGBColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let black = TerminalColorScheme.RGBColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        #expect(white.luminance > 0.9)
        #expect(black.luminance < 0.1)
    }

    @Test func `RGBColor lightened and darkened`() {
        let color = TerminalColorScheme.RGBColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let lighter = color.lightened(by: 0.1)
        let darker = color.darkened(by: 0.1)
        #expect(lighter.luminance > color.luminance)
        #expect(darker.luminance < color.luminance)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "TerminalColorScheme|error|FAIL" | head -20`
Expected: Compilation errors — `TerminalColorScheme` not defined

- [ ] **Step 3: Write the TerminalColorScheme model**

```swift
// Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift
import Foundation

/// Format-agnostic representation of a terminal color scheme.
/// Holds 16 ANSI colors + UI colors (background, foreground, etc.).
/// Codable for JSON persistence in ~/.claudebar/themes/.
public struct TerminalColorScheme: Codable, Sendable, Equatable {
    public let name: String
    public let background: RGBColor
    public let foreground: RGBColor
    public let boldText: RGBColor?
    public let cursor: RGBColor?
    public let selection: RGBColor?
    public let selectionText: RGBColor?
    public let ansiColors: [RGBColor]  // exactly 16

    public var isValid: Bool {
        ansiColors.count == 16
    }

    public init(
        name: String,
        background: RGBColor,
        foreground: RGBColor,
        boldText: RGBColor?,
        cursor: RGBColor?,
        selection: RGBColor?,
        selectionText: RGBColor?,
        ansiColors: [RGBColor]
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.boldText = boldText
        self.cursor = cursor
        self.selection = selection
        self.selectionText = selectionText
        self.ansiColors = ansiColors
    }

    // ANSI color semantic accessors
    public var black: RGBColor { ansiColors[0] }
    public var red: RGBColor { ansiColors[1] }
    public var green: RGBColor { ansiColors[2] }
    public var yellow: RGBColor { ansiColors[3] }
    public var blue: RGBColor { ansiColors[4] }
    public var magenta: RGBColor { ansiColors[5] }
    public var cyan: RGBColor { ansiColors[6] }
    public var white: RGBColor { ansiColors[7] }
    public var brightBlack: RGBColor { ansiColors[8] }
    public var brightRed: RGBColor { ansiColors[9] }
    public var brightGreen: RGBColor { ansiColors[10] }
    public var brightYellow: RGBColor { ansiColors[11] }
    public var brightBlue: RGBColor { ansiColors[12] }
    public var brightMagenta: RGBColor { ansiColors[13] }
    public var brightCyan: RGBColor { ansiColors[14] }
    public var brightWhite: RGBColor { ansiColors[15] }

    /// Whether this scheme has a dark background (luminance < 0.5).
    public var isDark: Bool {
        background.luminance < 0.5
    }
}

// MARK: - RGBColor

extension TerminalColorScheme {
    public struct RGBColor: Codable, Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Relative luminance (ITU-R BT.709).
        public var luminance: Double {
            0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        /// Returns a new color lightened by the given fraction (0.0-1.0).
        public func lightened(by amount: Double) -> RGBColor {
            RGBColor(
                red: min(1.0, red + (1.0 - red) * amount),
                green: min(1.0, green + (1.0 - green) * amount),
                blue: min(1.0, blue + (1.0 - blue) * amount),
                alpha: alpha
            )
        }

        /// Returns a new color darkened by the given fraction (0.0-1.0).
        public func darkened(by amount: Double) -> RGBColor {
            RGBColor(
                red: max(0.0, red * (1.0 - amount)),
                green: max(0.0, green * (1.0 - amount)),
                blue: max(0.0, blue * (1.0 - amount)),
                alpha: alpha
            )
        }

        /// Returns a new color with the given alpha.
        public func withAlpha(_ alpha: Double) -> RGBColor {
            RGBColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "TerminalColorScheme|passed|failed" | head -20`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift Tests/InfrastructureTests/TerminalImport/TerminalColorSchemeTests.swift
git commit -m "feat(theme-import): add TerminalColorScheme model with Codable + color utilities"
```

---

## Task 2: ITermColorsParser

**Files:**
- Create: `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift`
- Create: `Tests/InfrastructureTests/TerminalImport/ITermColorsParserTests.swift`

- [ ] **Step 1: Write test fixtures and failing tests**

```swift
// Tests/InfrastructureTests/TerminalImport/ITermColorsParserTests.swift
import Testing
import Foundation
@testable import Infrastructure

@Suite
struct ITermColorsParserTests {

    // Minimal valid .itermcolors with only required keys
    static let minimalItermcolors = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Background Color</key>
        <dict>
            <key>Red Component</key><real>0.15686</real>
            <key>Green Component</key><real>0.16471</real>
            <key>Blue Component</key><real>0.21176</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Foreground Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Bold Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Cursor Color</key>
        <dict>
            <key>Red Component</key><real>0.97255</real>
            <key>Green Component</key><real>0.97255</real>
            <key>Blue Component</key><real>0.94902</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Selection Color</key>
        <dict>
            <key>Red Component</key><real>0.26667</real>
            <key>Green Component</key><real>0.27843</real>
            <key>Blue Component</key><real>0.35294</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Selected Text Color</key>
        <dict>
            <key>Red Component</key><real>1</real>
            <key>Green Component</key><real>1</real>
            <key>Blue Component</key><real>1</real>
            <key>Alpha Component</key><real>1</real>
            <key>Color Space</key><string>sRGB</string>
        </dict>
        <key>Ansi 0 Color</key>
        <dict><key>Red Component</key><real>0.12941</real><key>Green Component</key><real>0.13333</real><key>Blue Component</key><real>0.17255</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 1 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.33333</real><key>Blue Component</key><real>0.33333</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 2 Color</key>
        <dict><key>Red Component</key><real>0.31373</real><key>Green Component</key><real>0.98039</real><key>Blue Component</key><real>0.48235</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 3 Color</key>
        <dict><key>Red Component</key><real>0.94510</real><key>Green Component</key><real>0.98039</real><key>Blue Component</key><real>0.54902</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 4 Color</key>
        <dict><key>Red Component</key><real>0.74118</real><key>Green Component</key><real>0.57647</real><key>Blue Component</key><real>0.97647</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 5 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.47451</real><key>Blue Component</key><real>0.77647</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 6 Color</key>
        <dict><key>Red Component</key><real>0.54510</real><key>Green Component</key><real>0.91373</real><key>Blue Component</key><real>0.99216</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 7 Color</key>
        <dict><key>Red Component</key><real>0.97255</real><key>Green Component</key><real>0.97255</real><key>Blue Component</key><real>0.94902</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 8 Color</key>
        <dict><key>Red Component</key><real>0.38431</real><key>Green Component</key><real>0.44706</real><key>Blue Component</key><real>0.64314</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 9 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.43137</real><key>Blue Component</key><real>0.43137</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 10 Color</key>
        <dict><key>Red Component</key><real>0.41176</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>0.58039</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 11 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>0.64706</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 12 Color</key>
        <dict><key>Red Component</key><real>0.83922</real><key>Green Component</key><real>0.67451</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 13 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>0.57255</real><key>Blue Component</key><real>0.87451</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 14 Color</key>
        <dict><key>Red Component</key><real>0.64314</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
        <key>Ansi 15 Color</key>
        <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real><key>Alpha Component</key><real>1</real><key>Color Space</key><string>sRGB</string></dict>
    </dict>
    </plist>
    """

    @Test func `parses background and foreground colors`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.name == "Dracula")
        #expect(abs(scheme.background.red - 0.15686) < 0.001)
        #expect(abs(scheme.background.green - 0.16471) < 0.001)
        #expect(abs(scheme.background.blue - 0.21176) < 0.001)
        #expect(abs(scheme.foreground.red - 0.97255) < 0.001)
    }

    @Test func `parses all 16 ANSI colors`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.ansiColors.count == 16)
        #expect(scheme.isValid)
        // Ansi 0 (black)
        #expect(abs(scheme.black.red - 0.12941) < 0.001)
        // Ansi 1 (red)
        #expect(abs(scheme.red.red - 1.0) < 0.001)
        #expect(abs(scheme.red.green - 0.33333) < 0.001)
        // Ansi 6 (cyan)
        #expect(abs(scheme.cyan.red - 0.54510) < 0.001)
        // Ansi 15 (bright white)
        #expect(abs(scheme.brightWhite.red - 1.0) < 0.001)
    }

    @Test func `parses optional colors when present`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.boldText != nil)
        #expect(scheme.cursor != nil)
        #expect(scheme.selection != nil)
        #expect(scheme.selectionText != nil)
    }

    @Test func `detects dark scheme by background luminance`() throws {
        let data = Data(Self.minimalItermcolors.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Dracula")
        #expect(scheme.isDark)
    }

    @Test func `throws on missing background color`() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real></dict>
        </dict>
        </plist>
        """
        let data = Data(xml.utf8)
        #expect(throws: ITermColorsParserError.self) {
            try ITermColorsParser.parse(from: data, name: "Bad")
        }
    }

    @Test func `throws on missing ANSI color`() {
        // Has bg+fg but only 15 ANSI colors (missing Ansi 15)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real></dict>
        """
        for i in 0..<15 {
            xml += """
                <key>Ansi \(i) Color</key>
                <dict><key>Red Component</key><real>0.5</real><key>Green Component</key><real>0.5</real><key>Blue Component</key><real>0.5</real></dict>
            """
        }
        xml += "</dict></plist>"
        let data = Data(xml.utf8)
        #expect(throws: ITermColorsParserError.self) {
            try ITermColorsParser.parse(from: data, name: "Incomplete")
        }
    }

    @Test func `handles legacy format without Alpha and Color Space`() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Background Color</key>
            <dict><key>Red Component</key><real>0.1</real><key>Green Component</key><real>0.1</real><key>Blue Component</key><real>0.1</real></dict>
            <key>Foreground Color</key>
            <dict><key>Red Component</key><real>0.9</real><key>Green Component</key><real>0.9</real><key>Blue Component</key><real>0.9</real></dict>
        """ + (0..<16).map { i in
            """
            <key>Ansi \(i) Color</key>
            <dict><key>Red Component</key><real>0.\(i)</real><key>Green Component</key><real>0.\(i)</real><key>Blue Component</key><real>0.\(i)</real></dict>
            """
        }.joined() + "</dict></plist>"
        let data = Data(xml.utf8)
        let scheme = try ITermColorsParser.parse(from: data, name: "Legacy")
        #expect(scheme.background.alpha == 1.0)
        #expect(scheme.ansiColors.count == 16)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "ITermColorsParser|error|FAIL" | head -20`
Expected: Compilation errors — `ITermColorsParser` not defined

- [ ] **Step 3: Write the parser implementation**

```swift
// Sources/Infrastructure/TerminalImport/ITermColorsParser.swift
import Foundation

/// Errors thrown by ITermColorsParser.
public enum ITermColorsParserError: Error, Equatable {
    case invalidPlist
    case missingColor(String)
}

/// Parses .itermcolors XML plist files into TerminalColorScheme.
///
/// The .itermcolors format is an XML property list where each color key maps to a dict
/// with Red/Green/Blue Component (floats 0.0-1.0) and optional Alpha Component and Color Space.
/// This is the standard export format from iTerm2 (Preferences > Profiles > Colors > Export).
public struct ITermColorsParser {

    /// Parse from a file URL.
    public static func parse(from url: URL) throws -> TerminalColorScheme {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try parse(from: data, name: name)
    }

    /// Parse from raw data with an explicit name.
    public static func parse(from data: Data, name: String) throws -> TerminalColorScheme {
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw ITermColorsParserError.invalidPlist
        }

        let background = try extractColor(from: plist, key: "Background Color")
        let foreground = try extractColor(from: plist, key: "Foreground Color")
        let boldText = try? extractColor(from: plist, key: "Bold Color")
        let cursor = try? extractColor(from: plist, key: "Cursor Color")
        let selection = try? extractColor(from: plist, key: "Selection Color")
        let selectionText = try? extractColor(from: plist, key: "Selected Text Color")

        var ansiColors: [TerminalColorScheme.RGBColor] = []
        for i in 0..<16 {
            let color = try extractColor(from: plist, key: "Ansi \(i) Color")
            ansiColors.append(color)
        }

        return TerminalColorScheme(
            name: name,
            background: background,
            foreground: foreground,
            boldText: boldText,
            cursor: cursor,
            selection: selection,
            selectionText: selectionText,
            ansiColors: ansiColors
        )
    }

    // MARK: - Private

    private static func extractColor(
        from plist: [String: Any],
        key: String
    ) throws -> TerminalColorScheme.RGBColor {
        guard let colorDict = plist[key] as? [String: Any] else {
            throw ITermColorsParserError.missingColor(key)
        }
        let red = (colorDict["Red Component"] as? Double) ?? 0.0
        let green = (colorDict["Green Component"] as? Double) ?? 0.0
        let blue = (colorDict["Blue Component"] as? Double) ?? 0.0
        let alpha = (colorDict["Alpha Component"] as? Double) ?? 1.0
        return TerminalColorScheme.RGBColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "ITermColorsParser|TerminalColorScheme|passed|failed" | head -20`
Expected: All parser + model tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/TerminalImport/ITermColorsParser.swift Tests/InfrastructureTests/TerminalImport/ITermColorsParserTests.swift
git commit -m "feat(theme-import): add ITermColorsParser for .itermcolors XML plist files"
```

---

## Task 3: TerminalThemeGenerator

**Files:**
- Create: `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift`
- Create: `Tests/InfrastructureTests/TerminalImport/TerminalThemeGeneratorTests.swift`

- [ ] **Step 1: Write failing tests for the mapping algorithm**

```swift
// Tests/InfrastructureTests/TerminalImport/TerminalThemeGeneratorTests.swift
import Testing
import Foundation
@testable import Infrastructure

@Suite
struct TerminalThemeGeneratorTests {

    /// Dracula-like dark scheme for testing.
    static let darkScheme = TerminalColorScheme(
        name: "Dracula",
        background: .init(red: 0.157, green: 0.165, blue: 0.212),
        foreground: .init(red: 0.973, green: 0.973, blue: 0.949),
        boldText: .init(red: 0.973, green: 0.973, blue: 0.949),
        cursor: .init(red: 0.973, green: 0.973, blue: 0.949),
        selection: .init(red: 0.267, green: 0.278, blue: 0.353),
        selectionText: .init(red: 1.0, green: 1.0, blue: 1.0),
        ansiColors: [
            .init(red: 0.129, green: 0.133, blue: 0.173),  // 0: black
            .init(red: 1.0, green: 0.333, blue: 0.333),    // 1: red
            .init(red: 0.314, green: 0.980, blue: 0.482),   // 2: green
            .init(red: 0.945, green: 0.980, blue: 0.549),   // 3: yellow
            .init(red: 0.741, green: 0.576, blue: 0.976),   // 4: blue
            .init(red: 1.0, green: 0.475, blue: 0.776),     // 5: magenta
            .init(red: 0.545, green: 0.914, blue: 0.992),   // 6: cyan
            .init(red: 0.973, green: 0.973, blue: 0.949),   // 7: white
            .init(red: 0.384, green: 0.447, blue: 0.643),   // 8: bright black
            .init(red: 1.0, green: 0.431, blue: 0.431),     // 9: bright red
            .init(red: 0.412, green: 1.0, blue: 0.580),     // 10: bright green
            .init(red: 1.0, green: 1.0, blue: 0.647),       // 11: bright yellow
            .init(red: 0.839, green: 0.675, blue: 1.0),     // 12: bright blue
            .init(red: 1.0, green: 0.573, blue: 0.875),     // 13: bright magenta
            .init(red: 0.643, green: 1.0, blue: 1.0),       // 14: bright cyan
            .init(red: 1.0, green: 1.0, blue: 1.0),         // 15: bright white
        ]
    )

    @Test func `generates theme properties from dark scheme`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(props.id == "imported-dracula")
        #expect(props.displayName == "Dracula")
        #expect(props.isDark)
    }

    @Test func `maps ANSI red to statusCritical`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        // statusCritical should come from ANSI 1 (red)
        #expect(abs(props.statusCritical.red - 1.0) < 0.001)
        #expect(abs(props.statusCritical.green - 0.333) < 0.001)
    }

    @Test func `maps ANSI green to statusHealthy`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(abs(props.statusHealthy.red - 0.314) < 0.001)
        #expect(abs(props.statusHealthy.green - 0.980) < 0.001)
    }

    @Test func `maps ANSI yellow to statusWarning`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(abs(props.statusWarning.red - 0.945) < 0.001)
    }

    @Test func `maps ANSI cyan to accentPrimary`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(abs(props.accentPrimary.red - 0.545) < 0.001)
        #expect(abs(props.accentPrimary.green - 0.914) < 0.001)
    }

    @Test func `maps foreground to textPrimary`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(abs(props.textPrimary.red - 0.973) < 0.001)
    }

    @Test func `derives card background from background lightened`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        // Card should be lighter than background
        #expect(props.cardBackground.luminance > Self.darkScheme.background.luminance)
    }

    @Test func `uses selection for progressTrack when available`() {
        let props = TerminalThemeGenerator.generate(from: Self.darkScheme)
        #expect(abs(props.progressTrack.red - 0.267) < 0.001)
    }

    @Test func `handles scheme without optional colors`() {
        let scheme = TerminalColorScheme(
            name: "Minimal",
            background: .init(red: 0.0, green: 0.0, blue: 0.0),
            foreground: .init(red: 1.0, green: 1.0, blue: 1.0),
            boldText: nil,
            cursor: nil,
            selection: nil,
            selectionText: nil,
            ansiColors: (0..<16).map { _ in .init(red: 0.5, green: 0.5, blue: 0.5) }
        )
        let props = TerminalThemeGenerator.generate(from: scheme)
        // textPrimary should fall back to foreground when boldText is nil
        #expect(abs(props.textPrimary.red - 1.0) < 0.001)
        // progressTrack should fall back to lightened background when selection is nil
        #expect(props.progressTrack.luminance > scheme.background.luminance)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "TerminalThemeGenerator|error|FAIL" | head -20`
Expected: Compilation errors — `TerminalThemeGenerator` not defined

- [ ] **Step 3: Write the generator implementation**

```swift
// Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift
import Foundation

/// Generated theme properties from a TerminalColorScheme.
/// Contains all values needed to build an ImportedTerminalTheme (App layer).
/// Lives in Infrastructure to keep SwiftUI out of the generation logic.
public struct GeneratedThemeProperties: Sendable {
    public let id: String
    public let displayName: String
    public let isDark: Bool

    // Background
    public let background: TerminalColorScheme.RGBColor
    public let cardBackground: TerminalColorScheme.RGBColor
    public let glassBackground: TerminalColorScheme.RGBColor
    public let glassBorder: TerminalColorScheme.RGBColor
    public let glassHighlight: TerminalColorScheme.RGBColor

    // Typography
    public let textPrimary: TerminalColorScheme.RGBColor
    public let textSecondary: TerminalColorScheme.RGBColor
    public let textTertiary: TerminalColorScheme.RGBColor

    // Status
    public let statusHealthy: TerminalColorScheme.RGBColor
    public let statusWarning: TerminalColorScheme.RGBColor
    public let statusCritical: TerminalColorScheme.RGBColor
    public let statusDepleted: TerminalColorScheme.RGBColor

    // Accents
    public let accentPrimary: TerminalColorScheme.RGBColor
    public let accentSecondary: TerminalColorScheme.RGBColor

    // Interactive
    public let progressTrack: TerminalColorScheme.RGBColor
}

/// Maps a TerminalColorScheme to GeneratedThemeProperties.
/// The mapping uses ANSI color semantics: red=critical, green=healthy,
/// yellow=warning, cyan=accent primary, blue=accent secondary.
public struct TerminalThemeGenerator {

    public static func generate(from scheme: TerminalColorScheme) -> GeneratedThemeProperties {
        let sanitizedId = scheme.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)

        return GeneratedThemeProperties(
            id: "imported-\(sanitizedId)",
            displayName: scheme.name,
            isDark: scheme.isDark,

            // Background: solid color; card is lightened 8%
            background: scheme.background,
            cardBackground: scheme.background.lightened(by: 0.08),
            glassBackground: scheme.background.lightened(by: 0.05).withAlpha(0.8),
            glassBorder: scheme.black.withAlpha(0.5),
            glassHighlight: scheme.cyan.withAlpha(0.15),

            // Typography: boldText→primary, foreground→secondary, foreground dimmed→tertiary
            textPrimary: scheme.boldText ?? scheme.foreground,
            textSecondary: scheme.foreground,
            textTertiary: scheme.foreground.withAlpha(0.7),

            // Status: direct ANSI semantic mapping
            statusHealthy: scheme.green,
            statusWarning: scheme.yellow,
            statusCritical: scheme.red,
            statusDepleted: scheme.red.withAlpha(0.7),

            // Accents: cyan primary, blue secondary
            accentPrimary: scheme.cyan,
            accentSecondary: scheme.blue,

            // Progress track: selection if available, else lightened background
            progressTrack: scheme.selection ?? scheme.background.lightened(by: 0.15)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist test InfrastructureTests 2>&1 | grep -E "TerminalThemeGenerator|passed|failed" | head -20`
Expected: All 9 generator tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift Tests/InfrastructureTests/TerminalImport/TerminalThemeGeneratorTests.swift
git commit -m "feat(theme-import): add TerminalThemeGenerator ANSI→theme mapping algorithm"
```

---

## Task 4: ImportedTerminalTheme (AppThemeProvider)

**Files:**
- Create: `Sources/App/Theme/ImportedTerminalTheme.swift`

- [ ] **Step 1: Write the ImportedTerminalTheme struct**

This converts `GeneratedThemeProperties` (RGBColor) into SwiftUI `Color` and `LinearGradient`.

```swift
// Sources/App/Theme/ImportedTerminalTheme.swift
import SwiftUI
import Infrastructure
import Domain

/// AppThemeProvider implementation generated from a terminal color scheme.
/// Created by TerminalThemeGenerator, backed by pre-computed RGBColor values.
public struct ImportedTerminalTheme: AppThemeProvider {
    private let props: GeneratedThemeProperties
    private let scheme: TerminalColorScheme

    public init(properties: GeneratedThemeProperties, scheme: TerminalColorScheme) {
        self.props = properties
        self.scheme = scheme
    }

    // MARK: - Identity

    public var id: String { props.id }
    public var displayName: String { props.displayName }
    public var icon: String { "terminal.fill" }
    public var subtitle: String? { "Imported" }
    public var statusBarIconName: String? { nil }
    public var customFontName: String? { nil }

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        let c = props.background.color
        return LinearGradient(colors: [c, c], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var showBackgroundOrbs: Bool { false }

    // MARK: - Cards & Glass

    public var cardGradient: LinearGradient {
        let c = props.cardBackground.color
        return LinearGradient(
            colors: [c.opacity(0.9), c.opacity(0.7)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public var glassBackground: Color { props.glassBackground.color }
    public var glassBorder: Color { props.glassBorder.color }
    public var glassHighlight: Color { props.glassHighlight.color }
    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 12 }

    // MARK: - Typography

    public var textPrimary: Color { props.textPrimary.color }
    public var textSecondary: Color { props.textSecondary.color }
    public var textTertiary: Color { props.textTertiary.color }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { props.statusHealthy.color }
    public var statusWarning: Color { props.statusWarning.color }
    public var statusCritical: Color { props.statusCritical.color }
    public var statusDepleted: Color { props.statusDepleted.color }

    // MARK: - Accents

    public var accentPrimary: Color { props.accentPrimary.color }
    public var accentSecondary: Color { props.accentSecondary.color }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [props.accentPrimary.color, props.accentSecondary.color],
            startPoint: .leading, endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [props.accentPrimary.color.opacity(0.25), props.accentSecondary.color.opacity(0.15)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        let yellow = scheme.yellow.color
        let brightYellow = scheme.brightYellow.color
        return LinearGradient(
            colors: [yellow, brightYellow],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { props.accentPrimary.color.opacity(0.1) }
    public var pressedOverlay: Color { props.accentPrimary.color.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { props.progressTrack.color }

    public func progressGradient(for percent: Double) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20: [statusCritical, statusDepleted]
        case 20..<50: [statusWarning, accentPrimary]
        default: [accentSecondary, statusHealthy]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - RGBColor → SwiftUI Color Bridge

extension TerminalColorScheme.RGBColor {
    /// Convert to SwiftUI Color.
    public var color: Color {
        Color(red: red, green: green, blue: blue).opacity(alpha)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `tuist build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Theme/ImportedTerminalTheme.swift
git commit -m "feat(theme-import): add ImportedTerminalTheme AppThemeProvider implementation"
```

---

## Task 5: ImportedThemeStore (Persistence)

**Files:**
- Create: `Sources/App/Theme/ImportedThemeStore.swift`

- [ ] **Step 1: Write the persistence layer**

```swift
// Sources/App/Theme/ImportedThemeStore.swift
import Foundation
import Infrastructure

/// Persists imported terminal color schemes as JSON files in ~/.claudebar/themes/.
/// On load, re-generates ImportedTerminalTheme from stored schemes.
@MainActor
public final class ImportedThemeStore {

    private let themesDirectory: URL

    public init(directory: URL? = nil) {
        self.themesDirectory = directory ?? Self.defaultDirectory()
    }

    // MARK: - Public API

    /// Load all imported schemes from disk.
    public func loadAll() -> [(TerminalColorScheme, Date)] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: themesDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (TerminalColorScheme, Date)? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? JSONDecoder().decode(StoredTheme.self, from: data)
                else { return nil }
                return (entry.scheme, entry.importedAt)
            }
    }

    /// Save a scheme to disk.
    public func save(_ scheme: TerminalColorScheme) throws {
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        let entry = StoredTheme(scheme: scheme, importedAt: Date())
        let data = try JSONEncoder().encode(entry)
        let filename = scheme.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
        let fileURL = themesDirectory.appendingPathComponent("\(filename).json")
        try data.write(to: fileURL, options: .atomic)
    }

    /// Delete a theme by its scheme name.
    public func delete(name: String) throws {
        let filename = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
        let fileURL = themesDirectory.appendingPathComponent("\(filename).json")
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    private static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar")
            .appendingPathComponent("themes")
    }

    private struct StoredTheme: Codable {
        let scheme: TerminalColorScheme
        let importedAt: Date
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `tuist build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Theme/ImportedThemeStore.swift
git commit -m "feat(theme-import): add ImportedThemeStore for JSON persistence in ~/.claudebar/themes/"
```

---

## Task 6: ThemeRegistry Integration

**Files:**
- Modify: `Sources/App/Theme/ThemeRegistry.swift`
- Modify: `Sources/App/Theme/ThemeEnvironment.swift`

- [ ] **Step 1: Update ThemeRegistry to load imported themes**

Add to `ThemeRegistry.swift` — after the existing `registerBuiltInThemes()` call in `init()`:

```swift
// In ThemeRegistry.swift, add a property:
private let importedThemeStore = ImportedThemeStore()

// In init(), after registerBuiltInThemes():
private init() {
    registerBuiltInThemes()
    loadImportedThemes()
}

// Add new methods:

/// Load imported themes from ~/.claudebar/themes/
private func loadImportedThemes() {
    for (scheme, _) in importedThemeStore.loadAll() {
        let props = TerminalThemeGenerator.generate(from: scheme)
        let theme = ImportedTerminalTheme(properties: props, scheme: scheme)
        register(theme)
    }
}

/// Import a .itermcolors file, persist it, and register the theme.
/// Returns the generated theme.
@discardableResult
public func importItermcolors(from url: URL) throws -> any AppThemeProvider {
    let scheme = try ITermColorsParser.parse(from: url)
    try importedThemeStore.save(scheme)
    let props = TerminalThemeGenerator.generate(from: scheme)
    let theme = ImportedTerminalTheme(properties: props, scheme: scheme)
    register(theme)
    return theme
}

/// Remove an imported theme by its ID.
public func removeImportedTheme(id: String) {
    guard let theme = themes[id], theme is ImportedTerminalTheme else { return }
    // Extract name from ID: "imported-dracula" → "dracula" → find stored name
    let displayName = theme.displayName
    themes.removeValue(forKey: id)
    themeOrder.removeAll { $0 == id }
    try? importedThemeStore.delete(name: displayName)
}

/// Whether a theme is imported (vs built-in).
public func isImported(id: String) -> Bool {
    themes[id] is ImportedTerminalTheme
}
```

- [ ] **Step 2: Update ThemeEnvironment for imported themes**

In `Sources/App/Theme/ThemeEnvironment.swift`, update `effectiveColorScheme` in `AppThemeProviderModifier`:

```swift
private var effectiveColorScheme: ColorScheme {
    let mode = ThemeMode(rawValue: themeModeId)
    switch mode {
    case .light: return .light
    case .dark, .cli, .yoyaku, .christmas: return .dark
    case .system, .none:
        // For imported themes, determine from theme itself
        if let theme = ThemeRegistry.shared.theme(for: themeModeId) as? ImportedTerminalTheme {
            return theme.id.contains("light") ? .light : .dark
        }
        // Check if it's an imported theme by asking the registry
        if ThemeRegistry.shared.isImported(id: themeModeId) {
            return .dark  // Most terminal themes are dark
        }
        return systemColorScheme
    }
}
```

**Wait** — that's not quite right. The `ImportedTerminalTheme` stores `isDark` from `GeneratedThemeProperties`. Let's expose it properly.

Update `ImportedTerminalTheme.swift` to add:

```swift
/// Whether this is a dark theme (for effective color scheme).
public var prefersDarkColorScheme: Bool { props.isDark }
```

And update `ThemeEnvironment.swift`:

```swift
private var effectiveColorScheme: ColorScheme {
    let mode = ThemeMode(rawValue: themeModeId)
    switch mode {
    case .light: return .light
    case .dark, .cli, .yoyaku, .christmas: return .dark
    case .system: return systemColorScheme
    case .none:
        // Imported theme — check its dark preference
        if let imported = ThemeRegistry.shared.theme(for: themeModeId) as? ImportedTerminalTheme {
            return imported.prefersDarkColorScheme ? .dark : .light
        }
        return systemColorScheme
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `tuist build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Theme/ThemeRegistry.swift Sources/App/Theme/ThemeEnvironment.swift Sources/App/Theme/ImportedTerminalTheme.swift
git commit -m "feat(theme-import): integrate imported themes into ThemeRegistry and ThemeEnvironment"
```

---

## Task 7: Theme Import UI

**Files:**
- Create: `Sources/App/Settings/ThemeImportView.swift`
- Modify: `Sources/App/Views/SettingsView.swift`

- [ ] **Step 1: Create ThemeImportView**

```swift
// Sources/App/Settings/ThemeImportView.swift
import SwiftUI
import Infrastructure

/// Import button and preview for terminal color schemes.
struct ThemeImportButton: View {
    @Environment(\.appTheme) private var theme
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importedThemeName: String?

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isImporting = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Import .itermcolors")
                        .font(theme.font(size: 11, weight: .medium))
                }
                .foregroundStyle(theme.accentPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.accentPrimary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.init(filenameExtension: "itermcolors")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }

            if let error = importError {
                Text(error)
                    .font(theme.font(size: 9))
                    .foregroundStyle(theme.statusCritical)
            }

            if let name = importedThemeName {
                Text("Imported: \(name)")
                    .font(theme.font(size: 9))
                    .foregroundStyle(theme.statusHealthy)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        importedThemeName = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let theme = try ThemeRegistry.shared.importItermcolors(from: url)
                importedThemeName = theme.displayName
            } catch {
                importError = "Parse error: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

/// Small delete button overlay for imported themes in the picker.
struct ImportedThemeBadge: View {
    let themeId: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        if ThemeRegistry.shared.isImported(id: themeId) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .onTapGesture {
                    ThemeRegistry.shared.removeImportedTheme(id: themeId)
                }
        }
    }
}
```

- [ ] **Step 2: Add import button to SettingsView themeCard**

In `Sources/App/Views/SettingsView.swift`, inside the `themeCard` computed property, after the `LazyVGrid` closing brace (line ~200), add:

```swift
            // After the LazyVGrid closing brace:
            ThemeImportButton()
                .frame(maxWidth: .infinity)
```

Also update the `ForEach` in the `LazyVGrid` to use `ThemeRegistry.shared.allThemes` instead of `ThemeMode.allCases`:

Replace:
```swift
ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
    ThemeOptionButton(
        mode: mode,
        isSelected: currentThemeMode == mode
    ) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            settings.themeMode = mode.rawValue
        }
    }
}
```

With:
```swift
ForEach(ThemeRegistry.shared.allThemes, id: \.id) { registeredTheme in
    ThemeOptionButton(
        themeId: registeredTheme.id,
        displayName: registeredTheme.displayName,
        icon: registeredTheme.icon,
        isSelected: settings.themeMode == registeredTheme.id,
        isImported: ThemeRegistry.shared.isImported(id: registeredTheme.id)
    ) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            settings.themeMode = registeredTheme.id
        }
    }
}
```

**Note:** This requires updating `ThemeOptionButton` to accept theme data directly instead of a `ThemeMode` enum. Read `ThemeOptionButton` in `SettingsView.swift` first and adapt the interface. The key change is: instead of taking a `ThemeMode`, it takes `themeId`, `displayName`, `icon`, `isSelected`, and `isImported`. If `isImported`, show a small delete "x" overlay.

- [ ] **Step 3: Verify it compiles and the UI renders**

Run: `tuist build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Settings/ThemeImportView.swift Sources/App/Views/SettingsView.swift
git commit -m "feat(theme-import): add import button and dynamic theme picker in settings"
```

---

## Task 8: Documentation

**Files:**
- Modify: `docs/architecture/THEME_DESIGN.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update THEME_DESIGN.md**

Add a new section "## Importing Terminal Themes" after "## Creating a New Theme":

```markdown
## Importing Terminal Themes

ClaudeBar can import `.itermcolors` files to automatically generate themes from terminal color schemes. Over 450 pre-made schemes are available at [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).

### How It Works

1. **Parse** — `ITermColorsParser` reads the XML plist, extracting 16 ANSI colors + background/foreground
2. **Generate** — `TerminalThemeGenerator` maps ANSI colors to AppThemeProvider properties:
   - ANSI Red → `statusCritical`
   - ANSI Green → `statusHealthy`
   - ANSI Yellow → `statusWarning`
   - ANSI Cyan → `accentPrimary`
   - ANSI Blue → `accentSecondary`
   - Background → `backgroundGradient`, derived card/glass colors
   - Foreground → `textPrimary`/`textSecondary`/`textTertiary`
3. **Persist** — Schemes are saved as JSON in `~/.claudebar/themes/`
4. **Register** — On launch, stored schemes are re-generated and registered in ThemeRegistry

### Files

| Component | Location |
|-----------|----------|
| Color model | `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift` |
| Parser | `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift` |
| Generator | `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift` |
| Theme | `Sources/App/Theme/ImportedTerminalTheme.swift` |
| Storage | `Sources/App/Theme/ImportedThemeStore.swift` |
| UI | `Sources/App/Settings/ThemeImportView.swift` |

### Adding Support for Other Formats

Create a new parser in `Sources/Infrastructure/TerminalImport/` that produces a `TerminalColorScheme`. The generator and theme layers work with any source format.
```

- [ ] **Step 2: Update README.md**

In the Features section, update the themes bullet:

```markdown
- **Multiple Themes** - Light, Dark, CLI (terminal-style), Christmas, and **imported terminal themes** (.itermcolors)
```

Add a new section after "## Usage":

```markdown
## Import Terminal Theme

Match ClaudeBar's appearance to your terminal. Import any `.itermcolors` file:

1. Open **Settings** (gear icon)
2. Click **Import .itermcolors**
3. Select your file (export from iTerm2: Preferences > Profiles > Colors > Color Presets > Export)

450+ pre-made schemes available at [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes/tree/master/schemes).

Imported themes are saved in `~/.claudebar/themes/` and persist across restarts.
```

- [ ] **Step 3: Update CLAUDE.md Theme System section**

Add to the Theme System section:

```markdown
### Importing Terminal Themes

The app supports importing `.itermcolors` files via `ITermColorsParser` in `Sources/Infrastructure/TerminalImport/`.
Imported themes are generated by `TerminalThemeGenerator` which maps ANSI colors to `AppThemeProvider` properties.
See `docs/architecture/THEME_DESIGN.md` for the full mapping table.
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/THEME_DESIGN.md README.md CLAUDE.md
git commit -m "docs: add terminal theme import documentation"
```

---

## Task 9: Final Integration Test

**Files:** None new — this is a verification task.

- [ ] **Step 1: Run all tests**

Run: `tuist test 2>&1 | tail -20`
Expected: All tests PASS (existing + new)

- [ ] **Step 2: Build release configuration**

Run: `tuist build ClaudeBar -C Release 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify the full import flow manually**

1. Download a test `.itermcolors` file:
```bash
curl -sL "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/Dracula.itermcolors" -o /tmp/Dracula.itermcolors
```

2. Run the app in Xcode, open Settings, click "Import .itermcolors", select `/tmp/Dracula.itermcolors`
3. Verify: "Dracula" appears in the theme picker, selecting it applies the theme

- [ ] **Step 4: Final commit with all changes**

```bash
git status  # verify clean working tree
git log --oneline -10  # verify commit history
```

- [ ] **Step 5: Push**

```bash
git push origin HEAD
```
