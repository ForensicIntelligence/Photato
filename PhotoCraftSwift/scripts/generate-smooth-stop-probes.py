#!/usr/bin/env python3
"""Original dense stop palettes for measuring color conversion independently of easing."""
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
    cases = [
        ('gray-palette', [(i * 8, 50, (expand(i * 64),) * 3) for i in range(513)]),
        ('color-palette', [(i * 8, 50, tuple(expand(v * 64) for v in
                             (i, (i * 149 + 73) % 513, (i * 307 + 151) % 513)))
                           for i in range(513)]),
        ('constant-gray', [(0, 50, (49343,) * 3), (4096, 50, (49343,) * 3)]),
    ]
    manifest = []
    for name, stops in cases:
        data = probes.rgb16(probes.gradient(stops))
        path = out / ('input-smooth-' + name + '-rgb16.psd')
        path.write_bytes(data)
        manifest.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                             stops=stops, method='Smoo', smoothness=4096, depth=16,
                             sample_at_stop_x_positions=True, merged_preview_is_stale=True,
                             original_procedural_data=True))
    (out / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps([dict(path=m['path'], sha256=m['sha256'], stops=len(m['stops'])) for m in manifest], indent=2))


if __name__ == '__main__':
    main()
