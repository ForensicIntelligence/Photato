#!/usr/bin/env python3
"""Execute the original Rust inpainting numerical code with inert cancellation and sequential bands."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
base=root.parent/'photocraft-main/crates/algo/src'
inpaint=(base/'inpaint.rs').read_text().split('#[cfg(test)]')[0]
poisson=(base/'poisson.rs').read_text().split('#[cfg(test)]')[0]
stub='''
mod photocraft_raster {
#[derive(Clone,Copy)] pub struct Interrupt<'a>(std::marker::PhantomData<&'a ()>);
#[derive(Debug)] pub struct Cancelled;
impl Interrupt<'_> { pub const NONE:Self=Self(std::marker::PhantomData); pub fn cancelled(&self)->bool{false} pub fn check(&self)->Result<(),Cancelled>{Ok(())} pub fn progress(&self,_:f32){} }
}
'''
main='''
fn main(){use std::io::Write;let mut out=Vec::new();
for (w,h,ch,kind) in [(9usize,7usize,1usize,0),(48,43,3,1),(80,64,4,2),(97,95,1,3),(128,96,3,4),(5,4,4,5)] {
let mask:Vec<bool>=(0..w*h).map(|i|{let x=i%w;let y=i/w;match kind {0=>false,5=>true,4=>x>29&&x<98&&y>20&&y<75,_=>{let dx=x as f32-w as f32/2.;let dy=y as f32-h as f32/2.;dx*dx+dy*dy<if kind==3{400.}else{36.}}}}).collect();
let img:Vec<f32>=(0..w*h*ch).map(|i|{let p=i/ch;let x=p%w;let y=p/w;let c=i%ch;
if mask[p] {0.03} else if c==3 {0.8} else if kind==2 {if (x/4)%2==0{0.2}else{0.8}} else {0.2+0.003*x as f32+0.001*y as f32+((x*13+y*7+c*11)%19) as f32*0.001}}).collect();
let mut p=inpaint::CompleteParams::default(); if kind==4{p.refine_extent=48;}
let complete=inpaint::complete(w,h,ch,&img,&mask,&p);
let texture=inpaint::synthesize(w,h,ch,&img,&mask,6,0x5eed);
let offset=inpaint::best_offset(w,h,ch,&img,&mask,3,24);
for v in [w,h,ch,kind,p.refine_extent]{out.extend((v as u32).to_le_bytes());}
for m in &mask{out.push(*m as u8);} for v in &img{out.extend(v.to_le_bytes());}
out.push(complete.is_some() as u8);if let Some(result)=complete {for v in result{out.extend(v.to_le_bytes());}}
for v in texture{out.extend(v.to_le_bytes());}
let (x,y)=offset.unwrap_or((i32::MIN,i32::MIN));out.extend(x.to_le_bytes());out.extend(y.to_le_bytes());
}std::io::stdout().write_all(&out).unwrap();}
'''
with tempfile.TemporaryDirectory(prefix='photato-inpaint-oracle-') as d:
 p=Path(d);source=stub+'mod poisson{\n'+poisson+'\nuse crate::photocraft_raster;\n}\nmod inpaint{\n'+inpaint+'\nuse crate::photocraft_raster;\n}\n'+main
 (p/'oracle.rs').write_text(source)
 subprocess.run(['rustc','--edition=2024','-O','--cfg','target_arch="wasm32"','-Aexplicit_builtin_cfgs_in_flags','-Awarnings',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
 data=subprocess.check_output([str(p/'oracle')])
(root/'Tests/PhotoCraftCoreTests/Fixtures/inpaint-oracle.bin').write_bytes(data)
manifest={'sources':{name:hashlib.sha256((base/name).read_bytes()).hexdigest() for name in ['inpaint.rs','poisson.rs']},'fixture_sha256':hashlib.sha256(data).hexdigest(),'regions':6,'scope':'Original Rust numerical functions are unchanged. The wasm32 cfg selects their existing sequential scheduling paths; execution is native host CPU, not WebAssembly. Cancellation/progress use an inert stub. Includes completion, texture synthesis and proximity offsets; odd grids, 1/3/4 channels, multi-level refinement, no-hole and all-hole cases. No Photoshop output qualification.'}
(root/'docs/INPAINT_ORACLE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(len(data),'fixture bytes')
