# Grok Bot verification

## Real app and CLI behavior

[grok-bot-tracking.png](grok-bot-tracking.png) is the user's screenshot of the installed v0.74.1 feature build. It shows native Grok usage and a separate Bot allowance/reset on the Grok card. It replaces the synthetic preview.

The packaged CLI was run against temporary copies of the configured Grok/Cursor entries, with Cursor tracking disabled. The original configuration was unchanged. [Runtime output](grok-bot-runtime.jsonl) contains an allowlist of result fields; identities, credentials, IPs, endpoints, percentages, and raw server responses are excluded.

Command for each temporary configuration:

```sh
CODEXBAR_CONFIG=/path/to/temporary/config.json \
  CodexBar.app/Contents/Helpers/CodexBarCLI usage --provider grok \
  --source oauth --format json --verbose --json-output
```

Cases: opt-in returns a known Bot allowance; opt-out omits it; Cursor source Off keeps native Grok usage and reports unknown Bot usage. Selecting an invalid saved replacement credential also produces unknown usage instead of falling back to the working ambient account. That replacement is a negative authentication test, not a second authenticated account.

## Linked-account regression

At feature head `224e2efd6ee687bc6a58c4106f1e1a68a557590b`, the initial three `GrokBotOwnershipTests` failed with eight expectations: old Bot usage survived account/source changes in live and saved-account readings, and a suspended request published after the account changed. [Baseline excerpt](grok-bot-baseline.txt) excludes unrelated logs.

The added tests exercise production enrichment, SettingsStore, UsageStore publication, saved-account activation, and timeout preservation with contained configuration and mocked transport. They also cover credential rotation, Cursor enablement, decoded snapshot ownership, and explicit Off when a saved account resolves as Manual. Native Grok usage and identity remain unchanged.

## Existing settings and accounts

The official v0.74.0 CLI archive's published checksum was verified. That CLI saved the [upgrade fixture](../../Tests/CodexBarTests/Fixtures/Config/grok-bot-upgrade-v0.74.0.json), containing only fictitious credentials, two Grok accounts, and one Cursor account.

The new SettingsStore and packaged CLI preserve that fixture byte for byte with Bot tracking off. Enabling tracking preserves every existing field and selected account. The v0.74.0 CLI also retains the new optional setting when resaving. See [upgrade output](grok-bot-upgrade.jsonl).

## Validation

- `make check`: passed, zero lint violations.
- `git diff --check`: passed.
- `make test-fast FILTER='GrokBotOwnershipTests|GrokBotUpgradeTests|GrokBotSettingsTests|GrokBotUsageEnrichmentTests|UsageStoreSupplementalUsageTests|TokenAccountCLISelectionTests'`: 39 tests in six suites passed.
- `make test-skip-build FILTER=ProviderArchitectureGatekeeperTests`: 48 tests passed.
- `./Scripts/test.sh --direct-workers 4`: 150/150 groups passed, complete inventory, no failures, retries, or timeouts. This is the documented parallel full-suite path for `make test`.
- `CODEXBAR_SIGNING=adhoc ARCHES=arm64 ./Scripts/package_app.sh debug`: passed; signature validation passed. The CLI results above use this fresh bundle.

## Placement decision

This proposal uses the existing Grok provider and shared named metric picker, including merged-icon presentation. It adds no dedicated Bot provider or status item. Maintainer confirmation of this placement is still required following [the owner direction on #4340](https://github.com/steipete/CodexBar/issues/4340#issuecomment-6048704175).
