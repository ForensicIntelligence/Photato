#!/usr/bin/env python3
"""Create an original full-range RGB16/alpha PSD probe (never a Photoshop oracle).

Each of the 65,536 alpha codes occurs once. RGB combines full-period permutations
and a repeating boundary palette. Photoshop's saved layer planes let the analysis
separate import quantization from merged-composite white matting.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def section(data):
    return struct.pack('>I', len(data)) + data


def generate():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    path = args.output / 'original-rgb16-matte-matrix.psd'
    assert not path.exists(), 'Preserve the existing input; use a new experiment directory'
    width = height = 256
    count = width * height
    boundaries = [0, 1, 2, 3, 127, 128, 255, 256, 32766, 32767, 32768, 32769,
                  65532, 65533, 65534, 65535]
    planes = [[(i * 40503) & 65535 for i in range(count)],
              [(i * 8191 + 31) & 65535 for i in range(count)],
              [boundaries[i % len(boundaries)] for i in range(count)],
              list(range(count))]
    raw = [struct.pack('>' + str(count) + 'H', *p) for p in planes]
    channels = [b'\0\0' + p for p in raw]
    name = b'Original alpha and color matrix'
    name = bytes([len(name)]) + name
    name += b'\0' * (-len(name) % 4)
    extra = section(b'') + section(b'') + name
    record = struct.pack('>hiiiiH', -1, 0, 0, height, width, 4)
    record += b''.join(struct.pack('>hI', cid, len(c))
                       for cid, c in zip([0, 1, 2, -1], channels))
    record += b'8BIMnorm\xff\0\0\0' + section(extra)
    record += b''.join(channels)
    record += b'\0' * (-len(record) % 4)
    layer_mask = section(b'') + section(b'') + b'8BIMLr16' + section(record)
    # Reuse only this project's own resolution and standard sRGB ICC resources.
    template = ROOT / 'artifacts/gradient-method-reference/native-stripes-coincident-inspected-rgb16.psd'
    data = template.read_bytes()
    at = 26 + 4 + int.from_bytes(data[26:30], 'big')
    resources = data[at + 4:at + 4 + int.from_bytes(data[at:at + 4], 'big')]
    header = b'8BPS\0\1' + b'\0' * 6 + struct.pack('>HIIHH', 4, height, width, 16, 3)
    # Deliberately white preview: force an actual Photoshop recalculation before use.
    preview = b'\xff' * (count * 2 * 3) + raw[3]
    result = header + section(b'') + section(resources) + section(layer_mask) + b'\0\0' + preview
    path.write_bytes(result)
    report = dict(input=path.name, input_sha256=hashlib.sha256(result).hexdigest(),
                  width=width, height=height, depth=16, pixels=count,
                  alpha_codes='Every integer 0...65535, once',
                  red='(index * 40503) & 65535', green='(index * 8191 + 31) & 65535',
                  blue_boundaries=boundaries,
                  layer_planes_sha256=[hashlib.sha256(p).hexdigest() for p in raw],
                  preview_is_stale=True, photoshop_saved=False,
                  resource_template=str(template.relative_to(ROOT)),
                  resource_template_sha256=hashlib.sha256(data).hexdigest(),
                  license='Original procedural test data: MIT OR Apache-2.0')
    (args.output / 'input-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    generate()
