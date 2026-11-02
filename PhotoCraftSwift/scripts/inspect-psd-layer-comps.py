#!/usr/bin/env python3
"""Read PSD/PSB comp metadata independently of Photato's Swift serializer.

Adobe's public file specification defines envelopes and alternative Lr16/Lr32
sections. Public field provenance and fixture licensing are recorded in
PSD_LAYER_COMP_REFERENCES.json. This reader does not decode/render pixels.
"""
from pathlib import Path
import struct,json,sys
class R:
 def __init__(self,b):self.b=b;self.i=0
 def take(self,n):
  if n<0 or self.i+n>len(self.b):raise ValueError('Truncated')
  b=self.b[self.i:self.i+n];self.i+=n;return b
 def n(self,w=4,signed=False):return int.from_bytes(self.take(w),'big',signed=signed)
 def text(self):return self.take(2*self.n()).decode('utf-16-be').rstrip('\x00')
 def id(self):n=self.n();return self.take(n or 4).decode('latin1')
 def desc(self):
  d={'_name':self.text(),'_class':self.id()}
  for _ in range(self.n()):key=self.id();d[key]=self.value()
  return d
 def value(self):
  kind=self.take(4)
  if kind in [b'Objc',b'GlbO']:return self.desc()
  if kind==b'VlLs':return [self.value() for _ in range(self.n())]
  if kind==b'long':return self.n(signed=True)
  if kind==b'comp':return self.n(8,signed=True)
  if kind==b'doub':return struct.unpack('>d',self.take(8))[0]
  if kind==b'bool':return bool(self.n(1))
  if kind==b'TEXT':return self.text()
  if kind==b'enum':return {'_type':self.id(),'_enum':self.id()}
  if kind==b'UntF':return {'_unit':self.take(4).decode(),'_value':struct.unpack('>d',self.take(8))[0]}
  if kind in [b'tdta',b'alis']:return {'bytes':self.take(self.n()).hex()}
  raise ValueError('Unknown '+repr(kind))
def descriptor(b):
 r=R(b);assert r.n()==16;d=r.desc();assert all(x==0 for x in r.b[r.i:]);return d
def inspect(path):
 r=R(Path(path).read_bytes());assert r.take(4)==b'8BPS';version=r.n(2);r.take(6);channels=r.n(2);h=r.n();w=r.n();depth=r.n(2);mode=r.n(2);r.take(r.n());resources=R(r.take(r.n()));comps=[]
 while resources.i<len(resources.b):
  assert resources.take(4)==b'8BIM';id=resources.n(2);n=resources.n(1);resources.take(n);resources.take((n+1)%2);size=resources.n();b=resources.take(size);resources.take(size%2)
  if id==1065:comps.append(descriptor(b))
 layers=R(r.take(r.n(8 if version==2 else 4)));info=R(layers.take(layers.n(8 if version==2 else 4)));records=[]
 if not info.b:
  layers.take(layers.n())  # Global layer mask, before alternative bit-depth records.
  while layers.i+12<=len(layers.b):
   assert layers.take(4) in [b'8BIM',b'8B64'];key=layers.take(4);n=layers.n(8 if version==2 and key in [b'Lr16',b'Lr32',b'Layr'] else 4);data=layers.take(n)
   if key in [b'Lr16',b'Lr32',b'Layr']:info=R(data);break
   layers.take((4-n%4)%4)

 if info.b:
  count=abs(info.n(2,signed=True))
  for _ in range(count):
   rect=[info.n(signed=True) for i in range(4)];n=info.n(2);info.take(n*(10 if version==2 else 6));info.take(12);extra=R(info.take(info.n()));extra.take(extra.n());extra.take(extra.n());n=extra.n(1);name=extra.take(n).decode('latin1');extra.take((4-(n+1)%4)%4);tags={};settings=[]
   while extra.i+12<=len(extra.b):
    sig=extra.take(4);key=extra.take(4).decode('latin1');b=extra.take(extra.n(8 if version==2 and key in ['LMsk','Lr16','Lr32','Layr','Mt16','Mt32','Mtrn','Alph','FMsk','lnk2','FEid','FXid','PxSD'] else 4));extra.take(len(b)%2)
    if key=='lyid':tags[key]=int.from_bytes(b,'big',signed=True)
    if key=='shmd':
     m=R(b)
     for _ in range(m.n()):
      signature=m.take(4).decode();item=m.take(4).decode();m.take(4);data=m.take(m.n());settings.append({'key':item,'signature':signature,'data':descriptor(data) if item=='cmls' else {'length':len(data)}})
   records.append({'name':name,'rect':rect,'tags':tags,'metadata':settings})
 return {'version':version,'width':w,'height':h,'depth':depth,'mode':mode,'resources':comps,'layers':records}
if __name__=='__main__':print(json.dumps(inspect(sys.argv[1]),indent=2))
