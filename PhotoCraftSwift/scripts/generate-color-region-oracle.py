#!/usr/bin/env python3
"""Execute the original Rust wand_region; only substitute storage/thread adapters."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
path = root.parent / 'photocraft-main/crates/algo/src/selection.rs'
source = path.read_text()
kernel = source[source.index('pub fn wand_region('):source.index('/// Combines a [`Region`]')]
# Select the upstream sequential implementations of the two row-parallel loops.
start = kernel.index('        #[cfg(not(target_arch = "wasm32"))]')
end = kernel.index('        let spans:', kernel.index('        #[cfg(target_arch = "wasm32")]', start))
kernel = kernel[:start] + kernel[end:]
start = kernel.index('    #[cfg(not(target_arch = "wasm32"))]')
end = kernel.index('    mask.chunks_mut', kernel.index('    #[cfg(target_arch = "wasm32")]', start))
kernel = kernel[:start] + kernel[end:]
adapters = r'''
use std::io::Write;
#[derive(Clone,Copy)] pub struct Rect { x0:i32, y0:i32, x1:i32, y1:i32 }
impl Rect {
fn new(x0:i32,y0:i32,x1:i32,y1:i32)->Self { Self{x0,y0,x1,y1} }
fn contains(&self,x:i32,y:i32)->bool { x>=self.x0&&y>=self.y0&&x<self.x1&&y<self.y1 }
fn width(&self)->i32 {self.x1-self.x0} fn height(&self)->i32 {self.y1-self.y0}
}
pub struct Region { bbox:Rect, mask:Vec<u8> }
fn u(out:&mut Vec<u8>,v:usize) {out.extend((v as u32).to_le_bytes());}
'''
main = r'''
fn main() {
let mut out=Vec::new();
for (kind,(w,h)) in [(17usize,13usize),(31,19),(23,23),(1,19),(19,1)].into_iter().enumerate() {
let area=Rect::new(-3,7,w as i32-3,h as i32+7);
let img:Vec<[u8;4]>=(0..w*h).map(|i| {
let x=i%w;let y=i/w;
match kind {
0=>if x==w/2 {[0,0,0,255]}else{[220,30,60,255]},
1=>if (x/4+y/3)%2==0 {[100,120,140,200]}else{[132,119,150,200]},
2=>[(x*11)as u8,(y*13)as u8,((x+y)*7)as u8,if x%3==0 {0}else{255}],
_=>[(i*31)as u8,(i*17)as u8,(i*11)as u8,255]
}}).collect();
for tol in [0usize,31,32,255] {for contiguous in [false,true] {for aa in [false,true] {
for (sx,sy) in [(0usize,0usize),(w/2,h/2),(w-1,h-1)] {
for v in [w,h,sx,sy,tol,contiguous as usize,aa as usize] {u(&mut out,v);}
for p in &img {out.extend(p);}
let region=wand_region(&img,area,(sx as i32+area.x0,sy as i32+area.y0),tol as f32,contiguous,aa).unwrap();
let mut full=vec![0u8;w*h];
for y in region.bbox.y0..region.bbox.y1 {for x in region.bbox.x0..region.bbox.x1 {
full[((y-area.y0)*w as i32+x-area.x0)as usize]=region.mask[((y-region.bbox.y0)*region.bbox.width()+x-region.bbox.x0)as usize];
}}
out.extend(full);
}}}}
}
std::io::stdout().write_all(&out).unwrap();
}
'''
with tempfile.TemporaryDirectory(prefix='photato-color-region-') as directory:
    folder = Path(directory)
    (folder / 'main.rs').write_text(adapters + kernel + main)
    subprocess.run(['rustc', '-O', '--edition=2024', str(folder / 'main.rs'), '-o', str(folder / 'oracle')], check=True)
    data = subprocess.check_output([str(folder / 'oracle')])
(root / 'Tests/PhotoCraftCoreTests/Fixtures/color-region-oracle.bin').write_bytes(data)
report = {
    'source': str(path.relative_to(root.parent)),
    'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    'fixture_sha256': hashlib.sha256(data).hexdigest(),
    'fixture_bytes': len(data), 'cases': 240,
    'mask_bytes': sum(w * h for w, h in [(17, 13), (31, 19), (23, 23), (1, 19), (19, 1)]) * 48,
    'method': 'Executed original wand_region with Rect/Region storage adapters; upstream sequential row loops selected. No color-match, flood, edge or rounding changes.',
    'scope': 'Source algorithm reference only. Not a Photoshop output reference.'
}
(root / 'docs/COLOR_REGION_ORACLE.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
