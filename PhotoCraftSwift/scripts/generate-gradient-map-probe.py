#!/usr/bin/env python3
"""Reproduce the original RGBA8 probe used for Photoshop Gradient Map references."""
from pathlib import Path
import struct
import zlib

root = Path(__file__).resolve().parent.parent
path = root / 'artifacts/gradient-map-reference/gradient-map-probe-rgb8.png'
rows = bytearray()
for y in range(64):
    rows.append(0)  # PNG filter: none
    for x in range(256):
        if y < 8:
            rgb = (x, x, x)
        elif y < 16:
            rgb = (x, 0, 0)
        elif y < 24:
            rgb = (0, x, 0)
        elif y < 32:
            rgb = (0, 0, x)
        else:
            rgb = ((73*x + 17*y) % 256, (29*x + 83*y) % 256, (11*x + 47*y) % 256)
        rows.extend((*rgb, 255 if y < 48 else (31*x + 19*y) % 256))

def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 64, 8, 6, 0, 0, 0))
png += chunk(b'sRGB', b'\x00') + chunk(b'IDAT', zlib.compress(rows, 6)) + chunk(b'IEND', b'')
if path.exists():
    assert path.read_bytes() == png, 'Existing reference probe differs; preserve it for investigation'
else:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
print(path)
