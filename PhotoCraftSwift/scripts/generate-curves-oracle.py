#!/usr/bin/env python3
"""Compile unchanged upstream spline/LUT code and pack independent Adobe records."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root.parent / 'photocraft-main/crates/compose/src/adjust.rs'
original = source.read_text()


def function(name):
    start = original.index('fn ' + name + '(')
    body = original.index('{', start)
    nesting = 1
    end = body + 1
    while nesting:
        nesting += (original[end] == '{') - (original[end] == '}')
        end += 1
    return original[start:end]


cases = [
    [[0, 0], [255, 255]], [[0, 255], [255, 0]],
    [[0, 0], [77, 50], [151, 153], [175, 188], [255, 255]],
    [[33, 255], [119, 127], [185, 0]],
    [[0, 0], [64, 240], [128, 5], [190, 200], [255, 0]],
    [[10, 20], [11, 240], [254, 40], [255, 255]],
    [[0, 128], [255, 128]], [[64, 32], [192, 224]],
    [[i * 14, (i * 47) % 256] for i in range(19)],
]
master = [[0, 0], [55, 20], [200, 240], [255, 255]]
definitions = ','.join('&[' + ','.join(f'[{x},{y}]' for x, y in c) + ']' for c in cases)
master_definition = ','.join(f'[{x},{y}]' for x, y in master)
rust = 'const LUT_SIZE:usize=4096; struct CurvePoint { input:f32, output:f32 }\n'
rust += '\n'.join(function(name) for name in ['curve_lut', 'lut'])
rust += '''
fn points(p:&[[i32;2]]) -> Vec<CurvePoint> { p.iter().map(|q| CurvePoint {input:q[0] as f32/255.,output:q[1] as f32/255.}).collect() }
fn main() {
'''
rust += f'let cases:&[&[[i32;2]]]=&[{definitions}];\nlet master=curve_lut(&points(&[{master_definition}]));\n'
rust += '''
 println!("[");
 for (index,p) in cases.iter().enumerate() {
  let table=curve_lut(&points(p));
  let combined:Vec<f32>=table.iter().map(|v| lut(&master,*v)).collect();
  let samples:Vec<f32>=(-1..=256).map(|i| lut(&combined,i as f32/255.)).collect();
  if index>0 { println!(","); }
  print!("{{\\"points\\":{:?},\\"table\\":{:?},\\"combined\\":{:?},\\"combinedTable\\":{:?}}}",p,table,samples,combined);
 }
 println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photato-curves-oracle-') as temp:
    path = Path(temp)
    (path/'oracle.rs').write_text(rust)
    subprocess.run(['rustc', '--edition', '2024', '-O', str(path/'oracle.rs'), '-o', str(path/'oracle')], check=True)
    vectors = json.loads(subprocess.check_output([str(path/'oracle')]))
(root/'Tests/PhotoCraftCoreTests/Fixtures/curves-oracle.json').write_text(json.dumps(vectors, separators=(',', ':')) + '\n')

# Independent big-endian records, output then input as specified by Adobe.
records = [master, cases[3], cases[4], cases[0]]
def record(points):
    return struct.pack('>H', len(points)) + b''.join(struct.pack('>HH', y, x) for x, y in points)
body = b''.join(record(c) for c in records)
fixtures = {
    'curves-record.acv': struct.pack('>HH', 4, 4) + body,
    'curves-record.curv': struct.pack('>BHI', 0, 1, 15) + body,
    'curves-extended.curv': struct.pack('>BHI', 0, 1, 15) + body + b'Crv ' + struct.pack('>HI', 4, 4)
        + b''.join(struct.pack('>H', i) + record(c) for i, c in enumerate(records)),
    'curves-bitmap.acv': struct.pack('>HH', 1, 10) + record(records[1]) + record(records[3]),
}
for name, binary in fixtures.items():
    (root/'Tests/PhotoCraftImagingTests/Fixtures'/name).write_bytes(binary)
(root/'docs/CURVES_ORACLE.json').write_text(json.dumps({
    'rust_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'cases': len(vectors), 'spline_samples': len(vectors)*4096, 'combined_samples': len(vectors)*258, 'combined_table_samples': len(vectors)*4096,
    'master_input_output_points': master, 'generator': 'scripts/generate-curves-oracle.py',
    'scope': 'Unchanged curve_lut and lut, component before composite; source compatibility only, not Photoshop exactness.',
    'binary_fixtures': {name: hashlib.sha256(data).hexdigest() for name, data in fixtures.items()},
    'format_reference': 'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/',
}, indent=2) + '\n')

# Record observed mathematical preset definitions and hashes; never copy Adobe files.
presets = []
for path in sorted(Path('/Applications/Adobe Photoshop 2026/Presets/Curves').glob('*.acv')):
    data = path.read_bytes()
    version, count = struct.unpack_from('>HH', data)
    assert version == 4
    offset = 4
    curves = []
    for _ in range(count):
        size, = struct.unpack_from('>H', data, offset)
        offset += 2
        curves.append([list(reversed(struct.unpack_from('>HH', data, offset + i*4))) for i in range(size)])
        offset += size*4
    assert offset == len(data)
    presets.append({'name': path.stem, 'sha256': hashlib.sha256(data).hexdigest(), 'input_output_curves': curves})
if presets:
    (root/'docs/PHOTOSHOP_CURVES_PRESETS.json').write_text(json.dumps(presets, indent=2) + '\n')
print(f'Generated {len(vectors)*4096} spline and {len(vectors)*258} combined samples; observed {len(presets)} installed presets.')
