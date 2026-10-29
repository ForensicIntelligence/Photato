#!/usr/bin/env python3
"""Independent PSD channel vectors crossing 64 KiB input/row boundaries.

Original fixtures, MIT OR Apache-2.0. Python stdlib only; not a Photato encoder
roundtrip or a live Photoshop rendering reference. Prediction uses Adobe's
public PSD format and the original PhotoCraft compression module's layout.
"""
from pathlib import Path
import hashlib, json, random, struct, zlib

root = Path(__file__).resolve().parent.parent
out = root / 'Tests/PhotoCraftImagingTests/Fixtures/psd-stream'
out.mkdir(exist_ok=True)
manifest = {'origin': __doc__, 'license': 'MIT OR Apache-2.0', 'cases': []}
for depth, width, height in [(8, 257, 257), (16, 257, 131), (32, 20000, 3)]:
    row_bytes = width * (depth // 8)
    raw = random.Random(120 + depth).randbytes(row_bytes * height)
    if depth == 32:
        # Retain random mantissas/signs but exclude non-finite float encodings.
        raw = b''.join(struct.pack('>I', n & 0xBFFFFFFF)
                       for (n,) in struct.iter_unpack('>I', raw))
    raw_name = f'rgb{depth}.raw'
    (out / raw_name).write_bytes(raw)
    for compression in [2, 3]:
        encoded = bytearray()
        for start in range(0, len(raw), row_bytes):
            row = raw[start:start + row_bytes]
            if compression == 3:
                if depth == 16:
                    values = list(struct.unpack('>' + 'H' * width, row))
                    row = b''.join(struct.pack('>H', n if i == 0 else (n - values[i-1]) % 65536)
                                   for i, n in enumerate(values))
                else:
                    if depth == 32:
                        row = b''.join(row[k::4] for k in range(4))
                    row = bytes(n if i == 0 else (n - row[i-1]) % 256 for i, n in enumerate(row))
            encoded.extend(row)
        data = struct.pack('>H', compression) + zlib.compress(encoded)
        assert len(data) > 65536
        name = f'rgb{depth}-compression{compression}.channel'
        (out / name).write_bytes(data)
        manifest['cases'].append(dict(file=name, raw=raw_name, width=width,
                                     height=height, depth=depth,
                                     sha256=hashlib.sha256(data).hexdigest(),
                                     rawSHA256=hashlib.sha256(raw).hexdigest()))
(out / 'provenance.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'cases': len(manifest['cases']), 'bytes': sum(p.stat().st_size for p in out.iterdir())}))
