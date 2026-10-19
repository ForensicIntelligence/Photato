#!/usr/bin/env python3
"""Execute upstream GRD/ActionDescriptor reader and writer without Cargo or application FFI."""
from pathlib import Path
import json, hashlib, subprocess
root = Path(__file__).resolve().parent.parent
rust = root.parent/'photocraft-main/crates/psd/src'
temp=Path('/private/tmp/photato-grd-oracle');temp.mkdir(exist_ok=True)
code=r'''
mod error {
#[derive(Debug)]pub enum PsdError{UnexpectedEof{offset:usize,needed:usize},InvalidSignature{expected:&'static str,found:[u8;4]},LimitExceeded(&'static str),Invalid(String),Unsupported(String)}
impl PsdError{pub fn invalid(v:impl Into<String>)->Self{Self::Invalid(v.into())}}
pub type Result<T>=std::result::Result<T,PsdError>;
}
'''
for name in ['io','descriptor','grd']: code+=f'#[path={json.dumps(str(rust/(name+".rs")))}] mod {name};\n'
code+=r'''
use std::io::Write;
fn fixture()->Vec<grd::GrdGradient>{use grd::*;vec![
GrdGradient{name:"Sunset ✓".into(),noise:false,stops:vec![
GrdStop{location:0.,midpoint:0.5,color:GrdColor::Foreground},
GrdStop{location:0.25,midpoint:0.3,color:GrdColor::Rgb([1.,0.5,0.])},
GrdStop{location:1.,midpoint:0.5,color:GrdColor::Background}],opacity:vec![(0.,1.,0.5),(1.,0.25,0.7)]},
GrdGradient{name:"RGB".into(),noise:false,stops:vec![
GrdStop{location:0.,midpoint:0.5,color:GrdColor::Rgb([0.125,0.875,0.25])},
GrdStop{location:1.,midpoint:0.9,color:GrdColor::Rgb([0.75,0.,1.])}],opacity:vec![(0.,0.2,0.5),(1.,1.,0.25)]}]}
fn main(){let args:Vec<_>=std::env::args().collect();
if args.len()>1{let data=std::fs::read(&args[1]).unwrap();let(v,n)=descriptor::VersionedDescriptor::parse_prefix(&data[6..]).unwrap();
let gradients=grd::parse(&data).unwrap();println!("count={} consumed={} tail={} tailhex={:02x?}",gradients.len(),n+6,data.len()-n-6,&data[n+6..data.len().min(n+86)]);
println!("root keys: {:?}",v.descriptor.items.iter().map(|i|&i.0).collect::<Vec<_>>());
if data.len()>n+18 {let(t,_)=descriptor::VersionedDescriptor::parse_prefix(&data[n+18..]).unwrap();
if let Some(descriptor::Value::List(items))=t.descriptor.get("hierarchy") { for (i,item) in items.iter().take(7).enumerate(){println!("hierarchy {i}: {item:?}");} }}
if args.len()>2 {assert_eq!(gradients,fixture()); println!("Native exported presets exactly match Rust metadata/colors/opacity/midpoints");}
else {println!("first preset: {:?}",gradients.first());}return;}
std::io::stdout().write_all(&grd::write(&fixture())).unwrap();}
'''
(temp/'main.rs').write_text(code)
subprocess.run(['rustc','--edition=2024','-O','-Awarnings',str(temp/'main.rs'),'-o',str(temp/'oracle')],check=True)
data=subprocess.check_output([str(temp/'oracle')])
(root/'Tests/PhotoCraftImagingTests/Fixtures/gradient-presets-oracle.grd').write_bytes(data)
manifest={'generator':'scripts/generate-gradient-preset-oracle.py','source_files':{str(p.name):hashlib.sha256(p.read_bytes()).hexdigest()for p in [rust/'grd.rs',rust/'descriptor.rs',rust/'io.rs']},'oracle_bytes':len(data),'oracle_sha256':hashlib.sha256(data).hexdigest(),'scope':'Original Rust GRD writer and ActionDescriptor transport; only the error enum is adapted. Native exported files can be verified with the compiled original reader.'}
(root/'docs/GRADIENT_PRESET_ORACLE.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
