#!/usr/bin/env python3
"""Inspect Photoshop-authored probe PSDs without using the native renderer."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parent.parent
FOLDER = ROOT / 'artifacts/gradient-map-reference'

def merged(path):
    data = path.read_bytes()
    assert data[:6] == b'8BPS\x00\x01'
    channels, height, width, depth, mode = struct.unpack('>HIIHH', data[12:26])
    assert depth == 8 and mode == 3 and channels in (3, 4)
    at = 26
    for _ in range(3):
        size = int.from_bytes(data[at:at + 4], 'big')
        at += 4 + size
    code = int.from_bytes(data[at:at + 2], 'big')
    at += 2
    if code == 0:
        raw = data[at:]
    elif code == 1:
        lengths = struct.unpack('>' + str(channels * height) + 'H', data[at:at + channels * height * 2])
        at += channels * height * 2
        raw = bytearray()
        for size in lengths:
            row = data[at:at + size]
            at += size
            offset = 0
            unpacked = bytearray()
            while offset < len(row):
                count = row[offset]
                offset += 1
                if count < 128:
                    unpacked.extend(row[offset:offset + count + 1])
                    offset += count + 1
                elif count > 128:
                    unpacked.extend(row[offset:offset + 1] * (257 - count))
                    offset += 1
            assert len(unpacked) == width
            raw.extend(unpacked)
    else:
        raise ValueError('Unsupported probe compression')
    assert len(raw) == width * height * channels
    rgba = bytes(raw[ch * width * height + i] if ch < channels else 255 for i in range(width * height) for ch in range(4))
    return width, height, rgba

def inspect():
    reports = []
    for path in sorted(FOLDER.glob('photoshop-gradient-map-*.psd')):
        data = path.read_bytes()
        at = data.index(b'8BIMgrdm')
        size = int.from_bytes(data[at + 8:at + 12], 'big')
        record = data[at + 12:at + 12 + size]
        version = int.from_bytes(record[:2], 'big')
        method = record[4:8].decode('ascii') if version == 3 else 'Clsc'
        width, height, rgba = merged(path)
        path.with_suffix('.merged-rgba8').write_bytes(rgba)
        path.with_suffix('.grdm').write_bytes(record)
        samples = [0, 16, 32, 64, 96, 127, 128, 160, 192, 224, 240, 255]
        report = dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(data).hexdigest(),
                      version=version, method=method, reverse=bool(record[2]), dither=bool(record[3]),
                      width=width, height=height, gray=[rgba[x * 4] for x in samples],
                      red=[rgba[(8 * width + x) * 4] for x in [64, 128, 192, 255]],
                      green=[rgba[(16 * width + x) * 4] for x in [64, 128, 192, 255]],
                      blue=[rgba[(24 * width + x) * 4] for x in [64, 128, 192, 255]])
        reports.append(report)
        print(path.name, method, report['gray'], report['red'], report['green'], report['blue'])
    (FOLDER / 'record-inspection.json').write_text(json.dumps(reports, indent=2) + '\n')
    return reports

if __name__ == '__main__':
    inspect()
