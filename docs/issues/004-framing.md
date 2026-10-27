# Issue 004 — zlib and GZIP framing

Milestone: M3

- [x] zlib header validation and Adler-32.
- [x] GZIP optional fields and CRC-32.
- [x] Raw/framed API separation.
- [x] Truncated and checksum-negative corpus.

Implemented in `compression.checksum`, `compression.zlib`, `compression.gzip`,
with package-internal framing accounting. See [the framing contract](../FRAMING.md)
for streaming/reset/member boundaries and evidence. Verify with
`bash scripts/check-framing.sh` (DMD/LDC probes and zlib differential cases) or
`dub test` (saved fixtures/unit tests). Preset dictionaries are reported with
their DICTID and `dictionaryRequired`, not decoded.
