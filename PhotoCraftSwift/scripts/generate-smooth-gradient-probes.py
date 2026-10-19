#!/usr/bin/env python3
"""Original Smooth input probes; Photoshop must recalculate their stale previews."""
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('probes', Path(__file__).with_name('generate-gradient-method-probes.py'))
probes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probes)


def section(data):
    return struct.pack('>I', len(data)) + data


def gradient(stops, smoothness=4096, method=b'Smoo', opacity=None):
    name = 'Original Smooth investigation\0'.encode('utf-16-be')
    data = b'\0\3\0\0' + method + struct.pack('>I', len(name) // 2) + name
    data += struct.pack('>H', len(stops))
    for location, midpoint, rgb in stops:
        data += struct.pack('>II6H', location, midpoint, 0, *rgb, 0, 0)
    opacity = [(0, 50, 255), (4096, 50, 255)] if opacity is None else opacity
    data += struct.pack('>H', len(opacity))
    for location, midpoint, alpha in opacity:
        data += struct.pack('>IIH', location, midpoint, alpha)
    data += struct.pack('>4H', 2, smoothness, 32, 0)
    data += struct.pack('>IHHIH8HH', 0, 0, 1, 2048, 3, 0, 0, 0, 0, 32768, 32768, 32768, 32768, 0)
    return data + b'\0' * (-len(data) % 4)


def rgb16(record, width=4097, height=4, channels=None):
    def expand(value):
        return (value * 65535 + 16384) // 32768
    if channels is None:
        channels = [[expand(x * 8) for y in range(height) for x in range(width)]] * 3
        channels += [[65535 if y < 3 else 32768 for y in range(height) for x in range(width)]]
    assert len(channels) == 4 and all(len(c) == width * height for c in channels)
    packed = [b'\0\0' + struct.pack('>' + str(width * height) + 'H', *c) for c in channels]
    def layer(name, w, h, planes, flags=0, tags=b''):
        label = bytes([len(name)]) + name
        label += b'\0' * (-len(label) % 4)
        extra = section(b'') + section(b'') + label + tags
        data = struct.pack('>iiiiH', 0, 0, h, w, 4)
        data += b''.join(struct.pack('>hI', cid, len(p)) for cid, p in zip([0, 1, 2, -1], planes))
        return data + b'8BIMnorm\xff\0' + bytes([flags, 0]) + section(extra)
    tags = b'8BIMgrdm' + section(record)
    info = struct.pack('>h', -2) + layer(b'Original grayscale samples', width, height, packed)
    info += layer(b'Smooth Gradient Map', 0, 0, [b'\0\0'] * 4, 24, tags)
    info += b''.join(packed) + b'\0\0' * 4
    info += b'\0' * (-len(info) % 4)
    layer_mask = section(b'') + section(b'') + b'8BIMLr16' + section(info)
    template = (ROOT / 'artifacts/gradient-method-reference/native-stripes-coincident-inspected-rgb16.psd').read_bytes()
    at = 26 + 4 + int.from_bytes(template[26:30], 'big')
    resources = template[at + 4:at + 4 + int.from_bytes(template[at:at + 4], 'big')]
    header = b'8BPS\0\1' + b'\0' * 6 + struct.pack('>HIIHH', 4, height, width, 16, 3)
    return header + section(b'') + section(resources) + section(layer_mask) + b'\0\0' + b''.join(p[2:] for p in packed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    black, white = (0, 0, 0), (65535, 65535, 65535)
    cases = [
        ('neutral-rgb16', [(0, 50, black), (4096, 50, white)], 4096, 16),
        ('neutral-zero-rgb8', [(0, 50, black), (4096, 50, white)], 0, 8),
        ('midpoint20-rgb8', [(0, 50, black), (4096, 20, white)], 4096, 8),
        ('gray-range-rgb8', [(0, 50, (16448,) * 3), (4096, 50, (49344,) * 3)], 4096, 8),
        ('red-blue-rgb8', [(0, 50, (65535, 0, 0)), (4096, 50, (0, 0, 65535))], 4096, 8),
        ('three-neutral-midpoints-rgb8', [(512, 50, (56026, 12079, 23387)), (2048, 50, (9509, 48830, 21331)), (3584, 50, (10023, 23644, 59367))], 4096, 8),
        ('gray-range-rgb16', [(0, 50, (16448,) * 3), (4096, 50, (49344,) * 3)], 4096, 16),
        ('red-blue-rgb16', [(0, 50, (65535, 0, 0)), (4096, 50, (0, 0, 65535))], 4096, 16),
    ]
    source = ROOT / 'Tests/PhotoCraftImagingTests/Fixtures/photoshop-gradient-map-classic-rgb8.psd'
    report = []
    for name, stops, smoothness, depth in cases:
        path = args.output / ('input-smooth-' + name + '.psd')
        assert not path.exists(), 'Preserve existing probes; choose a new output directory'
        record = gradient(stops, smoothness)
        data = rgb16(record) if depth == 16 else probes.replace_grdm(source.read_bytes(), record)
        path.write_bytes(data)
        report.append(dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                           depth=depth, stops=stops, smoothness=smoothness, method='Smoo',
                           merged_preview_is_stale=True, original_procedural_data=True))
    (args.output / 'inputs.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
