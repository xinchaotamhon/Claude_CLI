---
last_verified: 2026-08-25
verified_by: phase-2-account-onboarding-and-warm-start
status: active
---

# Next Actions

1. **Owner completes the remaining interactive logins.** Double-click
   `SIGN_ACCOUNT.bat`: `[1]` adds each Codex Free account, `[2]` adds Codex Plus,
   and `[G]` opens the three Google AI Pro slots. Enter passwords and 2FA only
   on the official browser pages. Codex App/global account switching is outside
   this project.
2. **Verify every completed slot before route promotion.** List project-local
   accounts from `SIGN_ACCOUNT.bat`; inspect only labels, declared plan, model
   route results and credential-file counts. Never read or print `auth.json`.
   Prove one bounded Claude-compatible request per candidate before retaining
   it; Free must not acquire Sol merely from an owner-entered label.
3. **Promote Google accounts incrementally.** Start with one Google slot and
   explicit account/model selection. Keep automatic fallback disabled. Confirm
   callback closure, account isolation and Claude tool-loop fidelity before
   wiring the second or third slot into normal RUN.
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
7. **Keep Codex App separate.** Its account switching and five-hour quota are
   not part of Claude CLI. Do not modify global `.codex`, App profiles or App
   login to solve project routing. If the owner tests the App separately, only
   record the result when it affects a proved project boundary.
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
