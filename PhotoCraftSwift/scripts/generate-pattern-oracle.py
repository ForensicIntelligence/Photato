#!/usr/bin/env python3
"""Execute original PhotoCraft pattern math/presets and PAT codec, without Cargo/FFI."""
from pathlib import Path
import hashlib, json, subprocess, tempfile, sys

root = Path(__file__).resolve().parent.parent
rust = root.parent / 'photocraft-main/crates'
paths = [rust / p for p in ['compose/src/pattern.rs', 'engine/src/pattern_cmds.rs', 'doc/src/pattern.rs', 'psd/src/patterns.rs', 'psd/src/compression.rs']]
compose, engine, doc, pat, compression = [p.read_text() for p in paths]
tile = compose[compose.index('pub struct Tile {'):compose.index('#[cfg(test)]')]
presets = engine[engine.index('fn hash01('):engine.index('fn bad(')]
identity = doc[doc.index('fn fnv('):doc.index('    /// The name shown')]+ '\n}\n'
adapters = r'''
use std::io::Write;
#[derive(Clone,Copy,Debug)] pub struct Rect {x0:i32,y0:i32,x1:i32,y1:i32}
impl Rect {fn new(x0:i32,y0:i32,x1:i32,y1:i32)->Self{Self{x0,y0,x1,y1}} fn width(&self)->u32{(self.x1-self.x0)as u32} fn height(&self)->u32{(self.y1-self.y0)as u32} fn is_empty(&self)->bool{self.x1<=self.x0||self.y1<=self.y0}}
#[derive(Clone,Copy,Debug)] enum ColorMode {Rgb}
#[derive(Clone,Copy,Debug)] enum SampleType {U8}
#[derive(Clone,Copy,Debug)] struct PixelFormat {mode:ColorMode,sample:SampleType,alpha:bool}
impl PixelFormat{fn new(mode:ColorMode,sample:SampleType,alpha:bool)->Self{Self{mode,sample,alpha}}}
pub struct Surface {fmt:PixelFormat,px:Vec<f32>}
impl Surface {
fn new(fmt:PixelFormat)->Self{Self{fmt,px:Vec::new()}}
fn write_region(&mut self,_r:Rect,px:&[f32]){self.px=px.iter().map(|v|(v.clamp(0.,1.)*255.).round()/255.).collect();}
fn read_region(&self,_r:Rect)->Vec<f32>{self.px.clone()} fn format(&self)->PixelFormat{self.fmt}
fn read_rgba_into(&self,_r:Rect,out:&mut[[f32;4]]){for(i,p)in self.px.chunks_exact(3).enumerate(){out[i]=[p[0],p[1],p[2],1.];}}
}
pub struct Pattern {id:String,name:String,width:u32,height:u32,surface:Surface}
impl Pattern {fn is_empty(&self)->bool{self.width==0||self.height==0} fn rect(&self)->Rect{Rect::new(0,0,self.width as i32,self.height as i32)}}
fn u(o:&mut Vec<u8>,v:usize){o.extend((v as u32).to_le_bytes());}
fn f(o:&mut Vec<u8>,v:f32){o.extend(v.to_le_bytes());}
fn string(o:&mut Vec<u8>,v:&str){u(o,v.len());o.extend(v.as_bytes());}
'''
main = r'''
fn main(){let mode=std::env::args().nth(1).unwrap();let mut out=Vec::new();
if mode=="presets" {for p in builtin(){u(&mut out,p.width as usize);u(&mut out,p.height as usize);string(&mut out,&p.name);string(&mut out,&p.id);for x in p.surface.px {f(&mut out,x);}}}
else {for (kind,(w,h)) in [(1usize,1usize),(2,3),(9,7),(17,13)].into_iter().enumerate(){
let data:Vec<[f32;4]>=(0..w*h).map(|i|[((i*11)%31)as f32/30.,((i*17)%37)as f32/36.,((i*7)%41)as f32/40.,if i%5==0 {0.}else{((i*3)%7)as f32/6.}]).collect();
u(&mut out,w);u(&mut out,h);for p in &data{for v in p{f(&mut out,*v);}}
let px=data.iter().map(|p|[p[0]*p[3],p[1]*p[3],p[2]*p[3],p[3]]).collect();let tile=Tile{w,h,px};
for (scale,angle,phase) in [(100.0f32,0.0f32,(0.0f32,0.0f32)),(33.,27.,(-4.25,3.5)),(225.,-90.,(2.,-5.)),(1000.,183.75,(0.25,0.75))]{
f(&mut out,scale);f(&mut out,angle);f(&mut out,phase.0);f(&mut out,phase.1);
let place=Placement::new(Rect::new(0,0,0,0),false,phase,scale/100.,angle);
for y in -7..12 {for x in -5..18 {let(u,v)=place.map(x as f64+0.5,y as f64+0.5);for q in tile.sample(u,v){f(&mut out,q);}}}
}let _=kind;}}
std::io::stdout().write_all(&out).unwrap();}
'''
# Original PAT parser/writer and PackBits methods; row-plane framing is an adapter.
pat_code = pat[pat.index('const MAX_EDGE:'):pat.index('#[cfg(test)]')]
packbits = compression[compression.index('pub mod packbits {'):compression.index('/// Geometry of a set of planes')]
pat_adapters = r'''
mod error {
#[derive(Debug)] pub enum PsdError {LimitExceeded(&'static str),UnexpectedEof{offset:usize,needed:usize},InvalidSignature{expected:&'static str,found:[u8;4]},Decompress(String),Invalid(String)}
impl PsdError{pub fn invalid(v:impl Into<String>)->Self{Self::Invalid(v.into())}}
pub type Result<T>=std::result::Result<T,PsdError>;
}use error::{PsdError,Result};
#[derive(Clone,Copy)] enum Compression{Raw,Rle,Unknown(u16)}
#[derive(Clone,Copy)] enum Version{Psd}
struct PlaneLayout{planes:usize,width:usize,height:usize,depth:u16,version:Version}
fn encode_planes(c:Compression,p:&[u8],l:&PlaneLayout)->Result<Vec<u8>>{
let row=(l.width*l.depth as usize).div_ceil(8);if matches!(c,Compression::Raw){return Ok(p.to_vec());}
let mut sizes=Vec::new();let mut all=Vec::new();for y in 0..l.height {let enc=packbits::encode_vec(&p[y*row..(y+1)*row]);sizes.extend((enc.len()as u16).to_be_bytes());all.extend(enc);}sizes.extend(all);Ok(sizes)}
fn decode_planes(c:Compression,p:&[u8],l:&PlaneLayout)->Result<Vec<u8>>{
let row=(l.width*l.depth as usize).div_ceil(8);if matches!(c,Compression::Raw){return Ok(p.to_vec());}
if !matches!(c,Compression::Rle){return Err(PsdError::invalid("compression"));}
let mut out=Vec::new();let mut at=l.height*2;for y in 0..l.height {let n=u16::from_be_bytes([p[y*2],p[y*2+1]])as usize;packbits::decode_into(&p[at..at+n],row,&mut out)?;at+=n;}Ok(out)}
'''
pat_main = r'''
use std::io::Write;
fn fixtures()->Vec<PsdPattern>{let mut out=Vec::new();
for depth in [8u16,16,32] {for alpha in [false,true] {let index=out.len();
let plane=|c:usize|->Vec<u8>{let mut b=Vec::new();for i in 0..15usize {let value=((i*3+c*5)%11)as f32/10.;match depth {8=>b.push((value*255.).round()as u8),16=>b.extend(((value*65535.).round()as u16).to_be_bytes()),_=>b.extend(value.to_be_bytes())}}b};
out.push(PsdPattern{mode:3,width:5,height:3,name:format!("Pattern ✓ {index}"),id:format!("pattern-{index}"),palette:None,depth,channels:vec![plane(0),plane(1),plane(2)],alpha:alpha.then(||plane(3))});}}
out.push(PsdPattern{mode:1,width:5,height:3,name:"Gray".into(),id:"gray".into(),palette:None,depth:8,channels:vec![(0..15).map(|i|i*17).collect()],alpha:None});
let palette:Vec<u8>=(0..256).flat_map(|i|[i as u8,(255-i)as u8,(i/2)as u8]).collect();
out.push(PsdPattern{mode:2,width:5,height:3,name:"Indexed".into(),id:"indexed".into(),palette:Some(palette),depth:8,channels:vec![(0..15).map(|i|i*17).collect()],alpha:None});
out.push(PsdPattern{mode:1,width:5,height:3,name:"Bitmap".into(),id:"bitmap".into(),palette:None,depth:1,channels:vec![vec![0xa8,0x50,0xf8]],alpha:None});out}
fn main(){if let Some(path)=std::env::args().nth(1){
if path=="rgb" {std::io::stdout().write_all(&write_pat_file(&fixtures()[..6]).unwrap()).unwrap();return;}
if path=="packets" {let plane:Vec<u8>=(0..520).map(|i|match i%260 {0..=127=>42,128..=129=>99,130..=258=>(i%256)as u8,_=>7}).collect();
let p=PsdPattern{mode:3,width:260,height:2,name:"Packet boundaries".into(),id:"packets".into(),palette:None,depth:8,channels:vec![plane.clone(),plane.clone(),plane],alpha:None};std::io::stdout().write_all(&write_pat_file(&[p]).unwrap()).unwrap();return;}
let bytes=std::fs::read(path).unwrap();let ps=parse_pat_file(&bytes).unwrap();
assert_eq!(ps.len(),9);for (i,p) in ps.iter().enumerate(){assert_eq!(p.width,5);assert_eq!(p.height,3);assert_eq!(p.mode,3);assert_eq!(p.channels.len(),3);assert!(!p.id.is_empty());if i<6 {assert_eq!(p.depth,[8,8,16,16,32,32][i]);}}
let mut expected=fixtures();
for p in expected.iter_mut().skip(6) {
let plane=p.channels[0].clone();
if p.mode==2 {let palette=p.palette.take().unwrap();p.channels=(0..3).map(|c|plane.iter().map(|i|palette[*i as usize*3+c]).collect()).collect();}
else {let bytes=if p.depth==1 {(0..15).map(|i|if plane[i/5]&(0x80>>(i%5))!=0 {0}else{255}).collect()}else{plane};p.channels=vec![bytes.clone(),bytes.clone(),bytes];p.depth=8;}
p.mode=3;
}
assert_eq!(ps,expected);
println!("Original Rust PAT parser verified all channel bytes, identifiers, names and dimensions of {} native-exported patterns",ps.len());
}else {let ps=fixtures();let b=write_pat_file(&ps).unwrap();assert_eq!(parse_pat_file(&b).unwrap(),ps);std::io::stdout().write_all(&b).unwrap();}}
'''
results = {}
with tempfile.TemporaryDirectory(prefix='photato-pattern-oracle-') as directory:
    folder = Path(directory)
    if len(sys.argv) == 1:
        (folder/'math.rs').write_text(adapters + identity + presets + tile + main)
        subprocess.run(['rustc','-O','--edition=2024','-Awarnings',str(folder/'math.rs'),'-o',str(folder/'math')],check=True)
        for name in ['presets','sampling']:
            data = subprocess.check_output([str(folder/'math'), name])
            (root/f'Tests/PhotoCraftCoreTests/Fixtures/pattern-{name}-oracle.bin').write_bytes(data)
            results[name] = {'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    (folder/'pat.rs').write_text(pat_adapters + packbits + pat_code + pat_main)
    subprocess.run(['rustc','-O','--edition=2024','-Awarnings',str(folder/'pat.rs'),'-o',str(folder/'pat')],check=True)
    if len(sys.argv) > 1:
        subprocess.run([str(folder/'pat'),sys.argv[1]],check=True)
    else:
        data=subprocess.check_output([str(folder/'pat')])
        (root/'Tests/PhotoCraftImagingTests/Fixtures/patterns-source.pat').write_bytes(data)
        results['pat']={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'patterns':9}
        for kind in ['rgb','packets']:
            extra=subprocess.check_output([str(folder/'pat'),kind])
            (root/f'Tests/PhotoCraftImagingTests/Fixtures/patterns-{kind}-source.pat').write_bytes(extra)
            results[kind+'_pat']={'bytes':len(extra),'sha256':hashlib.sha256(extra).hexdigest()}

        manifest={'sources':{str(p.relative_to(root.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},'fixtures':results,
          'method':'Original pattern identity, procedural preset, Tile and Placement methods; original PAT parser/writer and PackBits code with storage and row-plane framing adapters. No Swift implementation used to generate expected values.',
          'scope':'Source references, not Photoshop render references. Generated preset pixels are original upstream CC0 assets.'}
        (root/'docs/PATTERN_ORACLE.json').write_text(json.dumps(manifest,indent=2)+'\n')
        print(json.dumps(results,indent=2))
