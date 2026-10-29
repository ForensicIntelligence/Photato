from pathlib import Path
import struct,zlib,json
import sys
r=Path(__file__).resolve().parent;out=Path(sys.argv[1]);out.mkdir();raw=(r/'expected.rgba32le').read_bytes();icc=(r/'expected.icc').read_bytes();rows=[]
for little in [False,True]:
 for planar in [False,True]:
  for predictor in [False,True]:
   endian='<' if little else '>';u=lambda n:struct.pack(endian+'I',n);h=lambda n:struct.pack(endian+'H',n);strips=[]
   for plane in range(4 if planar else 1):
    stripe=bytearray()
    for y in range(2):
     vals=[raw[(y*3+x)*16+c*4:(y*3+x)*16+c*4+4] for x in range(3) for c in ([plane] if planar else range(4))]
     if predictor:
      big=b''.join(v[::-1] for v in vals);shuffled=bytearray(b''.join(big[c::4] for c in range(4)));step=1 if planar else 4
      for i in range(len(shuffled)-1,step-1,-1):shuffled[i]=(shuffled[i]-shuffled[i-step])&255
      stripe.extend(shuffled)
     else:stripe.extend(b''.join(v if little else v[::-1] for v in vals))
    strips.append(zlib.compress(stripe))
   result=bytearray((b'II' if little else b'MM')+h(42)+u(0));offsets=[]
   for data in strips:offsets.append(len(result));result.extend(data)
   if len(result)%2:result.append(0)
   ifd=len(result);result[4:8]=u(ifd)
   fields=[(256,4,1,u(3)),(257,4,1,u(2)),(258,3,4,h(32)*4),(259,3,1,h(8)),(262,3,1,h(2)),(273,4,len(strips),b''.join(u(n) for n in offsets)),(274,3,1,h(1)),(277,3,1,h(4)),(278,4,1,u(2)),(279,4,len(strips),b''.join(u(len(v)) for v in strips)),(284,3,1,h(2 if planar else 1)),(317,3,1,h(3 if predictor else 1)),(338,3,1,h(2)),(339,3,4,h(3)*4),(34675,7,len(icc),icc)]
   table=bytearray(h(len(fields)));extra=bytearray();start=ifd+2+12*len(fields)+4
   for tag,ty,count,data in fields:
    table.extend(h(tag)+h(ty)+u(count))
    if len(data)<=4:table.extend(data+bytes(4-len(data)))
    else:
     if len(extra)%2:extra.append(0)
     table.extend(u(start+len(extra)));extra.extend(data)
   result.extend(table+u(0)+extra);name=f'little{int(little)}-planar{int(planar)}-predict{int(predictor)}.tiff';(out/name).write_bytes(result);rows.append({'name':name,'little':little,'planar':planar,'predictor':predictor})
(out/'expected.rgba32le').write_bytes(raw);(out/'cases.json').write_text(json.dumps(rows,indent=2)+'\n')
