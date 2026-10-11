import CodexBarCore
import Foundation

extension SettingsStore {
    var grokBotUsageEnabled: Bool {
        get { self.configSnapshot.providerConfig(for: .grok)?.grokBotUsageEnabled ?? false }
        set {
            self.updateProviderConfig(provider: .grok) { $0.grokBotUsageEnabled = newValue }
        }
    }

    /// Provider-specific by design: Grok Bot readings belong to the linked Cursor credential scope.
    var grokBotCredentialScope: String {
        GrokBotUsageEnrichment.credentialScope(
            cursor: self.resolvedCookieSettings(provider: .cursor, tokenOverride: nil),
            grok: self.grokSettingsSnapshot(tokenOverride: nil))
    }

    /// Opt-out or linked credential changes hide only Bot usage, including saved-account snapshots.
    func grokBotUsageFilteredSnapshot(_ snapshot: UsageSnapshot?, provider: ProviderInstanceID) -> UsageSnapshot? {
        guard provider == .grok, let snapshot else { return snapshot }
        guard self.grokBotUsageEnabled, snapshot.grokBotCredentialScope == self.grokBotCredentialScope else {
            return GrokBotUsageEnrichment.removingBotUsage(from: snapshot)
        }
        return snapshot
    }

    var grokUsageDataSource: ProviderSourceMode {
        get { self.configSnapshot.providerConfig(for: .grok)?.source ?? .auto }
        set {
            self.updateProviderConfig(provider: .grok) { entry in
                entry.source = newValue == .auto ? nil : newValue
            }
            self.logProviderModeChange(provider: .grok, field: "source", value: newValue.rawValue)
        }
    }

    var grokCookieHeader: String {
        get { self[providerConfig: .grok, field: .cookieHeader] }
        set { self[providerConfig: .grok, field: .cookieHeader] = newValue }
    }

    var grokCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .grok, fallback: .auto) }
        set { self.setCookieSource(newValue, provider: .grok) }
    }
}

extension SettingsStore {
    func grokSettingsSnapshot(tokenOverride: TokenAccountOverride?)
        -> ProviderSettingsSnapshot
        .GrokProviderSettings
    {
        let account = ProviderTokenAccountSelection.selectedAccount(
            provider: .grok,
            settings: self,
            override: tokenOverride)
        let resolved = GrokCredentialRouting.cookieSettings(
            configuredSource: self.grokCookieSource,
            configuredHeader: self.grokCookieHeader,
            selectedAccountToken: account?.token)
        // Provider-specific by design: Bot usage keeps the linked Cursor account's source policy.
        let cursorCookies: ProviderSettingsSnapshot.CookieProviderSettings = self.resolvedCookieSettings(
            provider: .cursor, tokenOverride: nil)
        let configuredCursorSource = self.configSnapshot.providerConfig(for: .cursor)?.cookieSource ?? .auto
        let botCookieSource: ProviderCookieSource? = if configuredCursorSource == .off {
            .off
        } else if self.debugDisableKeychainAccess,
                  configuredCursorSource == .auto,
                  CookieHeaderNormalizer.normalize(cursorCookies.manualCookieHeader) == nil
        {
            .auto
        } else {
            nil
        }
        return GrokProviderSettings(
            cookieSource: resolved.cookieSource,
            manualCookieHeader: resolved.manualCookieHeader,
            grokBotUsageEnabled: self.grokBotUsageEnabled,
            // Provider-specific by design: Bot source policy and refresh ownership follow Cursor independently.
            grokBotSourceMode: self.configSnapshot.providerConfig(for: .cursor)?.source ?? .auto,
            grokBotCursorCookieSource: botCookieSource)
    }
}

extension UsageStore {
    func linkedCredentialScopeSignature(for provider: UsageProvider) -> String? {
        guard provider == .grok, self.settings.grokBotUsageEnabled else { return nil }
        return "\(self.settings.grokBotCredentialScope)|\(self.settings.providerConfigRevision(for: .cursor))"
    }

    func reconcileGrokBotUsageOwnership() {
        self.snapshots[.grok] = self.settings.grokBotUsageFilteredSnapshot(self.snapshots[.grok], provider: .grok)
        self.lastKnownResetSnapshots[.grok] = self.settings.grokBotUsageFilteredSnapshot(
            self.lastKnownResetSnapshots[.grok], provider: .grok)
        self.accountSnapshots[.grok] = self.accountSnapshots[.grok]?.map {
            self.grokBotUsageFilteredAccountSnapshot($0, provider: .grok)
        }
    }

    func grokBotUsageFilteredAccountSnapshot(
        _ cached: TokenAccountUsageSnapshot, provider: UsageProvider) -> TokenAccountUsageSnapshot
    {
        guard provider == .grok else { return cached }
        return TokenAccountUsageSnapshot(
            account: cached.account,
            snapshot: self.settings.grokBotUsageFilteredSnapshot(cached.snapshot, provider: .grok),
            error: cached.error,
            sourceLabel: cached.sourceLabel,
            cacheKey: cached.cacheKey,
            fetchError: cached.fetchError)
    }
}
