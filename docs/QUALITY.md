# Quality gates

- Pure-D implementation; no C/backend dependency in the core.
- DMD and LDC compile matrix.
- `@safe @nogc nothrow` probes for core operations.
- RFC-derived positive and malformed corpora.
- Differential byte/output comparison with zlib.
- Explicit output and expansion limits.
- No public API promotion before two independent consumers.
- Benchmarks must prevent compiler elimination and report checksum/output use.

Current checks: `bash scripts/check-core.sh` and
`bash scripts/check-primitives.sh` run tests and DIP1000/attribute probes on both
compilers. `dub test` includes M0/M1 unit tests and the primitive consumer probe.
The lookup benchmark is `bash scripts/bench-huffman.sh`. M2 adds
`bash scripts/check-inflate.sh` for saved/malformed Inflate corpora, attribute
probes and independently generated zlib differential cases under both compilers.
M3 adds `bash scripts/check-framing.sh` for incremental checksum/optional-header
tests, framed probes and zlib differential cases, including GZIP sequences.
Complete consumer gates remain pending.
