#!/usr/bin/env python3
"""Bind the current Stripes milestone to the tested sources, references and package."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'artifacts'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tests(name, expected):
    log = (OUT / name).read_text()
    count, failures, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', log)[-1]
    assert int(count) == expected and int(failures) == 0
    assert not re.search(r'Test Case .* skipped', log)
    for suite, n in [('GradientStripesTests', 2), ('GradientStripesRenderTests', 6),
                     ('GradientStripesWorkflowTests', 2)]:
        match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", log)
        assert match and int(match[1]) == n and int(match[2]) == 0, suite
    return dict(log=name, tests=expected, failures=0, seconds=float(seconds), sha256=sha(OUT / name))


full = tests('gradient-stripes-full-tests.log', 530)
release = tests('gradient-stripes-release-tests.log', 77)
package = json.loads((OUT / 'photato-package-check.json').read_text())
binary = ROOT / 'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(ROOT / 'build/Photato.zip')
assert package['swiftpm_tests_passed'] == full['tests'] and package['clean_zip_signature_verified']
sources = sorted((ROOT / 'Sources').rglob('*.swift'))
test_sources = sorted((ROOT / 'Tests').rglob('*.swift'))
assert len(sources) == 127
start = re.search(r"Test Suite 'All tests' started at ([\d-]+ [\d:.]+)\.", (OUT / full['log']).read_text())[1]
assert all(p.stat().st_mtime <= datetime.fromisoformat(start).timestamp() for p in sources + test_sources)
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in sources)
scope = json.loads((ROOT / 'docs/GRADIENT_STRIPES_REFERENCES.json').read_text())
fixtures = json.loads((ROOT / 'docs/GRADIENT_STRIPES_FIXTURES.json').read_text())
for item in fixtures['files'] + fixtures['preserved_native_inputs'] + fixtures['supporting_references']:
    assert sha(ROOT / item['path']) == item['sha256'], item['path']
    if 'grdm_method' in item:
        data = (ROOT / item['path']).read_bytes()
        at = data.index(b'8BIMgrdm') + 12
        assert int.from_bytes(data[at:at + 2], 'big') == item['grdm_version']
        assert data[at + 4:at + 8].decode('ascii') == item['grdm_method']
metrics = json.loads((OUT / 'gradient-stripes-photoshop-comparison.json').read_text())
assert len(metrics) == 3 and all(x['changed_pixels'] == 0 and x['byte_identical'] for x in metrics)
depths = json.loads((OUT / 'gradient-stripes-depth-comparison.json').read_text())
assert [x['depth'] for x in depths] == [8, 16]
assert depths[0]['byte_identical'] and depths[0]['changed_bytes'] == 0
assert not depths[1]['byte_identical'] and depths[1]['changed_pixels'] == 928
assert depths[1]['changed_bytes'] == 3712 and depths[1]['maximum_channel_steps'] <= 1.01
assert all(x['changed_opaque_pixels'] == 0 and x['changed_alpha_samples'] == 0 for x in depths)
assert scope['evidence']['native_live_ui']['final_binary_sha256'] == sha(binary)
snapshots = ['gradient-stripes-workspace.png', 'gradient-map-workspace.png', 'gradient-library-workspace.png',
             'gradient-fill-editor.png', 'gradient-tool-workspace.png', 'classic-gradient-workspace.png',
             'gradient-fill-workspace.png', 'gradient-renderer-atlas.png', 'pattern-workspace.png', 'pattern-fill-workspace.png']
assert all((OUT / name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
upstream = [ROOT / x['path'] for x in scope['sources'] if 'path' in x]
scripts = ['scripts/build-app.sh', 'scripts/verify-app-package.py', 'scripts/verify-gradient-stripes.py',
           'scripts/generate-gradient-method-probes.py', 'scripts/inspect-gradient-method-reference.py']
report = {
    'module': 'Native Stripes gradients and Photoshop depth/import compatibility', 'date': '2026-10-08',
    'goal_pass_classification': 'progress', 'full_photoshop_parity': False, 'native_swift': True,
    'full_suite': full, 'release_focused_suite': release, 'new_module_tests': 10,
    'source_changes_after_full_suite_started': [],
    'source_hashes': {str(p.relative_to(ROOT)): sha(p) for p in sources},
    'test_source_hashes': {str(p.relative_to(ROOT)): sha(p) for p in test_sources},
    'upstream_reference_hashes': {str(p): sha(p) for p in upstream},
    'verification_script_hashes': {name: sha(ROOT / name) for name in scripts},
    'package': package, 'fixture_manifest': fixtures,
    'rgb8_pixel_comparison': metrics, 'coincident_depth_comparison': depths,
    'rgb8_exact_reference_pixels': 51200, 'native_live_ui': scope['evidence']['native_live_ui'],
    'offscreen_snapshots': {name: sha(OUT / name) for name in snapshots},
    'implemented': scope['implemented'], 'remaining': scope['remaining'],
    'historical_gradient_map_manifest': 'gradient-map-release-verification.json',
    'performance_benchmarks_rerun': False, 'storekit_integration_tests_rerun': False,
}
(OUT / 'gradient-stripes-release-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: report[k] for k in ['module', 'full_suite', 'release_focused_suite', 'rgb8_exact_reference_pixels',
                                      'coincident_depth_comparison', 'package', 'full_photoshop_parity']}, indent=2))
