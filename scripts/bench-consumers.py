#!/usr/bin/env python3
"""Balanced repeated consumer benchmark; run check-consumers.sh first."""
import argparse
import json
import hashlib
import os
import pathlib
import platform
import re
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rounds', type=int, default=5)
    parser.add_argument('--iterations', type=int, default=20)
    parser.add_argument('--cpu', type=int)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    build = root / '.build/consumers'
    fixture = build / 'fixtures'
    keys = [(compiler, kernel, mode) for compiler in ['dmd', 'ldc2']
            for kernel in ['tiff', 'png'] for mode in ['reuse', 'fresh']]
    records = []
    for round_index in range(args.rounds):
        for compiler, kernel, mode in (keys if round_index % 2 == 0 else keys[::-1]):
            command = [str(build / f'{compiler}-{kernel}'), str(fixture / f'bench-{kernel}.{ "tif" if kernel == "tiff" else "idat" }'),
                       str(fixture / f'bench-{kernel}.raw')]
            if kernel == 'png':
                command += ['256', '256', '4', '8']
            command += [str(args.iterations), mode]
            if args.cpu is not None:
                command = ['taskset', '-c', str(args.cpu)] + command
            result = subprocess.run(['/usr/bin/time', '-f', 'max_rss_kib=%M'] + command,
                                    text=True, capture_output=True, check=True)
            fields = dict(re.findall(r'(\w+)=([^\s]+)', result.stdout + ' ' + result.stderr))
            record = {'round': round_index, 'compiler': compiler, 'kernel': kernel, 'mode': mode,
                      **fields}
            assert int(record['gcBytes']) == 0
            records.append(record)
    metadata = {
        'platform': platform.platform(), 'rounds': args.rounds, 'iterations': args.iterations,
        'baseline': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'dmd': subprocess.check_output(['dmd', '--version'], text=True).splitlines()[0],
        'ldc2': subprocess.check_output(['ldc2', '--version'], text=True).splitlines()[0],
        'flags': {'dmd': '-O -inline -boundscheck=on -dip1000', 'ldc2': '-O3 -boundscheck=on -dip1000'},
        'controls': 'one untimed warm-up; process-per-trial; reversed order every other round; no frequency lock',
        'cpu_affinity': args.cpu,
    }
    imageio = pathlib.Path(os.environ.get('IMAGEIO_D_ROOT', root.parent / 'd-geospatial-workspace/libs/imageio-d'))
    metadata['imageio_head'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=imageio, text=True).strip()
    paths = list((imageio / 'experiments/compression_consumer/source').glob('*.d'))
    paths += [imageio / 'experiments/tiff_core/source' / x for x in ['payload_decode.d', 'block_bridge.d', 'ifd_result.d']]
    metadata['imageio_source_sha256'] = {str(path.relative_to(imageio)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    (build / 'benchmark.json').write_text(json.dumps({'metadata': metadata, 'records': records}, indent=2) + '\n')
    for compiler, kernel, mode in keys:
        group = [x for x in records if (x['compiler'], x['kernel'], x['mode']) == (compiler, kernel, mode)]
        speeds = [float(x['MBps']) for x in group]
        rss = [int(x['max_rss_kib']) for x in group]
        print(f'{compiler:4} {kernel:4} {mode:5}: median {statistics.median(speeds):.2f} MB/s '
              f'range [{min(speeds):.2f}, {max(speeds):.2f}] RSS [{min(rss)}, {max(rss)}] KiB GC=0')
    print(build / 'benchmark.json')


if __name__ == '__main__':
    main()
