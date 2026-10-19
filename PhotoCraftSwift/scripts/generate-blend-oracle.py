#!/usr/bin/env python3
"""Execute the original Rust math to produce independent Swift regression vectors."""
from pathlib import Path
import re,subprocess,tempfile,hashlib,json
root=Path(__file__).resolve().parent.parent
source=root.parent/'photocraft-main/crates/color/src/blend.rs'
s=source.read_text().split('#[cfg(test)]')[0]
s=s.replace('use serde::{Deserialize, Serialize};','').replace(', Serialize, Deserialize','')
s += r'''
fn main() {
    let inputs = [[0.0,0.0,0.0], [1.0,1.0,1.0], [0.17,0.51,0.83], [0.92,0.36,0.04], [0.5,0.5,0.5], [0.99995,0.00005,0.7]];
    println!("["); let mut first=true;
    for (m,mode) in BlendMode::LAYER_MODES.iter().enumerate() {
        for b in inputs { for s in inputs {
            let o=blend_rgb(*mode,b,s);
            if !first {println!(",");} first=false;
            print!("{{\"mode\":{},\"backdrop\":{:?},\"source\":{:?},\"expected\":{:?}}}",m,b,s,o);
        }}
    }
    println!("]");
}
'''
with tempfile.TemporaryDirectory(prefix='photocraft-oracle-') as temp:
 p=Path(temp);(p/'oracle.rs').write_text(s)
 subprocess.run(['rustc','--edition','2024','-Awarnings','-O',str(p/'oracle.rs'),'-o',str(p/'oracle')],check=True)
 output=subprocess.check_output([str(p/'oracle')])
 # Normalize and prove it is JSON.
 vectors=json.loads(output)
 (root/'Tests/PhotoCraftCoreTests/Fixtures/blend-oracle.json').write_text(json.dumps(vectors,separators=(',',':'))+'\n')
 (root/'docs/BLEND_ORACLE.json').write_text(json.dumps({'rust_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'vectors':len(vectors),'generator':'scripts/generate-blend-oracle.py'},indent=2)+'\n')
print(f'Generated {len(vectors)} vectors from original Rust source.')
