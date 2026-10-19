#!/usr/bin/env python3
"""Record the qualified Gradient Fill source, tests, fixtures and packaged binary."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / 'artifacts'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def result(name):
    text = (out / name).read_text()
    count, failed, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', text)[-1]
    assert int(failed) == 0 and 'Test Case ' in text and not re.search(r'Test Case .* skipped', text)
    return dict(tests=int(count), failures=int(failed), seconds=float(seconds), log=name, sha256=sha(out / name))

full = result('gradient-fill-full-tests.log')
release = result('gradient-fill-release-tests.log')
assert full['tests'] == 484 and release['tests'] == 67
package = json.loads((out / 'photato-package-check.json').read_text())
binary = root / 'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(root / 'build/Photato.zip')
assert package['swiftpm_tests_passed'] == full['tests']
assert package['clean_zip_signature_verified']
source_paths = sorted((root / 'Sources').rglob('*.swift'))
assert len(source_paths) == 118
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in source_paths)
test_paths = [root / x for x in [
    'Tests/PhotoCraftCoreTests/GradientFillTests.swift',
    'Tests/PhotoCraftImagingTests/GradientFillRenderTests.swift',
    'Tests/PhotoCraftImagingTests/PSDMergedSampleTests.swift',
    'Tests/PhotoCraftAppTests/GradientFillWorkflowTests.swift',
]]
snapshots = ['gradient-fill-workspace.png', 'gradient-fill-editor.png']
assert all((out / name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
refs = json.loads((out / 'psd-gradient-fixture-manifest.json').read_text())
for item in refs['files']:
    assert sha(root / item['fixture_path']) == item['sha256']
metrics = json.loads((out / 'gradient-fill-reference.json').read_text())
exact = next(x for x in metrics if x['name'] == 'reference-layers-gradient-fill')
assert exact['byte_identical'] and exact['changed_pixels'] == 0
scope = json.loads((root / 'docs/GRADIENT_FILL_REFERENCES.json').read_text())
report = {
    'module': scope['module'], 'date': scope['date'], 'goal_pass_classification': 'progress',
    'full_photoshop_parity': False, 'native_swift': True,
    'full_suite': full, 'release_focused_suite': release, 'new_module_tests': 15,
    'package': package, 'source_hashes': {str(p.relative_to(root)): sha(p) for p in source_paths},
    'test_hashes': {str(p.relative_to(root)): sha(p) for p in test_paths},
    'snapshot_hashes': {name: sha(out / name) for name in snapshots},
    'fixture_manifest': refs, 'saved_reference_metrics': metrics,
    'source_changes_after_final_suite': [],
    'ui_verified_scope': 'Native offscreen layout plus AppKit event-routing tests; Mac remains locked',
    'live_photoshop_2026_verified': False,
    'macos_runtime_matrix_complete': False,
    'historical_storekit_tests_rerun': False,
    'historical_render_benchmarks_rerun': False,
    'remaining': scope['remaining'],
}
(out / 'gradient-fill-release-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print('Verified Gradient Fill:', full['tests'], 'full tests;', release['tests'], 'release tests; binary', package['binary_sha256'])
