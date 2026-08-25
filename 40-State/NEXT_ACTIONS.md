---
last_verified: 2026-08-25
verified_by: cli-proxy-api-phase-0-source-audit
status: active
---

# Next Actions

1. **Obtain owner approval for CLIProxyAPI Phase 1.** Phase 0 source intake is
   complete. Do not install a toolchain, build/start the challenger,
   authenticate or replace CCR until the owner approves the exact offline scope
   in `50-Evidence/2026-08-25-cli-proxy-api-phase-0-source-audit.md`.
2. **If approved, stage Go 1.26.x project-locally and patch update isolation.**
   Do not modify system PATH. Make `--local-model` suppress the unconditional
   Antigravity version request, commit that bounded patch on the nested
   `claude` branch, then build one ignored/hash-pinned Windows binary.
3. **Run only an offline challenger fixture.** Bind `127.0.0.1` on a separate
   port; use absolute project paths, current-user-only ACL, fake credentials,
   authenticated management and a local upstream. Add startup-time,
   stop/restart, no-external-write, streaming and Claude tool-loop gates. Keep
   `RUN_CLAUDE.bat` unchanged.
4. **Keep CCR as the rollback champion.** Do not delete or rewrite its ignored
   runtime/auth state. A challenger is promoted only after all existing gates
   and its focused isolation/protocol gates pass on the same artifact.
5. **Fully close and restart Codex App, then verify its normal surface.** The
   active global config on disk is restored, but the running App can cache its
   previous provider. Confirm the lower-left label is no longer
   `Claude Code Router` and Usage is visible again.
6. **Use the verified account routes.** Double-click `RUN_CLAUDE.bat` and pick
   the Terra or Luna line. Sol and legacy `gpt-5-codex` are intentionally hidden
   because direct requests from this Free account returned HTTP 400.
7. **Add another account when needed.** In `SIGN_ACCOUNT.bat`, run `[1]` again, choose a different label and sign
   into the other account in the newly opened browser flow. No switching in
   Codex App or global CLI is needed. Gate: both labels appear separately in
   RUN; duplicate detected account IDs are rejected.
8. **Refresh routes if model entitlement changes.** In `SIGN_ACCOUNT.bat`, use
   `[R]`, select the imported account and let the bounded checks rebuild its
   model routes. This does not repeat browser login but sends a minimal request
   to each candidate and can consume a small amount of quota.
9. **Verify explicit account switching manually.** After two accounts exist, exhaust or
   disable one account and confirm the intended switch behavior. Current CCR
   routes select accounts explicitly; automatic 9router-style fallback is not
   part of the active design.
10. **Configure an API route when needed.** Edit ignored `setting.json`; replace
   sample URL/key/model and enable provider/profile. Gate: reload with `[S]`
   without validation/RPC error; rollback: disable both and reload.
11. **Repair the local login helper only if missing/hash-mismatched.** Run
   `powershell -File tools\install_codex_login_runtime.ps1`. This is an explicit
   network/install action and must never be added to normal startup.
12. **Before every GitHub push, inspect staged files.** `setting.json`, `.ccr-local`,
   all EXE binaries, Node modules and the nested source repo must stay ignored.
13. **Review updates conservatively.** Source-diff CCR and CLIProxyAPI before
   merge; compare
   release notes/version/hash for closed binaries. Rerun all gates before any
   operational replacement.

Never ask an AI to read `setting.json`, per-account `auth.json`, CCR SQLite or
DPAPI data. Use `setting.example.json` or a separately sanitized description.
