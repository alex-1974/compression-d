#!/usr/bin/env python3
"""Generate TIFF through GDAL and PNG through independent filter math + zlib.

GDAL re-decodes every image; raw reference bytes come from GDAL ReadRaster.
Run with the system Python that provides osgeo, not a downloaded dependency.
"""
import argparse
import hashlib
import pathlib
import struct
import sys
import zlib
from osgeo import gdal

gdal.UseExceptions()


def pixels(width, height, bands, depth, order='='):
    values = [(x * 37 + y * 59 + b * 71 + x * y) % 256 if depth == 8 else
              (x * 251 + y * 503 + b * 30001 + x * y * 17) % 65536
              for y in range(height) for x in range(width) for b in range(bands)]
    return bytes(values) if depth == 8 else struct.pack(order + 'H' * len(values), *values)


def reference(ds, width, height, bands, depth, byteorder):
    sample = depth // 8
    data = ds.ReadRaster(0, 0, width, height, buf_type=gdal.GDT_Byte if depth == 8 else gdal.GDT_UInt16,
                         band_list=list(range(1, bands + 1)), buf_pixel_space=bands * sample,
                         buf_line_space=width * bands * sample, buf_band_space=sample)
    if depth == 16 and byteorder != sys.byteorder:
        swapped = bytearray(data)
        swapped[0::2], swapped[1::2] = data[1::2], data[0::2]
        data = bytes(swapped)
    return data


def tiff(out, name, width, height, bands, depth, tiled, predictor, big=False):
    filename = out / (name + '.tif')
    options = ['COMPRESS=DEFLATE', f'PREDICTOR={predictor}', 'INTERLEAVE=PIXEL',
               'BIGTIFF=NO', 'ENDIANNESS=' + ('BIG' if big else 'LITTLE'), 'ZLEVEL=6', 'NUM_THREADS=1']
    options += ['TILED=YES', 'BLOCKXSIZE=16', 'BLOCKYSIZE=16'] if tiled else ['TILED=NO', 'BLOCKYSIZE=7']
    if name.startswith('bench-'):
        options = [x for x in options if not x.startswith(('BLOCKXSIZE=', 'BLOCKYSIZE='))]
        options += ['BLOCKXSIZE=64', 'BLOCKYSIZE=64']
    ds = gdal.GetDriverByName('GTiff').Create(str(filename), width, height, bands,
         gdal.GDT_Byte if depth == 8 else gdal.GDT_UInt16, options=options)
    ds.WriteRaster(0, 0, width, height, pixels(width, height, bands, depth),
                   buf_type=gdal.GDT_Byte if depth == 8 else gdal.GDT_UInt16,
                   band_list=list(range(1, bands + 1)), buf_pixel_space=bands * (depth // 8),
                   buf_line_space=width * bands * (depth // 8), buf_band_space=depth // 8)
    ds = None
    ds = gdal.Open(str(filename))
    expected = reference(ds, width, height, bands, depth, 'big' if big else 'little')
    assert expected == pixels(width, height, bands, depth, '>' if big else '<')
    (out / (name + '.raw')).write_bytes(expected)
    return f'tiff\t{filename}\t{out / (name + ".raw")}\n'


def paeth(a, b, c):
    p = a + b - c
    distances = [abs(p - a), abs(p - b), abs(p - c)]
    return (a, b, c)[distances.index(min(distances))]


def png(out, name, width, height, bands, depth):
    plain = pixels(width, height, bands, depth, '>')
    stride, row = bands * (depth // 8), width * bands * (depth // 8)
    filtered = bytearray()
    for y in range(height):
        method = y % 5
        filtered.append(method)
        for x in range(row):
            offset = y * row + x
            left = plain[offset - stride] if x >= stride else 0
            up = plain[offset - row] if y else 0
            upper_left = plain[offset - row - stride] if y and x >= stride else 0
            predicted = (0, left, up, (left + up) // 2, paeth(left, up, upper_left))[method]
            filtered.append((plain[offset] - predicted) & 255)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    color = {1: 0, 2: 4, 3: 2, 4: 6}[bands]
    encoded = zlib.compress(filtered)
    file = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, depth, color, 0, 0, 0))
    # Multiple IDAT chunks; the consumer receives their single concatenated stream.
    middle = len(encoded) // 2
    file += chunk(b'IDAT', encoded[:middle]) + chunk(b'IDAT', encoded[middle:]) + chunk(b'IEND', b'')
    filename = out / (name + '.png')
    filename.write_bytes(file)
    ds = gdal.Open(str(filename))
    expected = reference(ds, width, height, bands, depth, 'big')
    assert expected == plain
    (out / (name + '.raw')).write_bytes(expected)
    (out / (name + '.idat')).write_bytes(encoded)
    return f'png\t{out / (name + ".idat")}\t{out / (name + ".raw")}\t{width}\t{height}\t{bands}\t{depth}\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=pathlib.Path)
    args = parser.parse_args()
    out = args.directory.resolve()
    out.mkdir(parents=True, exist_ok=True)
    manifest = ''
    for tiled in [False, True]:
        for depth, bands, predictor, big in [(8, 1, 1, False), (8, 3, 2, False),
                (16, 1, 1, False), (16, 3, 2, False), (16, 3, 2, True)]:
            name = f'tiff-{int(tiled)}-{depth}-{bands}-p{predictor}-{int(big)}'
            manifest += tiff(out, name, 37, 29, bands, depth, tiled, predictor, big)
    for depth in [8, 16]:
        for bands in [1, 2, 3, 4]:
            manifest += png(out, f'png-{depth}-{bands}', 19, 13, bands, depth)
    manifest += tiff(out, 'bench-tiff', 256, 256, 3, 16, True, 2)
    manifest += png(out, 'bench-png', 256, 256, 4, 8)
    (out / 'manifest.tsv').write_text(manifest)
    hashes = ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n'
                     for path in sorted(out.iterdir()) if path.suffix in ['.tif', '.png', '.raw', '.idat'])
    (out / 'SHA256SUMS').write_text(hashes)
    print(f'GDAL {gdal.VersionInfo()} zlib {zlib.ZLIB_VERSION}: 11 TIFF + 9 PNG oracle fixtures, {out}')


if __name__ == '__main__':
    main()
