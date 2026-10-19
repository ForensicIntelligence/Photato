#!/usr/bin/env python3
"""Original <=100-stop RGB16 Smooth probes; Photoshop must recalculate them."""
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
    parser.add_argument('--conversion-controls', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    gray = [(expand(i * 512),) * 3 for i in range(65)]
    colors = [tuple(expand(v * 512) for v in (i, (i * 19 + 7) % 65, (i * 43 + 29) % 65)) for i in range(65)]
    cases = [(name, [(i * 64, 50, rgb) for i, rgb in enumerate(palette)], list(range(0, 4097, 64)))
             for name, palette in [('gray65', gray), ('color65', colors), ('reversed-color65', colors[::-1])]]
    plateau_colors = colors[::2][:32]
    plateau_stops = [(0, 50, plateau_colors[0])]
    plateau_stops += [(i * 128 + dx, 50, rgb) for i, rgb in enumerate(plateau_colors) for dx in (32, 64, 96)]
    plateau_stops += [(4096, 50, plateau_colors[-1])]
    cases.append(('plateau-color32', plateau_stops, [i * 128 + 64 for i in range(32)]))
    cases = [(name, stops, positions, 'Smoo') for name, stops, positions in cases]
    if args.conversion_controls:
        cases = [(name, [(i * 64, 50, rgb) for i, rgb in enumerate(colors)], list(range(0, 4097, 64)), method)
                 for name, method in [('classic-color65', 'Gcls'), ('linear-color65', 'Lnr '), ('perceptual-color65', 'Perc')]]
    manifest = []
    for name, stops, positions, method in cases:
        assert len(stops) <= 100 and stops[0][0] == 0 and stops[-1][0] == 4096
        data = probes.rgb16(probes.gradient(stops, method=method.encode()))
        path = output / f'input-smooth-{name}-rgb16.psd'
        path.write_bytes(data)
        manifest.append(dict(name=name, path=str(path.relative_to(ROOT)),
                             sha256=hashlib.sha256(data).hexdigest(), stops=stops,
                             sample_positions=positions, method=method, depth=16, smoothness=4096,
                             width=4097, height=4, merged_preview_is_stale=True,
                             provenance='Original procedural color data on the RGB16 0...32768 working grid.',
                             license='MIT OR Apache-2.0'))
    (output / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps([dict(name=x['name'], stops=len(x['stops']), samples=len(x['sample_positions']), sha256=x['sha256']) for x in manifest], indent=2))


if __name__ == '__main__':
    main()
