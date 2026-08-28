---
last_verified: 2026-08-28
verified_by: ccr-dead-core-502-repair
status: active
---

# Next Actions

1. **Use one entry only.** Double-click `DASHBOARD.bat`; it is the only BAT at
   project root. Keep technical rollback launchers under `tools/`.
   Use **Xóa mục đã đóng** when terminal history becomes noisy; it preserves
   running terminals and every resumable session.
2. **Prove Plus through the deferred path.** Use **Codex Plus** and select the
   intended Plus account on OpenAI's official browser page. If Claude terminals
   are active, the dashboard must show a pending account; close them and click
   **Hoàn tất nhập tài khoản**. Confirm actual routes: Free must not receive Sol;
   Plus may retain Sol/Terra/Luna only after bounded checks pass.
3. **Use Google normally, but keep provider failures bounded.** `google_pro_1`
   exposes 13 launch routes from a 24-model catalog. After the print-mode repair,
   `gemini-3.7-flash-high` returned exact `OK` in one bounded real request.
   Earlier 429/cooldown observations remain valid historical evidence, so do not
   repeatedly hammer a route if the provider starts rejecting it; wait for reset
   or use another account you have explicitly authorized.
   If a catalog model is absent from the route palette, treat it as unsupported
   by the pinned runtime—not as a reason to hard-code or relabel it.
4. **Promote new Google models through the pinned runtime manifest.** Catalog
   discovery is dynamic, but launch capability is the intersection with
   `router_challenger/google-runtime-models.json`. On a future CLIProxyAPI
   update, review source/model registry, rebuild reproducibly, run offline and
   loopback gates, then update the manifest. Keep `Gemini` and `Claude / GPT`
   quota branches separate. One minimal real inference is proved; a real
   multi-turn/tool-loop proof remains an owner action and should be recorded
   without credentials or transcript data.
5. **Use the repaired session model deliberately.** **Mở terminal** always
   creates a new UUID, so it is valid to open two or more terminals with the
   same Google/Codex account and same model; they share account quota but not a
   transcript. **Mở lại** keeps the old session name/origin and records the new
   route separately. Close the old terminal before resuming that exact UUID;
   the dashboard now rejects simultaneous writers. A real Google cross-route
   resume is proved without sending a prompt; owner-visible multi-turn checking
   remains useful.
   The dashboard **Xóa** action is recoverable: close the session terminal
   first, confirm the prompt, and let the server move only that UUID to local
   trash. Do not manually delete the common Claude home.
6. **Treat quota display as advisory.** Codex uses the official app-server
   method, but plan policy and response buckets can still change; Google quota
   remains provider-internal. On auth/schema/network failure show
   `unknown`/reauthentication, preserve the last timestamped snapshot and never
   block manual route launch solely because quota refresh failed.
7. **Keep Google branches separate.** `gemini_models` and
   `claude_gpt_models` must never be averaged into one percentage. Five-hour
   values are optional; weekly/monthly duration is derived from provider data.
8. **Do not call local proxy counts subscription quota.** A custom API provider
   remains `unknown` unless its own documented/verified quota adapter is added.
9. **Do not enable automatic fallback yet.** Prefer owner-approved
   cross-provider fallback over automatic Free-account rotation. Before any
   pilot, prove one-hop finite allowlists, session affinity, recognized
   quota/rate-limit signals, no parallel race, and no retry after streamed
   output/tool side effects.
10. **Configure custom APIs only through ignored `setting.json`.** Use the
    dashboard button to open it, validate/reload through the existing route
    path and keep keys out of Git/docs/browser state.
11. **Keep CCR as rollback champion.** Do not delete its ignored runtime/auth
    state. If dashboard fails, use `tools\RUN_CLAUDE_TECHNICAL.bat`.
12. **Review updates conservatively.** Operational versions are now Claude
    `2.1.250` and isolated CLIProxyAPI `7.2.144-local.1`, both with exact
    rollback artifacts. Keep CCR at `3.0.21`:
    `3.0.22` is rejected until its changed runtime can preserve provider-only
    isolation with a new reviewed source/runtime patch. Never run CCR source
    tests directly; close Codex App/dashboard/router and use
    `tools/run_ccr_source_tests_isolated.ps1`. Hold Codex helper `0.149` while
    login and usage work. The four release checks run
    independently and concurrently; a failed repository is marked as an error
    without hiding the others. Diff CCR/CLIProxyAPI source before merge;
    compare release notes/version/hash for the closed Claude binary. Never
    auto-download or auto-merge during dashboard startup. Dashboard update
    cards are advisory metadata, not approval. Keep all reviewed token
    optimizers uninstalled unless a future offline golden-fixture pilot proves
    that warnings, stack traces and project memory remain intact.
    Current safe usage reductions are already enabled: common resumable
    sessions, native auto-compaction, nonessential-traffic suppression and
    finite retries. Keep `xhigh`; do not install a token clipper or silently
    downgrade models merely to make the usage number smaller.
13. **Before every push, inspect staged files.** `setting.json`, `.ccr-local`,
    `.runtime`, auth JSON, binaries, Node modules and nested source repositories
    must remain ignored.
14. **Rehearse a clean reconstruction when convenient.** Follow
    `docs/RECONSTRUCT_ON_NEW_MACHINE.md` in a disposable clone and prove the
    tracked patch/install paths before relying on portability for a machine move.
15. **Retest one true Codex cold start.** After no project Codex route is warm,
    open one terminal and send one ordinary first prompt. If it still fails,
    preserve the visible error and timestamp; do not alter credentials or run
    repeated retries before diagnosis.

AI sessions may inspect tracked contracts and secret-free status only. Do not
print or persist access tokens, refresh tokens, passwords, 2FA, provider account
IDs, emails from auth payloads, CCR SQLite or DPAPI plaintext.
