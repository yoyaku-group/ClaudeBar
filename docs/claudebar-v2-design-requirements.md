# ClaudeBar v2 — Design Requirements (canonical, rules/47 TEAM-tier)

> Origin : Ben directive 2026-08-20 (screenshots menu-bar + popup) + Ben verbatim
> 2026-07-* "développer beaucoup plus ClaudeBar / consolider avec Mac
> Guardian / s'inspirer du ClaudeBar officiel / un seul centralisé".
> This document is the **single source of truth** for ClaudeBar v2 visual
> and structural requirements. Future sessions must consult this file before
> proposing changes that touch provider rendering, menu-bar composition,
> multi-account display, or status glyphs. If you find yourself editing
> these surfaces without reading this first, you are about to drift —
> rules/47 §Anti-doctrinal.

---

## R1 — Kimi (K-I-M-I) must be visible

Kimi is a first-class provider (line 136 of `Sources/App/ClaudeBarApp.swift`,
`KimiProvider` with `cliProbe` + `apiProbe`). The popup must show Kimi in
the same tab strip as Claude / Codex / Z.ai / Amp.

- Detection : grep `Sources/App/ClaudeBarApp.swift` for `KimiProvider`.
  If absent → missing.
- Diagnostic UI : `Sources/App/Views/Settings/KimiConfigCard.swift` shows
  a warning banner when `KIMI_AUTH_TOKEN` env var + `kimi-auth` cookie
  are both missing.
- Probe mode default : `.api` (CLI `/usage` is dead since
  `kimi-code 0.37.1`). See Phase 6a commit (`ab72716`).

**Failure mode** : if Kimi is missing from the popup tabs, the build is
stale — Kimi is registered, the installed `.app` is older than the commit
that registered it. Rebuild + reinstall.

## R2 — Dual quota bars (session + week) per provider row

Each provider row in the popup must show **TWO** quota bars stacked, not
one:

1. **Session** (5-hour window) — primary, full opacity.
2. **Week** (7-day window) — secondary, 0.5 opacity when the active
   `OverviewWindowFilter` is `.session` (visual anchor of the filter).

When filter is `.all`, both bars are full opacity. When `.week`, both at
0.5 except week at full. Implementation: `WindowBarView` (private
SwiftUI struct) inside `Sources/App/Views/Overview/ProviderSnapshotRow.swift`.
Header label = worst window filtered (matches existing semantic).

Phase 1 commit : `0a8b0a5` (row-level), `8a324c7` (menu-bar NSImage
renderer for the stacked glyph).

## R3 — Multi-account email display for Claude

Ben has **2 Claude accounts** (e.g. `webmaster@yoyaku.fr` + `tech@yoyaku.fr`
or `benjamin@chapelle14.com`). The popup must show BOTH emails visibly so
Ben knows which account is at 0%.

Surfaces :
- Popup row : 3-line layout (provider / label / email monospaced).
  Email truncation mode = `.middle` (preserve first + last chars).
- Tooltip on menu-bar icon : prepend `email + " — " + label` text.
  Glyph itself unchanged (cat + percent stays compact — chat + % remain
  the primary identifier).
- Source : `ClaudeAccountInfoResolver` (`Sources/Infrastructure/...`)
  backed by `backfillClaudeAccountEmailsIfNeeded` (one-shot seeder).
- Model : `ProviderSnapshot.accountEmail: String?` (only populated when
  `multi.accounts.count > 1`).

Phase 1.5 commits : `637c3a5`, `23cc80c`, `4c750f1`, `67cb4e3`.

## R4 — SF Symbols / polished glyphs (no red dots)

The status glyphs in the menu-bar / popup must be SF Symbols themable via
the `statusIcon(for: QuotaStatus) -> String` slot on `AppThemeProvider`.
No raw Unicode `●` red dots, no emoji in the ClaudeBar menu-bar context
(emojis kept ONLY for the Mac Guardian legacy popup until retirement).

Default `AppThemeProvider.statusIcon(for:)` :
- `.healthy` → `chart.bar.fill`
- `.warning` → `chart.bar.fill`
- `.critical` → `exclamationmark.triangle.fill`
- `.depleted` → `chart.bar.xaxis`

Override in `YoyakuTheme.statusIcon(for:)` with ANSI-style set.
CLI theme override with ASCII style.

