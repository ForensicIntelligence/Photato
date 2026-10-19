#!/usr/bin/env python3
"""Execute unmodified PhotoCraft Rust toning functions as an independent Swift test oracle."""
from pathlib import Path
import hashlib, json, subprocess, tempfile, struct
root = Path(__file__).resolve().parent.parent
source = root.parent/'photocraft-main/crates/algo/src/retouch.rs'
commands = root.parent/'photocraft-main/crates/engine/src/retouch_cmds.rs'
s = source.read_text(); c = commands.read_text()
# Only remove serde attributes/dependency; every numerical function stays unchanged.
kernels = s[s.index('/// Rec. 601'):s.index('/// Gaussian blur')]
per_dab = c[c.index('fn per_dab('):c.index('/// Apply an RGB colour')]
main = r'''
fn main() {use std::io::Write; let mut out=Vec::new();
let mut colors:Vec<[f32;3]>=(0..512).map(|i|[((i*17)%257)as f32/256.,((i*37+3)%257)as f32/256.,((i*53+7)%257)as f32/256.]).collect();
for v in [-0.2f32,0.,0.000001,0.01,0.1,0.25,0.5,0.9,1.,1.1,2.]{colors.push([v,v,v]);}
for rgb in colors {for e in [-0.1f32,0.,0.001,0.2,0.5,1.2] {
for op in 0u32..4 {for range in 0u32..(if op<2 {3}else{1}) {for flag in 0u32..2 {
let value=if op<2 {dodge_burn(rgb,e,match range {0=>ToneRange::Shadows,1=>ToneRange::Midtones,_=>ToneRange::Highlights},op==1,flag==1)} else {sponge(rgb,e,op==3,flag==1)};
for v in [op,range,flag] {out.extend(v.to_le_bytes());}
for v in rgb.into_iter().chain([e]).chain(value) {out.extend(v.to_le_bytes());}
}}}}}
std::io::stdout().write_all(&out).unwrap();}
'''
with tempfile.TemporaryDirectory(prefix='photato-toning-oracle-') as d:
    p=Path(d); (p/'oracle.rs').write_text('#[derive(Clone,Copy)] pub enum ToneRange { Shadows,Midtones,Highlights }\n'+kernels+main)
    subprocess.run(['rustc','-O','--edition=2024',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
    data=subprocess.check_output([str(p/'oracle')])
    (p/'dab.rs').write_text(per_dab+'''fn main(){use std::io::Write;let mut out=Vec::new();for i in 0..=100 {for s in [0.001f32,0.01,0.1,0.25,0.5,1.,10.] {let e=i as f32/100.;for v in [e,s,per_dab(e,s)]{out.extend(v.to_le_bytes());}}}std::io::stdout().write_all(&out).unwrap();}''')
    subprocess.run(['rustc','-O',str(p/'dab.rs'),'-o',str(p/'dab')],check=True)
    dabs=subprocess.check_output([str(p/'dab')])
(root/'Tests/PhotoCraftCoreTests/Fixtures/toning-oracle.bin').write_bytes(data)
(root/'Tests/PhotoCraftCoreTests/Fixtures/toning-dab-oracle.bin').write_bytes(dabs)
(root/'docs/TONING_ORACLE.json').write_text(json.dumps({
 'source':str(source.relative_to(root.parent)), 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'commands_source_sha256':hashlib.sha256(commands.read_bytes()).hexdigest(),
 'fixture_sha256':hashlib.sha256(data).hexdigest(),'dab_fixture_sha256':hashlib.sha256(dabs).hexdigest(),
 'colors':523,'kernel_cases':len(data)//40,'kernel_channel_values':len(data)//40*3,'per_dab_cases':len(dabs)//12,
 'scope':'Unmodified Rust numerical functions executed by rustc -O. Serde-only enum traits removed. PhotoCraft empirical equations, not a Photoshop reference. Does not qualify full advanced brush dynamics.'},indent=2)+'\n')
print(len(data)//40,'RGB cases;',len(dabs)//12,'per-dab cases')
