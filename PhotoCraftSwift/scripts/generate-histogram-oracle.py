#!/usr/bin/env python3
"""Generate histogram/automatic-correction references from unchanged Rust source."""
from pathlib import Path
import hashlib, json, subprocess, tempfile

root = Path(__file__).resolve().parent.parent
histogram = root.parent / 'photocraft-main/crates/algo/src/histogram.rs'
edit = root.parent / 'photocraft-main/crates/engine/src/edit_cmds.rs'
text = edit.read_text()

def function(name):
    start = text.index('fn ' + name + '(')
    body = text.index('{', start)
    level, end = 1, body + 1
    while level:
        level += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

source = 'mod histogram {\n' + histogram.read_text().split('#[cfg(test)]')[0] + '\n}\n'
source += '''
#[derive(Clone, Copy)]
struct LevelsChannel { in_black:f32, in_white:f32, gamma:f32, out_black:f32, out_white:f32 }
impl Default for LevelsChannel { fn default()->Self {Self {in_black:0.,in_white:1.,gamma:1.,out_black:0.,out_white:1.}} }
'''
source += function('clip_points') + '\n' + function('median')
start = text.index('    let clip = 0.001;', text.index('fn auto_adjust('))
end = text.index('    let adj = Adjustment::Levels', start)
source += '\nfn auto(h:[[u64;256];3], kind:&str)->[LevelsChannel;3] {\n' + text[start:end] + '\nper\n}\n'
source += r'''
fn main() {
 println!("["); let mut first=true;
 for case in 0..5 {
  let pixels:Vec<[f32;4]>=match case {
   0=>vec![],
   1=>(0..256).map(|i| [i as f32/255.,(255-i) as f32/255.,0.5,0.25]).collect(),
   2=>(0..2000).map(|i| if i==0 {[0.,0.,0.,1.]} else if i==1999 {[1.,1.,1.,1.]} else {[(40+i%120) as f32/255.,(60+i%90) as f32/255.,(80+i%100) as f32/255.,1.]}).collect(),
   3=>vec![[0.0001,0.9999,0.5,1.],[-0.2,1.,0.,1.],[0.9,0.1,0.7,0.]],
   _=>vec![[0.3,0.4,0.5,1.];100],
  };
  let h=histogram::RgbHistogram::from_rgba(&pixels);
  for kind in ["tone","contrast","color"] {
   let records=auto(h.channels,kind);
   if !first {println!(",");} first=false;
   print!("{{\"caseIndex\":{},\"kind\":\"{}\",\"samples\":{},\"channels\":{:?},\"underflow\":{:?},\"overflow\":{:?},\"shadows\":{:?},\"highlights\":{:?},\"records\":[",case,kind,h.samples,h.channels,h.underflow,h.overflow,h.shadows,h.highlights);
   for (i,r) in records.iter().enumerate() { if i>0 {print!(",");} print!("[{}, {}, {}]", (r.in_black*255.).round() as u32,(r.in_white*255.).round() as u32,r.gamma); }
   print!("]}}");
  }
 }
 println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photato-histogram-oracle-') as temp:
    path=Path(temp)
    (path/'oracle.rs').write_text(source)
    subprocess.run(['rustc','--edition','2024','-Awarnings','-O',str(path/'oracle.rs'),'-o',str(path/'oracle')],check=True)
    vectors=json.loads(subprocess.check_output([str(path/'oracle')]))
(root/'Tests/PhotoCraftCoreTests/Fixtures/histogram-oracle.json').write_text(json.dumps(vectors,separators=(',',':'))+'\n')
(root/'docs/HISTOGRAM_ORACLE.json').write_text(json.dumps({
    'histogram_source_sha256':hashlib.sha256(histogram.read_bytes()).hexdigest(),
    'auto_source_sha256':hashlib.sha256(edit.read_bytes()).hexdigest(),
    'vectors':len(vectors),'generator':'scripts/generate-histogram-oracle.py',
    'scope':'Original histogram, clip_points, median and auto_adjust estimator; Auto Color remains a source approximation.'
},indent=2)+'\n')
print(f'Generated {len(vectors)} histogram/auto reference cases.')
