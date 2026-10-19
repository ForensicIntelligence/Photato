#!/usr/bin/env python3
"""Run unchanged PhotoCraft HSL/range code; pack independent AHU/PSD records."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root.parent/'photocraft-main/crates/compose/src/adjust.rs'
model = root.parent/'photocraft-main/crates/doc/src/adjust.rs'
original, definitions = source.read_text(), model.read_text()


def block(text, start):
    body = text.index('{', start)
    nesting, end = 1, body + 1
    while nesting:
        nesting += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


rust = '''
const LUT_SIZE:usize=4096;
struct Buffer { px:Vec<[f32;4]> }
#[derive(Clone)] struct HueRange { hue:f32, saturation:f32, lightness:f32, bounds:[f32;4] }
'''
rust += block(definitions, definitions.index('impl HueRange'))
rust += '\n'.join(block(original, original.index('fn '+name+'(')) for name in [
    'map_rgb', 'lut', 'hue_range_tables', 'hue_saturation', 'rgb_to_hsl', 'hsl_to_rgb'])
arm = original.index('Adjustment::HueSaturation { hue, saturation, lightness, colorize, ranges } =>')
body = block(original, original.index('{', original.index('=>', arm)))
rust += '\nfn apply(hue:&f32,saturation:&f32,lightness:&f32,colorize:&bool,ranges:&[HueRange;6],buf:&mut Buffer) '+body
rust += r'''
// Mathematical adapter for native extended encoded-sRGB storage. The HSL/range
// functions above remain untouched. Float fixtures evaluate their actual decoded input.
fn encode(v:f32)->f32 { if v==0. || v.abs()==1. {return v;} let a=v.abs(); let q=if a<=0.0031308 {a*12.92} else {1.055*a.powf(1./2.4)-0.055}; q.copysign(v) }
fn decode(v:f32)->f32 { if v==0. || v.abs()==1. {return v;} let a=v.abs(); let q=if a<=0.04045 {a/12.92} else {((a+0.055)/1.055).powf(2.4)}; q.copysign(v) }
fn main() {
 let params:[[i32;3];12]=[[0,0,0],[120,0,0],[-180,-100,0],[37,73,-17],[-57,-35,29],[0,0,0],[15,-10,3],[-35,20,-5],[35,25,0],[-145,50,30],[180,100,-40],[0,0,0]];
 let colors=[0.,0.01,0.125,0.25,0.5,0.75,0.875,0.99,1.];
 let mut inputs=Vec::new();
 for r in colors {for g in colors {for b in colors { inputs.push([r,g,b,0.37]); }}}
 for angle in [-45.,-15.,-0.01,0.,0.01,15.,45.,60.,180.,300.,345.,359.99] {
  let c=hsl_to_rgb(angle/360.,0.7,0.5);inputs.push([c[0],c[1],c[2],1.]);
 }
 inputs.extend_from_slice(&[[-0.25,0.2,0.5,0.5],[2.,1.2,0.4,1.],[0.5,0.5,0.5,0.],[0.4999,0.5,0.5001,0.75]]);
 let float_inputs:Vec<[f32;4]>=inputs.iter().map(|p| [encode(p[0]),encode(p[1]),encode(p[2]),p[3]]).collect();
 println!("[");
 for (index,p) in params.iter().enumerate() {
  let colorize=index>=8 && index<=10;
  let mut ranges=HueRange::defaults();
  if index==5 {ranges[0].saturation=-100.;}
  if index==6 {ranges[5].hue=-90.;ranges[5].saturation=60.;ranges[5].lightness=20.;ranges[0].hue=120.;ranges[0].lightness=-40.;}
  if index==7 {ranges[2].bounds=[43.,50.,95.,110.];ranges[2].hue=33.;ranges[2].saturation=-50.;ranges[3].lightness=45.;}
  if index==11 {ranges[0].bounds=[-2.,-1.,1.,2.];ranges[0].hue=180.;ranges[0].saturation=-100.;}
  if colorize {ranges[0].saturation=-100.;} // Must be ignored in Colorize.
  let mut buf=Buffer{px:inputs.clone()};
  let mut float_buf=Buffer{px:float_inputs.iter().map(|p| [decode(p[0]),decode(p[1]),decode(p[2]),p[3]]).collect()};
  apply(&(p[0] as f32),&(p[1] as f32),&(p[2] as f32),&colorize,&ranges,&mut buf);
  apply(&(p[0] as f32),&(p[1] as f32),&(p[2] as f32),&colorize,&ranges,&mut float_buf);
  let float_outputs:Vec<[f32;4]>=float_buf.px.iter().map(|p| [encode(p[0]),encode(p[1]),encode(p[2]),p[3]]).collect();
  let records:Vec<[i32;7]>=ranges.iter().map(|r| [r.bounds[0] as i32,r.bounds[1] as i32,r.bounds[2] as i32,r.bounds[3] as i32,r.hue as i32,r.saturation as i32,r.lightness as i32]).collect();
  if index>0 {println!(",");}
  print!("{{\"parameters\":{:?},\"colorize\":{},\"ranges\":{:?},\"inputs\":{:?},\"outputs\":{:?},\"floatInputs\":{:?},\"floatOutputs\":{:?}}}",p,colorize,records,inputs,buf.px,float_inputs,float_outputs);
 }
 println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photato-hue-oracle-') as temp:
    path = Path(temp)
    (path/'oracle.rs').write_text(rust)
    subprocess.run(['rustc','--edition','2024','-O',str(path/'oracle.rs'),'-o',str(path/'oracle')],check=True)
    vectors = json.loads(subprocess.check_output([str(path/'oracle')]))
(root/'Tests/PhotoCraftCoreTests/Fixtures/hue-saturation-oracle.json').write_text(json.dumps(vectors,separators=(',',':'))+'\n')

ranges = [[(60*i+delta)%360 for delta in [-45,-15,15,45]] + [0,0,0] for i in range(6)]
ranges[0][4:] = [120,-60,20]
ranges[3][4:] = [-20,40,-10]
record = struct.pack('>HBB6h',2,0,0,-145,25,7,30,-20,5) + b''.join(struct.pack('>7h',*r) for r in ranges)
(root/'Tests/PhotoCraftImagingTests/Fixtures/hue-saturation-record.ahu').write_bytes(record)
(root/'docs/HUE_SATURATION_ORACLE.json').write_text(json.dumps({
    'compose_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'model_source_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),
    'generator':'scripts/generate-hue-saturation-oracle.py','cases':len(vectors),
    'rgb_samples':sum(len(v['inputs']) for v in vectors),
    'encoded_float_samples':sum(len(v['floatInputs']) for v in vectors),
    'retained_rgb_reference_samples':2980, 'retained_encoded_float_reference_samples':2980,
    'retained_rust_case_indices':[0,1,2,8], 'superseded_rust_cases':[3,4,5,6,7,9,10,11],
    'superseded_colorize_lightness_cases':[9,10],
    'superseded_reason':'Photoshop saved composites contradict the original range/chroma weighting, additive saturation/lightness, positive saturation, processing order and Colorize lightness order. The original vectors remain historical data; retained cases qualify identity, master hue/desaturation and neutral-lightness Colorize.',
    'range_approximation':{'source': 'https://github.com/psd-tools/psd-tools/blob/1b8c1d404d1b976748e7dbbca33ed5898663371b/src/psd_tools/composite/adjustments.py', 'source_sha256': '51b51d26c4ac1f7e5a799ed286c0210f2e05c521d5f40e77f70d3a092e92d1b8', 'license': 'LICENSE-psd-tools', 'scope': 'Empirical 21x21 saturation overlap grid and positive range contribution. Native neutral axes stay exact. Master lightness precedes range contraction toward RGB extrema; master and range saturation are sequential. Positive boost uses 1/max(0.01,1-adjustment), an explicitly approximate finite cap, instead of adding 0.01 at all positive settings. No Rust/Python runtime or third-party package is linked.', 'photoshop_exact': False, 'saved_composite_report': 'artifacts/hue-reference-corrected.json'},
    'scope':'Unchanged source HueRange implementation, HSL conversions, range tables and HueSaturation match arm. Independent encoded/linear mathematical adapter for native float storage. Colorize fixtures use >=25 saturation; native lower values intentionally remove the source\'s undocumented floor. Source equations are approximations, not Photoshop qualification.',
    'native_identity_exceptions':{'reason':'The source projects extended RGB through HSL even when no setting affects the pixel. Native identity and excluded-color paths preserve input bits instead.', 'case_and_sample_indices':[[0,741],[0,742],[5,741],[11,741],[11,742]], 'currently_compared_case_and_sample_indices':[[0,741],[0,742]]},
    'binary_fixture':'Independent Python struct.pack: version 2, both parameter sets and six wrapped ranges, 100 bytes.',
    'binary_fixture_sha256':hashlib.sha256(record).hexdigest(),
    'format_reference':'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/',
},indent=2)+'\n')
presets=[]
for path in sorted(Path('/Applications/Adobe Photoshop 2026/Presets/Hue and Saturation').glob('*.ahu')):
    data=path.read_bytes()
    assert len(data)==100
    presets.append({'name':path.stem,'sha256':hashlib.sha256(data).hexdigest(),
        'version_colorize_padding':struct.unpack_from('>HBB',data),
        'colorization':struct.unpack_from('>3h',data,4),'master':struct.unpack_from('>3h',data,10),
        'ranges':[struct.unpack_from('>7h',data,16+14*i) for i in range(6)]})
if presets:
    (root/'docs/PHOTOSHOP_HUE_SATURATION_PRESETS.json').write_text(json.dumps(presets,indent=2)+'\n')
print(f"Generated {len(vectors)} cases, {sum(len(v['inputs']) for v in vectors)} RGB and encoded-float samples each; observed {len(presets)} installed presets.")
