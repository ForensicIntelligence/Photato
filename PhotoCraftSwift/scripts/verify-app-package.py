#!/usr/bin/env python3
"""Verify the current development ZIP and refresh its local release evidence."""
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / 'artifacts'


def test_result(name):
    log = (out / name).read_text()
    matches = re.findall(r'Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)', log)
    assert matches, f'No XCTest result in {name}'
    count, failed, seconds = matches[-1]
    assert int(failed) == 0 and int(count) > 0, matches[-1]
    assert not re.search(r"Test Case .* skipped", log)
    return int(count), float(seconds)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


matte_run = 'runs/20261008T190318Z-045-rgb16-matte-investigation/'
limit_run = 'runs/20261008T200005Z-048-smooth-stop-colors/'
tone_run = 'runs/20261008T205338Z-050-rgb16-gradient-map-tone/'
classic_run = 'runs/20261008T214911Z-052-classic-native-candidate/'
layout_run = 'runs/20261008T223104Z-054-native-layer-layout/'
current_run = 'runs/20261009T004847Z-058-layer-merging/'
count, seconds = test_result(current_run + 'full-tests.log')
menu_count, menu_seconds = test_result(current_run + 'release-tests.log')
tone_count, tone_seconds = test_result(tone_run + 'release-tests.log')
classic_count, classic_seconds = test_result(classic_run + 'release-tests.log')
layout_count, layout_seconds = test_result(layout_run + 'release-tests.log')
limit_count, limit_seconds = test_result(limit_run + 'release-tests.log')
matte_count, matte_seconds = test_result(matte_run + 'release-tests.log')
stripes_count, stripes_seconds = test_result('gradient-stripes-release-tests.log')
fast_count, fast_seconds = test_result('render-fast-path-release-tests.log')
gradient_count, gradient_seconds = test_result('gradient-release-tests.log')
fill_count, fill_seconds = test_result('gradient-fill-release-tests.log')
tool_count, tool_seconds = test_result('gradient-tool-release-tests.log')
library_count, library_seconds = test_result('gradient-library-release-tests.log')
map_count, map_seconds = test_result('gradient-map-release-tests.log')
assert count == 586 and menu_count == 133 and layout_count == 107 and classic_count == 92 and tone_count == 87 and limit_count == 82 and matte_count == 79 and stripes_count == 77 and fast_count == 26 and gradient_count == 18 and fill_count == 67 and tool_count == 43 and library_count == 55
menu_metrics = json.loads((out / 'menu-parity-report.json').read_text())
assert menu_metrics['entries'] == 801 and menu_metrics['primary_shortcuts'] == 102
assert menu_metrics['default_preset'] == 'Photoshop Defaults' and menu_metrics['alternative_shortcuts'] == 8
assert menu_metrics['full_photoshop_parity'] is False
layout_metrics = json.loads((out / 'layer-layout-reference.json').read_text())
assert len(layout_metrics) == 26 and sum(x['pixels'] for x in layout_metrics) == 1123200
assert all(x['composition_exact'] and x['export_exact'] for x in layout_metrics)
layout_sequence = json.loads((out / 'layer-layout-sequence-reference.json').read_text())
assert layout_sequence['pixels'] == 43200 and layout_sequence['composition_exact'] and layout_sequence['export_exact']
assert test_result(limit_run + 'full-tests.log')[0] == 535
assert test_result(matte_run + 'full-tests.log')[0] == 532
classic_metrics = json.loads((out / 'classic-gradient-map-reference.json').read_text())
assert len(classic_metrics) == 4 and sum(x['pixels'] for x in classic_metrics) == 114700
assert all(x['byte_identical'] and x['changed_pixels'] == 0 for x in classic_metrics)
tone_metrics = json.loads((out / 'gradient-map-tone-reference.json').read_text())
assert len(tone_metrics) == 3 and sum(x['pixels'] for x in tone_metrics) == 196608
assert all(x['byte_identical'] and x['changed_pixels'] == 0 for x in tone_metrics)
assert test_result('gradient-stripes-full-tests.log')[0] == 530
assert test_result('gradient-map-full-tests.log')[0] == 520 and map_count == 67
map_log = (out / 'gradient-map-release-tests.log').read_text()
for suite in ['GradientMapTests', 'GradientMapRenderTests', 'GradientMapWorkflowTests']:
    match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", map_log)
    assert match and int(match[1]) == 4 and int(match[2]) == 0, suite
