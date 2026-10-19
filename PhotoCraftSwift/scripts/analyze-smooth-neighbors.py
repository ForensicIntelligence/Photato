#!/usr/bin/env python3
"""Inspect original Smooth analytic-stop probes independently of the Swift renderer."""
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


inspector = module('inspector', 'inspect-smooth-gradient-probes.py')
analysis = module('analysis', 'analyze-smooth-gradient.py')


def samples(path):
    width, height, depth, raw = inspector.reference.merged(path)
    assert (width, height, depth) == (4097, 4, 16)
    values = struct.unpack('>' + str(len(raw) // 2) + 'H', raw)
    assert all(v == 65535 for v in values[width * height * 3:width * (height * 3 + 1)])
    rows = [list(values[width * height * c:width * (height * c + 1)]) for c in range(3)]
    return rows, hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    assert not args.output.exists(), 'Use a distinct output for every experiment'
    entries = [entry for path in sorted(run.glob('inputs-*/inputs.json'))
               for entry in json.loads(path.read_text())]
    results = []
    for entry in entries:
        source = ROOT / entry['path']
        saved = source.with_name(source.name.replace('input-', 'photoshop-', 1))
        assert inspector.digest(source) == entry['sha256']
        before = inspector.controls(source, (2, 3, 5))
        after = inspector.controls(saved, (2, 3, 5))
        assert before == after, 'These input stop values already use the working grid'
        rows, merged_hash = samples(saved)
        values = rows[0]
        low = analysis.lightness(values[0] / 65535)
        high = analysis.lightness(values[-1] / 65535)
        assert samples(source)[1] != merged_hash
        results.append(dict(input=inspector.identity(source), saved=inspector.identity(saved),
                            controls=after, controls_byte_values_preserved=True,
                            merged_sha256=merged_hash, first_row=values, first_row_rgb=rows,
                            neutral_channel_differences=[dict(channel=c,
                                changed=sum(a != b for a, b in zip(values, rows[c])),
                                maximum=max(abs(a - b) for a, b in zip(values, rows[c])))
                                for c in (1, 2)],
                            lightness_samples=[[x, analysis.lightness(values[x] / 65535)]
                                               for x in range(0, 4097, 256)],
                            normalized_lightness_samples=[[x, (analysis.lightness(values[x] / 65535) - low) / (high - low)]
                                                          for x in range(0, 4097, 256)]))
    report = dict(step='dev-step-047', references=results, reference_count=len(results),
                  first_row_is_opaque=True,
                  lightness_is_analysis_assumption=True,
                  lightness_samples_use_red_channel_as_neutral_approximation=True,
                  provenance='Original neutral analytical probes; recalculated by Reverse on/off and saved via Photoshop 2026 UI.',
                  license='MIT OR Apache-2.0; no Adobe code or preset libraries copied',
                  native_implementation_changed=False)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps([dict(file=row['saved']['path'], samples=row['lightness_samples'])
                      for row in results], indent=2))


if __name__ == '__main__':
    main()
