import SwiftUI
import Domain
import Infrastructure
import MenuBarExtraAccess
#if ENABLE_SPARKLE
import Sparkle
#endif

extension Notification.Name {
    static let hookSettingsChanged = Notification.Name("com.tddworks.claudebar.hookSettingsChanged")
}

@main
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    /// This is the single source of truth for providers and their state
    @State private var monitor: QuotaMonitor

    /// Monitors Claude Code sessions via hook events
    @State private var sessionMonitor: SessionMonitor

    /// Drives the menu-bar pixels and the background-refresh lifecycle
    /// imperatively, outside SwiftUI — the MenuBarExtra label hosting can
    /// permanently stop re-evaluating after system sleep (issue #192).
    private let statusItemDriver: StatusItemLabelDriver

    /// Binding required by `.menuBarExtraAccess`; also enables programmatic
    /// dropdown control if ever needed.
    @State private var isMenuPresented = false

    /// The hook HTTP server that receives events from Claude Code
    private let hookServer = HookHTTPServer()

    /// Task for the hook server event loop (allows cancellation on toggle off)
    @State private var hookServerTask: Task<Void, Never>?

    /// Alerts users when quota status degrades
    private let quotaAlerter = NotificationAlerter()

    /// Sends session start/end notifications
    private let sessionAlertSender = SystemAlertSender()

    #if ENABLE_SPARKLE
    /// Sparkle updater for auto-updates
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let provenance = BuildProvenance.current
        AppLog.ui.info("ClaudeBar v\(version) (\(build)) initializing — git \(provenance.gitSHA), built \(provenance.builtAtUTC), dirty=\(provenance.isDirty)")

        // Create the shared settings repository (JSON-backed: ~/.claudebar/settings.json)
        // JSONSettingsRepository implements all sub-protocols:
        // - AppSettingsRepository (app-level display/sync settings)
        // - ProviderSettingsRepository + all provider sub-protocols
        // - HookSettingsRepository
        let settingsRepository = JSONSettingsRepository.shared

        // Seed known Yoyaku Claude profiles so each isolated config directory
        // (e.g. ~/.claude, ~/.claude-admin) appears as a separate account.
        ClaudeBarApp.seedClaudeAccountsIfNeeded(settingsRepository: settingsRepository)
        // Backfill email on accounts that were seeded before the resolver
        // was wired (Ben 2026-08-19: dashboard couldn't tell which Claude
        // account was at 0% because the email was missing).
        ClaudeBarApp.backfillClaudeAccountEmailsIfNeeded(settingsRepository: settingsRepository)

        // Create all providers with their probes (rich domain models)
        // Each provider manages its own isEnabled state (persisted via ProviderSettingsRepository)
        // Each probe checks isAvailable() for credentials/prerequisites
        let repository = AIProviders(providers: [
            ClaudeProvider(
                cliProbe: ClaudeUsageProbe(),
                apiProbe: ClaudeAPIUsageProbe(),
                passProbe: ClaudePassProbe(),
                settingsRepository: settingsRepository,
                dailyUsageAnalyzer: ClaudeDailyUsageAnalyzer(),
                cliProbeFactory: { configDir in
                    if let configDir {
                        return ClaudeUsageProbe(configDirectory: configDir)
                    }
                    return ClaudeUsageProbe()
                },
                apiProbeFactory: { configDir in
                    if let configDir {
                        return ClaudeAPIUsageProbe(configDirectory: configDir)
                    }
                    return ClaudeAPIUsageProbe()
                }
            ),
            CodexProvider(
                rpcProbe: CodexUsageProbe(),
                apiProbe: CodexAPIUsageProbe(),
                settingsRepository: settingsRepository
            ),
            GeminiProvider(probe: GeminiUsageProbe(), settingsRepository: settingsRepository),
            AntigravityProvider(probe: AntigravityUsageProbe(), settingsRepository: settingsRepository),
            // Ecosystem quota SSOT: Qwen (CGU-mandated manual quota — no API
            // polling, ever) + any provider whose native probe is disabled.
            // Natively-enabled providers are skipped so rows never duplicate.
            // Phase 0c (2026-08-19): qwen_personal_pro → alibaba entry added so
            // the LLMRouterProvider stops emitting its own qwen_personal_pro row
            // when the native Alibaba probe is enabled. Without this, ClaudeBar
            // shows the same Qwen plan twice: once via the LLM-router adapter
            // and once via AlibabaUsageProbe (which currently fails on
            // ConsoleNeedLogin). Cookie-based source (Phase 2b) is a separate
            // concern — the skipSlugs entry alone fixes the duplicate today.
            LLMRouterProvider(
                probe: LLMRouterStateProbe(
                    skipSlugs: [
                        ("glm_pro", "zai"),
                        ("minimax_max", "minimax"),
                        ("kimi", "kimi"),
                        ("bedrock", "bedrock"),
                        ("qwen_personal_pro", "alibaba"),
                    ]
                    .filter { settingsRepository.isEnabled(forProvider: $0.1, defaultValue: true) }
                    .map(\.0)
                ),
                settingsRepository: settingsRepository
            ),
            ZaiProvider(
                probe: ZaiUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            CopilotProvider(
                billingProbe: CopilotUsageProbe(settingsRepository: settingsRepository),
                internalProbe: CopilotInternalAPIProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            BedrockProvider(
                probe: BedrockUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            AmpCodeProvider(probe: AmpCodeUsageProbe(), settingsRepository: settingsRepository),
            KimiProvider(
                cliProbe: KimiCLIUsageProbe(),
                apiProbe: KimiUsageProbe(),
                settingsRepository: settingsRepository
            ),
            KiroProvider(probe: KiroUsageProbe(), settingsRepository: settingsRepository),
            CursorProvider(probe: CursorUsageProbe(), settingsRepository: settingsRepository),
            MiniMaxProvider(
                probe: MiniMaxUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            DeepSeekProvider(
                probe: DeepSeekUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            VercelProvider(
                probe: VercelUsageProbe(settingsRepository: settingsRepository),
                settingsRepository: settingsRepository
            ),
            AlibabaProvider(
                probe: AlibabaUsageProbe(settingsRepository: settingsRepository, cookieProvider: AlibabaBrowserCookieProvider()),
                settingsRepository: settingsRepository
            ),
            MistralProvider(
                probe: MistralUsageProbe(),
                settingsRepository: settingsRepository
            ),
            OpenCodeProvider(
                probe: OpenCodeUsageProbe(),
                settingsRepository: settingsRepository
            ),
            OmpProvider(
                probe: OmpUsageProbe(),
                settingsRepository: settingsRepository
            ),
            GrokProvider(
                probe: GrokUsageProbe(),
                settingsRepository: settingsRepository
            ),
        ])
        AppLog.providers.info("Created \(repository.all.count) providers")

        // Initialize the domain service with quota alerter
        // QuotaMonitor automatically validates selected provider on init
        let monitor = QuotaMonitor(
            providers: repository,
            alerter: quotaAlerter
        )
        self.monitor = monitor
        AppLog.monitor.info("QuotaMonitor initialized")

        let sessionMonitor = SessionMonitor()
        self.sessionMonitor = sessionMonitor

        // The driver owns the menu-bar pixels and the refresh-loop lifecycle
        // (outside SwiftUI — see StatusItemLabelDriver). Pixels start flowing
        // once `.menuBarExtraAccess` hands over the NSStatusItem.
        statusItemDriver = StatusItemLabelDriver(
            monitor: monitor,
            settings: AppSettings.shared,
            sessionMonitor: sessionMonitor
        )
        statusItemDriver.startMonitoringLifecycle()

        // Load user extensions from ~/.claudebar/extensions/
        let extensionRegistry = ExtensionRegistry(
            settingsRepository: settingsRepository,
            configRepository: AppSettings.shared.extensionConfig
        )
        let extensionProviders = extensionRegistry.loadExtensions(into: monitor)
        if !extensionProviders.isEmpty {
            AppLog.providers.info("Loaded \(extensionProviders.count) extension provider(s): \(extensionProviders.map(\.name).joined(separator: ", "))")
        }

        // Start hook server if hooks are enabled
        if settingsRepository.isHookEnabled() {
            // Reconcile installed hooks so newly-added events (e.g.
            // UserPromptSubmit, which revives a stopped session) register for
            // existing users without re-toggling the setting. install() is
            // idempotent — it replaces only ClaudeBar's own matcher entries
            // per event and preserves hooks from other tools.
            if HookInstaller.isInstalled() {
                try? HookInstaller.install()
            }
            startHookServer()
        }

        // Note: Notification permission is requested in onAppear, not here
        // Menu bar apps need the run loop to be active before requesting permissions

        AppLog.ui.info("ClaudeBar initialization complete")
    }

    /// App settings for theme
    @State private var settings = AppSettings.shared

    /// Current theme mode from settings
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    private func startHookServer() {
        // Cancel any existing server task
        hookServerTask?.cancel()
        hookServer.stop()

        hookServerTask = Task {
            do {
                let events = try await hookServer.start()
                AppLog.hooks.info("Hook server started, listening for events")
                for await event in events {
                    // Ignore ClaudeBar's own background quota probe so routine
                    // polling doesn't spam "Claude Code Finished: Probe"
                    // notifications or pollute the recent-sessions list. (issue #172)
                    guard !event.isClaudeBarProbe else { continue }
                    await sessionMonitor.processEvent(event)
                    await sendSessionNotification(for: event)
                }
            } catch {
                AppLog.hooks.error("Failed to start hook server: \(error.localizedDescription)")
            }
        }
    }

    func stopHookServer() {
        hookServerTask?.cancel()
        hookServerTask = nil
        hookServer.stop()
    }

    @MainActor private func sendSessionNotification(for event: SessionEvent) {
        let projectName = (event.cwd as NSString).lastPathComponent

        switch event.eventName {
        case .sessionStart:
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Started",
                    body: "Session started in \(projectName)",
                    categoryIdentifier: "SESSION_START"
                )
            }
        case .sessionEnd:
            let taskCount = sessionMonitor.recentSessions.first?.completedTaskCount ?? 0
            let duration = sessionMonitor.recentSessions.first?.durationDescription ?? ""
            let summary = taskCount > 0
                ? "Completed \(taskCount) task\(taskCount == 1 ? "" : "s") in \(duration)"
                : "Session ended after \(duration)"
            Task {
                try? await sessionAlertSender.send(
                    title: "Claude Code Finished",
                    body: "\(projectName) — \(summary)",
                    categoryIdentifier: "SESSION_END"
                )
            }
        default:
            break
        }
    }

    /// Detects and validates isolated Claude config directories on first run.
    /// Existing accounts are authoritative and are never replaced or pruned.
    static func seedClaudeAccountsIfNeeded(settingsRepository: any MultiAccountSettingsRepository) {
        let existing = settingsRepository.accounts(forProvider: "claude")
        let discovered = ClaudeAccountDiscovery().discover(existing: existing)
        guard existing.isEmpty else { return }
        for candidate in discovered {
            settingsRepository.addAccount(
                candidate,
                forProvider: "claude"
            )
        }
    }

    /// Backfills the `email` field on existing Claude accounts that were
    /// seeded before the resolver was wired. Runs unconditionally on
    /// every startup — cheap (one file read per account) and idempotent.
    /// Skips accounts that already have an email. Resolves via
    /// `ClaudeAccountInfoResolver` against `<configDir>/.claude.json`
    /// (or `~/.claude.json` for the default account where configDir == HOME).
    /// Ben 2026-08-19: needed to tell which Claude account was at 0%.
    static func backfillClaudeAccountEmailsIfNeeded(settingsRepository: any MultiAccountSettingsRepository) {
        for config in settingsRepository.accounts(forProvider: "claude") {
            guard config.email == nil else { continue }
            guard let configDir = config.probeConfig["claudeConfigDir"] else { continue }
            let jsonPath = (configDir as NSString).appendingPathComponent(".claude.json")
            guard FileManager.default.fileExists(atPath: jsonPath) else { continue }
            let resolver = ClaudeAccountInfoResolver(configURL: URL(fileURLWithPath: jsonPath))
            guard let email = resolver.resolve()?.email else { continue }
            settingsRepository.updateAccount(
                ProviderAccountConfig(
                    accountId: config.accountId,
                    label: config.label,
                    email: email,
                    organization: config.organization,
                    probeConfig: config.probeConfig
                ),
                forProvider: "claude"
            )
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                #if ENABLE_SPARKLE
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                    .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                MenuContentView(monitor: monitor, sessionMonitor: sessionMonitor, quotaAlerter: quotaAlerter) { enabled in
                        if enabled { startHookServer() } else { stopHookServer() }
                    }
                    .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
            // Opening/closing the dropdown flips `isMenuPresented`, which makes
            // SwiftUI re-evaluate the scene and wipe the AppKit-drawn button
            // image. The dropdown's lifecycle maps 1:1 to those flips, so
            // re-assert the menu-bar pixels on both edges.
            .onAppear { statusItemDriver.reassertPresentation() }
            .onDisappear { statusItemDriver.reassertPresentation() }
        } label: {
            // Deliberately static: the menu-bar pixels are drawn by
            // StatusItemLabelDriver into the status item's button image,
            // because this SwiftUI label hosting can permanently stop
            // re-evaluating after system sleep (issue #192). The placeholder
            // only gives the scene a label to anchor the dropdown to.
            Color.clear.frame(width: 1, height: 1)
        }
        // Must be the first scene modifier (extends MenuBarExtra, not Scene).
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            statusItemDriver.attach(statusItem)
        }
        .menuBarExtraStyle(.window)

        // Standalone Settings window (opened from the popover's gear button).
        // Hidden title bar: the sidebar runs the full window height and the
        // traffic lights overlay its top — see SettingsWindowView.
        Window("ClaudeBar Settings", id: "settings") {
            Group {
                #if ENABLE_SPARKLE
                SettingsWindowView(monitor: monitor) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
                #else
                SettingsWindowView(monitor: monitor) { enabled in
                    if enabled { startHookServer() } else { stopHookServer() }
                }
                .appThemeProvider(themeModeId: settings.themeMode)
                #endif
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)
    }

}

private func sessionPhaseColor(_ phase: ClaudeSession.Phase) -> Color {
    phase.color
}

/// The menu bar icon that reflects the overall quota status.
/// When a Claude Code session is active, shows a terminal icon with phase color.
/// Uses theme's `statusBarIconName` if set, otherwise shows status-based icons.
struct StatusBarIcon: View {
    let status: QuotaStatus
    var activeSession: ClaudeSession? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        if let session = activeSession {
            // Active session: show terminal icon with phase color
            HStack(spacing: 3) {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(sessionPhaseColor(session.phase))
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor)
            }
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        // Use theme's custom icon if provided
        if let themeIcon = theme.statusBarIconName {
            return themeIcon
        }
        // Otherwise use status-based icon
        switch status {
        case .depleted:
            return "chart.bar.xaxis"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning, .healthy:
            return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        theme.statusColor(for: status)
    }
}

// MARK: - StatusBarIcon Preview

#Preview("StatusBarIcon - All States") {
    HStack(spacing: 30) {
        VStack {
            StatusBarIcon(status: .healthy)
            Text("HEALTHY")
                .font(.caption)
                .foregroundStyle(.green)
        }
        VStack {
            StatusBarIcon(status: .warning)
            Text("WARNING")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        VStack {
            StatusBarIcon(status: .critical)
            Text("CRITICAL")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .depleted)
            Text("DEPLETED")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "cli")
            Text("CLI")
                .font(.caption)
                .foregroundStyle(CLITheme().accentPrimary)
        }
        VStack {
            StatusBarIcon(status: .healthy)
                .appThemeProvider(themeModeId: "christmas")
            Text("CHRISTMAS")
                .font(.caption)
                .foregroundStyle(ChristmasTheme().accentPrimary)
        }
    }
    .padding(40)
    .background(Color.black)
}
