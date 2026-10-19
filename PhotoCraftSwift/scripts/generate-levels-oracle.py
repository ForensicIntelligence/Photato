#!/usr/bin/env python3
"""Run unchanged upstream Rust Levels math; no Swift implementation is consulted."""
from pathlib import Path
import hashlib
import json
import subprocess
import struct
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


rust = '''
struct LevelsChannel { in_black:f32, in_white:f32, gamma:f32, out_black:f32, out_white:f32 }
'''
rust += '\n'.join(function(name) for name in ['levels_q', 'levels_float', 'lut'])
rust += r'''
fn ch(p:[i32;5]) -> LevelsChannel { LevelsChannel {in_black:p[0] as f32/255.,in_white:p[1] as f32/255.,gamma:p[2] as f32/100.,out_black:p[3] as f32/255.,out_white:p[4] as f32/255.} }
fn main() {
 let cases=[[0,255,100,0,255],[44,214,178,0,255],[15,230,130,10,245],[0,255,50,255,0],[24,220,250,16,240],[1,254,999,0,255],[0,255,10,0,255]];
 let master=ch([10,245,120,7,250]);
 let mut first=true; println!("[");
 for (index,params) in cases.iter().enumerate() { let record=ch(*params);
  for depth in [8,16,32] {
   let q=if depth==8 {Some(255.)} else {Some(32768.)};
   let table:Vec<f32>=(0..4096).map(|i| levels_q(&record,levels_q(&master,i as f32/4095.,q),q)).collect();
   for sample in -1..=256 { let input=sample as f32/255.;
    let value=if depth==32 {levels_float(&record,input)} else {levels_q(&record,input,q)};
    let combined=if depth==32 {levels_float(&record,levels_float(&master,input))} else {lut(&table,input)};
    if !first {println!(",");} first=false;
    print!("{{\"caseIndex\":{},\"parameters\":{:?},\"depth\":{},\"input\":{},\"channel\":{},\"combined\":{}}}",index,params,depth,input,value,combined);
   }
  }
 }
 println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photato-levels-oracle-') as temp:
    path = Path(temp)
    (path / 'oracle.rs').write_text(rust)
    subprocess.run(['rustc', '--edition', '2024', '-O', str(path / 'oracle.rs'), '-o', str(path / 'oracle')], check=True)
    vectors = json.loads(subprocess.check_output([str(path / 'oracle')]))
(root / 'Tests/PhotoCraftCoreTests/Fixtures/levels-oracle.json').write_text(json.dumps(vectors, separators=(',', ':')) + '\n')
# Independent big-endian fixture from Adobe's record specification, not our codec.
records = [(15, 230, 10, 245, 130), (0, 255, 0, 255, 50), (44, 214, 0, 255, 178)] + [(0, 255, 0, 255, 100)] * 26
binary = struct.pack('>H', 2) + b''.join(struct.pack('>5H', *record) for record in records)
(root / 'Tests/PhotoCraftImagingTests/Fixtures/levels-record.alv').write_bytes(binary)
(root / 'docs/LEVELS_ORACLE.json').write_text(json.dumps({
    'rust_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'vectors': len(vectors), 'generator': 'scripts/generate-levels-oracle.py',
    'scope': 'Unchanged levels_q, levels_float and lut; RGB master then channel. This source uses an approximate Photoshop shadow toe.',
    'binary_fixture': 'Python struct.pack, big-endian version 2 and 29 five-short records',
    'binary_fixture_sha256': hashlib.sha256(binary).hexdigest(),
    'format_reference': 'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/',
}, indent=2) + '\n')
print(f'Generated {len(vectors)} Rust Levels vectors.')
