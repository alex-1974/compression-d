# JPEG native ROI admission gate

## API contract

`PixelRegion` uses the full-resolution reference grid. `RoiPlan` reports the
component-plane origin, dimensions, sampling factors and MCU coverage.
`decodeJpegPlanesRegion` writes only the requested native component window.
`decodeJpegPlanesRegionIndexed` additionally accepts a validated restart index.
The caller owns encoded input, destination planes, index storage and the
`RoiDecodeReport` storage.

The decoder never converts colour or upsamples chroma. A successful result is
exact only for the requested native component planes. Invalid input, invalid
geometry, stale indexes and insufficient destinations return structured status
values without publishing partial output as complete.

## Acceptance status

- [x] ROI geometry and checked edge handling
- [x] Native 4:2:0 differential test
- [x] Native 4:2:2 geometry test
- [x] Restart index with source length and fingerprint
- [x] Restart marker ordering and bounds validation
- [x] Indexed ROI differential test against full decode plus crop
- [x] Observable full-decode fallback
- [x] DMD and LDC unit tests
- [x] DMD and LDC benchmark matrix
- [x] No TIFF, imageio-d or colour-management dependency
- [x] Independent libjpeg smoke oracle (`scripts/check-jpeg-roi.sh`)
- [x] Generated external valid/truncated/marker/prefix corpus (`scripts/check-jpeg-fuzz.sh`)
- [x] Deterministic property-style ROI, bounds and fingerprint tests
- [x] Bounded corpus harness under DMD and LDC (`tools/jpeg_fuzz.d`)
- [x] Repeated mutation corpus under LDC AddressSanitizer

## Performance interpretation

The benchmark in `docs/JPEG_ROI_BENCHMARKS.md` demonstrates lower MCU counts
and lower wall time for ROIs after a restart boundary. ROIs before the first
usable boundary correctly use the full-decode fallback. Results are evidence
for this implementation and must be reproduced on target hardware before
making a general performance claim.

## Admission decision

The API is suitable for experimental consumer integration behind an explicit
feature gate. The smoke gate, malformed corpus harness, deterministic tests,
benchmark matrix and LDC AddressSanitizer run pass. The sanitizer corpus is
generated per run; a future release gate may additionally persist seed corpora
and run for longer wall-clock budgets.
