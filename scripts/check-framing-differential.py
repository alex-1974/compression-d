#!/usr/bin/env python3
"""Deterministic framed decode/checksum comparison with Python zlib, seed 1952."""
import gzip
import hashlib
import importlib.util
import pathlib
import random
import subprocess
import sys
import zlib

sys.dont_write_bytecode = True


def main():
    rng = random.Random(1952)
    cases = []
    for mode, wbits in [('z', 15), ('g', 31)]:
        for index in range(120):
            length = rng.choice([0, 1, 5, 257, 1024, 32768, 66000])
            if index % 3 == 0:
                plain = bytes(rng.randrange(256) for _ in range(length))
            elif index % 3 == 1:
                plain = bytes([rng.randrange(256)]) * length
            else:
                pattern = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 1024)))
                plain = (pattern * (length // len(pattern) + 1))[:length]
            encoder = zlib.compressobj(rng.randrange(10), wbits=wbits,
                                      strategy=rng.choice([zlib.Z_DEFAULT_STRATEGY, zlib.Z_FIXED, zlib.Z_HUFFMAN_ONLY]))
            encoded = encoder.compress(plain) + encoder.flush()
            cases.append((mode, encoded + b'\xA5\x5A'))
            cases.append((mode, encoded[:rng.randrange(len(encoded))]))
            bad = bytearray(encoded)
            bad[rng.randrange(len(bad))] ^= 1 << rng.randrange(8)
            cases.append((mode, bytes(bad)))
    spec = importlib.util.spec_from_file_location('fixtures', pathlib.Path(__file__).with_name('generate-framing-fixtures.py'))
    fixtures = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixtures)
    for flags in range(32):
        encoded = fixtures.optional_gzip(b'header options', flags)
        cases.append(('g', encoded))
        for index in [-1, -8, 0, 3]:
            bad = bytearray(encoded)
            bad[index] ^= 0x80
            cases.append(('g', bytes(bad)))
    for index in range(40):
        first = gzip.compress(bytes([index]) * rng.randrange(2000), mtime=0)
        second = gzip.compress(bytes([index + 1]) * rng.randrange(2000), mtime=0)
        cases.extend([('a', first + second), ('a', first + second[:-1]), ('a', first + b'\x42')])
    encoder = zlib.compressobj(zdict=b'example dictionary')
    cases.append(('z', encoder.compress(b'example dictionary hello') + encoder.flush()))
    references = []
    for mode, encoded in cases:
        remaining = encoded
        plain = b''
        consumed = 0
        try:
            while True:
                decoder = zlib.decompressobj(wbits=15 if mode == 'z' else 31)
                chunk = decoder.decompress(remaining, 1_048_577 - len(plain))
                plain += chunk
                if len(plain) > 1_048_576:
                    references.append(None)
                    break
                if not decoder.eof:
                    references.append(False)
                    break
                consumed += len(remaining) - len(decoder.unused_data)
                remaining = decoder.unused_data
                if mode != 'a' or not remaining:
                    references.append((consumed, plain))
                    break
        except zlib.error:
            references.append(False)
    process = subprocess.run([sys.argv[1]], input=''.join(f'{mode} {data.hex()}\n' for mode, data in cases),
                             text=True, capture_output=True, check=True)
    lines = process.stdout.splitlines()
    assert len(lines) == len(cases), process.stderr
    valid = invalid = 0
    for index, (reference, line) in enumerate(zip(references, lines)):
        status, error, consumed, produced, digest = line.split()
        if reference is None:
            continue
        if reference is False:
            assert status == 'error', (index, 'accepted malformed/truncated frame', line)
            invalid += 1
        else:
            count, plain = reference
            assert (status, error, int(consumed), int(produced), digest.lower()) == (
                'done', 'none', count, len(plain), hashlib.sha256(plain).hexdigest()), (index, line)
            valid += 1
    print(f'zlib {zlib.ZLIB_VERSION}: {valid} valid frames, {invalid} rejected frames; seed=1952')


if __name__ == '__main__':
    main()
