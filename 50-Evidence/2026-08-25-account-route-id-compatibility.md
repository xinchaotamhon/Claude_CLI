# Account route-ID compatibility — 2026-08-25

## Accepted outcome

An account already imported through the project-local browser flow must load in
`RUN_CLAUDE.bat` even when its local label normalizes to a provider ID containing
slug-safe underscore or dot characters. The repair must not read, print or
rewrite real account authentication.

## Owner observation

The owner reported that one account had signed in, but the next RUN failed in
`Read-AccountProfiles` with `The project-local account profile index contains an
invalid route.` No private account label, auth payload, token or database content
was copied into this evidence.

## Root cause and control flow

- `ConvertTo-ProviderSlug` permits `[a-z0-9_.-]` after normalization.
- `Add-CodexAccountProfile` creates `account-$ProviderId` and writes it to the
  ignored project-local account profile index.
- Before this repair, `Read-AccountProfiles` accepted only `[a-z0-9-]` for that
  generated route ID.
- `Get-ModePath`, used after selecting the displayed route to prepare Claude's
  isolated settings path, independently repeated the same narrower rule.
- Therefore a generator-valid `_` or `.` could make the next RUN reject its own
  output before route selection. Authentication and model discovery were not
  the cause.

## Reproduction and repair

The offline self-test now uses the synthetic label
`account_name+tag@example.test`. It writes and reloads the resulting route using
a temporary index under the self-test root. Before the validator change, this
fixture reproduced the exact invalid-route failure. The reader now accepts
`^[a-z0-9][a-z0-9_.-]{0,62}$`, matching the slug-safe character set used by the
generator while retaining the 63-character bound. `Get-ModePath` uses the same
validator, and the fixture also resolves the generated ID through that path
boundary so a route cannot merely display and then fail when selected.

This is a backward-compatible reader repair: the existing ignored route index
does not need migration, and the account does not need another browser login.

## Deterministic evidence

- Pre-change cumulative baseline: `20260824T172947Z-7cb886ff`, 8/8 enabled smoke
  gates passed.
- Sanitized fixture before repair: `20260824T173222Z-32aa653f`, expected failure
  in `claude.router-menu-selftest` with the owner-observed error.
- Focused post-repair run: `20260824T173312Z-a0cee41d`, both
  `claude.router-menu-selftest` and `claude.codex-account-import` passed.
- Extended post-repair run: `20260824T173807Z-f32e0a0f`, the same focused gates
  passed after the fixture was extended through isolated Claude mode-path
  resolution.
- Integrated cumulative run: `20260824T173932Z-43d5c46b`, all 8 enabled smoke
  gates passed after code, memory and bounded CLOVER-pattern updates.
- Tests used temporary fake settings/account indexes and Windows DPAPI only.
  They did not read ignored `setting.json`, real `auth.json`, CCR SQLite, request
  logs or provider credentials; they made no browser/provider/model request.

## Bounded CLOVER entry-router review

The owner also supplied the updated
`D:/mydata/my-project/CLOVER/START_HERE.md`, observed SHA-256
`08bfa3309451150e6580064b8ed2ffa9c8e447f10f8595e64233ad371aa8802`.
The local project adopted only entry-relative path anchoring, exact failure for
a missing supplied entry, navigation-versus-authority separation, and one
canonical front door per intended outcome. No CLOVER file, state, command,
permission or runtime is required for routine continuation of this project.

## Rollback

Revert the compatible account-ID regex, synthetic self-test fixture, verifier
markers and related memory updates together. That rollback would intentionally
restore the reported RUN failure for account labels whose normalized IDs contain
underscore or dot characters.
