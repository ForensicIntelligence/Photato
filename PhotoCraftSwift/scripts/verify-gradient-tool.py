#!/usr/bin/env python3
"""Historical tool milestone verifier (121 sources/496 tests).

For the current library milestone, run verify-gradient-library.py instead.
"""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
out = root/'artifacts'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def tests(name):
    text = (out/name).read_text()
    count, failures, seconds = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', text)[-1]
    assert int(failures) == 0 and not re.search(r'Test Case .* skipped', text)
    return dict(log=name, tests=int(count), failures=0, seconds=float(seconds), sha256=sha(out/name))
full = tests('gradient-tool-full-tests.log')
release = tests('gradient-tool-release-tests.log')
assert full['tests'] == 496 and release['tests'] == 43
for suite in ['GradientPaintTests', 'GradientToolWorkflowTests']:
    for log in [full['log'], release['log']]:
        match = re.search(r"Test Suite '"+suite+r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", (out/log).read_text())
        assert match and int(match[1]) == 6 and int(match[2]) == 0
package = json.loads((out/'photato-package-check.json').read_text())
binary = root/'build/Photato.app/Contents/MacOS/Photato'
assert package['binary_sha256'] == sha(binary)
assert package['zip_sha256'] == sha(root/'build/Photato.zip')
assert package['swiftpm_tests_passed'] == full['tests'] and package['clean_zip_signature_verified']
sources = sorted((root/'Sources').rglob('*.swift'))
test_sources = sorted((root/'Tests').rglob('*.swift'))
assert len(sources) == 121
start = re.search(r"Test Suite 'All tests' started at ([\d-]+ [\d:.]+)\.", (out/full['log']).read_text())[1]
start_time = datetime.fromisoformat(start).timestamp()
assert all(p.stat().st_mtime <= start_time for p in sources+test_sources), 'Source changed after suite started'
assert all(p.stat().st_mtime <= binary.stat().st_mtime for p in sources)
oracle = json.loads((root/'docs/GRADIENT_TOOL_ORACLE.json').read_text())
assert sha(root/'Tests/PhotoCraftCoreTests/Fixtures/gradient-tool-oracle.bin') == oracle['oracle_sha256']
assert sha(root.parent/oracle['source']) == oracle['source_sha256']
assert 'Classic Gradient geometry: 12920 bit-identical Rust Float32 samples' in (out/release['log']).read_text()
snapshots = ['gradient-tool-workspace.png', 'classic-gradient-workspace.png']
assert all((out/name).stat().st_mtime >= binary.stat().st_mtime for name in snapshots)
scope = json.loads((root/'docs/GRADIENT_TOOL_REFERENCES.json').read_text())
report = {
 'module':'Native Gradient and Classic Gradient tools', 'date':'2026-10-08',
 'goal_pass_classification':'progress', 'native_swift':True, 'full_photoshop_parity':False,
 'full_suite':full, 'release_focused_suite':release, 'new_module_tests':12,
 'source_hashes':{str(p.relative_to(root)):sha(p) for p in sources},
 'test_source_hashes':{str(p.relative_to(root)):sha(p) for p in test_sources},
 'source_changes_after_full_suite_started':[],
 'oracle':oracle, 'package':package,
 'offscreen_snapshots':{name:sha(out/name) for name in snapshots},
 'live_photoshop_verified':False, 'implemented':scope['implemented'], 'remaining':scope['remaining'],
 'historical_fill_release_manifest':'gradient-fill-release-verification.json',
 'historical_storekit_results_rerun':False, 'performance_benchmarks_rerun':False,
}
(out/'gradient-tool-release-verification.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['source_hashes','test_source_hashes','implemented','remaining']}, indent=2))