library_log = (out / 'gradient-library-release-tests.log').read_text()
for suite, expected in [('GradientLibraryTests', 7), ('GradientLibraryWorkflowTests', 5)]:
    match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", library_log)
    assert match and int(match[1]) == expected and int(match[2]) == 0, suite
tool_log = (out / 'gradient-tool-release-tests.log').read_text()
for suite in ['GradientPaintTests', 'GradientToolWorkflowTests']:
    match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", tool_log)
    assert match and int(match[1]) == 6 and int(match[2]) == 0, suite
fill_log = (out / 'gradient-fill-release-tests.log').read_text()
for suite, expected in [('GradientFillTests', 4), ('GradientFillRenderTests', 5), ('GradientFillWorkflowTests', 3), ('PSDMergedSampleTests', 3)]:
    match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures", fill_log)
    assert match and int(match[1]) == expected and int(match[2]) == 0, suite
for item in json.loads((out / 'psd-gradient-fixture-manifest.json').read_text())['files']:
    assert sha(root / item['fixture_path']) == item['sha256']
fill_metrics = json.loads((out / 'gradient-fill-reference.json').read_text())
reference = next(x for x in fill_metrics if x['name'] == 'reference-layers-gradient-fill')
assert reference['byte_identical'] and reference['changed_pixels'] == 0
assert reference['usable_merged_pixel_reference'] and reference['width'] * reference['height'] == 1024
assert sum(x['imported'] for x in fill_metrics) == 2
fast_log = (out / 'render-fast-path-release-tests.log').read_text()
module_count, module_seconds = 0, 0.0
for suite, expected in [('PatternFillTests', 5), ('PatternFillRenderTests', 9), ('PatternFillWorkflowTests', 3)]:
    match = re.search(r"Test Suite '" + suite + r"' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures.*?in ([\d.]+)", fast_log)
    assert match and int(match[1]) == expected and int(match[2]) == 0, suite
    module_count += int(match[1])
    module_seconds += float(match[3])
folder = Path(tempfile.mkdtemp(prefix='photato-verify-', dir='/private/tmp'))
subprocess.run(['ditto', '-x', '-k', str(root / 'build/Photato.zip'), str(folder)], check=True)
app = folder / 'Photato.app'
binary = app / 'Contents/MacOS/Photato'
resources = app / 'Contents/Resources'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
for key in ['CFBundleDisplayName', 'CFBundleName', 'CFBundleExecutable']:
    assert info[key] == 'Photato'
assert info['CFBundleIconFile'] in ['Photato', 'Photato.icns']
assert info['CFBundleIdentifier'] == 'local.photocraft.swift'
assert info['LSMinimumSystemVersion'] == '14.0'
archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip().split()
assert set(archs) == {'arm64', 'x86_64'}
versions = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
assert versions.count('minos 14.0') == 2
licenses = ['LICENSE-MIT', 'LICENSE-APACHE', 'LICENSE-psd-tools', 'NOTICE', 'ATTRIBUTION.md']
for name in licenses:
    assert (resources / name).read_bytes() == (root / name).read_bytes(), name
assert (resources / 'ProjectLinks.json').read_bytes() == (root / 'scripts/ProjectLinks.json').read_bytes()
assert not any(p.suffix.lower() in ['.psd', '.storekit', '.grd'] or p.name == 'Tests' for p in app.rglob('*'))
assert sha(binary) == sha(root / 'build/Photato.app/Contents/MacOS/Photato')
assert sha(root / 'Assets/PhotatoIcon.png') == sha(root.parent / 'PhotatoIcon.png')
assert sha(resources / 'Photato.icns') == 'ec36eb1b2e88294c413d1bdd5c46e3708a1b2dcb2f32d828faca1e6e10733e9e'
for snapshot in ['pattern-workspace.png', 'pattern-fill-workspace.png', 'gradient-renderer-atlas.png', 'gradient-fill-workspace.png', 'gradient-fill-editor.png', 'gradient-tool-workspace.png', 'classic-gradient-workspace.png', 'gradient-library-workspace.png', 'gradient-map-workspace.png', 'gradient-stripes-workspace.png']:
    assert (out / snapshot).stat().st_mtime >= (root / 'build/Photato.app/Contents/MacOS/Photato').stat().st_mtime
