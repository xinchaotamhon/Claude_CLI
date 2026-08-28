# CCR dead-core 502 root-cause repair — 2026-08-28

## Owner-observed failure

Claude through a Codex/OpenAI route returned HTTP 502 with `Core gateway auth
token is not initialized` while the project-local gateway endpoint was still
listening. No credential value, account identifier, request body or transcript
was retained in this evidence.

## Proved root cause

- Public `127.0.0.1:3456/health` returned HTTP 200 but its JSON payload reported
  `status:error` and pointed to core `127.0.0.1:3457`.
- The core port did not answer. Authenticated project-local management status
  reported no core PID and recorded core exit code `3221225786`, hexadecimal
  `0xC000013A` (Windows console-control termination).
- CCR source clears `coreAuthToken` when the nested core exits but leaves the
  public gateway shell listening. The project launcher checked only HTTP 200,
  so three repeated checks repeated the same shallow false-positive.
- The nested core spawn retained IPC ownership but did not request a separate
  Windows process group or a hidden window. This allowed launcher-console
  control events to terminate the core without terminating management/public
  gateway state.

## Repair

- Fork commit `e703b588fd645c52a311700090ed2f6bb76e6d01` adds Windows-only
  `detached` and `windowsHide` spawn flags while retaining the IPC channel and
  parent lifecycle ownership. It is pushed to the owner fork branch `claude`.
- The version-locked operational patcher reproduces the exact change in ignored
  CCR 3.0.21 runtime after reconstruction and is idempotent even when a guarded
  replacement contains its original text as a suffix.
- Router readiness now verifies four independent postconditions before reading
  the DPAPI client key: exact management-process identity, public payload
  `status=running`, management ownership of a positive PID/exact endpoints, and
  direct core payload `status=ok` with a runtime ID.
- Only an exact recorded core-process termination permits one bounded
  `restartGateway` RPC. It never rotates account/model, never falls back to
  another provider and never sends a model prompt.

## Verification

- Pre-fix focused regression: 2 tests produced 7 expected failures, proving the
  new tests detected missing deep health and Windows process isolation.
- Post-fix startup regression: 14/14 passed.
- Runtime patch application passed twice consecutively, proving idempotence.
- The project-local management service was restarted from the patched bundle.
  Public health then reported `running` with exact core endpoint 3457; direct
  core health reported `ok` with a non-empty runtime ID. The launcher process
  exited while management/public/core remained available.
- Focused owner-profile gate run `20260828T150128Z-7874962d` passed 4/4:
  router layout, router self-test, external Codex App isolation and warm start.
- Final owner-profile gate run `20260828T150731Z-590717cd` passed all 24 enabled
  smoke gates, including dashboard/session/Google/account regressions. No
  provider/model request was made by the diagnosis, repair or verification.

## Rollback and residual unknowns

- Roll back the parent launcher/deep-health changes and restore the prior fork
  commit only after stopping the project-local router. Reconstructing the pinned
  runtime reapplies whatever exact tracked patch set is checked out.
- The source repository test suite was not run because the active Codex App is
  part of this task; project policy forbids direct CCR source tests and requires
  closing the app/dashboard/router before using the isolated wrapper.
- A normal owner prompt after this patched cold start remains the only bounded
  provider-facing proof still needed. It consumes provider quota and was not
  performed automatically.
