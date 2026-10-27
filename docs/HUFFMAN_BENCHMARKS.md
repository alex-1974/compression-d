# Huffman lookup experiments

Reproduce with `bash scripts/bench-huffman.sh 20 12345`. The script compiles
DMD with `-O -inline` and LDC with `-O3`, retaining assertions and bounds checks.
Arguments select the number of decode passes and the runtime corpus seed.

Each corpus has 65,536 deterministically generated symbols. The fixed corpus
samples all 288 structural fixed-tree symbols, including reserved ones. The
deep corpus samples a complete synthetic tree with lengths 1..14,15,15.
Neither corpus represents a complete compressed file or real-world frequencies.

Corpus creation and one warm-up pass occur outside the timed region. Each
variant decodes the same bytes. Every symbol contributes to a rolling checksum,
which is printed and checked against the original generated symbol sequence.
Non-inlined pass functions and runtime inputs prevent whole-loop constant
folding. Tree builds are measured separately (2,000 builds at the default
pass count) and their success count is consumed and printed. The core methods
have `@nogc` compile probes; benchmark setup allocates its corpus outside timing.

Illustrative local run on 2026-10-27, Linux x86_64, Intel Core i7-9750H:

| Compiler | Corpus | Root bits | Workspace bytes | Million symbols/s | Build µs |
| --- | --- | ---: | ---: | ---: | ---: |
| DMD 2.111.0 | fixed | 0 | 708 | 8.07 | 1.4 |
| DMD 2.111.0 | fixed | 9 | 2,756 | 26.20 | 8.0 |
| DMD 2.111.0 | deep-15 | 0 | 708 | 6.06 | 0.3 |
| DMD 2.111.0 | deep-15 | 9 | 2,756 | 5.74 | 5.3 |
| LDC 1.42.0 | fixed | 0 | 708 | 32.76 | 1.1 |
| LDC 1.42.0 | fixed | 9 | 2,756 | 98.88 | 3.1 |
| LDC 1.42.0 | deep-15 | 0 | 708 | 29.48 | 0.1 |
| LDC 1.42.0 | deep-15 | 9 | 2,756 | 30.95 | 0.6 |

Both strategies/compilers produced checksum `14467969053391168196` for the
fixed corpus and `1835156834334950852` for deep-15 with these arguments.

The nine-bit table costs 2,048 extra bytes and improves fixed-tree lookup by
about 3x in this run. It does not consistently improve deep-tree lookup and
costs more to build. Both variants remain available: nine bits is the default
lookup choice; zero is the compact option and comparison baseline. An Inflate
consumer can choose differently after representative end-to-end measurements.

These are single-run observations, subject to scheduling, CPU frequency and
compiler optimization. They measure symbol lookup rather than decompression
MB/s and establish no regression thresholds. Image-consumer throughput and
complete workspace/memory measurements remain M4.
