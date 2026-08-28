# Google interactive launch print-mode repair — 2026-08-28

## Owner-observed failure

- Google 1 and Google 2 reached their local ports, but both Gemini and
  Claude-family routes exited immediately with `Input must be provided either
  through stdin or as a prompt argument when using --print`.
- The warning that `gemini-3.7-flash-high` was unknown to Claude Code appeared
  before the failure, but the same exit also occurred for
  `claude-opus-4-6-thinking`; it was therefore not sufficient as a cause.

## Proved root cause

- `tools/google_project_runtime.ps1` invoked the interactive function as
  `exit (Start-Claude ...)`. PowerShell evaluated the function in a captured
  output pipeline. Claude Code detected the captured native stream, selected
  print mode and rejected the absent one-shot prompt before model inference.
- A provider-free reproduction used a dummy closed loopback endpoint and the
  same function-in-`exit (...)` shape. It produced the exact owner error. A
  top-level invocation with the same Claude binary, model arguments and local
  config remained interactive.
- The model-name warning affects Claude's assumed auto-compact window only. It
  did not cause the process to enter print mode and did not block inference.

## Repair and bounded alternative review

- `Start-Claude` now writes the native exit status to a script-local integer.
  The function is called as a standalone statement, then the script exits with
  that integer. Claude's interactive streams remain attached to the console.
- The offline verifier rejects both `exit (Start-Claude` and the former
  `return $ExitCode` capture path.
- A separate-console launcher was piloted but not retained. After the pipeline
  repair, the existing allowlisted `ProcessStartInfo` dispatcher reached
  `claude_starting` and remained alive. Keeping it avoided an unnecessary
  Windows Script Host dependency and preserved the established one-terminal
  lifecycle contract.

## Verification

- PowerShell parsed the runtime and dashboard terminal scripts; focused
  dashboard lifecycle and account/model contract checks passed.
- Direct Google 1 launch of `claude-opus-4-6-thinking` reached the Claude Code
  2.1.250 interactive prompt and remained alive without sending a prompt.
- Full dashboard dispatch reached `claude_starting` and remained alive for both
  `claude-opus-4-6-thinking` and `gemini-3.7-flash-high`. Exact test process
  trees were stopped after observation; no wildcard process termination ran.
- One bounded real request through Google 1 and `gemini-3.7-flash-high`
  returned exact output `OK` in 15 seconds with one output token. This proves
  that launch and one upstream inference worked at that time; it does not prove
  future quota, provider identity, privacy or tool-loop behavior.
- The owner then used the dashboard-opened Gemini terminal normally; a `hi`
  prompt returned a complete greeting in 6 seconds at `xhigh` effort.
- All 22 enabled smoke gates passed under the owner Windows profile in run
  `20260828T103224Z-756f1b17`. The gate run itself made no model request.
- No credential, auth payload, provider account identifier, email, session
  transcript or client key was retained in this evidence.

## Rollback

- Source rollback checkpoint is parent commit `6082bd5`. Reverting only the
  runtime and verifier changes restores the prior behavior; ignored account,
  proxy and session state need not be deleted.
- Historical Google 429/cooldown evidence remains valid. A successful bounded
  request here is current availability evidence, not a fallback or quota
  guarantee.
