"""Run licensed PhotoCraft ink functions unchanged to generate small independent fixtures."""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--work-dir',type=Path,required=True);args=p.parse_args();args.work_dir.mkdir(parents=True,exist_ok=False)
here=Path(__file__).resolve().parent;root=here.parents[3];source=root.parent/'photocraft-main/crates/doc/src/mode.rs';text=source.read_text()
transfer=text[text.index('fn curve_eval('):text.index('/// Layer › Smart Objects')]
density=text[text.index('impl DuotoneInk {\n    /// Ink density'):text.index('impl Duotone {\n    /// Simulated')]
render=text[text.index('impl Duotone {\n    /// Simulated'):text.index('impl Duotone {\n    /// A Gradient Map')]
def ink(name,color,curve=None):return {'name':name,'color':color,'curve':curve or [[0,0],[1,1]]}
cases=[{'name':'black','inks':[ink('Black',[0,0,0])]},{'name':'cyan-magenta','inks':[ink('Cyan',[0,1,1]),ink('Magenta',[1,0,1])]},{'name':'half-black','inks':[ink('Half black',[0,0,0],[[0,0],[1,0.5]])]},{'name':'curved-tritone','inks':[ink('Black',[0,0,0],[[0,0],[0.25,0.1],[0.6,0.7],[1,1]]),ink('Brown',[0.62,0.38,0.18],[[0,0],[0.2,0.5],[0.75,0.25],[1,0.8]]),ink('Blue',[0.27,0.38,0.58],[[0,0.15],[0.5,0.8],[1,0.4]])]}]
def f(x):return repr(float(x))+'f32'
body=['fn main() { let dir=std::env::args().nth(1).unwrap();']
for case in cases:
 inks=[]
 for ink in case['inks']:
  points=','.join('CurvePoint{input:'+f(a)+',output:'+f(b)+'}' for a,b in ink['curve'])
  inks.append('DuotoneInk{color:['+','.join(map(f,ink['color']))+'],curve:vec!['+points+']}')
 body.append('let d=Duotone{inks:vec!['+','.join(inks)+']};let mut rgb=Vec::new();let mut plates=Vec::new();')
 body.append('for i in 0..256 {let g=i as f32/255.0;for c in d.render(g){rgb.push((c.clamp(0.0,1.0)*255.0).round() as u8);}}')
 body.append('for ink in &d.inks {for i in 0..256 {let g=i as f32/255.0;plates.push((ink.density(1.0-g)*255.0).round() as u8);}}')
 body.append('std::fs::write(format!("{}/'+case['name']+'.rgb",dir),rgb).unwrap();std::fs::write(format!("{}/'+case['name']+'.plates",dir),plates).unwrap();')
body.append('}')
oracle='// MIT OR Apache-2.0. Functions copied unchanged from the retained PhotoCraft source.\nstruct CurvePoint{input:f32,output:f32}\nstruct DuotoneInk{color:[f32;3],curve:Vec<CurvePoint>}\nstruct Duotone{inks:Vec<DuotoneInk>}\n'+transfer+density+render+'\n'.join(body)
rs=args.work_dir/'ink-oracle.rs';rs.write_text(oracle);exe=args.work_dir/'ink-oracle'
subprocess.run(['rustc','--edition=2021','-O',str(rs),'-o',str(exe)],check=True);subprocess.run([str(exe),str(here)],check=True)
record={'license':'MIT OR Apache-2.0','source':'../photocraft-main/crates/doc/src/mode.rs','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference':'curve_eval, DuotoneInk.density and Duotone.render extracted unchanged; standalone fixture types omit unrelated fields/serialization.','scope':'Four configurations, all256 gray samples; byte comparisons of rendered RGB8 and each ink separation. Does not qualify Photoshop numerical output or custom overprint display.','cases':cases,'outputs':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(here.iterdir()) if p.suffix in ['.rgb','.plates']}}
(here/'provenance.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'configurations':len(cases),'rgb_samples':len(cases)*256*3,'plate_samples':sum(len(c['inks']) for c in cases)*256,'half_black_midpoint':(here/'half-black.plates').read_bytes()[128]}))