metrics = json.loads((out / 'pattern-fill-reference.json').read_text())
assert next(x for x in metrics if x['name'] == 'reference-layers-pattern-fill')['byte_identical_pixels']
performance = json.loads((out / 'performance-pattern-fill-24mp.json').read_text())
assert len(performance['samples']) == 2
assert all(x['parameter_matches_full_float_bits'] and x['mask_regional_matches_full_float_bits'] for x in performance['samples'])
comparison = json.loads((out / 'render-performance-comparison.json').read_text())
# Keep prior render benchmarks attached to the binary that was actually measured.
benchmark_matches_binary = comparison['final_binary_sha256'] == sha(binary)
assert comparison['all_native_full_regional_checks_exact']
package = {
    'extracted_app': str(app), 'architectures': archs, 'minimum_macos': '14.0',
    'binary_sha256': sha(binary), 'zip_sha256': sha(root / 'build/Photato.zip'),
    'icon_sha256': sha(resources / 'Photato.icns'),
    'source_icon_sha256': sha(root / 'Assets/PhotatoIcon.png'),
    'clean_zip_signature_verified': True, 'license_integrity_verified': True,
    'desktop_fileprovider_may_readd_finder_metadata_after_launch': True,
    'bundled_license_names': licenses, 'swiftpm_tests_passed': count,
    'historical_render_benchmark_binary_sha256': comparison['final_binary_sha256'],
    'historical_render_benchmark_matches_current_binary': benchmark_matches_binary,
}
(out / 'photato-package-check.json').write_text(json.dumps(package, indent=2) + '\n')
(out / 'photato-verification-location.txt').write_text(str(app) + '\n')
sources = list((root / 'Sources').rglob('*.swift'))
common = {k: v for k, v in package.items() if k != 'extracted_app'}
common.update({
    'clean_extracted_app': str(app), 'swift_source_files': len(sources),
    'swift_source_lines': sum(len(p.read_text().splitlines()) for p in sources),
    'swiftpm_tests_failed': 0, 'swiftpm_tests_skipped': 0,
    'latest_test_runtime_seconds': seconds, 'workspace_connected_tools': 29,
    'gradient_tests_added': 13, 'gradient_release_focused_tests_passed': gradient_count,
    'gradient_release_seconds': gradient_seconds,
    'gradient_full_tests_log': current_run + 'full-tests.log',
    'gradient_release_tests_log': 'gradient-release-tests.log',
    'gradient_reference_manifest': '../docs/GRADIENT_REFERENCES.json',
    'gradient_backend_integrated_with_workspace': True,
    'gradient_psd_fill_integrated': True,
    'gradient_live_photoshop_verified': False,
    'gradient_native_atlas': 'gradient-renderer-atlas.png',
    'gradient_fill_tests_added': 15,
    'gradient_fill_release_focused_tests_passed': fill_count,
    'gradient_fill_release_seconds': fill_seconds,
    'gradient_fill_release_tests_log': 'gradient-fill-release-tests.log',
    'gradient_fill_reference_manifest': '../docs/GRADIENT_FILL_REFERENCES.json',
    'gradient_fill_saved_reference_metrics': fill_metrics,
    'gradient_fill_offscreen_layout_verified': True,
    'gradient_fill_ui_snapshots': ['gradient-fill-workspace.png', 'gradient-fill-editor.png'],
    'gradient_live_classic_tools_implemented': True,
    'gradient_tool_tests_added': 12,
    'gradient_tool_release_focused_tests_passed': tool_count,
    'gradient_tool_release_seconds': tool_seconds,
    'gradient_tool_release_tests_log': 'gradient-tool-release-tests.log',
    'gradient_tool_geometry_exact_rust_samples': 12920,
    'gradient_tool_reference_manifest': '../docs/GRADIENT_TOOL_REFERENCES.json',
    'gradient_tool_ui_snapshots': ['gradient-tool-workspace.png', 'classic-gradient-workspace.png'],
    'gradient_tool_offscreen_layout_verified': True,
    'gradient_tool_full_photoshop_interaction_verified': False,
    'gradient_preset_library_ui_implemented': True,
    'gradient_library_tests_added': 12,
    'gradient_library_release_focused_tests_passed': library_count,
    'gradient_library_release_seconds': library_seconds,
    'gradient_library_release_tests_log': 'gradient-library-release-tests.log',
    'gradient_library_reference_manifest': '../docs/GRADIENT_LIBRARY_REFERENCES.json',
    'gradient_library_ui_snapshots': ['gradient-library-workspace.png', 'gradient-fill-editor.png'],
    'gradient_library_offscreen_layout_verified': True,
    'gradient_library_live_photoshop_verified': False,
    'gradient_library_native_restart_exact_ramp_samples': 2049,
    'gradient_map_implemented': True,
    'gradient_map_tests_added': 12,
    'gradient_map_release_focused_tests_passed': map_count,
    'gradient_map_release_seconds': map_seconds,
    'gradient_map_release_tests_log': 'gradient-map-release-tests.log',
    'gradient_map_reference_manifest': '../docs/GRADIENT_MAP_REFERENCES.json',
    'gradient_map_pixel_metrics': json.loads((out / 'gradient-map-photoshop-comparison.json').read_text()),
    'gradient_map_fixture_manifest': '../docs/GRADIENT_MAP_FIXTURES.json',
    'gradient_map_live_photoshop_editable_export_inspected': True,
    'gradient_map_photoshop_byte_equivalence': False,
    'gradient_map_offscreen_snapshot': 'gradient-map-workspace.png',
    'gradient_map_unsupported_methods': ['Smooth'],
    'gradient_map_psd_editable_depths': [8, 16],
    'gradient_map_rgb32_native_legacy_retained': True,
    'gradient_map_psd_max_color_stops': 100,
    'gradient_map_psd_max_opacity_stops': 100,
    'gradient_map_stop_limit_tests_added': 3,
    'gradient_map_stop_limit_release_focused_tests': limit_count,
    'gradient_map_stop_limit_release_seconds': limit_seconds,
    'gradient_map_stop_limit_release_tests_log': limit_run + 'release-tests.log',
    'classic_rgb16_gradient_map_implemented': True,
    'classic_rgb16_tests_added': 5,
    'classic_rgb16_optimized_tests': classic_count,
    'classic_rgb16_optimized_seconds': classic_seconds,
    'classic_rgb16_tests_log': classic_run + 'release-tests.log',
    'menu_entries': menu_metrics['entries'],
    'menu_primary_shortcuts': menu_metrics['primary_shortcuts'],
    'menu_tests_added': 6,
    'menu_optimized_tests': menu_count,
    'menu_optimized_seconds': menu_seconds,
    'menu_reference_manifest': '../docs/MENU_PARITY_REFERENCES.json',
    'menu_full_photoshop_parity': False,
    'layer_layout_commands_implemented': 14,
    'layer_layout_tests_added': 15,
    'layer_layout_optimized_tests': layout_count,
    'layer_layout_optimized_seconds': layout_seconds,
    'layer_layout_tests_log': layout_run + 'release-tests.log',
    'layer_layout_reference_manifest': '../docs/LAYER_LAYOUT_REFERENCES.json',
    'layer_layout_single_operation_cases': 26,
    'layer_layout_consecutive_command_cases': 1,
    'layer_layout_qualified_rgba_pixels': 1166400,
    'layer_layout_full_photoshop_parity': False,
    'classic_rgb16_reference_manifest': '../docs/CLASSIC_GRADIENT_RESEARCH.json',
    'classic_rgb16_qualified_pixels': classic_metrics,
    'classic_rgb16_remaining_one_level_positions': 2,
    'gradient_map_rgb16_tone_implemented': True,
    'gradient_map_rgb16_tone_tests_added': 5,
    'gradient_map_rgb16_tone_release_focused_tests': tone_count,
    'gradient_map_rgb16_tone_release_seconds': tone_seconds,
    'gradient_map_rgb16_tone_release_tests_log': tone_run + 'release-tests.log',
    'gradient_map_rgb16_tone_reference_manifest': '../docs/GRADIENT_MAP_TONE_REFERENCES.json',
    'gradient_map_rgb16_tone_exact_indices': 131072,
    'gradient_map_rgb16_tone_stripes_pixels': tone_metrics,
    'gradient_map_stop_limit_reference_manifest': '../docs/GRADIENT_MAP_LIMIT_REFERENCES.json',
    'gradient_stripes_implemented': True,
    'gradient_stripes_tests_added': 10,
    'gradient_stripes_release_focused_tests_passed': stripes_count,
    'gradient_stripes_release_seconds': stripes_seconds,
    'gradient_stripes_release_tests_log': 'gradient-stripes-release-tests.log',
    'gradient_stripes_reference_manifest': '../docs/GRADIENT_STRIPES_REFERENCES.json',
    'gradient_stripes_fixture_manifest': '../docs/GRADIENT_STRIPES_FIXTURES.json',
    'gradient_stripes_pixel_metrics': json.loads((out / 'gradient-stripes-photoshop-comparison.json').read_text()),
    'gradient_stripes_depth_metrics': json.loads((out / 'gradient-stripes-depth-comparison.json').read_text()),
    'gradient_stripes_rgb8_exact_reference_pixels': 51200,
    'gradient_stripes_offscreen_snapshot': 'gradient-stripes-workspace.png',
    'native_archive_version': 8,
    'psd_merged_white_matte_fixed': True,
    'rgb16_merged_matte_reference_manifest': '../docs/RGB16_MATTE_REFERENCES.json',
    'rgb16_merged_matte_tests_added': 2,
    'rgb16_merged_matte_exact_reference_pixels': 65536,
    'rgb16_merged_matte_release_focused_tests': matte_count,
    'rgb16_merged_matte_release_seconds': matte_seconds,
    'rgb16_merged_matte_release_tests_log': matte_run + 'release-tests.log',
    'gradient_fill_full_suite_after_source_changes': [],
    'render_benchmarks_rerun_for_gradient': False,
    'storekit_integration_tests_rerun_for_gradient': False,
    'goal_pass_classification': 'progress', 'full_photoshop_parity': False,
    'pattern_fill_core_tests': 5, 'pattern_fill_imaging_tests': 9,
    'pattern_fill_workflow_tests': 3, 'pattern_fill_tests_log': 'full-tests.log',
    'pattern_fill_release_tests_passed': module_count,
    'pattern_fill_release_test_seconds': module_seconds,
    'pattern_fill_release_tests_log': 'render-fast-path-release-tests.log',
    'pattern_fill_reference_metrics': metrics,
    'pattern_fill_reference_manifest': '../docs/PATTERN_FILL_REFERENCES.json',
    'pattern_fill_fixture_manifest': 'psd-pattern-fixture-manifest.json',
    'pattern_fill_psd_generated_depths': [8, 16, 32],
    'pattern_fill_live_ui_verified': False, 'pattern_fill_photoshop_2026_exactness_verified': False,
    'pattern_fill_offscreen_layout_verified': True, 'pattern_fill_snapshot': 'pattern-fill-workspace.png',
    'pattern_fill_performance': 'performance-pattern-fill-24mp.json',
    'pattern_fill_native_regional_full_float_bit_equivalence': True,
    'pattern_fill_post_suite_source_changes': [],
    'storekit_integration_tests_rerun_for_pattern_fill': False,
    'latest_performance': 'performance-pattern-fill-24mp.json',
    'latest_performance_sample': 'performance-pattern-fill-24mp.json',
    'render_fast_path_tests_added': 7,
    'render_fast_path_release_tests_passed': fast_count,
    'render_fast_path_release_seconds': fast_seconds,
    'render_fast_path_release_tests_log': 'render-fast-path-release-tests.log',
    'render_fast_path_prepared_sparse_exact_values': 156000,
    'render_fast_path_rust_exact_values': 27968,
    'render_fast_path_blend_depth_cases': 81,
    'render_fast_path_direct_picking_pixels': 3420,
    'render_fast_path_pattern_preparation_bytes_limit': 4194304,
    'render_fast_path_profile': 'pattern-fill-profile.txt',
    'render_fast_path_performance_comparison': 'render-performance-comparison.json',
    'render_fast_path_performance_metrics': comparison,
    'render_fast_path_live_photoshop_verified': False,
    'storekit_integration_tests_rerun_for_render_fast_path': False,
})
scope = json.loads((root / 'docs/PATTERN_FILL_REFERENCES.json').read_text())
common['pattern_fill_remaining'] = scope['remaining']
for name in ['photato-release-verification.json', 'verification.json']:
    path = out / name
    data = json.loads(path.read_text())
    data.update(common)
    data['pattern_remaining'] = [x for x in data.get('pattern_remaining', []) if x != 'Pattern fill layers and embedded PSD patterns']
    if name == 'verification.json':
        data.update({
            'tests_passed': count,
            'tests_passed_scope': f'{count} package tests rerun in full; purchase support removed at step237',
            'package_tests_passed': count, 'package_tests_failed': 0, 'package_tests_skipped': 0,
            'app_icon_sha256': package['icon_sha256'],
        })
    path.write_text(json.dumps(data, indent=2) + '\n')
print(json.dumps(package, indent=2))
print('Swift source files:', len(sources))
