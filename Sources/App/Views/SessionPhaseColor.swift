import SwiftUI
import Domain

extension ClaudeSession.Phase {
    /// The display color for this session phase.
    /// Single source of truth — used by StatusBarIcon, SessionIndicatorView, etc.
    var color: Color {
        switch self {
        case .active: return CLITheme.green
        case .subagentsWorking: return CLITheme.blue
        case .stopped: return CLITheme.amber
        case .ended: return CLITheme.gray
        }
    }
}
