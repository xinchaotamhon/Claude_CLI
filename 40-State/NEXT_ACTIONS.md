---
last_verified: 2026-08-25
verified_by: cli-proxy-api-phase-1-offline-pilot
status: active
---

# Next Actions

1. **Keep Phase 1 offline and CCR active.** Use `RUN_CHALLENGER_PILOT.bat` only
   for the deterministic fixture/status/stop surface. It does not sign in or
   run real Claude work. Keep `RUN_CLAUDE.bat` unchanged.
2. **Build an original minimal dashboard, not the blocked candidate.**
   EasyCLIProxyAPI `v0.2.61` is source-pinned for feature comparison only; its
   tagged tree has no license grant and contains unsafe integration surfaces.
   Do not copy/patch/build it. Implement only project-owned account, quota,
   explicit route and fallback controls against CLIProxyAPI management APIs.
3. **Design Phase 2 before any real OAuth.** Require one isolated auth directory
   per account, explicit selected-account routing, no round-robin/failover,
   verified token-file ACL, bounded callback ports and a clean account removal
   path. Obtain owner approval before opening a browser or provider endpoint.
4. **Implement quota adapters only with proved provenance.** Google AI Pro must
   keep separate `gemini_models` and `claude_gpt_models` weekly branches;
   five-hour data is optional. If an official/provider surface cannot be
   proved, show `unknown` rather than infer from proxy traffic.
5. **Keep CCR as the rollback champion.** Do not delete or rewrite its ignored
   runtime/auth state. A challenger is promoted only after all existing gates
   and its focused isolation/protocol gates pass on the same artifact.
6. **Reconstruct the pilot only explicitly when needed.** Run
   `tools\install_challenger_pilot.ps1`; it downloads official Go into
   `vendor`, recreates the ignored pinned source/patch and builds hash-checked
   binaries. Normal startup never downloads or builds.
7. **Fully close and restart Codex App, then verify its normal surface.** The
   active global config on disk is restored, but the running App can cache its
   previous provider. Confirm the lower-left label is no longer
   `Claude Code Router` and Usage is visible again.
8. **Use the verified account routes.** Double-click `RUN_CLAUDE.bat` and pick
   the Terra or Luna line. Sol and legacy `gpt-5-codex` are intentionally hidden
   because direct requests from this Free account returned HTTP 400.
9. **Add another account when needed.** In `SIGN_ACCOUNT.bat`, run `[1]` again, choose a different label and sign
   into the other account in the newly opened browser flow. No switching in
   Codex App or global CLI is needed. Gate: both labels appear separately in
   RUN; duplicate detected account IDs are rejected.
10. **Refresh routes if model entitlement changes.** In `SIGN_ACCOUNT.bat`, use
   `[R]`, select the imported account and let the bounded checks rebuild its
   model routes. This does not repeat browser login but sends a minimal request
   to each candidate and can consume a small amount of quota.
11. **Verify explicit account switching manually.** After two accounts exist, exhaust or
   disable one account and confirm the intended switch behavior. Current CCR
   routes select accounts explicitly; automatic 9router-style fallback is not
   part of the active design.
12. **Configure an API route when needed.** Edit ignored `setting.json`; replace
   sample URL/key/model and enable provider/profile. Gate: reload with `[S]`
   without validation/RPC error; rollback: disable both and reload.
13. **Repair the local login helper only if missing/hash-mismatched.** Run
   `powershell -File tools\install_codex_login_runtime.ps1`. This is an explicit
   network/install action and must never be added to normal startup.
14. **Before every GitHub push, inspect staged files.** `setting.json`, `.ccr-local`,
   all EXE binaries, Node modules and the nested source repo must stay ignored.
15. **Review updates conservatively.** Source-diff CCR and CLIProxyAPI before
   merge; compare
   release notes/version/hash for closed binaries. Rerun all gates before any
   operational replacement.

Never ask an AI to read `setting.json`, per-account `auth.json`, CCR SQLite or
DPAPI data. Use `setting.example.json` or a separately sanitized description.
