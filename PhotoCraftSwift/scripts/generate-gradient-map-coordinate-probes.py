#!/usr/bin/env python3
"""Original RGB16 source matrices for separating map tone and ramp precision."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('probes', Path(__file__).with_name('generate-smooth-gradient-probes.py'))
probes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probes)


def expand(value):
    return (value * 65535 + 16384) // 32768


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--holdout', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    working = []
    for i in range(65536):
        rgb = [(i * 10597 + 7141) % 32769, (i * 13217 + 367) % 32769, (i * 6701 + 1237) % 32769]
        if i % 8 == 0:
            rgb = [rgb[0]] * 3
        working.append(rgb)
    working[0:4] = [[0, 0, 0], [32768] * 3, [16384] * 3, [32768, 0, 0]]
    if args.holdout:
        working = []
        state = 0x50484F54
        for i in range(65536):
            rgb = []
            for _ in range(3):
                state = (state * 1664525 + 1013904223) & 0xffffffff
                rgb.append(state % 32769)
            if i % 17 == 0:
                rgb = [rgb[0]] * 3
            working.append(rgb)
    channels = [[expand(rgb[c]) for rgb in working] for c in range(3)] + [[65535] * 65536]
    colors = [tuple(expand(v * 512) for v in (i, (i * 19 + 7) % 65, (i * 43 + 29) % 65)) for i in range(65)]
    cases = [('tone-identity', [(0, 50, (0,) * 3), (4096, 50, (65535,) * 3)], 0),
             ('classic-palette65', [(i * 64, 50, rgb) for i, rgb in enumerate(colors)], 4096)]
    cases = [(name, stops, smoothness, 'Gcls') for name, stops, smoothness in cases]
    if args.holdout:
        cases = [cases[0]] + [(name + '-palette65', cases[1][1], 4096, method)
                              for name, method in [('classic', 'Gcls'), ('linear', 'Lnr '),
                                                   ('perceptual', 'Perc'), ('smooth', 'Smoo'), ('stripes', 'GIMs')]]
    manifest = []
    for name, stops, smoothness, method in cases:
        data = probes.rgb16(probes.gradient(stops, smoothness=smoothness, method=method.encode()),
                            width=256, height=256, channels=channels)
        path = output / f'input-coordinate-{name}-rgb16.psd'
        path.write_bytes(data)
        manifest.append(dict(name=name, path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                             method=method, smoothness=smoothness, stops=stops, source_working_rgb=working,
                             depth=16, width=256, height=256, merged_preview_is_stale=True,
                             provenance='Original procedural RGB16 matrix, MIT OR Apache-2.0.'))
    if args.holdout:
        stops = cases[-1][1]
        data = probes.rgb16(probes.gradient(stops, method=b'GIMs'))
        path = output / 'input-coordinate-stripes-ramp-rgb16.psd'
        path.write_bytes(data)
        manifest.append(dict(name='stripes-ramp', path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                             method='GIMs', smoothness=4096, stops=stops, depth=16, width=4097, height=4,
                             merged_preview_is_stale=True, provenance='Original Stripes LUT probe, MIT OR Apache-2.0.'))
    (output / 'inputs.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    print(json.dumps([{k: x[k] for k in ['name', 'path', 'sha256', 'smoothness', 'width', 'height']} for x in manifest], indent=2))


if __name__ == '__main__':
    main()
