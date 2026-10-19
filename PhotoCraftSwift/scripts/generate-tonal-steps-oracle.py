#!/usr/bin/env python3
"""Execute unchanged Rust Posterize for all legal settings and 8-bit inputs."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root.parent / 'photocraft-main/crates/compose/src/adjust.rs'
text = source.read_text()
start = text.index('pub fn posterize(')
body = text.index('{', start)
end, nesting = body + 1, 1
while nesting:
    nesting += (text[end] == '{') - (text[end] == '}')
    end += 1
rust = text[start:end] + r'''
fn main() {
    use std::io::Write;
    let mut bytes = Vec::new();
    for levels in 2..=255 { for input in 0..=255 {
        bytes.push((posterize(input as f32 / 255., levels) * 255.).round() as u8);
    }}
    std::io::stdout().write_all(&bytes).unwrap();
}
'''
with tempfile.TemporaryDirectory(prefix='photato-tonal-oracle-') as directory:
    path = Path(directory)
    (path / 'oracle.rs').write_text(rust)
    subprocess.run(['rustc', '--edition', '2024', '-O', str(path / 'oracle.rs'), '-o', str(path / 'oracle')], check=True)
    data = subprocess.check_output([str(path / 'oracle')])
assert len(data) == 254 * 256
(root / 'Tests/PhotoCraftCoreTests/Fixtures/posterize-u8-oracle.bin').write_bytes(data)
(root / 'docs/TONAL_STEPS_ORACLE.json').write_text(json.dumps({
    'source': str(source.relative_to(root.parent)),
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'generator': 'scripts/generate-tonal-steps-oracle.py',
    'posterize_u8_cases': 254,
    'posterize_u8_samples': len(data),
    'fixture_sha256': hashlib.sha256(data).hexdigest(),
    'scope': 'Every 8-bit input at every legal Posterize level, produced by executing the unchanged Rust function. Threshold uses 0.3/0.59/0.11 reference luminance, ties-to-even RGB/8 rounding and depth-specific boundaries; RGB/16 Posterize uses the measured 0...32768 grid, superseding source 8-bit reduction. HDR and full Photoshop exactness remain unqualified.',
    'independent_psd_manifest': 'artifacts/psd-tonal-step-fixture-manifest.json'
}, indent=2) + '\n')
print('Generated', len(data), 'RGB/8 Posterize channel samples')
