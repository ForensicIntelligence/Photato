#!/usr/bin/env python3
"""Execute the unchanged Rust Classic Gradient geometry, without Cargo or an app dependency."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source_path = root.parent / 'photocraft-main/crates/algo/src/paint.rs'
source = source_path.read_text()
start = source.index('pub fn tool_gradient_t(')
end = source.index('{', start) + 1
level = 1
while level:
    level += (source[end] == '{') - (source[end] == '}')
    end += 1
function = source[start:end]
code = '''use std::io::Write;
#[derive(Clone, Copy)] pub enum GradientShape { Linear, Radial, Angle, Reflected, Diamond }
''' + function + r'''
fn f(out:&mut Vec<u8>, v:f32) {out.extend(v.to_le_bytes());}
fn main() {
 let mut out=Vec::new();
 for (i,shape) in [GradientShape::Linear,GradientShape::Radial,GradientShape::Angle,GradientShape::Reflected,GradientShape::Diamond].into_iter().enumerate() {
  for (from,to) in [((0f32,0f32),(10f32,0f32)), ((7.,3.),(7.,-42.)),
   ((-103.25,12.5),(17.75,-80.125)), ((23.,7.),(-19.,-53.)),
   ((1.,1.),(1.,1.)), ((0.,0.),(0.000001,-0.000001)),
   ((1234.5,-789.),(-32000.125,16238.25)), ((-33.33,41.27),(128.875,512.37))] {
   for y in -8..9 {for x in -9..10 {
    let px=from.0 + (x as f32/8.) * (to.0-from.0).abs().max(13.) + 0.5;
    let py=from.1 + (y as f32/7.) * (to.1-from.1).abs().max(11.) + 0.5;
    out.extend((i as u32).to_le_bytes());
    for v in [from.0,from.1,to.0,to.1,px,py,tool_gradient_t(shape,from,to,px,py)] {f(&mut out,v)}
   }}
  }
 }
 std::io::stdout().write_all(&out).unwrap();
}
'''
with tempfile.TemporaryDirectory(prefix='photato-gradient-tool-oracle-', dir='/private/tmp') as temp:
    temp = Path(temp)
    (temp/'main.rs').write_text(code)
    subprocess.run(['rustc', '--edition=2024', '-O', '-Awarnings', str(temp/'main.rs'), '-o', str(temp/'oracle')], check=True)
    data = subprocess.check_output([str(temp/'oracle')])
target = root/'Tests/PhotoCraftCoreTests/Fixtures/gradient-tool-oracle.bin'
target.write_bytes(data)
manifest = {
    'generator': 'scripts/generate-gradient-tool-oracle.py',
    'source': 'photocraft-main/crates/algo/src/paint.rs',
    'source_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
    'function_sha256': hashlib.sha256(function.encode()).hexdigest(),
    'oracle_sha256': hashlib.sha256(data).hexdigest(),
    'oracle_bytes': len(data), 'geometry_samples': len(data)//32,
    'scope': 'Original Rust tool_gradient_t executed with Float32 input/output. Not a Photoshop pixel oracle. No Rust code is linked into Photato.'
}
(root/'docs/GRADIENT_TOOL_ORACLE.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(manifest, indent=2))
