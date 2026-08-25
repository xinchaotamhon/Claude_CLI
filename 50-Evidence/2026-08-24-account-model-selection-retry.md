# Evidence — Codex account model-selection retry

Date: 2026-08-24
Scope: `SIGN_ACCOUNT.bat` option `[1]`

## Sanitized observed failure

- Owner-observed browser output: login completed successfully.
- CCR returned exactly one available model: `gpt-5-codex`.
- An unrelated alias was entered at `Choose the default model [1]`.
- Observed result: `Invalid model selection` aborted import after successful
  authentication. The private account label is intentionally excluded.

## Root cause

`Select-CodexAccountModel` accepted only a blank value or numeric index and
threw immediately on every other value. It unnecessarily prompted even when
there was only one possible model. Because account auth was already stored in a
folder-local home but the provider save happened later, the failure also left a
valid unfinished login with no resume path.

## Implemented prevention

- One model is selected automatically.
- Multiple models accept a valid number or exact model ID, case-insensitively.
- Invalid input displays a corrective message and loops instead of throwing.
- Each local account home stores only a SHA-256 marker of its account label.
  Re-entering the exact label resumes an unfinished local auth file by existence
  check only; auth content is never read or printed.
- Label-marker mismatch selects a different provider ID/home rather than
  crossing account state.

## Deterministic evidence

- Before fix, focused gate run `20260824T131431Z-f79b2947` failed as expected.
- After implementation, focused run `20260824T131635Z-dcac8929` passed both
  `claude.router-menu-selftest` and `claude.codex-account-import`.
- Final cumulative run `20260824T131834Z-90423874` passed all 8 enabled required
  smoke gates on the same artifact.
- Self-test covers numeric choice, exact model ID, rejected unavailable alias,
  sole-model auto-selection and fake unfinished-home resume. It uses isolated
  fake auth and makes no browser/provider request.

## Rollback

Restore the prior selector and account-slot functions. No real account home,
auth, provider or external login is modified by deterministic tests.
