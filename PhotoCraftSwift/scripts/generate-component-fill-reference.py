#!/usr/bin/env python3
"""Extract original Photoshop saved layer planes; not a generated expected algorithm."""
from pathlib import Path
import hashlib,json,struct,zlib
import sys
R=Path(sys.argv[1]).resolve()
def decode(path):
 data=path.read_bytes()
 assert data[:6]==b'8BPS\0\1'
 assert data[22:26]==b'\0\x08\0\x03', 'Only this RGB8 fixture is qualified'
 at=26
 for _ in range(2):at+=4+int.from_bytes(data[at:at+4],'big')
 layer_block_size=int.from_bytes(data[at:at+4],'big');at+=4
 block=data[at:at+layer_block_size]
 size=int.from_bytes(block[:4],'big');info=block[4:4+size]
 count=int.from_bytes(info[:2],'big',signed=True);assert abs(count)==1,count
 top,left,bottom,right,n=struct.unpack('>iiiiH',info[2:20]);w,h=right-left,bottom-top
 descriptions=[struct.unpack('>hI',info[20+i*6:26+i*6]) for i in range(n)]
 at=20+n*6;assert info[at:at+8]==b'8BIMnorm';at+=12
 at+=4+int.from_bytes(info[at:at+4],'big');planes={}
 for cid,length in descriptions:
  payload=info[at:at+length];assert len(payload)==length;at+=length
  compression=int.from_bytes(payload[:2],'big')
  if compression==0:raw=payload[2:]
  elif compression in (2,3):
   raw=bytearray(zlib.decompress(payload[2:]))
   if compression==3:
    for y in range(h):
     for x in range(1,w):raw[y*w+x]=(raw[y*w+x]+raw[y*w+x-1])&255
   raw=bytes(raw)
  elif compression==1:
   lengths=struct.unpack('>'+str(h)+'H',payload[2:2+h*2]);cursor=2+h*2;raw=b''
   for length in lengths:
    row=payload[cursor:cursor+length];cursor+=length;q=0;expanded=bytearray()
    while q<len(row):
     control=row[q];q+=1
     if control<128:expanded+=row[q:q+control+1];q+=control+1
     elif control>128:expanded+=row[q:q+1]*(257-control);q+=1
    assert len(expanded)==w,(len(expanded),w)
    raw+=expanded
   assert cursor==len(payload)
  else:raise ValueError(compression)
  assert len(raw)==w*h;planes[cid]=raw
 return (top,left,bottom,right),planes

out=Path(__file__).resolve().parents[1]/'Tests/PhotoCraftCoreTests/Fixtures'
cases=[];data=bytearray()
for base,name,value,opacity in [('component-baseline','component-red-white',1,1),('component-baseline','component-red-white-50',1,.5),('ramp-baseline','ramp-red-white-50',1,.5),('ramp-baseline','ramp-red-white-33',1,.33),('ramp-baseline','ramp-red-black-50',0,.5)]:
 bounds,before=decode(R/(base+'.psd'));after_bounds,after=decode(R/(name+'.psd'))
 assert after_bounds==bounds
 for c in (1,2,-1):assert before[c]==after[c]
 def rgba(planes):return bytes(v for i in range(len(planes[0])) for v in [planes[c][i] for c in [0,1,2,-1]])
 original,result=rgba(before),rgba(after)
 offset=len(data);data+=original+result
 cases.append({'name':name,'width':bounds[3]-bounds[1],'height':bounds[2]-bounds[0],'value':value,'opacity':opacity,'offset':offset,'baselinePSD':base+'.psd','baselineSHA256':hashlib.sha256((R/(base+'.psd')).read_bytes()).hexdigest(),'resultPSD':name+'.psd','resultSHA256':hashlib.sha256((R/(name+'.psd')).read_bytes()).hexdigest(),'inputSHA256':hashlib.sha256(original).hexdigest(),'outputSHA256':hashlib.sha256(result).hexdigest()})
manifest={'provenance':'Original procedural artwork, saved independently in Adobe Photoshop 2026 27.2.0 on2026-10-13. Direct Python PSD8 plane/PackBits/ZIP decoder; no native output used as expectation. Original test data: MIT OR Apache-2.0. See docs/COMPONENT_FILL_REFERENCES.json for scope and UI evidence.','layout':'Each case contains width*height*4 interleaved RGBA8 baseline bytes at offset, followed by the same number of independently saved result bytes.','byteCount':len(data),'sha256':hashlib.sha256(data).hexdigest(),'cases':cases}
for name,content in [('photoshop-component-fill-rgb8.bin',bytes(data)),('photoshop-component-fill-rgb8.json',(json.dumps(manifest,indent=2)+'\n').encode())]:
 path=out/name
 if path.exists():assert path.read_bytes()==content,'Preserve prior fixture before changing it'
 else:path.write_bytes(content)
print(json.dumps({'cases':len(cases),'byteCount':len(data),'sha256':manifest['sha256']}))
