# Codex Free model-route repair — 2026-08-25

## Owner observation

Claude launched through the imported `codex_free_1/gpt-5-codex` route, but a
minimal `hi` prompt returned `API Error: 400 All target providers failed.`
The route menu also mapped Claude's Opus, Sonnet and Haiku roles to the same
single upstream model, so those three labels did not represent three Codex
models.

## Sanitized diagnosis

The project sent bounded `Reply exactly OK` requests through its authenticated
loopback gateway. Client keys remained DPAPI-protected; OAuth tokens, auth
files, SQLite, raw request bodies and raw provider responses were not retained.

The failed attempt reported:

- target provider: `codex_free_1` / `openai_responses`;
- stage: `upstream_response`;
- upstream status: HTTP 400;
- sanitized detail: `gpt-5-codex` is not supported when Codex is used with a
  ChatGPT account.

CCR source proved why the bad route existed. If its live Codex `/models` probe
fails or returns no models, the import catches the error and silently reuses
the built-in default `gpt-5-codex`. That fallback was discoverable but was not
usable by this account.

## Candidate verification

Current OpenAI model documentation identified the Sol, Terra and Luna IDs.
Direct Claude-gateway probes on this ChatGPT Free account observed:

| Model | Gateway result | Disposition |
|---|---:|---|
| `gpt-5.6-sol` | HTTP 400, unsupported for this ChatGPT account | hidden |
| `gpt-5.6-terra` | HTTP 200, stream completed | enabled |
| `gpt-5.6-luna` | HTTP 200, stream completed | enabled |
| `gpt-5-codex` | HTTP 400, unsupported for this ChatGPT account | hidden |

CCR's generic `checkProviderConnectivity` reported Sol as available even though
the real Claude-compatible `/v1/messages` path rejected it. Therefore direct
gateway evidence overrides that generic probe for account entitlement.

## Repair

- Account import excludes the rejected legacy fallback and Sol for the current
  Free-account policy.
- Import and `SIGN_ACCOUNT.bat` action `[R]` run bounded model connectivity
  checks for Terra and Luna without another browser login.
- Every retained model becomes a separate RUN profile instead of mapping an
  array into one route.
- `Read-AccountProfiles` now enumerates multiple profiles; the previous
  one-element array behavior had hidden this reader defect while every account
  owned only one route.
- The existing account was refreshed. RUN now shows separate Terra and Luna
  routes only.

## Verification and rollback

- Final real Terra request: HTTP 200 and completed stream through
  `http://127.0.0.1:3456/v1/messages`.
- Focused offline checks passed: account-import verifier, router layout,
  settings flow, external-App isolation and owner-profile DPAPI self-test.
- Final cumulative run `20260825T052438Z-21e21f26`: all 9 enabled smoke gates
  passed under the owner's Windows profile.
- Focused regression owner: `claude.codex-account-import`, including candidate
  filtering and two-model profile round-trip.
- Rollback: restore the prior single-profile writer, restore array-preserving
  reader behavior and re-add `gpt-5-codex`. This rollback is not recommended
  because it recreates the proved 400 route.
