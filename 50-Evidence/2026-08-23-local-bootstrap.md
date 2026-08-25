# Local bootstrap evidence — 2026-08-23

## Scope

Prepared the independent Claude CLI folder, copied the approved local native
binary into `bin/`, created the root-relative launcher and Git boundary, and
validated the project-memory scaffold. No interactive login, task execution, or
network request was performed by these checks.

## Binary observation

- Observed tool output: `2.1.241 (Claude Code)`.
- Observed size: `337745056` bytes.
- SHA-256: `C49A05922A787C33478067A5164002932235F6611948523B55AE1FBDB303AC1F`.
- Checksum artifact: [checksums/claude.exe.sha256](../checksums/claude.exe.sha256).
- Runtime artifact: `bin/claude.exe`, excluded by the root `.gitignore`.
- Provenance: copied from the official native per-user installation already
  present on this machine; the original installation was not modified.

## Observed checks

| Command or procedure | Expected | Observed | Verdict |
|---|---|---|---|
| `python tools/verify_local_setup.py .` | Exit 0; local binary and isolation markers exist | Exit 0; layout complete; network not used | PASS |
| `RUN_CLAUDE.bat --version` | Resolve `bin/claude.exe`; exit 0 | Resolved local binary; printed `2.1.241`; exit 0 | PASS |
| `python tools/audit_project_memory.py . --json` | No errors or warnings | No errors; no warnings; 14 Markdown files scanned | PASS |
| `python tools/validate_standard_adoption.py .` | Adoption receipt valid | Standard `1.2.2`; status `PASS` | PASS |
| `python tools/run_gates.py --project-root . --tier smoke --evidence-dir 50-Evidence --fail-fast` | All enabled required smoke gates pass | 5 of 5 passed in run `20260823T164702Z-d11a6bfe` | PASS |

## Boundaries and remaining unknowns

- `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_TMPDIR` are routed under this project by
  the launcher; the generated local directories are ignored by Git.
- The launcher does not automatically download, install, update, or publish a
  binary.
- Authentication, network access, organization policy, subscription/API
  entitlement, and real project work remain owner-approved runtime actions.
- The requested external CLOVER path was absent; the available CLOVER root
  router was read during bootstrap and its conventions were translated locally.
