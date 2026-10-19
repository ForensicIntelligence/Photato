#!/usr/bin/env python3
"""Validate original Smooth research inputs/references without the Swift decoder.

This is bounded diagnostic code for these original probes, not a general PSD reader.
It does not certify a Smooth renderer or infer acquisition actions from file bytes.
"""
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    'reference', Path(__file__).with_name('inspect-gradient-method-reference.py'))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return dict(path=str(path.relative_to(ROOT)), sha256=digest(path), bytes=path.stat().st_size)


def controls(path, expected_counts=(2, 3), expected_method='Smoo', expected_reverse=False):
    data = path.read_bytes()
    assert data.count(b'8BIMgrdm') == 1, 'Expected exactly one Gradient Map record'
    at = data.index(b'8BIMgrdm')
    size = int.from_bytes(data[at + 8:at + 12], 'big')
    record = data[at + 12:at + 12 + size]
    assert len(record) == size and record[:8] == b'\0\3' + bytes([int(expected_reverse), 0]) + expected_method.encode()
    at = 12 + int.from_bytes(record[8:12], 'big') * 2
    count = int.from_bytes(record[at:at + 2], 'big')
    assert count in expected_counts
    at += 2
    stops = []
    for _ in range(count):
        location, midpoint, space, r, g, b, c4, unused = struct.unpack('>II6H', record[at:at + 20])
        assert space == c4 == unused == 0
        stops.append([location, midpoint, [r, g, b]])
        at += 20
    count = int.from_bytes(record[at:at + 2], 'big')
    assert count == 2
    at += 2
    opacity = []
    for _ in range(count):
        opacity.append(list(struct.unpack('>IIH', record[at:at + 10])))
        at += 10
    assert opacity == [[0, 50, 255], [4096, 50, 255]]
    interpolation, smoothness, expansion, reserved = struct.unpack('>4H', record[at:at + 8])
    assert (interpolation, expansion, reserved) == (2, 32, 0)
    return dict(version=3, method=expected_method, reverse=expected_reverse, dither=False,
                color_stops=stops, opacity_stops=opacity, smoothness=smoothness)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    assert not args.output.exists(), 'Choose a distinct report name; preserve earlier attempts'
    inputs = [item for folder in ('inputs-02', 'inputs-03')
              for item in json.loads((run / folder / 'inputs.json').read_text())]
    assert len(inputs) == 8
    results = []
    for item in inputs:
        original = ROOT / item['path']
        reproduced = run / 'reproduced-inputs' / original.name
        saved = original.with_name(original.name.replace('input-', 'photoshop-', 1))
        assert digest(original) == item['sha256'] == digest(reproduced)
        expected = controls(original)
        assert expected['color_stops'] == item['stops']
        assert expected['smoothness'] == item['smoothness']
        actual = controls(saved)
        # These saves normalize color components on the 0...32768 working grid.
        def normalized(value):
            working = (value * 32768 + 32767) // 65535
            return (working * 65535 + 16384) // 32768
        normalized_controls = dict(expected, color_stops=[
            [location, midpoint, [normalized(c) for c in rgb]]
            for location, midpoint, rgb in expected['color_stops']])
        assert actual == normalized_controls, 'Unexpected saved control changes'
        differences = [dict(stop=index, channel=channel, input=a, saved=b)
                       for index, (before, after) in enumerate(zip(expected['color_stops'], actual['color_stops']))
                       for channel, (a, b) in enumerate(zip(before[2], after[2])) if a != b]
        iw, ih, idepth, stale = reference.merged(original)
        width, height, depth, pixels = reference.merged(saved)
        assert (iw, ih, idepth) == (width, height, depth)
        assert pixels != stale, 'Reference must not contain the stale input preview'
        results.append(dict(input=identity(original), reproduced_input=identity(reproduced),
                            photoshop_output=identity(saved), input_controls=expected,
                            saved_controls=actual, color_component_changes=differences,
                            width=width, height=height, depth=depth,
                            merged_sha256=hashlib.sha256(pixels).hexdigest(),
                            identical_regenerated_input=True,
                            saved_controls_match_working_grid_normalization=True,
                            differs_from_stale_input_preview=True))
    new = run / 'inputs-02/photoshop-smooth-neutral-zero-rgb8.psd'
    old = ROOT / 'Tests/PhotoCraftImagingTests/Fixtures/photoshop-gradient-map-smooth-rgb8.psd'
    assert reference.merged(new) == reference.merged(old)
    report = dict(step='dev-step-046', reference_count=8, references=results,
                  neutral_smoothness_0_100_merged_identical=True,
                  older_neutral_reference=identity(old),
                  provenance='Original procedural inputs; saved through the Photoshop 2026 UI. See DEVLOG step 046 for acquisition actions.',
                  license='Original probe data contributed under MIT OR Apache-2.0; no Adobe code or preset libraries copied.',
                  implementation_status='Smooth remains unsupported. These are research references, not a parity certification.',
                  limitations=['Record scanning is bounded to these single-grdm probes.',
                               'Merged preview validation does not compare base-layer channels or all PSD metadata.',
                               'Input previews are stale and cannot serve as expected renderer outputs.'],
                  generator=identity(ROOT / 'scripts/generate-smooth-gradient-probes.py'),
                  decoder=identity(ROOT / 'scripts/inspect-gradient-method-reference.py'),
                  inspector=identity(Path(__file__).resolve()))
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(references=8, regenerated_inputs_identical=8,
                          working_grid_normalized_saved_controls=8,
                          files_with_color_component_changes=sum(bool(r['color_component_changes']) for r in results),
                          distinct_saved_previews=8,
                          neutral_smoothness_0_100_merged_identical=True), indent=2))


if __name__ == '__main__':
    main()