Phase 5c commit : `5437d9b`.

Provider icons : unified on `ProviderVisualIdentityLookup.symbolIcon`
SSOT (Phase 5a `e7ea45b`). Adding a new provider = one entry there, not
four parallel mappings.

## R5 — Running cat animation (RunCat visual absorbed)

`RunningCatRenderer` (`Sources/App/StatusItemLabelDriver.swift:314-330`)
already animates a tint-interpolated cat icon based on worst-health
across providers. After Phase 8 (single centralized icon, gated on P4
retirement), this becomes the ONLY icon in the menu-bar.

Phase 4 retirement checklist (do NOT execute before Phase 4 timeline) :
1. Confirm `app.overviewModeEnabled = true` default.
2. `rm ~/repos/llm-router/integrations/swiftbar/yoyaku-quotas.5m.sh`
   (symlink).
3. `rm ~/repos/mac-guardian/swiftbar/guardian.10s.sh` (copy).
4. `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.yoyaku.swiftbar.plist`.
5. After ≥1 week stable : `rm /Applications/RunCat.app` +
   `rm /Applications/SwiftBar.app`.

## R6 — Single centralized icon in menu-bar

After Phase 4 retirement, the menu-bar has **exactly one** ClaudeBar icon.
All other entries (RunCat, SwiftBar, Mac Guardian native popup) are
retired. Mac Guardian data lives in ClaudeBar's `GuardianCardView` (in
the popup) — see Phase 5d + Phase 9a commits.

`RunningCatRenderer` + the dual-bar `StatusBarDualBarImageRenderer` (Phase
7 `8a324c7`) + `inlineEmailSuffix` (Phase 7c) compose the single icon.

## R7 — Polished visual matching ClaudeBar-official + Apple SF Symbols

The visual aesthetic Ben referenced is the ClaudeBar-official design (the
upstream `tddworks/ClaudeBar`) + Apple system menu style (CPU/Memory/
Storage/Battery grid from `~/Desktop/_screenshots/Capture d'écran
2026-08-20 à 07.56.34.png`).

Required patterns :
- Monochrome SF Symbols in a 4-column grid layout for non-Provider popups
  (e.g. Guardian card).
- Pill-shaped health indicators (`HEALTHY`/`WARNING`/`CRITICAL`).
- Glassmorphism backgrounds (already in theme).
- Provider rows with icon (SF Symbol) + label + email monospaced + 2
  stacked progress bars.

## Build / install reminder

All R1–R7 changes are committed on branch
`feat/yoyaku-multi-profile` (locally, NOT pushed as of 2026-08-20).
Phase 4 retirement requires Ben's push gesture (sandbox blocks SSH + gh
token expired on the autopilot session) + CI vert + 1 week soak.

Until the build is reinstalled, Ben sees the **old build** (`06a3939`)
which predates R2/R3/R4. The Kimi row from R1 is also old-build-stale
because `KimiProvider` was registered after `06a3939`.

## Reference screenshots (Ben's actual visible state 2026-08-20)

- `~/Desktop/_screenshots/Capture d'écran 2026-08-20 à 07.56.20.png` —
  ClaudeBar popup (4 tabs : Claude / Codex / Z.ai / Amp, 1 SESSION bar)
- `~/Desktop/_screenshots/Capture d'écran 2026-08-20 à 07.56.24.png` —
  Mac Guardian popup (separate widget)
- `~/Desktop/_screenshots/Capture d'écran 2026-08-20 à 07.56.28.png` —
  ClaudeBar popup with SESSION 100% + HEALTHY pill
- `~/Desktop/_screenshots/Capture d'écran 2026-08-20 à 07.56.34.png` —
  Apple system info (CPU/Memory/Storage/Battery grid) — visual reference

## Cross-references

- `~/.claude/plans/claude-code-v2-1-234-fluttering-cherny.md` — active plan
  with Phase 5–9 design expansion details.
- `~/.claude/projects/-Users-yoyaku/memory/` — feedback memory pointers.
- rules/47 — memory → repo doctrine routing (this file IS the canonical
  home for ClaudeBar v2 design requirements per the rules/47 decision
  tree: TEAM-tier (concrete to ClaudeBar repo)).
- rules/73 — anti-monkey-patch : adding a provider rendering surface
  without checking this file = drift recipe.
