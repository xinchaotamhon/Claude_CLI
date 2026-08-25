# External Codex App isolation repair — 2026-08-25

## Owner observation

Codex App displayed `Claude Code Router` in its lower-left account/provider
surface and no longer displayed normal Usage. The owner required this project
to remain independent inside `D:\mydata\new-git-3\claude_CLI-V`.

## Proved cause

CCR source maps profile scope `global` to the UI label `System default` and
surface `auto` to `CLI & APP`. For a Codex profile in global scope,
`applyCodexProfile` resolves the default file to `~/.codex/config.toml`, writes
the provider name (default `Claude Code Router`), model catalog and loopback
gateway endpoint, and records a takeover marker for later restoration.

The external Codex config was inspected only for fixed CCR markers, gateway URL
and SHA-256; auth, tokens and arbitrary config values were not printed.

Before repair:

- active config SHA-256:
  `4A75B82802C9F59B8119D8B5433FA4D2F82A3BDCA44054609D84B07933463BFC`;
- CCR root/provider markers: present;
- provider name `Claude Code Router`: present;
- loopback gateway `127.0.0.1:3456`: present;
- project-local `global-profile-takeover.json`: present.

CCR's two clean snapshots were byte-identical, both SHA-256
`281FBC9C6183FBA5CDED167A4A4552F53E17A230CD27DBA344D43D9076C92671`,
and neither contained a CCR marker or loopback gateway URL.

The missing Usage surface is consistent with Codex App being switched from its
first-party ChatGPT provider to a custom local model provider. That UI
consequence is a source-backed inference; the config takeover itself is proved.

## Repair applied

The project forced a config synchronization that removed all CCR agent
profiles and used `saveConfig` with profile cleanup enabled. CCR restored the
external config on disk from its own clean snapshot. The currently running
Codex App may retain the previous provider in memory until it is fully closed
and reopened.

After repair:

- active config SHA-256 equals the clean snapshot SHA-256 above;
- CCR root/provider markers: absent;
- provider name `Claude Code Router`: absent;
- loopback gateway URL: absent;
- project-local takeover marker: absent.

Normal project entry points now enforce the boundary:

- all `config.profile.profiles` entries are removed before save;
- a local takeover marker invalidates the settings fast path and forces cleanup;
- profile cleanup is applied during settings sync and account import;
- `RUN_CLAUDE.bat --router-ui` and account-menu option `[2]` were removed;
- API providers are configured only through ignored `setting.json`;
- project-local Codex browser accounts remain under `.ccr-local`.

## External artifact cleanup

The owner explicitly authorized removal of the eight previously identified CCR
artifacts. The cleanup named seven files and the `.claude-code-router`
directory literally; it used no wildcard and touched no active config, auth or
history path. All eight targets are absent after deletion. The active config
still has SHA-256
`281FBC9C6183FBA5CDED167A4A4552F53E17A230CD27DBA344D43D9076C92671`.

## Verification and rollback

- Focused gate: `claude.external-app-isolation`.
- Final cumulative run `20260825T043650Z-959db717`: all 9 enabled smoke
  gates passed, including DPAPI under the owner's Windows profile.
- Post-gate recheck: active global config still matched the clean SHA-256;
  marker/provider/loopback checks remained false, takeover marker remained
  absent and project router ports had no listeners. A later owner-authorized
  exact cleanup removed all eight inactive external artifacts without changing
  the active config hash.
- Existing setting, account and router gates remain required.
- Owner visual check still required: reopen Codex App and confirm the normal
  account label and Usage surface return.
- Rollback of project code: revert the agent-profile removal, `applyProfile`
  cleanup, UI removal, gate and documentation together. This rollback is not
  recommended because it restores the demonstrated external takeover path.
