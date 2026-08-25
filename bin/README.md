# Local Claude Code binary

Place the official Windows Claude Code native binary at `bin/claude.exe`.
`RUN_CLAUDE.bat` prefers this path and does not modify the user-level install.

The binary is proprietary and is intentionally excluded from normal Git
history by the root `.gitignore`. Do not patch, decompile, or redistribute it
without checking the applicable Anthropic terms. Keep the source, release
version, architecture, acquisition date, and SHA-256 hash in
`checksums/claude.exe.sha256` and the evidence index.

The launcher does not download or replace the binary automatically. A Human
owner must approve a replacement and rerun the local verification gate.
