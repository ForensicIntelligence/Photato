#!/usr/bin/env python3
"""Original RGB16 analytic-stop probes. Input merged previews are intentionally stale."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('probes', Path(__file__).with_name('generate-smooth-gradient-probes.py'))
probes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probes)


def encoded_lightness(value):
    linear = value ** 3
    encoded = 12.92 * linear if linear <= .0031308 else 1.055 * linear ** (1 / 2.4) - .055
    working = int(encoded * 32768 + .5)
    return (working * 65535 + 16384) // 32768


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--gray-boundaries', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(exist_ok=False)
    cases = [
        ('three-linear-lightness', [(0, 0), (2048, .5), (4096, 1)]),
        ('three-black-plateau', [(0, 0), (2048, 0), (4096, 1)]),
        ('three-white-plateau', [(0, 0), (2048, 1), (4096, 1)]),
        ('narrow-two-stops', [(1024, 0), (3072, 1)]),
        ('five-linear-lightness', [(0, 0), (1024, .25), (2048, .5), (3072, .75), (4096, 1)]),
    ]
    if args.gray_boundaries:
        def lightness(value):
            encoded = value / 65535
            return (((encoded + .055) / 1.055) ** 2.4) ** (1 / 3)
        low, high = lightness(16448), lightness(49343)
        cases = [
            ('three-gray-plateau', [(0, low), (2048, low), (4096, high)]),
            ('narrow-gray-stops', [(1024, low), (3072, high)]),
        ]
    manifest = []
    for name, positions in cases:
        stops = [(position, 50, (encoded_lightness(value),) * 3) for position, value in positions]
        record = probes.gradient(stops)
        data = probes.rgb16(record)
        path = out / ('input-smooth-' + name + '-rgb16.psd')
        path.write_bytes(data)
        manifest.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                             stops=stops, intended_analysis_lightness=positions, smoothness=4096,
                             method='Smoo', depth=16, merged_preview_is_stale=True,
                             original_procedural_data=True))
    (out / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
