import Foundation

public enum HomewardPolicy {
    public static let firmGracePeriod: TimeInterval = 30
    public static var firmGracePeriodDescription: String {
        "\(Int(firmGracePeriod))-second"
    }
    public static let gentleAttentionDelay: TimeInterval = 5
    public static let forceTerminationVerificationDelay: TimeInterval = 2
    public static let launchMetadataRetryDelay: TimeInterval = 0.25
    public static let countdownTick: TimeInterval = 1
    public static let blockedFeedbackCooldown: TimeInterval = 10 * 60
    public static let previewStepTimeout: TimeInterval = 60
    public static let extensionDurationsMinutes = [10, 15, 30]
    public static let gentleShortcutExtensionMinutes = 10
    public static let customCutoffDefaultLeadTime: TimeInterval = 60 * 60
    public static let nextLocalMidnightFallbackInterval: TimeInterval =
        24 * 60 * 60
}
