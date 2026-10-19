#!/usr/bin/env python3
"""Run unmodified Rust gradient geometry/ramp/interpolation functions in a standalone harness."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
root = Path(__file__).resolve().parent.parent
rust = root.parent / 'photocraft-main/crates'
files = ['compose/src/effects.rs', 'compose/src/fill_layout.rs', 'compose/src/gradient_fill.rs',
         'io/src/gradient_bake.rs', 'color/src/lib.rs', 'engine/src/preset_import_cmds.rs']
effects, layout, fill, bake, color, preset_import = [(rust / p).read_text() for p in files]
code = r'''
use std::io::Write;
#[derive(Clone,Copy,Debug,PartialEq)] pub enum GradientStyle {Linear,Radial,Angle,Reflected,Diamond}
#[derive(Clone,Copy)] pub struct Rect {x0:i32,y0:i32,x1:i32,y1:i32}
impl Rect {fn width(&self)->u32 {(self.x1-self.x0)as u32} fn height(&self)->u32 {(self.y1-self.y0)as u32}}
const MIN_LEN:f32=0.5;
'''
code += 'mod effects { use super::*;\n' + effects[effects.index('pub fn gradient_units('):effects.index('/// Samples colour and opacity stops')] + '}\nuse effects::*;\n'
code += layout[layout.index('pub fn gradient_layout('):layout.index('/// [`effects::gradient_t`]')] if '/// [`effects::gradient_t`]' in layout else layout[layout.index('pub fn gradient_layout('):layout.index('#[cfg(test)]')]
# Only the layout function; later wrappers are not needed.
start = code.index('pub fn gradient_layout('); body = code.index('{', start); depth = 1; end = body+1
while depth:
    depth += (code[end] == '{') - (code[end] == '}'); end += 1
code = code[:end] + '\n'
code += fill[fill.index('pub fn midpoint_remap('):fill.index('/// Adds one level')]
code += 'mod photocraft_color {\n' + color[color.index('pub fn dither_noise('):color.index('use serde::')] + '}\n'
code += fill[fill.index('pub fn dither('):fill.index('/// Renders', fill.index('pub fn dither('))] if '/// Renders' in fill[fill.index('pub fn dither('):] else ''
# extract individual function with balanced braces

def function(source, signature):
    start = source.index(signature); at=source.index('{',start)+1; depth=1
    while depth:
        depth += (source[at]=='{')-(source[at]=='}'); at+=1
    return source[start:at]+'\n'
if 'pub fn dither(' not in code: code+=function(fill,'pub fn dither(')
for sig in ['fn frame_dims(', 'fn centre(', 'fn unit_reach(', 'pub fn handles(', 'pub fn from_handles(']:
    code += function(fill, sig)
code += function(preset_import, 'fn hsb_to_rgb(')
code += '#[derive(Clone,Copy,PartialEq)] enum Method {Classic,Perceptual,Linear}\n'
code += bake[bake.index('fn lin('):bake.index('/// Dense linear stops')]
code += r'''
fn u(out:&mut Vec<u8>,v:u32){out.extend(v.to_le_bytes());}
fn f(out:&mut Vec<u8>,v:f32){out.extend(v.to_le_bytes());}
fn fs(out:&mut Vec<u8>,v:&[f32]){for x in v {f(out,*x)}}
fn main(){let mut out=Vec::new();u(&mut out,120);
for(si,style)in[GradientStyle::Linear,GradientStyle::Radial,GradientStyle::Angle,GradientStyle::Reflected,GradientStyle::Diamond].into_iter().enumerate(){
for(x,y,w,h)in[(0,0,4,4),(-17,23,191,73),(10,-15,600,60)]{
let frame=Rect{x0:x,y0:y,x1:x+w,y1:y+h};
for(angle,scale,offset)in[(0.0f32,1.0f32,(0.0f32,0.0f32)),(30.,0.25,(0.,0.)),(87.,2.75,(-0.25,0.4)),(-137.5,1.125,(0.123,-0.77))]{
for reverse in[false,true]{u(&mut out,si as u32);for q in[x,y,w,h]{u(&mut out,q as u32)}fs(&mut out,&[angle,scale,offset.0,offset.1]);u(&mut out,reverse as u32);
let(a,s,o)=gradient_layout(style,angle,scale,offset,frame);fs(&mut out,&[a,s,o.0,o.1]);
let(from,to)=handles(style,angle,scale,offset,frame);fs(&mut out,&[from[0],from[1],to[0],to[1]]);
let(aa,ss,oo)=from_handles(style,from,to,frame,angle);fs(&mut out,&[aa,ss,oo.0,oo.1]);
for yy in -4..7{for xx in -5..8{let px=x as f32+xx as f32*w as f32/7.+0.5;let py=y as f32+yy as f32*h as f32/5.+0.5;
fs(&mut out,&[px,py,gradient_t(style,angle,scale,reverse,offset,frame,px,py),gradient_t(style,a,s,reverse,o,frame,px,py)]);}}
}}}}
u(&mut out,27);
for (mi,method) in [Method::Classic,Method::Linear,Method::Perceptual].into_iter().enumerate(){for smooth in[0.0f32,0.37,1.]{for set in 0..3{
let (stops,mids) = match set {
0=>(vec![(0.,[0.,0.,0.]),(1.,[1.,1.,1.])],vec![0.5]),
1=>(vec![(0.,[0.882,0.602,0.201]),(0.375,[0.164,0.568,0.851]),(1.,[0.75,0.02,0.13])],vec![0.25,0.8]),
_=>(vec![(0.125,[0.1,0.7,0.5]),(0.25,[1.,0.,1.]),(0.75,[1.,1.,0.]),(0.875,[0.,0.03,0.82])],vec![0.,1.,0.62]),};
u(&mut out,mi as u32);f(&mut out,smooth);u(&mut out,stops.len()as u32);
for(i,(p,c))in stops.iter().enumerate(){fs(&mut out,&[*p,c[0],c[1],c[2],if i==0{0.5}else{mids[i-1]}]);}
let pts:Vec<_>=stops.iter().map(|(t,c)|(*t,into_space(method,*c))).collect();
for i in 0..=192{let t=i as f32/192.;f(&mut out,t);fs(&mut out,&out_of_space(method,eval(&pts,&mids,smooth,t)));}
}}}
u(&mut out,256);
for i in 0..256i32{let t=i as f32/255.;let cs=vec![(0.,[0.1,0.7,0.9,1.]),(0.25,[0.9,0.3,0.7,1.]),(1.,[0.25,0.1,0.5,1.])];
let mut c=sample_color(&cs,&[0.25,0.75],t);let alpha=sample_opacity(&[(0.,1.),(0.75,0.3),(1.,0.6)],t);c[3]*=alpha;
f(&mut out,t);fs(&mut out,&c);dither(&mut c,i-170,i*13-2200);fs(&mut out,&c);}
u(&mut out,135);
for h in [-137.5f32,0.,27.,60.,90.,120.,180.,210.,240.,300.,359.9,360.,720.,1440.,-720.]{
for s in [0.0f32,0.37,1.] {for v in[0.0f32,0.71,1.] {fs(&mut out,&[h,s,v]);fs(&mut out,&hsb_to_rgb([h,s,v]));}}}
u(&mut out,3);
for smooth in[0.0f32,0.37,1.]{f(&mut out,smooth);
let pts=vec![(0.,[0.2;3]),(0.375,[1.;3]),(1.,[0.1;3])];
for i in 0..=192{let t=i as f32/192.;f(&mut out,t);f(&mut out,eval(&pts,&[0.25,0.75],smooth,t)[0].clamp(0.,1.));}}
std::io::stdout().write_all(&out).unwrap();}
'''
with tempfile.TemporaryDirectory(prefix='photato-gradient-oracle-', dir='/private/tmp') as temp:
    temp=Path(temp); (temp/'main.rs').write_text(code)
    subprocess.run(['rustc','--edition=2024','-O','-Awarnings',str(temp/'main.rs'),'-o',str(temp/'oracle')],check=True)
    data=subprocess.check_output([str(temp/'oracle')])
    target=root/'Tests/PhotoCraftCoreTests/Fixtures/gradient-oracle.bin'; target.write_bytes(data)
    manifest={'generator':'scripts/generate-gradient-oracle.py',
      'source_files': {p:hashlib.sha256((rust/p).read_bytes()).hexdigest() for p in files},
      'oracle_bytes':len(data),'oracle_sha256':hashlib.sha256(data).hexdigest(),
      'geometry_cases':120,'geometry_parameters':34320,'geometry_metadata_values':1440,'interpolation_cases':27,
      'interpolation_rgb_values':15633,'ramp_dither_values':2048,'hsb_rgb_values':405,'opacity_values':579,
      'scope':'Executed original Rust functions, not Photoshop output certification. Direct interpolation avoids upstream 97-stop baking; adapters only provide geometry types and output framing.'}
    (root/'docs/GRADIENT_ORACLE.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))
