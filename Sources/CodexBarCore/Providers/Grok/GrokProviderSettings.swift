import Foundation

public struct GrokProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?
    public let grokBotUsageEnabled: Bool
    public let grokBotSourceMode: ProviderSourceMode
    /// Preserves explicit Off and automatic local-session routing when shared settings resolve cookies as manual.
    public let grokBotCursorCookieSource: ProviderCookieSource?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.init(cookieSource: cookieSource, manualCookieHeader: manualCookieHeader, grokBotUsageEnabled: false)
    }

    public init(
        cookieSource: ProviderCookieSource,
        manualCookieHeader: String?,
        grokBotUsageEnabled: Bool,
        grokBotSourceMode: ProviderSourceMode = .auto,
        grokBotCursorCookieSource: ProviderCookieSource? = nil)
    {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
        self.grokBotUsageEnabled = grokBotUsageEnabled
        self.grokBotSourceMode = grokBotSourceMode
        self.grokBotCursorCookieSource = grokBotCursorCookieSource
    }
}

public enum GrokProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.grok
    public typealias Section = GrokProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias GrokProviderSettings = CodexBarCore.GrokProviderSettings
    public var grok: GrokProviderSettings? {
        self[GrokProviderSettingsKey.self]
    }

    public static func make(grok: GrokProviderSettings?) -> Self {
        self.make(grok, for: GrokProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func grok(_ section: GrokProviderSettings) -> Self {
        Self(section, for: GrokProviderSettingsKey.self)
    }
}
