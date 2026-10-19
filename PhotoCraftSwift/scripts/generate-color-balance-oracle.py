#!/usr/bin/env python3
"""Run unchanged source color balance equations and independently pack blnc."""
from pathlib import Path
import hashlib, json, struct, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
source=root.parent/'photocraft-main/crates/compose/src/adjust.rs'
color=root.parent/'photocraft-main/crates/color/src/convert.rs'
s=source.read_text()
def block(text,start):
    body=text.index('{',start)
    nesting,end=1,body+1
    while nesting:
        nesting+=(text[end]=='{')-(text[end]=='}')
        end+=1
    return text[start:end]
arm=s.index('Adjustment::ColorBalance { shadows, midtones, highlights, preserve_luminosity } =>')
body=block(s,s.index('{',s.index('|c|',arm)))
rust=block(color.read_text(),color.read_text().index('pub fn rgb_to_gray'))
rust+='\nfn apply(c:[f32;3], shadows:&[f32;3],midtones:&[f32;3],highlights:&[f32;3],preserve_luminosity:&bool)->[f32;3] '+body
rust+=r'''
fn encode(v:f32)->f32 {if v==0. || v.abs()==1. {return v;} let a=v.abs();let q=if a<=0.0031308 {a*12.92} else {1.055*a.powf(1./2.4)-0.055};q.copysign(v)}
fn decode(v:f32)->f32 {if v==0. || v.abs()==1. {return v;} let a=v.abs();let q=if a<=0.04045 {a/12.92} else {((a+0.055)/1.055).powf(2.4)};q.copysign(v)}
fn main(){
 let params:[[i32;9];8]=[[0;9],[-30,20,0,10,-5,100,0,0,-100],[20,-10,5,-15,10,30,0,5,-20],[100,-100,100,0,0,0,0,0,0],[0,0,0,-100,100,-100,0,0,0],[0,0,0,0,0,0,100,-100,100],[-100,-100,-100,-100,-100,-100,-100,-100,-100],[100,100,100,100,100,100,100,100,100]];
 let mut inputs=Vec::new();
 for r in [0.,0.01,0.125,0.25,0.5,0.75,0.875,0.99,1.] {for g in [0.,0.01,0.125,0.25,0.5,0.75,0.875,0.99,1.] {for b in [0.,0.01,0.125,0.25,0.5,0.75,0.875,0.99,1.] {inputs.push([r,g,b,0.37]);}}}
 for i in 0..257 {let v=i as f32/256.;inputs.push([v,v,v,1.]);}
 inputs.extend_from_slice(&[[-0.25,0.2,0.5,0.5],[2.,1.2,0.4,1.],[0.5,0.5,0.5,0.],[-0.0,0.0,1.,0.75]]);
 let float_inputs:Vec<[f32;4]>=inputs.iter().map(|p| [encode(p[0]),encode(p[1]),encode(p[2]),p[3]]).collect();
 println!("[");
 for (index,p) in params.iter().enumerate(){
 for preserve in [false,true]{
 let a=[p[0] as f32,p[1] as f32,p[2] as f32];let b=[p[3] as f32,p[4] as f32,p[5] as f32];let c=[p[6] as f32,p[7] as f32,p[8] as f32];
 let output:Vec<[f32;4]>=inputs.iter().map(|x|{if x[3]<=0. {return *x;}let y=apply([x[0],x[1],x[2]],&a,&b,&c,&preserve);[y[0],y[1],y[2],x[3]]}).collect();
 let float_output:Vec<[f32;4]>=float_inputs.iter().map(|x|{if x[3]<=0. {return *x;}let y=apply([decode(x[0]),decode(x[1]),decode(x[2])],&a,&b,&c,&preserve);[encode(y[0]),encode(y[1]),encode(y[2]),x[3]]}).collect();
 if index>0 || preserve {println!(",");}
 print!("{{\"parameters\":{:?},\"preserve\":{},\"inputs\":{:?},\"outputs\":{:?},\"floatInputs\":{:?},\"floatOutputs\":{:?}}}",p,preserve,inputs,output,float_inputs,float_output);
 }}
 println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photato-balance-oracle-') as temp:
    p=Path(temp);(p/'oracle.rs').write_text(rust)
    subprocess.run(['rustc','--edition','2024','-O',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
    vectors=json.loads(subprocess.check_output([str(p/'oracle')]))
(root/'Tests/PhotoCraftCoreTests/Fixtures/color-balance-oracle.json').write_text(json.dumps(vectors,separators=(',',':'))+'\n')
record=struct.pack('>9hBx',-30,20,0,10,-5,100,0,0,-100,1)
(root/'Tests/PhotoCraftImagingTests/Fixtures/color-balance-record.bin').write_bytes(record)
(root/'docs/COLOR_BALANCE_ORACLE.json').write_text(json.dumps({
    'compose_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'color_source_sha256':hashlib.sha256(color.read_bytes()).hexdigest(),
    'generator':'scripts/generate-color-balance-oracle.py',
    'cases':len(vectors),'rgb_samples':sum(len(v['inputs']) for v in vectors),
    'encoded_float_samples':sum(len(v['floatInputs']) for v in vectors),
    'scope':'Unchanged Rust ColorBalance closure and Rec.601 rgb_to_gray. Encoded/linear adapter for native float storage. Both luminosity options, all tones, endpoints, gray ramp and extended/hidden colors. Approximation, not Photoshop pixel qualification.',
    'intentional_identity_exception':'All-zero settings preserve exact input bits, including HDR colors that Rust clamps/reconstructs. Cases 0 and 1, extended inputs 986 and 987.',
    'binary_fixture':'Independent Python struct.pack >9hBx, signed tone triples, one-byte luminosity and padding; also checked against psd-tools ColorBalance reader.',
    'binary_sha256':hashlib.sha256(record).hexdigest(),
    'references':['https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/','https://raw.githubusercontent.com/psd-tools/psd-tools/main/src/psd_tools/psd/adjustments.py']
},indent=2)+'\n')
print(f"Generated {len(vectors)} cases, {sum(len(v['inputs']) for v in vectors)} RGB and encoded-float samples each.")
