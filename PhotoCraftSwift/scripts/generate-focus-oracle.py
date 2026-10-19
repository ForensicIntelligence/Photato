#!/usr/bin/env python3
"""Execute PhotoCraft's original local blur/sharpen and Smudge numerical methods."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
root=Path(__file__).resolve().parent.parent
algo=root.parent/'photocraft-main/crates/algo/src/retouch.rs'
paint=root.parent/'photocraft-main/crates/paint/src/retouch.rs'
tip=root.parent/'photocraft-main/crates/paint/src/lib.rs'
a=algo.read_text();p=paint.read_text();t=tip.read_text()
focus=a[a.index('pub fn local_blur('):a.index('#[cfg(test)]')]
smudge=p[p.index('pub fn mix_premultiplied('):p.index('#[cfg(test)]')]
start=t.index('pub fn dab_coverage(');end=t.index('/// Rasterize a stroke',start)
coverage=t[start:end]
helpers=r'''
use std::io::Write;
fn u(o:&mut Vec<u8>,v:usize){o.extend((v as u32).to_le_bytes());}
fn f(o:&mut Vec<u8>,v:f32){o.extend(v.to_le_bytes());}
fn floats(o:&mut Vec<u8>,v:&[f32]){for x in v{f(o,*x);}}
'''
main=r'''
fn main(){let mut o=Vec::new();
for (kind,(w,h,ch,alpha)) in [(1usize,1usize,1,None),(19,1,4,Some(3)),(1,17,3,None),(17,19,1,None),(29,23,4,Some(3)),(32,24,4,Some(3)),(41,35,3,None),(65,63,4,Some(3))].into_iter().enumerate(){
let data:Vec<f32>=(0..w*h*ch).map(|i|if Some(i%ch)==alpha {if (i/ch)%5==0 {0.}else{((i*7)%97)as f32/96.}}else{((i*37+13)%257)as f32/256.*(if kind==7 {2.}else{1.})-0.1}).collect();
let win=if w<3||h<3 {(0,0,w,h)}else{(1,2,w-1,h)};
let sigma=[1.0f32,1.5,4.0][kind%3];let amount=[0.0f32,1.0,4.0][kind%3];
for v in [w,h,ch,alpha.unwrap_or(u32::MAX as usize),win.0,win.1,win.2,win.3]{u(&mut o,v);}f(&mut o,sigma);f(&mut o,amount);floats(&mut o,&data);
floats(&mut o,&local_blur(&data,w,h,ch,alpha,win,sigma));
floats(&mut o,&local_sharpen(&data,w,h,ch,alpha,win,amount,false));
floats(&mut o,&local_sharpen(&data,w,h,ch,alpha,win,amount,true));
}std::io::stdout().write_all(&o).unwrap();}
'''
stubs=r'''
#[derive(Clone,Copy,Debug,PartialEq)] pub struct Rect {x0:i32,y0:i32,x1:i32,y1:i32}
impl Rect {fn contains(&self,x:i32,y:i32)->bool{x>=self.x0&&y>=self.y0&&x<self.x1&&y<self.y1}}
#[derive(Clone,Debug)] pub struct Region {rect:Rect,ch:usize,data:Vec<f32>}
impl Region {fn at(&self,x:i32,y:i32)->usize{((y-self.rect.y0)*(self.rect.x1-self.rect.x0)+(x-self.rect.x0))as usize*self.ch}
fn px(&self,x:i32,y:i32)->&[f32]{let i=self.at(x,y);&self.data[i..i+self.ch]}
fn px_mut(&mut self,x:i32,y:i32)->&mut[f32]{let i=self.at(x,y);&mut self.data[i..i+self.ch]}}
pub struct Point{x:f64,y:f64} pub struct Dab {center:Point}
pub struct Footprint{rect:Rect,dab:Dab,coverage:Vec<f32>}
impl Footprint{fn at(&self,x:i32,y:i32)->f32{if !self.rect.contains(x,y){return 0.;}self.coverage[((y-self.rect.y0)*(self.rect.x1-self.rect.x0)+x-self.rect.x0)as usize]}}
'''
smain=r'''
fn main(){let mut out=Vec::new();
for kind in 0..6 {let w=31usize;let h=23usize;let ch=if kind==0 {1}else if kind==1 {3}else{4};let alpha=if ch==4 {Some(3)}else{None};
let strength=[0.0f32,0.25,0.5,1.,0.8,0.3][kind];let size=if kind%2==0 {7.0f32}else{12.};
let finger=if kind>=4 {Some(vec![0.9f32,0.2,0.4,0.6])}else{None};
let data:Vec<f32>=(0..w*h*ch).map(|i|if Some(i%ch)==alpha{if i/ch%5==0 {0.}else{((i*7)%97)as f32/96.}}else{((i*37+13)%257)as f32/256.}).collect();
let points=[(0.25f32,1.5f32),(4.25,5.5),(10.75,9.5),(16.25,9.5),(23.75,16.5),(30.25,22.5)];
for v in [w,h,ch,alpha.unwrap_or(u32::MAX as usize)]{u(&mut out,v);}f(&mut out,size);f(&mut out,strength);
u(&mut out,finger.as_ref().map_or(0,|f|f.len()));u(&mut out,points.len());if let Some(f)=&finger{floats(&mut out,f);}floats(&mut out,&data);
let mut work=Region{rect:Rect{x0:0,y0:0,x1:w as i32,y1:h as i32},ch,data};
let mut sm=Smudge::new(strength,finger,size).with_alpha(alpha);
for (cx,cy) in points {
let r=size/2.;let rect=Rect{x0:((cx-r-1.).floor()as i32).max(0),y0:((cy-r-1.).floor()as i32).max(0),x1:((cx+r+1.).ceil()as i32).min(w as i32),y1:((cy+r+1.).ceil()as i32).min(h as i32)};
let mut cov=Vec::new();for y in rect.y0..rect.y1{for x in rect.x0..rect.x1{cov.push(dab_coverage(((x as f32+0.5-cx).powi(2)+(y as f32+0.5-cy).powi(2)).sqrt(),r,0.7)*0.8);}}
f(&mut out,cx);f(&mut out,cy);for v in [rect.x0,rect.y0,rect.x1,rect.y1]{u(&mut out,v as usize);}floats(&mut out,&cov);
sm.dab(&mut work,&Footprint{rect,dab:Dab{center:Point{x:cx as f64,y:cy as f64}},coverage:cov});floats(&mut out,&work.data);
}}
std::io::stdout().write_all(&out).unwrap();}
'''
results={}
with tempfile.TemporaryDirectory(prefix='photato-focus-oracle-') as folder:
 d=Path(folder)
 for name,source in [('focus',focus+helpers+main),('smudge',stubs+smudge+coverage+helpers+smain)]:
  (d/'main.rs').write_text(source)
  subprocess.run(['rustc','-O','--edition=2024',str(d/'main.rs'),'-o',str(d/'oracle')],check=True)
  data=subprocess.check_output([str(d/'oracle')]);(root/f'Tests/PhotoCraftCoreTests/Fixtures/{name}-oracle.bin').write_bytes(data)
  results[name]={'fixture_sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
(root/'docs/FOCUS_ORACLE.json').write_text(json.dumps({'sources':{str(p.relative_to(root.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [algo,paint,tip]},'fixtures':results,'scope':'Unmodified Rust local blur/sharpen and Smudge methods; standalone Region/Footprint storage adapters replace application dependencies. No Rust is linked into Photato. These source algorithms are not Photoshop references.','focus_regions':8,'smudge_strokes':6,'smudge_dabs':36},indent=2)+'\n')
print(json.dumps(results,indent=2))
