#!/usr/bin/env python3
"""Independently decode bounded Smooth controls and exact-stop RGB16 samples."""
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('reference', Path(__file__).with_name('inspect-smooth-gradient-probes.py'))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    assert not args.output.exists()
    results = []
    inputs = [(item, 'reproduced-01') for item in json.loads((run / 'inputs-01/inputs.json').read_text())]
    if (run / 'inputs-02/inputs.json').exists():
        inputs += [(item, 'reproduced-02') for item in json.loads((run / 'inputs-02/inputs.json').read_text())]
    for item, reproduction in inputs:
        source = ROOT / item['path']
        saved = source.with_name(source.name.replace('input-', 'photoshop-', 1))
        reproduced = run / reproduction / source.name
        assert reference.digest(source) == item['sha256'] == reference.digest(reproduced)
        before = reference.controls(source, tuple(range(1, 101)), item['method'])
        after = reference.controls(saved, tuple(range(1, 101)), item['method'])
        assert before == after and before['color_stops'] == item['stops']
        width, height, depth, raw = reference.reference.merged(saved)
        assert (width, height, depth) == (4097, 4, 16)
        assert raw != reference.reference.merged(source)[3]
        values = struct.unpack('>' + str(len(raw) // 2) + 'H', raw)
        pixels = width * height
        assert len(values) == pixels * 4
        assert all(a == 65535 for a in values[pixels * 3:pixels * 3 + width * 3])
        # All three opaque rows receive the same Gradient Map coordinate.
        for channel in range(3):
            plane = values[channel * pixels:(channel + 1) * pixels]
            assert plane[:width] == plane[width:2 * width] == plane[2 * width:3 * width]
        stops = {x: rgb for x, _, rgb in after['color_stops']}
        samples = []
        for x in item['sample_positions']:
            expected = stops[x]
            actual = [values[c * pixels + x] for c in range(3)]
            samples.append(dict(x=x, stop_rgb=expected, output_rgb=actual,
                                difference=[a - b for a, b in zip(actual, expected)]))
        results.append(dict(name=item['name'], input=reference.identity(source),
                            photoshop=reference.identity(saved), reproduced_input=reference.identity(reproduced),
                            saved_controls_unchanged=True, stop_count=len(stops), samples=samples,
                            different_samples=sum(any(x['difference']) for x in samples),
                            maximum_stored_level_difference=max(abs(d) for s in samples for d in s['difference']),
                            merged_sha256=hashlib.sha256(raw).hexdigest()))
    by_name = {r['name']: r for r in results}
    comparisons = []
    original_colors = {tuple(s['stop_rgb']): s for s in by_name['color65']['samples']}
    for name in ['reversed-color65', 'plateau-color32', 'classic-color65', 'linear-color65', 'perceptual-color65']:
        if name not in by_name:
            continue
        pairs = [(original_colors[tuple(s['stop_rgb'])], s) for s in by_name[name]['samples']]
        diffs = [dict(color=b['stop_rgb'], original_x=a['x'], other_x=b['x'],
                      original_output=a['output_rgb'], other_output=b['output_rgb'],
                      difference=[y - x for x, y in zip(a['output_rgb'], b['output_rgb'])]) for a, b in pairs]
        comparisons.append(dict(other=name, pairs=len(pairs),
                                different_samples=sum(any(s['difference']) for s in diffs),
                                maximum_stored_level_difference=max(abs(d) for s in diffs for d in s['difference']),
                                samples=diffs))
    report = dict(step='dev-step-049', cases=results, color_context_comparisons=comparisons,
                  provenance='Original procedural probes recalculated through Photoshop 2026 UI.',
                  license='MIT OR Apache-2.0',
                  scope='Opaque exact-stop samples and saved controls; no inference that arbitrary interpolation is implemented.',
                  generator=reference.identity(ROOT / 'scripts/generate-bounded-smooth-palettes.py'),
                  inspector=reference.identity(Path(__file__).resolve()))
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(cases=[{k: r[k] for k in ['name', 'stop_count', 'saved_controls_unchanged', 'different_samples', 'maximum_stored_level_difference']} for r in results],
                          comparisons=[{k: r[k] for k in ['other', 'pairs', 'different_samples', 'maximum_stored_level_difference']} for r in comparisons]), indent=2))


if __name__ == '__main__':
    main()
