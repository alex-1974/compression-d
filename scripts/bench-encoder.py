#!/usr/bin/env python3
"""Small reproducible fixed-LZ encoder benchmark against Python's zlib."""
import subprocess
import time
import zlib

root = __import__("pathlib").Path(__file__).resolve().parent.parent
subprocess.run([str(root / "scripts" / "check-encoder-property.sh")], check=True,
               stdout=subprocess.DEVNULL)
d_bench = root / ".build" / "encoder-bench"
subprocess.run(["dmd", "-O", "-I" + str(root / "source"), "-of=" + str(d_bench),
                str(root / "source/compression/bitstream.d"),
                str(root / "source/compression/checksum.d"),
                str(root / "source/compression/core.d"),
                str(root / "source/compression/deflate.d"),
                str(root / "source/compression/encode.d"),
                str(root / "source/compression/framing.d"),
                str(root / "source/compression/huffman.d"),
                str(root / "source/compression/zlib.d"),
                str(root / "tests/encoder_bench.d")], check=True)
print(subprocess.check_output([str(d_bench)], text=True).strip())
corpus = bytes((ord('A') + (i % 11)) if i % 37 < 32 else (i * 13) & 0xff
               for i in range(155648))
rounds = 40
start = time.perf_counter()
for _ in range(rounds):
    zlib.compress(corpus, 6)
zlib_seconds = time.perf_counter() - start
print(f"zlib: bytes={len(corpus)} rounds={rounds} MB/s={len(corpus)*rounds/zlib_seconds/1e6:.2f}")
zlib_size = len(zlib.compress(corpus, 6))
print(f"zlib: compressed={zlib_size} level=6")
print("compression-d encoder property probe: 256 deterministic roundtrips passed")
