#!/usr/bin/env python3
"""Decode original input and Photoshop-saved Gradient Map stop-limit records."""
import argparse
import base64
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def record(path):
    data = path.read_bytes()
    assert data.count(b'8BIMgrdm') == 1
    offset = data.index(b'8BIMgrdm')
    size = int.from_bytes(data[offset + 8:offset + 12], 'big')
    value = data[offset + 12:offset + 12 + size]
    assert len(value) == size and value[:4] == b'\0\3\0\0'
    assert value[4:8] in (b'Gcls', b'GIMs')
    at = 12 + int.from_bytes(value[8:12], 'big') * 2
    count = int.from_bytes(value[at:at + 2], 'big')
    assert 1 <= count <= 1000
    at += 2
    colors = []
    for _ in range(count):
        position, midpoint, space, r, g, b, extra, reserved = struct.unpack('>II6H', value[at:at + 20])
        assert space == extra == reserved == 0
        colors.append([position, midpoint, [r, g, b]])
        at += 20
    count = int.from_bytes(value[at:at + 2], 'big')
    assert count <= 1000
    at += 2
    opacity = []
    for _ in range(count):
        opacity.append(list(struct.unpack('>IIH', value[at:at + 10])))
        at += 10
    assert struct.unpack('>4H', value[at:at + 8]) == (2, 4096, 32, 0)
    return value, dict(method=value[4:8].decode(), color_stops=colors, opacity_stops=opacity)


def identity(path):
    return dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--fixture', type=Path)
    args = parser.parse_args()
    assert not args.output.exists()
    if args.fixture:
        assert not args.fixture.exists()
    run = args.run.resolve()
    results, fixtures = [], []
    for item in json.loads((run / 'limits-01/inputs.json').read_text()):
        source = ROOT / item['path']
        saved = source.with_name(source.name.replace('input-', 'photoshop-', 1))
        input_record, before = record(source)
        output_record, after = record(saved)
        assert identity(source)['sha256'] == item['sha256']
        assert before == {k: item[k] for k in before}
        assert after['method'] == before['method']
        assert after['color_stops'] == before['color_stops'][:100]
        assert after['opacity_stops'] == before['opacity_stops'][:100]
        name = source.stem.removeprefix('input-')
        results.append(dict(name=name, input=identity(source), photoshop=identity(saved),
                            input_colors=len(before['color_stops']), saved_colors=len(after['color_stops']),
                            input_opacity=len(before['opacity_stops']), saved_opacity=len(after['opacity_stops']),
                            exact_prefix_retained=True))
        fixtures.append(dict(name=name, inputRecord=base64.b64encode(input_record).decode(),
                             photoshopRecord=base64.b64encode(output_record).decode(),
                             inputColors=len(before['color_stops']), inputOpacity=len(before['opacity_stops'])))
    report = dict(step='dev-step-048', cases=results,
                  source='Original procedural probes recalculated and saved via Photoshop 2026 UI.',
                  license='MIT OR Apache-2.0; no Adobe code or preset libraries copied.',
                  warning='Photoshop explicitly warns that excess color/transparency stops will be removed. Warnings were accepted only for disposable original probes.',
                  scope='Gradient Map grdm controls only; this does not qualify Gradient Fill, GRD or rendered pixel equality.',
                  generator=identity(ROOT / 'scripts/generate-gradient-map-limit-probes.py'),
                  inspector=identity(Path(__file__).resolve()))
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    if args.fixture:
        args.fixture.write_text(json.dumps(dict(provenance=report['source'], license=report['license'], cases=fixtures), indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
