import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ClaudeBackgroundAutoRefreshFailureTests {
    @Test
    func `restrictive background Auto failures preserve last good Claude snapshot`() async throws {
        try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
            let missingCredentialsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-claude-creds-\(UUID().uuidString).json")

            try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(missingCredentialsURL) {
                try await KeychainAccessGate.withTaskOverrideForTesting(true) {
                    let (store, prior) = try await MainActor.run {
                        let settings = Self.makeSettingsStore(
                            suite: "ClaudeBackgroundAutoRefreshFailureTests-preserve")
                        settings.refreshFrequency = .manual
                        settings.statusChecksEnabled = false
                        settings.claudeUsageDataSource = .auto
                        settings.claudeOAuthKeychainPromptMode = .onlyOnUserAction

                        let metadata = ProviderRegistry.shared.metadata
                        for provider in UsageProvider.allCases {
                            try settings.setProviderEnabled(
                                provider: provider,
                                metadata: #require(metadata[provider]),
                                enabled: provider == .claude)
                        }

                        let store = UsageStore(
                            fetcher: UsageFetcher(environment: [:]),
                            browserDetection: BrowserDetection(cacheTTL: 0),
                            settings: settings,
                            startupBehavior: .testing,
                            environmentBase: [:])
                        let prior = UsageSnapshot(
                            primary: RateWindow(
                                usedPercent: 12,
                                windowMinutes: 300,
                                resetsAt: nil,
                                resetDescription: nil),
                            secondary: nil,
                            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                            identity: ProviderIdentitySnapshot(
                                providerID: .claude,
                                accountEmail: "claude@example.com",
                                accountOrganization: nil,
                                loginMethod: "Pro"))
                        store._setSnapshotForTesting(prior, provider: .claude)
                        store._test_providerFetchOutcomeOverride = { _ in
                            Self.unavailableClaudeOutcome()
                        }
                        return (store, prior)
                    }

                    await ProviderInteractionContext.$current.withValue(.background) {
                        await store.refreshProvider(.claude)
                        await store.refreshProvider(.claude)
                    }

                    let result = await MainActor.run {
                        (
                            updatedAt: store.snapshot(for: .claude)?.updatedAt,
                            error: store.error(for: .claude))
                    }
                    #expect(result.updatedAt == prior.updatedAt)
                    #expect(result.error == nil)
                }
            }
        }
    }

    @Test
    func `restrictive background Auto failures stay quiet without prior Claude snapshot`() async throws {
        try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
            let missingCredentialsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-claude-creds-\(UUID().uuidString).json")

            try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(missingCredentialsURL) {
                try await KeychainAccessGate.withTaskOverrideForTesting(true) {
                    let store = try await MainActor.run {
                        let settings = Self.makeSettingsStore(
                            suite: "ClaudeBackgroundAutoRefreshFailureTests-quiet-empty")
                        settings.refreshFrequency = .manual
                        settings.statusChecksEnabled = false
                        settings.claudeUsageDataSource = .auto
                        settings.claudeOAuthKeychainPromptMode = .onlyOnUserAction

                        let metadata = ProviderRegistry.shared.metadata
                        for provider in UsageProvider.allCases {
                            try settings.setProviderEnabled(
                                provider: provider,
                                metadata: #require(metadata[provider]),
                                enabled: provider == .claude)
                        }

                        let store = UsageStore(
                            fetcher: UsageFetcher(environment: [:]),
                            browserDetection: BrowserDetection(cacheTTL: 0),
                            settings: settings,
                            startupBehavior: .testing,
                            environmentBase: [:])
                        store._test_providerFetchOutcomeOverride = { _ in
                            Self.unavailableClaudeOutcome()
                        }
                        return store
                    }

                    await ProviderInteractionContext.$current.withValue(.background) {
                        await store.refreshProvider(.claude)
                    }

                    let result = await MainActor.run {
                        (
                            snapshot: store.snapshot(for: .claude),
                            error: store.error(for: .claude))
                    }
                    #expect(result.snapshot == nil)
                    #expect(result.error == nil)
                }
            }
        }
    }

    @Test
    func `background Auto unavailable strategy matches restrictive Keychain settings`() {
        #expect(ClaudeBackgroundAutoRefreshFailure.matches(
            provider: .claude,
            error: ProviderFetchError.noAvailableStrategy(.claude),
            source: .auto,
            interaction: .background,
            keychainSettingsRequireUserAction: true))
    }

    @Test
    func `Claude unavailable strategy remains concrete outside restrictive background Auto`() {
        let error = ProviderFetchError.noAvailableStrategy(.claude)

        #expect(!ClaudeBackgroundAutoRefreshFailure.matches(
            provider: .claude,
            error: error,
            source: .cli,
            interaction: .background,
            keychainSettingsRequireUserAction: true))
        #expect(!ClaudeBackgroundAutoRefreshFailure.matches(
            provider: .claude,
            error: error,
            source: .auto,
            interaction: .userInitiated,
            keychainSettingsRequireUserAction: true))
        #expect(!ClaudeBackgroundAutoRefreshFailure.matches(
            provider: .claude,
            error: error,
            source: .auto,
            interaction: .background,
            keychainSettingsRequireUserAction: false))
    }

    @Test
    func `Disable Keychain background Auto surfaces no-strategy instead of staying quiet`() async throws {
        try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
            let missingCredentialsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-claude-creds-\(UUID().uuidString).json")

            try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(missingCredentialsURL) {
                try await KeychainAccessGate.withTaskOverrideForTesting(true) {
                    let store = try await MainActor.run {
                        let settings = Self.makeSettingsStore(
                            suite: "ClaudeBackgroundAutoRefreshFailureTests-disable-keychain-error")
                        settings.refreshFrequency = .manual
                        settings.statusChecksEnabled = false
                        settings.claudeUsageDataSource = .auto
                        settings.debugDisableKeychainAccess = true
                        settings.claudeOAuthKeychainPromptMode = .onlyOnUserAction

                        let metadata = ProviderRegistry.shared.metadata
                        for provider in UsageProvider.allCases {
                            try settings.setProviderEnabled(
                                provider: provider,
                                metadata: #require(metadata[provider]),
                                enabled: provider == .claude)
                        }

                        let store = UsageStore(
                            fetcher: UsageFetcher(environment: [:]),
                            browserDetection: BrowserDetection(cacheTTL: 0),
                            settings: settings,
                            startupBehavior: .testing,
                            environmentBase: [:])
                        store._test_providerFetchOutcomeOverride = { _ in
                            Self.unavailableClaudeOutcome()
                        }
                        return store
                    }

                    await ProviderInteractionContext.$current.withValue(.background) {
                        await store.refreshProvider(.claude)
                    }

                    let result = await MainActor.run {
                        (
                            snapshot: store.snapshot(for: .claude),
                            error: store.error(for: .claude))
                    }
                    #expect(result.snapshot == nil)
                    #expect(result.error != nil)
                }
            }
        }
    }

    @MainActor
    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        return settings
    }

    private static func unavailableClaudeOutcome() -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .failure(ProviderFetchError.noAvailableStrategy(.claude)),
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "claude.oauth",
                    kind: .oauth,
                    wasAvailable: false,
                    errorDescription: nil),
                ProviderFetchAttempt(
                    strategyID: "claude.cli",
                    kind: .cli,
                    wasAvailable: false,
                    errorDescription: nil),
            ])
    }
}
