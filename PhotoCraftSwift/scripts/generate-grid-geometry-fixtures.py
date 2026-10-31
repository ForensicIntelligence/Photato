#!/usr/bin/env python3
"""Independent exact integer pixel maps of owned Float32 RGBA patterns."""
from pathlib import Path
import hashlib,json,struct
root=Path(__file__).resolve().parents[1];out=root/'Tests/PhotoCraftCoreTests/Fixtures/paged-geometry';out.mkdir(parents=True,exist_ok=True)
w,h=129,65;palette=[0x80000000,0x3e800000,0x40800000,0xbe800000,0x00000001,0x3f800000];alpha=[0,0x3f000000,0x3f800000,0x80000000]
raw=bytearray()
for y in range(h):
 for x in range(w):raw+=struct.pack('<IIII',palette[(x+y)%len(palette)],palette[(x*3+y)%len(palette)],palette[(x+y*5)%len(palette)],alpha[(x+y)%4])
(out/'linear-input.rgba').write_bytes(raw);cases=[]
for name in ['clockwise','counterclockwise','half','horizontal','vertical']:
 nw,nh=(h,w)if name in ['clockwise','counterclockwise']else(w,h);mapped=bytearray(len(raw))
 for y in range(h):
  for x in range(w):
   nx,ny=(h-1-y,x)if name=='clockwise'else(y,w-1-x)if name=='counterclockwise'else(w-1-x,h-1-y)if name=='half'else(w-1-x,y)if name=='horizontal'else(x,h-1-y)
   mapped[(ny*nw+nx)*16:(ny*nw+nx+1)*16]=raw[(y*w+x)*16:(y*w+x+1)*16]
 filename='linear-'+name+'.rgba';(out/filename).write_bytes(mapped);cases.append({'turn':name,'file':filename,'width':nw,'height':nh,'sha256':hashlib.sha256(mapped).hexdigest()})
(out/'linear-grid.json').write_text(json.dumps({'license':'MIT OR Apache-2.0, same as fork','provenance':'Independent Python integer coordinate permutations of owned raw Float32 bits, including HDR/negative/subnormal/signed-zero/hidden RGB and alpha. No native resampler or Photoshop implementation used.','generator':'scripts/generate-grid-geometry-fixtures.py','generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'width':w,'height':h,'cases':cases},indent=2)+'\n')
print('Independent raw32 fixtures:',len(cases))
