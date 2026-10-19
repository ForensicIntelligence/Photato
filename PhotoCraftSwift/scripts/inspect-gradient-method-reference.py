#!/usr/bin/env python3
"""Inspect original Photoshop gradient probes independently of the Swift PSD decoder."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / 'Tests/PhotoCraftImagingTests/Fixtures'
ARTIFACTS = ROOT / 'artifacts/gradient-method-reference'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def merged(path, opaque_rgb=False):
    data = path.read_bytes()
    assert data[:6] == b'8BPS\x00\x01'
    channels, height, width, depth, mode = struct.unpack('>HIIHH', data[12:26])
    assert mode == 3 and depth in (8, 16) and (channels == 4 or opaque_rgb and channels == 3)
    at = 26
    for _ in range(3):
        at += 4 + int.from_bytes(data[at:at + 4], 'big')
    compression = int.from_bytes(data[at:at + 2], 'big')
    at += 2
    if compression == 0:
        raw = data[at:]
    else:
        assert compression == 1
        count = height * channels
        sizes = struct.unpack('>' + str(count) + 'H', data[at:at + count * 2])
        at += count * 2
        raw = bytearray()
        for size in sizes:
            row = data[at:at + size]
            at += size
            cursor = 0
            decoded = bytearray()
            while cursor < len(row):
                n = row[cursor]
                cursor += 1
                if n < 128:
                    assert cursor + n + 1 <= len(row)
                    decoded.extend(row[cursor:cursor + n + 1])
                    cursor += n + 1
                elif n > 128:
                    assert cursor < len(row)
                    decoded.extend(row[cursor:cursor + 1] * (257 - n))
                    cursor += 1
            assert len(decoded) == width * depth // 8
            raw.extend(decoded)
    assert len(raw) == width * height * channels * depth // 8
    if channels == 3:
        raw = bytes(raw) + b'\xff' * (width * height * depth // 8)
    return width, height, depth, bytes(raw)


def inspect():
    names = [
        'photoshop-stripes-three-stop-rgb8', 'photoshop-stripes-fill-three-stop-rgb8',
        'photoshop-stripes-coincident-rgb8', 'photoshop-stripes-coincident-rgb16',
        'photoshop-smooth-three-stop-0-rgb8', 'photoshop-smooth-three-stop-100-rgb8',
        'photoshop-classic-three-stop-0-rgb8', 'native-stripes-legacy-rgb32',
    ]
    files = []
    for name in names:
        path = FIXTURES / (name + '.psd')
        data = path.read_bytes()
        row = dict(path=str(path.relative_to(ROOT)), sha256=sha(path), size=len(data),
                   photoshop_saved=name.startswith('photoshop-'))
        if b'8BIMgrdm' in data:
            at = data.index(b'8BIMgrdm') + 12
            row.update(grdm_version=int.from_bytes(data[at:at + 2], 'big'),
                       grdm_method=data[at + 4:at + 8].decode('ascii'))
        if row['photoshop_saved']:
            width, height, depth, raw = merged(path)
            row.update(width=width, height=height, depth=depth,
                       stored_merged_sha256=hashlib.sha256(raw).hexdigest())
        files.append(row)
    preserved = []
    for name in ['fill-inspected-rgb8', 'coincident-inspected-rgb8',
                 'coincident-inspected-rgb16', 'coincident-inspected-rgb32']:
        path = ARTIFACTS / ('native-stripes-' + name + '.psd')
        preserved.append(dict(path=str(path.relative_to(ROOT)), sha256=sha(path)))
    # The native export was independently recalculated by toggling Reverse on/off.
    roundtrips = []
    for stem, reference in [('fill', 'photoshop-stripes-fill-three-stop-rgb8'),
                            ('coincident', 'photoshop-stripes-coincident-rgb8')]:
        a = merged(ARTIFACTS / ('native-stripes-' + stem + '-inspected-rgb8.psd'))
        b = merged(FIXTURES / (reference + '.psd'))
        assert a == b
        roundtrips.append(dict(reference=reference, pixels=a[0] * a[1],
                               stored_channels_byte_identical=True))
    smooth0 = merged(FIXTURES / 'photoshop-smooth-three-stop-0-rgb8.psd')
    smooth100 = merged(FIXTURES / 'photoshop-smooth-three-stop-100-rgb8.psd')
    assert smooth0 == smooth100
    report = {
        'date': '2026-10-08',
        'source': 'Original procedural probes opened, recalculated and saved through Photoshop 2026 UI',
        'files': files, 'preserved_native_inputs': preserved,
        'supporting_references': [dict(path=str(p.relative_to(ROOT)), sha256=sha(p))
            for p in [FIXTURES / 'photoshop-gradient-map-stripes-rgb8.psd',
                      FIXTURES / 'photoshop-gradient-map-classic-rgb8.psd']],
        'native_export_photoshop_recalculation': roundtrips,
        'smooth_0_and_100_merged_channels_identical': True,
        'smooth_is_implemented': False,
        'rgb32_observation': 'Photoshop warned about unsupported layer data, discarded the adjustment after Keep Layers, and disabled Image > Adjustments > Gradient Map. No RGB32 Photoshop output is a reference.',
        'input_generator': 'scripts/generate-gradient-method-probes.py',
        'input_merged_previews_are_stale': True,
        'qualification': 'Only Photoshop-saved output files serve as pixel references. The legacy RGB32 file is an original native persistence/rejection fixture. No installed preset library or Adobe code is copied. RGB16 partial-alpha white matting remains different.',
    }
    (ROOT / 'docs/GRADIENT_STRIPES_FIXTURES.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'files': len(files), 'independent_exact_roundtrips': roundtrips,
                      'smooth_0_and_100_identical': True}, indent=2))


if __name__ == '__main__':
    inspect()
