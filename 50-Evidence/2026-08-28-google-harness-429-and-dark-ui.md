# Google Claude-harness 429 containment and dark control-room redesign — 2026-08-28

## Outcome

The project-local Google OAuth slot, loopback CLIProxyAPI process, Anthropic
protocol adapter and dynamic model catalog are operational. A direct minimal
Anthropic request had previously completed, but current Claude Code requests
are rejected by the upstream Antigravity provider with HTTP 429. This is now a
visible, bounded provider failure instead of a multi-minute apparent hang and
an automatically disappearing terminal.

The localhost dashboard was also redesigned as a compact dark product control
room. It keeps the same API/actions and account/session/update behavior while
removing the oversized marketing-style hero, nested card treatment and long
native route menu presentation.

## Live Google diagnosis

The owner explicitly authorized bounded provider requests for diagnosis.
Sanitized observations:

- the exact project-local proxy identity and loopback listener verified on the
  assigned Google slot;
- model catalog and split Google usage buckets were readable;
- Claude Code with `gemini-3-flash` returned HTTP 429 `Resource has been
  exhausted`;
- `gemini-3.5-flash-extra-low` and `gemini-3.1-flash-lite` returned provider
  cooldown/429 even with a fresh proxy process and a minimal bare Claude prompt;
- the pre-repair default of ten retries caused an exponential retry delay that
  looked like a frozen terminal; and
- the displayed weekly/five-hour percentage is an advisory provider bucket,
  not proof that a particular model/request is currently admitted.

No access token, refresh token, client key, email, prompt transcript or raw auth
payload is retained in this evidence. The exact upstream reason behind
`Resource exhausted`—account quota, per-model rate or another provider policy—
is unknown; the provider response proves only the rejection boundary.

## Runtime containment

`tools/google_project_runtime.ps1` now applies only to the Google child Claude
process:

- `CLAUDE_CODE_MAX_RETRIES=2`;
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`;
- `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`;
- `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1`; and
- `--prompt-suggestions false`.

Every inherited process variable is restored after Claude exits. The shared
machine environment is not modified. `tools/dashboard_terminal.ps1` keeps a
failed launch window open until the owner presses Enter, while successful
sessions retain their normal exit behavior.

## UI/UX resource adoption

The owner-supplied CLOVER opportunity catalog was searched before rebuilding.
Current primary sources were reviewed for `pbakaus/impeccable` and
`nexu-io/open-design`; both are adopted as pattern references only. No package,
skill, hook, framework, template, font, design bundle or cloud dependency was
installed.

Applied patterns include semantic dark tokens, tinted near-black surfaces,
flatter information hierarchy, fewer decorative pills/cards, a launch-first
layout, compact provider grouping, visible keyboard focus and responsive
breakpoints. Browser verification at 1280 px observed no horizontal overflow,
31 selectable routes, working Escape dismissal and no console warning/error.

## Verification

- Dashboard TypeScript and Vite production build: PASS.
- Local dashboard capability/isolation verifier: PASS.
- Dashboard action lifecycle verifier: PASS.
- Account/catalog management verifier: PASS.
- Google runtime self-test: PASS.
- Browser DOM/interaction/visual check: PASS.
- Full smoke run `20260828T094039Z-13e8d342`: 22/22 PASS, including external
  Codex App isolation and the isolated challenger source gate.

## Rollback

Revert this change to restore the previous layout and retry behavior. Runtime
account/auth/session data under `.runtime` is not part of the commit and does
not need migration. Reverting the retry containment reintroduces long upstream
429 waits, so it is not recommended while Antigravity remains rate-limited.
