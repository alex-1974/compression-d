# Consumer validation (M4)

M4 establishes a real local imageio-d TIFF Deflate consumer plus a separate PNG
scanline experiment. It does not admit a production imageio-d API, claim full
TIFF/PNG support, or stabilize compression-d's experimental API.

## Reproduce

Requirements: DMD 2.111.0, LDC 1.42.0 (tested), Python with GDAL `osgeo`, and
`/usr/bin/time`. GDAL, libtiff/libpng and Python zlib are independent fixture/
reference tooling; none is a runtime backend of the D consumers.

```sh
bash scripts/check-consumers.sh
python3 scripts/bench-consumers.py --rounds 5 --iterations 20 --cpu 0
```

Set `IMAGEIO_D_ROOT` for another imageio-d checkout or `CONSUMER_PYTHON` for
another Python with GDAL bindings. The default checkout is
`../d-geospatial-workspace/libs/imageio-d`; default Python is `/usr/bin/python3`.
Omit/change `--cpu 0` if that CPU is unavailable. No frequency lock is assumed.

Generated images, GDAL raw references, their SHA-256 manifest, binaries and
benchmark JSON stay under `.build/consumers/`. The checker also retains
`imageio-consumer-context.tar.gz` containing the exact experiment and its three
pre-existing TIFF helper modules. They are local research context, not provider
library source or a production dependency. The public imageio-d `develop` branch
currently has documentation only: this gate requires the local research
checkout, not just that remote branch. It is deliberately a separate local
cross-repository gate rather than an un-runnable core-CI job.

## imageio-d TIFF integration

New additive files live in imageio-d's `experiments/compression_consumer/`.
The experiment declares a real DUB **path dependency** on `compression-d` and
has been built/executed through that dependency under DMD and LDC, as well as
through the independent DIP1000 consumer probe. It uses existing `Block`,
`Layout` and `TagValue` vocabulary without promoting the old TIFF research code
or creating a production source tree/package in imageio-d.

The bridge inflates one strip/tile's zlib stream into caller-owned scratch,
enforcing its checked expected byte count, consuming exactly its declared
compressed length and verifying Adler-32. Only then does it undo horizontal
Predictor 2 and copy visible pixels to an explicit interleaved layout. Edge
tiles use full padded tile scratch. Scalar state/workspace reset between
independent zlib blocks; caller storage is reused without GC allocation.

The bounded metadata adapter supports classic TIFF, chunky unsigned homogeneous
8/16-bit samples, strips/tiles, both file byte orders and Predictor 1/2. Samples
retain their **file byte order**. GDAL's native sample output is explicitly
converted to that same byte order for byte comparison. There is no implicit
RGBA, alpha premultiplication, color conversion or native-endian conversion.
Deflate ID 8 is in the external corpus; ID 32946 is accepted by the adapter but
not separately reference-qualified. BigTIFF, planar/signed/float samples and
other predictors remain unqualified. The borrowing metadata cursor is local:
the older imageio Reader lacks `scope` member contracts and is preserved.

Geometry/products/strides, descriptor counts, compressed ranges, overlap,
destination and scratch are validated before emission. Normal file-ordered
block tables take linear range preflight; unordered tables retain a quadratic
overlap fallback (not qualified for very large unordered tables). A failing
codec block never changes its destination pixels; earlier committed blocks
remain visible and `blocksWritten` reports them. Scratch is unspecified after
failure. Capacity and codec errors remain distinguishable.

Eleven TIFF oracle images are independently encoded/decoded by GDAL 3.13.3
(`VersionInfo` 3130300 on the test host): gray/RGB, 8/16-bit, little/big endian,
five strips or six tiles with visible edges, Predictor 1/2, plus a 256x256 RGB16
16-tile workload. Both compiler outputs match every reference byte. Negatives
cover checksum/truncation, exact/short/long decoded size, compressed suffixes,
descriptor overlap/range, invalid layout, checked overflow, exactly sufficient
and one-byte-short strip/tile scratch. A padded 4x4-to-visible-3x2 tile and a
strided destination have explicit unchanged-padding guards. Another 500 bounded
metadata mutations exercise status/bounds behavior without allocating from
unchecked geometry.

## PNG scanline consumer

`experiments/consumers/png_scanlines.d` consumes the **concatenated IDAT zlib
stream**, supplied with caller-known shape. It is not a PNG chunk parser and
does not claim chunk-CRC/interlace/palette/metadata support. It accepts
non-interlaced 8/16-bit grayscale, gray-alpha, RGB and RGBA scanlines, applies
filters 0..4 and preserves network-order sample bytes and alpha values.

The caller supplies a decoder workspace, `(rowBytes + 1) * height` filtered
scratch and `rowBytes * height` output. Products are checked. The full zlib
trailer, expected filtered size, compressed consumption and all filter tags
are validated before output emission. On failure destination is unchanged;
scratch may be overwritten. This first experiment materializes the filtered
frame; it is not yet a row-streamed residency claim.

