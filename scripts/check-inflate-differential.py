#!/usr/bin/env python3
"""Compare a compiled Pure-D oracle with Python zlib; deterministic seed 1951."""
import hashlib
import random
import subprocess
import sys
import zlib


def main():
    rng = random.Random(1951)
    cases = []
    for index in range(240):
        length = rng.choice([0, 1, 2, 257, 258, 1024, 32768, 32769, 66000])
        mode = index % 4
        if mode == 0:
            plain = bytes(rng.randrange(256) for _ in range(length))
        elif mode == 1:
            plain = bytes([rng.randrange(256)]) * length
        elif mode == 2:
            pattern = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 1024)))
            plain = (pattern * (length // len(pattern) + 1))[:length]
        else:
            plain = bytes(rng.randrange(8) for _ in range(length))
        strategy = rng.choice([zlib.Z_DEFAULT_STRATEGY, zlib.Z_FIXED, zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE])
        encoder = zlib.compressobj(rng.randrange(10), wbits=-15, strategy=strategy)
        split = length // 2
        encoded = encoder.compress(plain[:split])
        if index % 3 == 0:
            encoded += encoder.flush(zlib.Z_SYNC_FLUSH)
        encoded += encoder.compress(plain[split:]) + encoder.flush()
        cases.append(encoded + b'\xA5\x5A')
        if encoded:
            cases.append(encoded[:rng.randrange(len(encoded))])
            mutation = bytearray(encoded)
            mutation[rng.randrange(len(mutation))] ^= 1 << rng.randrange(8)
            cases.append(bytes(mutation))
    # Reserved headers and unstructured malformed inputs.
    cases += [bytes([7]), bytes.fromhex('010100000041')]
    cases += [bytes(rng.randrange(256) for _ in range(rng.randrange(100))) for _ in range(100)]
    references = []
    for encoded in cases:
        decoder = zlib.decompressobj(wbits=-15)
        try:
            plain = decoder.decompress(encoded, 1_048_577)
            if len(plain) > 1_048_576:
                references.append(None)  # Reference exceeded the shared safety cap.
            elif decoder.eof:
                references.append((len(encoded) - len(decoder.unused_data), plain))
            else:
                references.append(False)
        except zlib.error:
            references.append(False)
    process = subprocess.run([sys.argv[1]], input='\n'.join(x.hex() for x in cases) + '\n',
                             text=True, capture_output=True, check=True)
    lines = process.stdout.splitlines()
    assert len(lines) == len(cases), (len(lines), len(cases), process.stderr)
    valid = invalid = 0
    for index, (reference, line) in enumerate(zip(references, lines)):
        status, error, consumed, produced, digest = line.split()
        if reference is None:
            continue
        if reference is False:
            assert status == 'error', (index, 'accepted malformed/truncated input', line)
            invalid += 1
        else:
            count, plain = reference
            assert (status, error, int(consumed), int(produced), digest.lower()) == (
                'done', 'none', count, len(plain), hashlib.sha256(plain).hexdigest()), (index, line)
            valid += 1
    print(f'zlib {zlib.ZLIB_VERSION}: {valid} valid outputs/counts, {invalid} rejected inputs; seed=1951')


if __name__ == '__main__':
    main()
