#!/usr/bin/env python3
"""Create original Gradient Map input cases; Photoshop must recalculate and save outputs.

Only the retained grdm controls are replaced in our original Photoshop-authored probe.
Merged previews remain stale by design and are NEVER used as output references.
"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'artifacts/gradient-method-reference'
OUT.mkdir(exist_ok=True)
SOURCE = ROOT / 'Tests/PhotoCraftImagingTests/Fixtures/photoshop-gradient-map-classic-rgb8.psd'

def n(value, size):
    return value.to_bytes(size, 'big')

def replace_grdm(data, record):
    at = 26
    for _ in range(2):
        at += 4 + int.from_bytes(data[at:at+4], 'big')
    outer = at
    outer_len = int.from_bytes(data[outer:outer+4], 'big')
    inner = outer + 4
    inner_len = int.from_bytes(data[inner:inner+4], 'big')
    count = abs(int.from_bytes(data[inner+4:inner+6], 'big', signed=True))
    at = inner + 6
    for _ in range(count):
        channel_count = int.from_bytes(data[at+16:at+18], 'big')
        extra = at + 18 + channel_count * 6 + 12
        extra_len = int.from_bytes(data[extra:extra+4], 'big')
        tag = data.find(b'8BIMgrdm', extra+4, extra+4+extra_len)
        if tag != -1:
            length = int.from_bytes(data[tag+8:tag+12], 'big')
            end = tag + 12 + length + length % 2
            replacement = b'8BIMgrdm' + n(len(record), 4) + record + b'\0' * (len(record) % 2)
            result = bytearray(data[:tag] + replacement + data[end:])
            delta = len(replacement) - (end-tag)
            for offset, old in [(extra, extra_len), (inner, inner_len), (outer, outer_len)]:
                result[offset:offset+4] = n(old+delta, 4)
            return bytes(result)
        at = extra + 4 + extra_len
    raise ValueError('Missing original Gradient Map layer')

def grdm(method, smoothness, opacity=True):
    name = 'Original three-color probe\0'.encode('utf-16-be')
    data = n(3, 2) + b'\0\0' + method.encode('ascii') + n(len(name)//2, 4) + name
    stops = [(512, 50, (218, 47, 91)), (2048, 25, (37, 190, 83)), (3584, 75, (39, 92, 231))]
    data += n(len(stops), 2)
    for position, midpoint, rgb in stops:
        data += n(position, 4) + n(midpoint, 4) + n(0, 2)
        data += b''.join(n(c*257, 2) for c in rgb) + n(0, 2) + n(0, 2)
    alphas = [(0, 50, 0), (1434, 20, 64), (3686, 80, 255)] if opacity else [(0, 50, 255), (4096, 50, 255)]
    data += n(len(alphas), 2)
    for position, midpoint, alpha in alphas:
        data += n(position, 4) + n(midpoint, 4) + n(alpha, 2)
    data += n(2, 2) + n(smoothness, 2) + n(32, 2) + n(0, 2)
    data += n(0, 4) + n(0, 2) + n(1, 2) + n(2048, 4) + n(3, 2)
    data += b''.join(n(v, 2) for v in [0,0,0,0,32768,32768,32768,32768]) + n(0, 2)
    return data + b'\0' * (-len(data) % 4)

def main():
    records = []
    for method, smoothness, opacity in [('GIMs', 4096, True), ('Smoo', 4096, True), ('Smoo', 0, True), ('Gcls', 0, True)]:
        name = f'input-{method.strip().lower()}-smoothness-{smoothness}-rgb8.psd'
        data = replace_grdm(SOURCE.read_bytes(), grdm(method, smoothness, opacity))
        path = OUT / name
        path.write_bytes(data)
        records.append(dict(path=str(path.relative_to(ROOT)), method=method, smoothness=smoothness,
                            sha256=hashlib.sha256(data).hexdigest(), merged_preview_is_stale=True))
        print(path)
    (OUT / 'inputs.json').write_text(json.dumps(records, indent=2)+'\n')

if __name__ == '__main__':
    main()
