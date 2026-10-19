#!/usr/bin/env python3
"""Bind the RGB16 matte correction to saved references, tests and the final package."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
RUN = ROOT / 'artifacts/runs/20261008T190318Z-045-rgb16-matte-investigation'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tests(name, expected):
    path = RUN / name
    log = path.read_text()
    count, failures, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', log)[-1]
    assert int(count) == expected and int(failures) == 0
    assert not re.search(r'Test Case .* skipped', log)
    for suite, n in [('PSDMergedSampleTests', 5), ('GradientStripesRenderTests', 6)]:
        match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", log)
        assert match and int(match[1]) == n and int(match[2]) == 0, suite
    assert 'RGB16 Photoshop alpha matrix: 0 changed stored bytes in 65,536 pixels' in log
    assert 'Stripes Photoshop coincident RGB16: 0 changed stored bytes' in log
    return dict(path=str(path.relative_to(ROOT)), tests=expected, failures=0,
                seconds=float(seconds), sha256=sha(path))


full = tests('full-tests.log', 532)
optimized = tests('release-tests.log', 79)
scope = json.loads((ROOT / 'docs/RGB16_MATTE_REFERENCES.json').read_text())
reference = scope['reference']
assert sha(ROOT / reference['path']) == reference['sha256']
assert sha(ROOT / reference['input']) == reference['input_sha256']
independent = json.loads((RUN / 'analysis-03.json').read_text())
assert independent['reference_sha256'] == reference['sha256']
assert independent['input_sha256'] == reference['input_sha256']
assert independent['saved_layer_vs_working_grid_expansion'] == [0, 0, 0, 0]
assert independent['merged_alpha_vs_saved_layer_differences'] == 0
assert independent['candidates']['working_grid_subtract_rounded_distance']['differing_pixels'] == 0
assert independent['candidates']['working_grid_round']['differing_pixels'] == 8385
depths = json.loads((ROOT / 'artifacts/gradient-stripes-depth-comparison.json').read_text())
assert [x['depth'] for x in depths] == [8, 16]
assert all(x['byte_identical'] and x['changed_bytes'] == 0 for x in depths)
package = json.loads((ROOT / 'artifacts/photato-package-check.json').read_text())
binary = ROOT / 'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(ROOT / 'build/Photato.zip')
assert package['swiftpm_tests_passed'] == 532 and package['clean_zip_signature_verified']
sources = sorted((ROOT / 'Sources').rglob('*.swift'))
test_sources = sorted((ROOT / 'Tests').rglob('*.swift'))
assert len(sources) == 127 and len(test_sources) == 112
started = re.search(r"Test Suite 'All tests' started at ([\d-]+ [\d:.]+)\.", (RUN / 'full-tests.log').read_text())[1]
assert all(p.stat().st_mtime <= datetime.fromisoformat(started).timestamp() for p in sources + test_sources)
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in sources)
live = json.loads((RUN / 'live-export-verification.json').read_text())
assert live['binary_sha256'] == sha(binary) and live['merged_channels_byte_identical']
assert live['straight_layer_channels_byte_identical'] and live['pixels'] == 65536
assert sha(ROOT / live['export_path']) == live['export_sha256']
recalculated = live['photoshop_recalculation']
assert recalculated['merged_channels_byte_identical'] and recalculated['straight_layer_channels_byte_identical']
assert sha(ROOT / recalculated['path']) == recalculated['sha256']
snapshots = ['gradient-stripes-workspace.png', 'gradient-map-workspace.png', 'gradient-library-workspace.png',
             'gradient-fill-editor.png', 'gradient-tool-workspace.png', 'classic-gradient-workspace.png',
             'gradient-fill-workspace.png', 'gradient-renderer-atlas.png', 'pattern-workspace.png', 'pattern-fill-workspace.png']
assert all((ROOT / 'artifacts' / name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
assert all(sha(RUN / 'final-artifacts' / name) == sha(ROOT / 'artifacts' / name) for name in snapshots)
report = dict(module='Native RGB16 PSD merged transparency', date='2026-10-08',
              goal_pass_classification='progress', full_photoshop_parity=False,
              full_suite=full, optimized_suite=optimized, new_tests=2,
              source_hashes={str(p.relative_to(ROOT)): sha(p) for p in sources},
              test_source_hashes={str(p.relative_to(ROOT)): sha(p) for p in test_sources},
              source_changes_after_full_suite_started=[],
              fixture_manifest=scope, independent_analysis=independent,
              coincident_stripes_depth_comparison=depths,
              package=package, live_export=live,
              offscreen_snapshots={str((RUN / 'final-artifacts' / name).relative_to(ROOT)):
                                   sha(RUN / 'final-artifacts' / name) for name in snapshots},
              verification_script_hashes={str(p.relative_to(ROOT)): sha(p) for p in [
                  Path(__file__), ROOT / 'scripts/verify-app-package.py', ROOT / 'scripts/build-app.sh',
                  ROOT / 'scripts/generate-rgb16-matte-probe.py', ROOT / 'scripts/inspect-rgb16-matte-reference.py']},
              prior_release='artifacts/gradient-stripes-release-verification.json',
              storekit_integration_tests_rerun=False, performance_benchmarks_rerun=False)
output = RUN / 'release-verification.json'
assert not output.exists(), 'Preserve this verification and use a new filename for a revised attempt'
output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: report[k] for k in ['module', 'full_suite', 'optimized_suite', 'package', 'full_photoshop_parity']}, indent=2))
