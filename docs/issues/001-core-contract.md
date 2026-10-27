# Issue 001 — Define core contract

Milestone: M0

- [x] Define `Result` and structured error taxonomy.
- [x] Define output-limit and expansion-limit semantics.
- [x] Decide raw slice versus typed workspace API.
- [x] Add DMD/LDC compile probes.

Implemented in `source/compression/core.d`; the experimental contract is
documented in [CORE_CONTRACT.md](../CORE_CONTRACT.md). Typed codec workspaces
are selected; concrete layouts follow with the codecs. Verify with
`bash scripts/check-core.sh`; CI also builds the library with both compilers.
