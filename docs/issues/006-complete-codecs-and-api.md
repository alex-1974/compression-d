# Issue 006 — Complete codec functionality and stabilize the API

## Context

`compression-d` has a research-grade Pure-D Inflate/zlib/GZIP decode core and
validated TIFF/PNG consumer experiments. The following functionality remains
missing or is not yet admitted as stable.

## Work items

### P0 — Core completeness and safety

- [ ] Add preset dictionary support.
- [ ] Expand malformed-input and compression-bomb corpora.
- [ ] Freeze the workspace-size contract.
- [ ] Audit `@safe`, `@nogc`, `nothrow`, overflow and aliasing guarantees.
- [x] Add reproducible fuzz/property tests.

### P1 — Encoding

- [x] Implement bounded Raw DEFLATE encoding.
- [x] Add zlib encoding with Adler-32.
- [x] Add GZIP encoding with CRC-32 and member metadata.
- [x] Define streaming versus one-shot encoder APIs.
- [x] Benchmark encoding against zlib.

### P1 — Container and consumer coverage

- [ ] Add a complete PNG chunk parser.
- [ ] Validate signature, chunk lengths, CRCs, IDAT sequencing and IEND.
- [ ] Decide policy for interlace, palette, transparency and metadata.
- [ ] Keep TIFF layout and predictor logic in `imageio-d`.

### P2 — API and ecosystem

- [x] Decide between raw slices, typed workspaces, or both.
- [x] Provide stable API documentation and examples.
- [ ] Define DMD/LDC compatibility policy.
- [ ] Complete license and dependency review.
- [ ] Validate a second independent consumer.
- [ ] Define first public release criteria.

## Acceptance criteria

- DMD and LDC pass all core, primitive, Inflate, framing and consumer gates.
- Differential output and rejection behavior are checked independently.
- No native compression backend is used by the D core.
- Output, expansion and workspace limits are explicit and tested.
- Public API promotion is documented by an ADR and release decision.
