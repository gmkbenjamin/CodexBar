import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct GrokBotOwnershipTests {
    @Test
    func `switching Cursor accounts hides only Bot usage even when the next refresh times out`() async throws {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-switch")
        defer { fixture.settings.configFileWatcher?.stop() }
        let original = try await Self.enrichedSnapshot(settings: fixture.settings)
        fixture.store.snapshots[.grok] = original
        fixture.settings.addTokenAccount(provider: .grok, label: "Grok", token: "grok-fixture")
        let grokAccount = try #require(fixture.settings.effectiveSelectedTokenAccount(for: .grok))
        fixture.store.cacheTokenAccountSnapshot(
            provider: .grok, account: grokAccount, snapshot: original, sourceLabel: "grok-fixture")
        #expect(fixture.store.snapshot(for: .grok)?.extraRateWindows?.first?.window.usedPercent == 42)

        fixture.settings.setActiveTokenAccountIndex(1, for: .cursor)
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
        let cached = fixture.store.validTokenAccountSnapshots(provider: .grok, accounts: [grokAccount])
        try Self.expectNativeUsageOnly(#require(cached.first?.snapshot))
        fixture.store.activateCachedTokenAccountSnapshot(provider: .grok, accountID: grokAccount.id)
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))

        fixture.store._test_providerFetchOutcomeOverride = { _ in
            ProviderFetchOutcome(result: .failure(URLError(.timedOut)), attempts: [])
        }
        await fixture.store.refreshProvider(.grok, allowDisabled: true)
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
    }

    @Test
    func `a Cursor account change rejects a suspended Grok refresh result`() async throws {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-in-flight")
        defer { fixture.settings.configFileWatcher?.stop() }
        let original = try await Self.enrichedSnapshot(settings: fixture.settings)
        fixture.store.snapshots[.grok] = original
        let gate = GrokBotOwnershipGate()
        fixture.store._test_providerFetchOutcomeOverride = { _ in
            await gate.wait()
            return ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: original.replacing(primary: .value(Self.rateWindow(usedPercent: 91))),
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "grok-fixture",
                    strategyID: "fixture",
                    strategyKind: .web)),
                attempts: [])
        }
        let refresh = Task { await fixture.store.refreshProvider(.grok, allowDisabled: true) }
        await gate.waitUntilStarted()
        fixture.settings.setActiveTokenAccountIndex(1, for: .cursor)
        await gate.resume()
        await refresh.value
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
    }

    @Test(arguments: [ProviderCookieSource.off, .auto])
    func `changing the linked Cursor source immediately hides the old Bot reading`(
        source: ProviderCookieSource) async throws
    {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-source-\(source.rawValue)")
        defer { fixture.settings.configFileWatcher?.stop() }
        fixture.store.snapshots[.grok] = try await Self.enrichedSnapshot(settings: fixture.settings)
        fixture.settings.cursorCookieSource = source
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
    }

    @Test
    func `rotating a selected Cursor credential removes the old Bot reading`() async throws {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-rotate")
        defer { fixture.settings.configFileWatcher?.stop() }
        fixture.store.snapshots[.grok] = try await Self.enrichedSnapshot(settings: fixture.settings)
        let cursorAccount = try #require(fixture.settings.effectiveSelectedTokenAccount(for: .cursor))
        fixture.settings.updateTokenAccount(
            provider: .cursor, accountID: cursorAccount.id, token: "cursor-account-a-rotated")
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
        fixture.store.reconcileGrokBotUsageOwnership()
        Self.expectNativeUsageOnly(fixture.store.snapshots[.grok])
    }

    @Test
    func `Cursor tracking enablement does not change Bot credential ownership`() async throws {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-enable")
        defer { fixture.settings.configFileWatcher?.stop() }
        fixture.store.snapshots[.grok] = try await Self.enrichedSnapshot(settings: fixture.settings)
        for enabled in [true, false] {
            fixture.settings.setProviderEnabled(
                provider: .cursor, metadata: CursorProviderDescriptor.descriptor.metadata, enabled: enabled)
            #expect(fixture.store.snapshot(for: .grok)?.extraRateWindows?.first?.window.usedPercent == 42)
        }
    }

    @Test
    func `decoded Bot usage cannot authorize an account scoped reading`() async throws {
        let fixture = try Self.fixture(suite: "GrokBotOwnershipTests-decoded")
        defer { fixture.settings.configFileWatcher?.stop() }
        let snapshot = try await Self.enrichedSnapshot(settings: fixture.settings)
        #expect(snapshot.grokBotCredentialScope != nil)
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(!json.contains("grokBotCredentialScope"))
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: encoded)
        #expect(decoded.grokBotCredentialScope == nil)
        fixture.store.snapshots[.grok] = decoded
        Self.expectNativeUsageOnly(fixture.store.snapshot(for: .grok))
    }

    private static func fixture(suite: String) throws -> ProviderSettingsDescriptorTests.ProviderSettingsFixture {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: suite)
        fixture.settings.refreshFrequency = .manual
        fixture.settings.statusChecksEnabled = false
        fixture.settings.grokBotUsageEnabled = true
        fixture.settings.addTokenAccount(provider: .cursor, label: "A", token: "cursor-account-a")
        fixture.settings.addTokenAccount(provider: .cursor, label: "B", token: "cursor-account-b")
        fixture.settings.setActiveTokenAccountIndex(0, for: .cursor)
        return fixture
    }

    private static func enrichedSnapshot(settings: SettingsStore) async throws -> UsageSnapshot {
        let strategy = GrokBotUsageEnrichment(base: GrokBotOwnershipBaseStrategy()) { _ in
            NamedRateWindow(
                id: CursorSandUsageStatus.extraWindowID,
                title: CursorSandUsageStatus.extraWindowTitle,
                window: Self.rateWindow(usedPercent: 42))
        }
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 5,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: ProviderRegistry.makeSettingsSnapshot(settings: settings, tokenOverride: nil),
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: BrowserDetection(cacheTTL: 0)),
            browserDetection: BrowserDetection(cacheTTL: 0))
        return try await strategy.fetch(context).usage
    }

    private static func expectNativeUsageOnly(_ snapshot: UsageSnapshot?) {
        #expect(snapshot?.primary?.usedPercent == 23)
        #expect(snapshot?.accountEmail(for: .grok) == "grok@example.com")
        #expect(snapshot?.extraRateWindows?.contains { $0.id == CursorSandUsageStatus.extraWindowID } != true)
    }

    fileprivate nonisolated static func rateWindow(usedPercent: Double) -> RateWindow {
        RateWindow(usedPercent: usedPercent, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
    }
}

private struct GrokBotOwnershipBaseStrategy: ProviderFetchStrategy {
    let id = "fixture"
    let kind = ProviderFetchKind.web
    func isAvailable(_: ProviderFetchContext) async -> Bool { true }
    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        self.makeResult(
            usage: UsageSnapshot(
                primary: GrokBotOwnershipTests.rateWindow(usedPercent: 23),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_787_647_576),
                identity: ProviderIdentitySnapshot(
                    providerID: .grok,
                    accountEmail: "grok@example.com",
                    accountOrganization: nil,
                    loginMethod: "SuperGrok")),
            sourceLabel: "grok-fixture")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool { false }
}

private actor GrokBotOwnershipGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        self.started = true
        await withCheckedContinuation { self.continuation = $0 }
    }

    func waitUntilStarted() async {
        while !self.started {
            await Task.yield()
        }
    }

    func resume() {
        self.continuation?.resume()
        self.continuation = nil
    }
}
