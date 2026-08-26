---
last_verified: 2026-08-26
verified_by: one-door-local-dashboard
status: active
---

# Next Actions

1. **Use one entry only.** Double-click `DASHBOARD.bat`. `SIGN_ACCOUNT.bat` is
   only a compatibility alias; do not add another account menu. Keep
   `RUN_CLAUDE.bat` as technical rollback.
2. **Complete owner-interactive Codex logins from the dashboard.** Use
   **Codex Free** for the remaining Free accounts and **Codex Plus** for the Plus
   account. Enter password and 2FA only on the official browser page. Confirm
   the resulting models: Free must not receive Sol; Plus may retain
   Sol/Terra/Luna only after bounded provider checks pass.
3. **Complete Google slots one at a time.** Start with Google AI Pro Slot 1,
   finish official OAuth, return to the dashboard and refresh quota. Verify the
   `Gemini` and `Claude / GPT` groups independently before Slot 2 or 3.
4. **Promote Google routes incrementally.** A completed OAuth slot is not yet a
   Claude route. Prove one explicit account/model request and full tool loop,
   then add only that route to the selector. Keep automatic fallback off.
5. **Prove parallel terminals.** After a second account exists, open two
   dashboard terminals with different routes, then two with the same route.
   Expected: each terminal keeps its selected model; same-account terminals
   share provider quota; neither changes Codex App/global state.
6. **Treat quota display as advisory.** Codex and Google quota endpoints are
   undocumented and may change. On 401/schema/network failure show
   `unknown`/reauthentication, preserve the last timestamped snapshot and never
   block manual route launch solely because quota refresh failed.
7. **Keep Google branches separate.** `gemini_models` and
   `claude_gpt_models` must never be averaged into one percentage. Five-hour
   values are optional; weekly/monthly duration is derived from provider data.
8. **Do not call local proxy counts subscription quota.** A custom API provider
   remains `unknown` unless its own documented/verified quota adapter is added.
9. **Do not enable automatic fallback yet.** Before promotion, prove finite
   allowlists, session affinity, a recognized quota/rate-limit signal, bounded
   attempts and no retry after streamed output/tool side effects.
10. **Configure custom APIs only through ignored `setting.json`.** Use the
    dashboard button to open it, validate/reload through the existing route
    path and keep keys out of Git/docs/browser state.
11. **Keep CCR as rollback champion.** Do not delete its ignored runtime/auth
    state. If dashboard fails, stop its process and use `RUN_CLAUDE.bat`.
12. **Review updates conservatively.** Diff CCR/CLIProxyAPI source before merge;
    compare release notes/version/hash for the closed Claude binary. Never
    auto-download or auto-merge during dashboard startup.
13. **Before every push, inspect staged files.** `setting.json`, `.ccr-local`,
    `.runtime`, auth JSON, binaries, Node modules and nested source repositories
    must remain ignored.

AI sessions may inspect tracked contracts and secret-free status only. Do not
print or persist access tokens, refresh tokens, passwords, 2FA, provider account
IDs, emails from auth payloads, CCR SQLite or DPAPI plaintext.
