# Quality gates

- Pure-D implementation; no C/backend dependency in the core.
- DMD and LDC compile matrix.
- `@safe @nogc nothrow` probes for core operations.
- RFC-derived positive and malformed corpora.
- Differential byte/output comparison with zlib.
- Explicit output and expansion limits.
- No public API promotion before two independent consumers.
- Benchmarks must prevent compiler elimination and report checksum/output use.
