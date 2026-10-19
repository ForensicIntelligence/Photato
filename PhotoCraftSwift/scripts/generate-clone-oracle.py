#!/usr/bin/env python3
"""Execute the unchanged Rust round-tip equation used by retouch strokes."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
root=Path(__file__).resolve().parent.parent
source=root.parent/'photocraft-main/crates/paint/src/lib.rs'
text=source.read_text();start=text.index('pub fn dab_coverage(');end=text.index('\n}',start)+2
fn=text[start:end]
main='''
fn main(){ use std::io::Write; let mut out=Vec::new();
for radius in [0.25f32,0.5,1.,2.,8.,30.] {for hardness in [0f32,0.25,0.8,1.] {for i in 0..=256 {
let distance=(radius+1.)*i as f32/256.;
for v in [distance,radius,hardness,dab_coverage(distance,radius,hardness)] {out.extend(v.to_le_bytes());}
}}}std::io::stdout().write_all(&out).unwrap();}
'''
with tempfile.TemporaryDirectory(prefix='photato-clone-oracle-') as d:
 p=Path(d);(p/'oracle.rs').write_text(fn+main)
 subprocess.run(['rustc','-O',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
 data=subprocess.check_output([str(p/'oracle')])
(root/'Tests/PhotoCraftCoreTests/Fixtures/clone-tip-oracle.bin').write_bytes(data)
(root/'docs/CLONE_STAMP_ORACLE.json').write_text(json.dumps({'source':str(source.relative_to(root.parent)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'cases':len(data)//16,'fixture_sha256':hashlib.sha256(data).hexdigest(),'scope':'Round-tip coverage only. Full stroke, transformed sampling, blending, UI and Photoshop byte identity are separate gates.'},indent=2)+'\n')
print(len(data)//16,'reference tip samples')
