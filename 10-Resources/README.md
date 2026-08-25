# Project Resources

`RESOURCE_ADOPTIONS.json` records only resources actually adopted by this project, including Vault capability/resource ID, pinned version/hash, local integration point, reason, constraints and verification gate.

Search this record before rebuilding. When a new local tool may help another
project, add a candidate to `40-State/RESOURCE_CANDIDATES.json`. If the Vault is
available, prepare a sanitized candidate and run
`python "<VAULT_ROOT>/tools/vault2.py" check-intake <CANDIDATE.json> --json`.
This command is a
non-mutating validation preview; it does not promote, install, execute, or
authorize the candidate. Apply accepted intake only through the separately
authorized Human-controlled Vault workflow.
