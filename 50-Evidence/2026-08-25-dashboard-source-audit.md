# EasyCLIProxyAPI dashboard source audit — 2026-08-25

## Outcome

EasyCLIProxyAPI has strong feature overlap but cannot be adopted into this
repository now. Public tag `v0.2.61` was cloned only as an ignored nested source
checkout, inspected and left unmodified/unrun. No release binary or dependency
was downloaded, no OAuth flow was opened, no auth file was read by the app and
no provider request was sent.

Exact identity:

- Upstream: `https://github.com/router-for-me/EasyCLIProxyAPI.git`
- Tag: `v0.2.61`
- Commit: `3d44eba4926cb60b8654576ebf173e613f457fd1`
- Tree: `da48e47ea5b9275ca3d1a3bed874a02e1d93b19f`
- Commit date: `2026-08-23T23:20:40+08:00`
- Local ignored checkout: `dashboard_easycli_source`, branch `claude`
- License: no `LICENSE`, `COPYING` or package license grant was present in the
  tagged tree. Public visibility is not treated as permission to copy, modify
  or distribute.

Tracked `router_challenger/DASHBOARD_SOURCE.json` records source anchors and
`tools/verify_dashboard_source.py` verifies the optional checkout offline.

## Useful behavior observed

- Tauri/React/Rust UI includes local core lifecycle, OAuth pages, API provider
  aggregation, authentication-file management and quota cards.
- Quota parser handles primary/secondary windows and names five-hour and weekly
  windows. This is useful proof that a GUI can present these concepts, but it is
  not evidence that every provider exposes authoritative values.
- Management requests are routed through the CLIProxyAPI management API.

## Blocking behavior observed

- App and core update/download implementation is substantial, including
  portable replacement and automatic installation of a bundled core.
- Agent discovery scans Codex/Claude locations and can build/write agent
  configurations. This recreates the external-App takeover class previously
  removed from this project.
- Windows tray, run-on-startup and background/close behavior are built in.
- Auth-file workflows can inspect, upload, download, open and manage credential
  files.
- The development script uses Vite host `0.0.0.0`; it is not an acceptable
  project default.
- No license grant was found. This blocks maintaining a project fork even if
  all isolation paths could be patched.

## Decision

Do not download a release, build, run, fork, patch or copy source from this
candidate. Keep it only as an inspect-only feature reference. Build an original
minimal dashboard around the project's own secret-free usage and fallback
contracts, or re-audit if upstream later adds a compatible license. CCR remains
the current operational router rather than the dashboard foundation.
