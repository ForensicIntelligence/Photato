from pathlib import Path
import struct,json,hashlib
r=Path(__file__).resolve().parent;w,h=512,384
entries={}
def tag(n,t,v):
 if t==2: b=v.encode()+b'\0';count=len(b)
 elif t in (1,7):b=bytes(v);count=len(v)
 elif t in (3,4):b=struct.pack('<'+('H' if t==3 else 'I')*len(v),*v);count=len(v)
 elif t in (5,10):b=b''.join(struct.pack('<'+('II' if t==5 else 'ii'),*p) for p in v);count=len(v)
 entries[n]=(t,count,b)
for n,v in [(256,w),(257,h),(259,1),(262,32803),(277,1),(278,h),(279,w*h*2),(284,1),(274,1)]:tag(n,4 if n in [256,257,278,279] else 3,[v])
tag(258,3,[16]);tag(273,4,[0]);tag(254,4,[0]);tag(271,2,'Photato');tag(272,2,'Synthetic Bayer Test');tag(305,2,'Photato deterministic test fixture');tag(33421,3,[2,2]);tag(33422,1,[0,1,1,2]);tag(50706,1,[1,4,0,0]);tag(50707,1,[1,1,0,0]);tag(50708,2,'Photato Synthetic Bayer Test');tag(50710,1,[0,1,2]);tag(50711,3,[1]);tag(50713,3,[1,1]);tag(50714,5,[(64,1)]);tag(50717,4,[4095]);tag(50718,5,[(1,1),(1,1)]);tag(50719,4,[0,0]);tag(50720,4,[w,h]);tag(50721,10,[(4124,10000),(3576,10000),(1805,10000),(2126,10000),(7152,10000),(722,10000),(193,10000),(1192,10000),(9505,10000)]);tag(50728,5,[(1,1),(1,1),(1,1)]);tag(50778,3,[21]);tag(50829,4,[0,0,h,w])
start=8+2+12*len(entries)+4;extra=bytearray();table=bytearray()
for n,(t,count,b) in sorted(entries.items()):
 if len(b)<=4: value=b.ljust(4,b'\0')
 else:
  if (start+len(extra))%2:extra+=b'\0'
  value=struct.pack('<I',start+len(extra));extra+=b
 table+=struct.pack('<HHI',n,t,count)+value
pixels=start+len(extra)
for i,(n,_) in enumerate(sorted(entries.items())):
 if n==273:table[i*12+8:i*12+12]=struct.pack('<I',pixels)
data=b'II'+struct.pack('<HIH',42,8,len(entries))+table+struct.pack('<I',0)+extra
for y in range(h):
 for x in range(w):
  c=[[0,1],[1,2]][y%2][x%2];rgb=[0.1+0.65*x/(w-1),0.12+0.55*y/(h-1),0.15+0.45*((x//16+y//16)%2)]
  data+=struct.pack('<H',round(64+rgb[c]*(4095-64)))
(r/'synthetic-bayer.dng').write_bytes(data)
(r/'provenance.json').write_text(json.dumps({'size':[w,h],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'sensor':'Synthetic RGGB Bayer, single 16-bit CFA plane, 12-bit white level, no embedded preview/JPEG','provenance':'Generated entirely from this script; no external image or proprietary camera data. MIT OR Apache-2.0, same as Photato source.','generator':'generate.py'},indent=2)+'\n')
print(r/'synthetic-bayer.dng')
