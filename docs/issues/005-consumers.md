# Issue 005 — Consumer validation

Milestone: M4

- [x] imageio-d TIFF Deflate bridge.
- [x] PNG scanline consumer experiment.
- [x] Verify workspace reuse and concurrent decode isolation.
- [x] Compare DMD/LDC throughput and allocations.

Completed as local research evidence: see [CONSUMERS.md](../CONSUMERS.md).
The additive imageio-d experiment declares a real compression-d path dependency;
its existing dirty research context is preserved. Run
`bash scripts/check-consumers.sh` and `python3 scripts/bench-consumers.py` with
that checkout and GDAL available. This is not production/API admission.
