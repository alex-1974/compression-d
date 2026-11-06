# TIFF-compatible LZW decoder

`compression.lzw` implements the TIFF LZW variant: MSB-first codes, 9--12 bit
code widths, Clear (256), EOI (257), and the TIFF early-change width rule. The
decoder is allocation-free and uses a caller-owned `LzwWorkspace` containing a
fixed 4096-entry dictionary and decode stack. `decodeLzw` is resumable and
applies the common `Result` and `DecodeLimits` contracts.

TIFF strip/tile boundaries, expected decoded sizes, predictors, and pixel
layout remain consumer responsibilities. The decoder stops at EOI and leaves
following bytes unconsumed.
