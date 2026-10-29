#!/usr/bin/env python3
"""Original small PSB conformance fixtures; no Photato encoder or Photoshop oracle.

Framing follows Adobe's public PSD/PSB specification and observed extra wide
keys documented by PhotoCraft crates/psd/src/tagged.rs (MIT OR Apache-2.0).
Fixtures exercise container parsing, not independently measured rendering parity.
"""
from pathlib import Path
import struct,zlib,json,hashlib
root=Path(__file__).resolve().parent.parent
out=root/'Tests/PhotoCraftImagingTests/Fixtures/psb';out.mkdir(exist_ok=True)
pack=lambda fmt,*v:struct.pack('>'+fmt,*v)
sec=lambda b,n=4:pack('I' if n==4 else 'Q',len(b))+b
wide={'LMsk','Lr16','Lr32','Layr','Mt16','Mt32','Mtrn','Alph','FMsk','lnk2','FEid','FXid','PxSD','lnk3','lnkE','pths','extd','extn','FELS','cinf','artd'}
def tag(key,data,global_=False,signature=b'8BIM'):
 return signature+key.encode()+sec(data,8 if key in wide else 4)+b'\0'*((-len(data))%(4 if global_ else 2))
def samples(depth,values):
 return b''.join(pack('B',round(v*255)) if depth==8 else pack('H',round(v*65535)) if depth==16 else pack('f',v) for v in values)
def channel(data,w,h,depth,compression,planes=1):
 rb=w*(depth//8); rows=[data[i:i+rb] for i in range(0,len(data),rb)]
 assert len(rows)==h*planes
 if compression==0:body=data
 elif compression==1:
  encoded=[bytes([len(row)-1])+row for row in rows]
  body=b''.join(pack('I',len(row)) for row in encoded)+b''.join(encoded)
 else:
  encoded=bytearray()
  for row in rows:
   if compression==3:
    if depth==16:
     vals=list(struct.unpack('>'+'H'*w,row));row=b''.join(pack('H',v if i==0 else (v-vals[i-1])%65536) for i,v in enumerate(vals))
    else:
     if depth==32:row=b''.join(row[k::4] for k in range(4))
     row=bytes(v if i==0 else (v-row[i-1])%256 for i,v in enumerate(row))
   encoded.extend(row)
  body=zlib.compress(encoded)
 return pack('H',compression)+body
w,h=4,3;n=w*h
values=[[0,.25,.5,1]*3,[1,.5,.25,0]*3,[.5]*n,[1]*n]
manifest={'origin':'Original Python-authored procedural PSB fixtures; no production encoder and no live Photoshop save.','license':'MIT OR Apache-2.0','specification':'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/','purpose':'Independent binary framing, sample-plane and compression conformance; not Photoshop rendering equivalence.','cases':[]}
for depth in [8,16,32]:
 for compression in range(4):
  planes=[samples(depth,v) for v in values];mask=samples(depth,[0,.25,.5,1]);payload=[];records=[];channelOffsets=[]
  for index,kind in enumerate([3,0,1]):
   rawname=['End group','Pixels','Group'][index].encode();name=bytes([len(rawname)])+rawname;name+=b'\0'*((-len(name))%4)
   unicode=['End group','PSB pixels Ω','Group'][index].encode('utf-16be')
   extras=sec(pack('4i4B',1,1,3,3,255,0,0,0) if kind==0 else b'')+sec(b'')+name
   extras+=tag('luni',pack('I',len(unicode)//2)+unicode,signature=b'8B64')
   if kind:extras+=tag('lsct',pack('I',kind)+b'8BIMpass')
   streams=[(i if i<3 else -1,channel(v,w,h,depth,compression)) for i,v in enumerate(planes)] if kind==0 else [(i,pack('H',0)) for i in [0,1,2,-1]]
   if kind==0:streams.append((-2,channel(mask,2,2,depth,compression)))
   bounds=[0,0,h,w] if kind==0 else [0,0,0,0]
   rec=pack('4iH',*bounds,len(streams))+b''.join(pack('hQ',i,len(v)) for i,v in streams)+b'8BIM'+(b'norm' if kind==0 else b'pass')+bytes([255,0,0,0])+sec(extras)
   records.append(rec);payload.extend(v for _,v in streams)
  info=pack('h',-3)+b''.join(records)+b''.join(payload);info+=b'\0'*(len(info)%2)
  layer=sec(info,8) if depth==8 else sec(b'',8)
  layer+=sec(b'')
  if depth!=8:layer+=tag('Lr16' if depth==16 else 'Lr32',info,True,signature=b'8B64')
  layer+=tag('cinf',b'original!',True,signature=b'8B64')
  merged=b''.join(planes)
  data=b'8BPS'+pack('H',2)+b'\0'*6+pack('HIIHH',4,h,w,depth,3)+sec(b'')+sec(b'')+sec(layer,8)+channel(merged,w,h,depth,compression,4)
  name=f'rgb{depth}-compression{compression}.psb';(out/name).write_bytes(data)
  manifest['cases'].append({'file':name,'depth':depth,'compression':compression,'width':w,'height':h,'sha256':hashlib.sha256(data).hexdigest(),'planes':[p.hex() for p in planes],'mask':mask.hex(),'layerCount':2})
(out/'provenance.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'cases':len(manifest['cases']),'bytes':sum((out/c['file']).stat().st_size for c in manifest['cases'])}))