Nine PNG oracle images use independently written filtering/zlib/chunk generation
and GDAL reference decoding, including all five filters, 1..4 channels, both
sample depths, two IDAT chunks and a 256x256 RGBA8 workload. Every output byte
matches. Negative probes cover bad filters (including a late row), bad Adler,
sizes, capacities, overflow and unchanged destination guards.

## Isolation and allocation evidence

Core/bridge/filter calls compile as `@safe pure nothrow @nogc` with DIP1000.
Two actual OS threads synchronize on a barrier, then independently reuse their
own decoder/scratch/output for 2,000 TIFF and 2,000 PNG decodes. They share only
immutable encoded input and verify every result. Per-thread GC allocation
counters stay unchanged during these loops. The executable is invoked with
`--DRT-testmode=run-main`, so concurrency `main` actually runs after unit tests.

Every end-to-end/benchmark trial also checks the current-thread GC allocated
byte counter around the decode/checksum loop: **zero bytes** on both compilers.
Setup allocates file/reference/descriptor/output/scratch buffers beforehand;
this is not a claim that opening files or preparing a consumer allocates nothing.
There are no native backend calls in the D decode path. RSS below is process
RSS including runtime/setup, not a measurement of just the decoder workspace.

`InflateWorkspace.sizeof` is 39,328 bytes on both tested x86_64 compilers. The
benchmark TIFF needs 24,576 scratch bytes (one 64x64 RGB16 tile) and 393,216
output bytes, plus descriptors/input and scalar parser state. It stages each
decoded tile and places its pixels once; Predictor 2 is one additional scratch
pass. Raw history writes and benchmark checksum reads are separate work. The
PNG workload needs 262,400 filtered scratch bytes and 262,144 output bytes,
plus decoder/input/state. No full-image intermediate is used by the TIFF
bridge, while PNG filtered-frame materialization is explicit.

## Repeated measurements

Local snapshot: 2026-10-27, Linux x86_64, Intel Core i7-9750H. Baseline provider
commit `67f7fa3` plus these M4 experiment additions; imageio-d baseline
`e6fa00f` plus its preserved local research. `benchmark.json` records compiler
versions, exact dependency source hashes, baseline commits and all raw trials.
Fixtures/hashes are deterministic for the installed GDAL/zlib tool versions.

DMD: `-O -inline`; LDC: `-O3`. Both retain assertions and explicit bounds
checks, with DIP1000 enabled. Each process performs an untimed warm-up,
preflights byte equality, then runs 20 iterations. Decode calls are non-inlined
across the timing loop, and every output contributes a printed CRC checksum.
Parsing/file I/O and buffer allocation are outside timing. Each of five rounds
reverses trial order relative to the preceding round. Trials are pinned to CPU 0;
frequency/thermal state is uncontrolled. Throughput includes zlib validation,
prediction/filtering, pixel placement and a complete output CRC scan.

| Compiler | Consumer | Workspace policy | Median MB/s | Min–max MB/s | Peak RSS KiB range |
| --- | --- | --- | ---: | ---: | ---: |
| DMD 2.111.0 | TIFF | reuse | 62.16 | 58.85–63.98 | 4308–4416 |
| DMD 2.111.0 | TIFF | reinitialize | 62.19 | 53.58–63.34 | 4248–4416 |
| DMD 2.111.0 | PNG | reuse | 32.12 | 25.58–34.06 | 4112–4256 |
| DMD 2.111.0 | PNG | reinitialize | 33.51 | 26.92–34.31 | 4096–4256 |
| LDC 1.42.0 | TIFF | reuse | 92.91 | 89.29–105.24 | 4464–4592 |
| LDC 1.42.0 | TIFF | reinitialize | 102.25 | 87.55–106.61 | 4496–4572 |
| LDC 1.42.0 | PNG | reuse | 73.40 | 39.43–75.50 | 4268–4496 |
| LDC 1.42.0 | PNG | reinitialize | 73.47 | 60.86–75.12 | 4260–4396 |

Reinitialize assigns `InflateWorkspace.init` before every timed decode; reuse
does not. These ranges do **not** establish a speed benefit from reuse or a
stable regression threshold. Reuse establishes controllable residency and zero
hot-path GC growth. DMD/LDC differences are observations for these workloads,
not claims of performance parity with mature native TIFF/PNG libraries.
No GDAL timing is compared: GDAL's caching/I/O work is not the same kernel.

## Admission boundary

M4's four consumer-validation items are satisfied as **local research evidence**.
imageio-d's pre-existing uncommitted work is preserved; only the new additive
consumer directory belongs to this task there, and it is left uncommitted with
that research context. No branch restructuring, publication or production
admission is implied. M5 must still assess independent acceptance of these
research consumers, complete license/API review and decide public admission;
broader corpora/hosts remain unqualified.

References: [GDAL GTiff](https://gdal.org/en/stable/drivers/raster/gtiff.html),
[PNG filtering](https://www.w3.org/TR/png/#9Filters).
