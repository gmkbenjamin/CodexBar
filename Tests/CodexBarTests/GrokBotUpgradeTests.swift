import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct GrokBotUpgradeTests {
    @Test
    func `stable 0 74 settings and accounts survive upgrade with Bot tracking off`() throws {
        let url = try #require(Bundle.module.url(
            forResource: "grok-bot-upgrade-v0.74.0", withExtension: "json", subdirectory: "Fixtures/Config"))
        let original = try Data(contentsOf: url)
        let configStore = testConfigStore(suiteName: "GrokBotUpgradeTests-stable")
        try configStore.saveEncodedData(original)
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(),
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        defer { settings.configFileWatcher?.stop() }
        #expect(!settings.grokBotUsageEnabled)
        #expect(settings.providerConfig(for: .grok)?.grokBotUsageEnabled == nil)
        #expect(settings.tokenAccounts(for: .grok).map(\.label) == ["Personal", "Work"])
        #expect(settings.selectedTokenAccount(for: .grok)?.label == "Work")
        #expect(settings.selectedTokenAccount(for: .cursor)?.label == "Linked")
        #expect(try configStore.encodedData(for: settings.configSnapshot) == original)

        settings.grokBotUsageEnabled = true
        var updated = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: configStore.fileURL))
            as? [String: Any])
        var providers = try #require(updated["providers"] as? [[String: Any]])
        let index = try #require(providers.firstIndex { $0["id"] as? String == "grok" })
        #expect(providers[index].removeValue(forKey: "grokBotUsageEnabled") as? Bool == true)
        updated["providers"] = providers
        let before = try JSONSerialization.jsonObject(with: original) as? NSDictionary
        #expect((updated as NSDictionary) == before)
        #expect(settings.selectedTokenAccount(for: .grok)?.label == "Work")
        #expect(settings.selectedTokenAccount(for: .cursor)?.token == "fixture-cursor-linked")
    }
}
