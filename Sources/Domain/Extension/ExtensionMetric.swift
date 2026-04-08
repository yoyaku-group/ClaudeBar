import Foundation

/// A generic metric value displayed by extension sections.
/// Used for custom data that doesn't fit the standard quota/cost/daily models.
public struct ExtensionMetric: Sendable, Equatable, Codable {
    public let label: String
    public let value: String
    public let unit: String
    public let icon: String?
    public let color: String?
    public let delta: MetricDelta?
    public let progress: Double?

    public init(
        label: String,
        value: String,
        unit: String,
        icon: String? = nil,
        color: String? = nil,
        delta: MetricDelta? = nil,
        progress: Double? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
        self.delta = delta
        self.progress = progress
    }
}

/// Comparison delta for a metric (e.g., "Vs Mar 16 -$701.58 (98.6%)")
public struct MetricDelta: Sendable, Equatable, Codable {
    public let vs: String
    public let value: String
    public let percent: Double?

    public init(vs: String, value: String, percent: Double? = nil) {
        self.vs = vs
        self.value = value
        self.percent = percent
    }
}

/// Status information for a status banner section.
public struct StatusInfo: Sendable, Equatable, Codable {
    public let text: String
    public let level: StatusLevel

    public init(text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }
}

/// Severity level for status banners.
public enum StatusLevel: String, Sendable, Equatable, Codable {
    case healthy
    case warning
    case critical
    case inactive
}
