#!/usr/bin/env python3
"""Original boundary probes for Photoshop Gradient Map stop retention."""
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
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(exist_ok=False)
    report = []
    for name, count, alpha_count, depth, method in [
        ('classic-colors100-rgb16', 100, 2, 16, 'Gcls'),
        ('classic-colors101-rgb16', 101, 2, 16, 'Gcls'),
        ('stripes-colors101-rgb8', 101, 2, 8, 'GIMs'),
        ('classic-opacity100-rgb16', 2, 100, 16, 'Gcls'),
        ('classic-opacity101-rgb16', 2, 101, 16, 'Gcls'),
    ]:
        stops = [(round(i * 4096 / (count - 1)), 50,
                  tuple(expand(v) for v in [round(i * 32768 / (count - 1))] * 3)) for i in range(count)]
        opacity = [(round(i * 4096 / (alpha_count - 1)), 50,
                    round(i * 255 / (alpha_count - 1))) for i in range(alpha_count)]
        record = probes.gradient(stops, method=method.encode(), opacity=opacity)
        base = ROOT / 'Tests/PhotoCraftImagingTests/Fixtures/photoshop-gradient-map-classic-rgb8.psd'
        data = probes.rgb16(record) if depth == 16 else probes.probes.replace_grdm(base.read_bytes(), record)
        path = out / ('input-' + name + '.psd')
        path.write_bytes(data)
        report.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                           color_stops=stops, opacity_stops=opacity, method=method, depth=depth,
                           merged_preview_is_stale=True, original_procedural_data=True))
    (out / 'inputs.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps([dict(path=r['path'], colors=len(r['color_stops']), opacity=len(r['opacity_stops']),
                          sha256=r['sha256']) for r in report], indent=2))


if __name__ == '__main__':
    main()
