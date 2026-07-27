import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuCardUpcomingResetsTests {
    @Test
    @MainActor
    func `upcoming resets display defaults off and persists`() throws {
        let suite = "MenuCardUpcomingResetsTests-setting"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.showUpcomingResets == false)
        store.showUpcomingResets = true

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.showUpcomingResets == true)
    }

    @Test
    func `menu card omits upcoming resets when setting is off`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(3600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: 5 * 60,
                resetsAt: reset,
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            showUpcomingResets: false,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let resetText = try #require(model.metrics.first?.resetText)
        #expect(resetText == "Resets in 1h")
        #expect(!resetText.contains("Then"))
    }

    @Test
    func `menu card appends upcoming resets when setting is on`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(3600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: 5 * 60,
                resetsAt: reset,
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            showUpcomingResets: true,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let resetText = try #require(model.metrics.first?.resetText)
        #expect(resetText == "Resets in 1h\nThen 6h · 11h · 16h")
    }

    @Test
    func `menu card upcoming resets honor absolute date style`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(3600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: 5 * 60,
                resetsAt: reset,
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .absolute,
            showUpcomingResets: true,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let resetText = try #require(model.metrics.first?.resetText)
        let primaryStamp = UsageFormatter.resetDescription(from: reset, now: now)
        let nextStamp = UsageFormatter.resetTimestampDescription(from: reset.addingTimeInterval(5 * 3600))
        #expect(resetText.hasPrefix("Resets \(primaryStamp)\nThen "))
        #expect(resetText.contains(nextStamp))
        #expect(!resetText.contains("Resets in"))
    }
}
