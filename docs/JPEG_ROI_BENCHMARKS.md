# JPEG ROI benchmark

The benchmark is `benchmarks/jpeg_roi.d`. It uses a deterministic 256x256
grayscale image, a 32x32 ROI, 20 passes per case, and restart intervals 1, 4,
and 16. Build and run it with DMD or LDC by compiling the benchmark together
with `source/compression/jpeg.d`.

Representative runs on the same host:

| Compiler | ROI | Restart | Full ms | Indexed ms | Decoded MCUs |
|---|---:|---:|---:|---:|---:|
| DMD | origin | 4 | 116.5 | 114.1 | 1024 |
| DMD | centre | 4 | 115.6 | 67.6 | 564 |
| DMD | bottom-right | 4 | 116.2 | 13.4 | 100 |
| LDC | origin | 4 | 166.1 | 167.2 | 1024 |
| LDC | centre | 4 | 181.5 | 105.5 | 564 |
| LDC | bottom-right | 4 | 166.2 | 19.0 | 100 |

The origin ROI correctly uses `fullDecodeFallback`. Indexed decoding reduces
work substantially for later ROIs, but the current restart-index strategy still
decodes more MCUs than the requested 16 because it starts at the preceding
restart boundary. Measurements are evidence for this implementation and are
not a general JPEG performance claim.
