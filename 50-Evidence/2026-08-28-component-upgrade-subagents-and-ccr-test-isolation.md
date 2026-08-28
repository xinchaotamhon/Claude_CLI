# 2026-08-28 component upgrade, subagents and CCR test isolation

## Scope and baseline

The owner requested current necessary component updates, guidance for native
Claude subagents and an assessment of reusable outcomes for CLOVER. Automatic
fallback remained disabled. Before replacement, the full owner-profile smoke
suite passed 22/22 in run `20260827T183918Z-bdfd45c5`.

No credential, account payload, request body or ignored `setting.json` content
was read into this record.

## Claude Code 2.1.247

- Official release: <https://github.com/anthropics/claude-code/releases/tag/v2.1.247>
- Official Windows x64 archive SHA-256:
  `fc4f2ff5bc4af613f92174a2b9051a52a9c2c557ab45796a248d6811044ef808`
- Installed project-local binary reports `2.1.247 (Claude Code)`.
- Installed SHA-256:
  `00e5be0a8b69893cad9259a1e8b80d59be8f3eb367d4a16c19f91bcd279423b7`.
- Prior `2.1.241` binary was retained under ignored
  `.runtime/update-backups/claude-code/2.1.241`; prior SHA-256 is
  `c49a05922a787c33478067a5164002932235f6611948523b55ae1fbdb303ac1f`.

This release is relevant to the owner request because it repairs a subagent
first-call model-404 path by using the session fallback chain. Native Claude
subagents require no extra repository. The project guide recommends `/agents`,
project scope and `model: inherit`; experimental agent teams remain off because
they create multiple full sessions and consume materially more usage.

## CLIProxyAPI 7.2.143

- Upstream tag: `v7.2.143`
- Upstream commit: `4b5f1eab25fca4b3815369a826e958e7c070a69e`
- Upstream tree: `08ceb94c634abedef9ec1ade765f781261f2f772`
- Four existing project isolation/OAuth patches applied without conflicts.
- Patched commit: `d60235408ba2f2ef8f59f66f6e172b2df6d1ec82`
- Patched tree: `3f2fbceb13baeff5a03de2addcd00ce5a08352e7`
- Focused source tests `go test ./cmd/server ./sdk/auth` passed.
- The pinned source verifier passed against the exact tag, commit order, patch
  hashes, anchors, branch and single upstream remote.
- A second deterministic build reproduced SHA-256
  `95ca070ecb8529dd84f0fce2aa8592fbfcbb7a94a1d3b2ab73d83d87c1237e32`;
  fixture SHA-256 remained
  `f3205d4fa5102b2f8e1d4748dccc028929e84078b9911420116c35122aef48e2`.
- The old `7.2.141-local.4` source and binary remain under ignored
  `.runtime/update-backups/cli-proxy-api`.

OAuth and a live provider request are not claimed for this exact upgraded
binary. Google route promotion still requires an owner browser action followed
by bounded catalog and tool-loop proof.

## CCR 3.0.22 review and rejection

The local source patch cherry-picked cleanly onto exact tag `v3.0.22` and
TypeScript typecheck passed. The core unit suite observed 620 passes, 6 failures
and 15 skips; failures were in upstream Windows/test-fixture/plugin/startup
surfaces. All observed subagent virtual-suffix, route, UTF-8 streaming and model
catalog tests passed.

Promotion was rejected for two independent reasons:

1. the published `3.0.22` minified runtime contained zero matches for each of
   the four exact reviewed `3.0.21` isolation patch anchors; and
2. running the upstream suite directly while the real router/Codex App were
   live exercised a global profile synchronization path.

The rejected review worktree, npm runtime and temporary branch were removed.
Operational source/runtime remain CCR `3.0.21` at fork commit
`ffc823b683861ad3f86c8dd38c0dbe61eef62f6c`.

## External Codex repair and new hard gate

Observed symptom: Codex App displayed **Claude Code Router** in its account
surface. The external Codex directory contained a changed `config.toml` plus
six CCR catalog/config/backup artifacts created at the test time.

Recovery used the matching `config.toml.ccr-original`; that original and CCR's
backup had identical SHA-256
`fe5b1f375c25fc751bef921e222f06cc6a962104b857b949b0ec162363e45037`.
The restored file was hash-verified before exactly six artifacts were removed.
A subsequent scan observed zero CCR-named artifacts and zero CCR/loopback
markers in the external config. The contaminated and restored snapshots are
retained only in ignored project-local rollback storage.

`tools/run_ccr_source_tests_isolated.ps1` is now mandatory. It refuses a live
Codex/ChatGPT App or project dashboard/router, redirects HOME/APPDATA/
LOCALAPPDATA/TEMP/CODEX_HOME/CCR internal paths below the project, enables
provider-only mode and compares an external Codex fingerprint before/after.
The static isolation gate passed and a live refusal was observed while this
Codex App task was open.

## CLOVER contribution assessment

No CLOVER file was changed. Three sanitized reusable candidates are worth a
separate owner-approved Vault/CLOVER admission proposal:

1. recoverable account/provider/session removal with active-process guards;
2. dynamic provider catalog/quota adapters that preserve `unknown` rather than
   hard-code transient model or quota claims; and
3. exact-tag upgrades as reproducible patch series with rollback copies and
   cumulative gates, including isolation of third-party source tests from live
   user applications.

These are project observations, not yet verified Vault resources. Raw logs,
private paths, credentials and account data must not be copied into CLOVER.

## Rollback

- Claude: restore ignored backup `2.1.241`, then restore its tracked checksum
  and lock version in one reviewed commit.
- CLIProxyAPI: stop the challenger, restore the ignored `7.2.141-local.4`
  source/binary backup and the former tracked source/build/patch metadata.
- CCR: no rollback needed because `3.0.22` was never promoted.

## Final gates

All 22 enabled smoke gates passed under the owner profile in
`20260828T021912Z-afe77299`. The run included source pins, project-local Claude
and CCR layout, DPAPI/menu self-test, external-app isolation, Google account
flow, the reproducible offline challenger protocol pilot, dashboard lifecycle,
session trash, terminal cleanup and account management. It made no provider or
model request. A scan after the suite still found zero CCR-named artifacts and
zero CCR/loopback markers in external Codex configuration.
