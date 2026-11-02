#!/usr/bin/env python3
"""Independent PSD/PSB resource and shadow-descriptor reader; no pixel rendering."""
from pathlib import Path
import importlib.util,json,sys
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('psd_comp_transport',Path(__file__).with_name('inspect-psd-layer-comps.py'));transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
R=transport.R

def inspect(path):
 r=R(Path(path).read_bytes());assert r.take(4)==b'8BPS';version=r.n(2);r.take(6);r.n(2);h=r.n();w=r.n();depth=r.n(2);mode=r.n(2);r.take(r.n());resources=R(r.take(r.n()));light={};counts={}
 while resources.i<len(resources.b):
  assert resources.take(4)==b'8BIM';id=resources.n(2);n=resources.n(1);resources.take(n);resources.take((n+1)%2);n=resources.n();data=resources.take(n);resources.take(n%2)
  if id in [1037,1049]:
   assert len(data)==4;counts[id]=counts.get(id,0)+1;light['angle' if id==1037 else 'altitude']=int.from_bytes(data,'big',signed=id==1037)
 layers=R(r.take(r.n(8 if version==2 else 4)));info=R(layers.take(layers.n(8 if version==2 else 4))) if layers.b else R(b'')
 if layers.b and not info.b:
  layers.take(layers.n())
  while layers.i+12<=len(layers.b):
   assert layers.take(4) in [b'8BIM',b'8B64'];key=layers.take(4);n=layers.n(8 if version==2 and key in [b'Lr16',b'Lr32',b'Layr'] else 4);data=layers.take(n)
   if key in [b'Lr16',b'Lr32',b'Layr']:info=R(data);break
   layers.take((4-n%4)%4)
 styles=[]
 if info.b:
  for _ in range(abs(info.n(2,signed=True))):
   info.take(16);count=info.n(2);info.take(count*(10 if version==2 else 6));info.take(12);extra=R(info.take(info.n()));extra.take(extra.n());extra.take(extra.n());n=extra.n(1);name=extra.take(n).decode('latin1');extra.take((4-(n+1)%4)%4)
   while extra.i+12<=len(extra.b):
    assert extra.take(4) in [b'8BIM',b'8B64'];key=extra.take(4);n=extra.n();data=extra.take(n);extra.take(n%2)
    if key in [b'lfx2',b'lmfx']:
     assert data[:4]==b'\0\0\0\0';desc=transport.descriptor(data[4:]);styles.append({'layer':name,'descriptor':desc})
 return {'version':version,'width':w,'height':h,'depth':depth,'mode':mode,'light':light,'resource_counts':counts,'styles':styles}
if __name__=='__main__':print(json.dumps(inspect(sys.argv[1]),indent=2))
