#!/usr/bin/env python3
"""Bind Gradient Map evidence to final sources, original references and packaged app."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
out = root / 'artifacts'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tests(name, expected):
    log = (out / name).read_text()
    count, failures, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', log)[-1]
    assert int(count) == expected and int(failures) == 0
    assert not re.search(r'Test Case .* skipped', log)
    for suite in ['GradientMapTests', 'GradientMapRenderTests', 'GradientMapWorkflowTests']:
        match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", log)
        assert match and int(match[1]) == 4 and int(match[2]) == 0, suite
    return dict(log=name, tests=expected, failures=0, seconds=float(seconds), sha256=sha(out / name))

full = tests('gradient-map-full-tests.log', 520)
release = tests('gradient-map-release-tests.log', 67)
package = json.loads((out / 'photato-package-check.json').read_text())
binary = root / 'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(root / 'build/Photato.zip')
assert package['swiftpm_tests_passed'] == full['tests'] and package['clean_zip_signature_verified']
sources = sorted((root / 'Sources').rglob('*.swift'))
test_sources = sorted((root / 'Tests').rglob('*.swift'))
assert len(sources) == 127
start = re.search(r"Test Suite 'All tests' started at ([\d-]+ [\d:.]+)\.", (out / full['log']).read_text())[1]
start_time = datetime.fromisoformat(start).timestamp()
assert all(p.stat().st_mtime <= start_time for p in sources + test_sources), 'Source changed after suite started'
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in sources)
snapshots = ['gradient-map-workspace.png', 'gradient-library-workspace.png', 'gradient-fill-editor.png', 'gradient-tool-workspace.png', 'classic-gradient-workspace.png', 'gradient-fill-workspace.png', 'gradient-renderer-atlas.png', 'pattern-workspace.png', 'pattern-fill-workspace.png']
assert all((out / name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
scope = json.loads((root / 'docs/GRADIENT_MAP_REFERENCES.json').read_text())
fixtures = json.loads((root / 'docs/GRADIENT_MAP_FIXTURES.json').read_text())
assert scope['evidence']['native_live_ui']['final_binary_sha256'] == sha(binary)
for item in fixtures['files'] + [fixtures['source_probe'], fixtures['native_export_ui']]:
    assert sha(root / item['path']) == item['sha256'], item['path']
for item in fixtures['files']:
    data = (root / item['path']).read_bytes()
    at = data.index(b'8BIMgrdm') + 12
    assert int.from_bytes(data[at:at + 2], 'big') == item['grdm_version']
    assert data[at + 4:at + 8].decode('ascii') == item['grdm_method']
metrics = json.loads((out / 'gradient-map-photoshop-comparison.json').read_text())
assert len(metrics) == 3
for item in metrics:
    assert item['changed_pixels'] == scope['evidence']['changed_pixels'][item['method']]
    assert item['alpha_changed_samples'] == 0 and item['maximum_channel_steps'] <= 1.01
    assert item['byte_identical'] is False
assert next(x for x in metrics if x['method'] == 'Classic')['gray_changed_pixels'] == 0
upstream = [root / item['path'] for item in scope['sources'] if 'path' in item]
report = {
    'module': 'Native Gradient Map adjustment', 'date': '2026-10-08',
    'goal_pass_classification': 'progress', 'native_swift': True, 'full_photoshop_parity': False,
    'full_suite': full, 'release_focused_suite': release, 'new_module_tests': 12,
    'source_hashes': {str(p.relative_to(root)): sha(p) for p in sources},
    'test_source_hashes': {str(p.relative_to(root)): sha(p) for p in test_sources},
    'upstream_reference_hashes': {str(p): sha(p) for p in upstream},
    'source_changes_after_full_suite_started': [], 'package': package,
    'fixture_manifest': fixtures, 'photoshop_pixel_comparison': metrics,
    'photoshop_reference_pixels_per_method': 16384,
    'photoshop_methods_compared': ['Classic', 'Linear', 'Perceptual'],
    'unsupported_photoshop_methods': ['Smooth', 'Stripes'],
    'native_export_live_ui_inspection': fixtures['native_export_ui'],
    'native_export_photoshop_recalculated_pixels_verified': False,
    'offscreen_snapshots': {name: sha(out / name) for name in snapshots},
    'native_live_pointer_keyboard_qualification_complete': False,
    'native_live_ui': scope['evidence']['native_live_ui'],
    'verification_script_hashes': {name: sha(root / name) for name in ['scripts/build-app.sh', 'scripts/verify-app-package.py', 'scripts/verify-gradient-map.py', 'scripts/generate-gradient-map-probe.py', 'scripts/inspect-gradient-map-reference.py']},
    'implemented': scope['implemented'], 'remaining': scope['remaining'],
    'historical_library_manifest': 'gradient-library-release-verification.json',
    'historical_storekit_results_rerun': False, 'performance_benchmarks_rerun': False,
}
(out / 'gradient-map-release-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k not in ['source_hashes', 'test_source_hashes', 'upstream_reference_hashes', 'fixture_manifest', 'implemented', 'remaining']}, indent=2))
