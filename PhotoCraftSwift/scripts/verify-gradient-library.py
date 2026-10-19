#!/usr/bin/env python3
"""Bind gradient-library checks to the final tested sources and universal package."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
out = root / 'artifacts'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def tests(name):
    log = (out / name).read_text()
    count, failures, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', log)[-1]
    assert int(failures) == 0 and not re.search(r'Test Case .* skipped', log)
    return dict(log=name, tests=int(count), failures=0, seconds=float(seconds), sha256=sha(out / name))

full = tests('gradient-library-full-tests.log')
release = tests('gradient-library-release-tests.log')
assert full['tests'] == 508 and release['tests'] == 55
for suite, count in [('GradientLibraryTests', 7), ('GradientLibraryWorkflowTests', 5)]:
    for result in [full, release]:
        match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", (out / result['log']).read_text())
        assert match and int(match[1]) == count and int(match[2]) == 0, suite
package = json.loads((out / 'photato-package-check.json').read_text())
binary = root / 'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(root / 'build/Photato.zip')
assert package['swiftpm_tests_passed'] == full['tests'] and package['clean_zip_signature_verified']
sources = sorted((root / 'Sources').rglob('*.swift'))
test_sources = sorted((root / 'Tests').rglob('*.swift'))
assert len(sources) == 124
start = re.search(r"Test Suite 'All tests' started at ([\d-]+ [\d:.]+)\.", (out / full['log']).read_text())[1]
start_time = datetime.fromisoformat(start).timestamp()
assert all(p.stat().st_mtime <= start_time for p in sources + test_sources), 'Source changed after suite started'
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in sources)
snapshots = ['gradient-library-workspace.png', 'gradient-fill-editor.png', 'gradient-tool-workspace.png', 'classic-gradient-workspace.png']
assert all((out / name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
scope = json.loads((root / 'docs/GRADIENT_LIBRARY_REFERENCES.json').read_text())
upstream = [root / item['path'] for item in scope['sources'] if 'path' in item]
report = {
    'module': 'Persistent native gradient preset library', 'date': '2026-10-08',
    'goal_pass_classification': 'progress', 'native_swift': True, 'full_photoshop_parity': False,
    'full_suite': full, 'release_focused_suite': release, 'new_module_tests': 12,
    'source_hashes': {str(p.relative_to(root)): sha(p) for p in sources},
    'test_source_hashes': {str(p.relative_to(root)): sha(p) for p in test_sources},
    'upstream_reference_hashes': {str(p): sha(p) for p in upstream},
    'source_changes_after_full_suite_started': [], 'package': package,
    'native_restart_exact_ramp_samples': 2049,
    'whole_imported_grd_byte_preservation': 'Synthetic fixture through native save/reload/export; root, unknown and unavailable fields retained',
    'offscreen_snapshots': {name: sha(out / name) for name in snapshots},
    'live_photoshop_verified': False, 'native_pointer_drag_verified': False,
    'implemented': scope['implemented'], 'remaining': scope['remaining'],
    'historical_tool_release_manifest': 'gradient-tool-release-verification.json',
    'historical_storekit_results_rerun': False, 'performance_benchmarks_rerun': False,
}
(out / 'gradient-library-release-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k not in ['source_hashes', 'test_source_hashes', 'upstream_reference_hashes', 'implemented', 'remaining']}, indent=2))
