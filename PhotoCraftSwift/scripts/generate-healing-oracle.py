#!/usr/bin/env python3
"""Run the original Rust membrane and seamless-clone functions, without linking Rust into Photato."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
root = Path(__file__).resolve().parent.parent
source = root.parent / 'photocraft-main/crates/algo/src/poisson.rs'
s = source.read_text()
solver = s[s.index('const TOL:'):s.index('/// Reference solver')]
seamless = s[s.index('pub fn seamless_clone('):s.index('/// Membrane fill')]
# Replace only Rayon scheduling/interleaving with sequential orchestration.
channels = '''
fn per_channel(w:usize,h:usize,ch:usize,f:impl Fn(usize)->Vec<f32>+Sync+Send)->Vec<f32>{
let mut out=vec![0.;w*h*ch]; for c in 0..ch {let p=f(c); for i in 0..w*h {out[i*ch+c]=p[i];}}out}
'''
main = '''
fn main() {use std::io::Write;let mut out=Vec::new();
let cases=[(1usize,1usize,0),(1,17,1),(19,1,2),(7,9,3),(31,29,4),(80,60,5),(96,72,6),(65,67,7),(11,13,8)];
for (w,h,kind) in cases {let ch=4usize;
let mask:Vec<bool>=(0..w*h).map(|i|{let x=i%w;let y=i/w;match kind {
0=>true,1=>i>0&&i+1<w*h,2=>i%3!=0,3=>false,4|5|6=>{let dx=x as f32-w as f32/2.;let dy=y as f32-h as f32/2.;dx*dx+dy*dy<(w.min(h) as f32*0.35).powi(2)},7=>x%7<4&&y%11<8,_=>x>0&&y>0&&x+1<w&&y+1<h}}).collect();
let src:Vec<f32>=(0..w*h*ch).map(|i|(((i*37+11)%257) as f32/256.-0.15)*(if kind==8 {2.}else{1.})).collect();
let dst:Vec<f32>=(0..w*h*ch).map(|i|((i*13+17)%193) as f32/192.).collect();
let result=seamless_clone(w,h,ch,&src,&dst,&mask);
for x in [w,h,ch]{out.extend((x as u32).to_le_bytes());}for m in &mask{out.push(*m as u8);}
for values in [&src,&dst,&result]{for v in values{out.extend(v.to_le_bytes());}}
}std::io::stdout().write_all(&out).unwrap();}
'''
with tempfile.TemporaryDirectory(prefix='photato-healing-oracle-') as d:
    p=Path(d); (p/'oracle.rs').write_text(solver+channels+seamless+main)
    subprocess.run(['rustc','-O',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
    data=subprocess.check_output([str(p/'oracle')])
fixture=root/'Tests/PhotoCraftCoreTests/Fixtures/healing-oracle.bin';fixture.write_bytes(data)
pos=0; cases=0; values=0
while pos<len(data):
    import struct
    w,h,c=struct.unpack_from('<III',data,pos);pos+=12+w*h*(1+12*c);cases+=1;values+=w*h*c
(root/'docs/HEALING_ORACLE.json').write_text(json.dumps({
    'source':str(source.relative_to(root.parent)), 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'fixture_sha256':hashlib.sha256(data).hexdigest(),'cases':cases,'channel_values':values,
    'scope':'Unmodified Rust numerical solver and seamless_clone executed by rustc -O. Only per-channel scheduling/interleaving is sequential in the harness. Tests include inputs and expected outputs. This is not a Photoshop reference.'},indent=2)+'\n')
print(cases,'regions,',values,'reference channel values')
