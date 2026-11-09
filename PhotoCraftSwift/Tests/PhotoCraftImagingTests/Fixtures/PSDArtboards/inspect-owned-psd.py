from pathlib import Path
import hashlib,json,struct,sys
class Reader:
 def __init__(self,data):self.data=data;self.p=0
 def read(self,n):
  assert 0<=n<=len(self.data)-self.p,(n,self.p,len(self.data));v=self.data[self.p:self.p+n];self.p+=n;return v
 def n(self,n,signed=False):return int.from_bytes(self.read(n),'big',signed=signed)
 def text(self,n):return self.read(n).decode('latin1')
 def section(self,n=4):return Reader(self.read(self.n(n)))
 def unicode(self):return self.read(self.n(4)*2).decode('utf-16be')
 def ident(self):return self.text(self.n(4)or 4)
 def descriptor(self):
  name=self.unicode();cls=self.ident();count=self.n(4);items={}
  for _ in range(count):
   key=self.ident();kind=self.text(4);assert key not in items;items[key]={'type':kind,'value':self.value(kind)}
  return {'name':name,'class':cls,'items':items}
 def value(self,t):
  if t in ['Objc','GlbO']:return self.descriptor()
  if t=='VlLs':return [{'type':(kind:=self.text(4)),'value':self.value(kind)}for _ in range(self.n(4))]
  if t=='doub':return struct.unpack('>d',self.read(8))[0]
  if t=='UntF':return {'unit':self.text(4),'value':struct.unpack('>d',self.read(8))[0]}
  if t=='TEXT':return self.unicode()
  if t=='enum':return {'type':self.ident(),'value':self.ident()}
  if t=='long':return self.n(4,True)
  if t=='comp':return self.n(8,True)
  if t=='bool':return bool(self.n(1))
  if t in ['tdta','alis','Pth ']:return {'bytes':self.n(4),'hex':self.read(0).hex()}
  raise ValueError(t)
wide={'LMsk','Lr16','Lr32','Layr','Mt16','Mt32','Mtrn','Alph','FMsk','lnk2','FEid','FXid','PxSD','lnk3','lnkE','pths','extd','extn','FELS','cinf','artd'}
def tagged(r,version,padding):
 result=[]
 while len(r.data)-r.p>=12:
  sig=r.text(4);assert sig in ['8BIM','8B64'];key=r.text(4);size=r.n(8 if version==2 and key in wide else 4);data=r.read(size)
  pad=(-size)%padding
  if pad:r.read(pad)
  row={'key':key,'bytes':size,'sha256':hashlib.sha256(data).hexdigest()}
  if key in ['artb','artd','abdd']:
   x=Reader(data);assert x.n(4)==16;row['descriptor']=x.descriptor();assert x.p==len(data)or all(v==0 for v in data[x.p:])
  if key in ['lsct','lsdk']:row['section']=int.from_bytes(data[:4],'big')
  result.append((row,data))
 return result
def layers(r,version):
 count=r.n(2,True);records=[]
 for _ in range(abs(count)):
  rect=[r.n(4,True)for _ in range(4)];channels=[(r.n(2,True),r.n(8 if version==2 else 4))for _ in range(r.n(2))]
  assert r.text(4)=='8BIM';blend=r.text(4);opacity,clipped,flags,_=[r.n(1)for _ in range(4)];extra=r.section();extra.section();extra.section();n=extra.n(1);name=extra.text(n);extra.read((-(n+1))%4)
  tags=tagged(extra,version,2);records.append({'name':name,'bounds_top_left_bottom_right':rect,'blend':blend,'opacity':opacity,'clipped':clipped,'flags':flags,'channel_sizes':channels,'tags':[a for a,b in tags]})
 for row in records:
  for key,size in row['channel_sizes']:r.read(size)
 return records
def parse(path):
 raw=path.read_bytes();r=Reader(raw);assert r.text(4)=='8BPS';version=r.n(2);r.read(6);channels=r.n(2);height=r.n(4);width=r.n(4);depth=r.n(2);mode=r.n(2);r.section();resources=r.section();mask=r.section(8 if version==2 else 4);info=mask.section(8 if version==2 else 4)
 records=layers(info,version)if info.data else[];mask.section();globaltags=tagged(mask,version,4)
 for row,data in globaltags:
  if row['key']in['Lr16','Lr32']:records=layers(Reader(data),version)
 return {'path':str(path),'sha256':hashlib.sha256(raw).hexdigest(),'version':version,'width':width,'height':height,'depth':depth,'mode':mode,'header_channels':channels,'layers':records,'global_tags':[a for a,b in globaltags]}
if __name__=='__main__':
 p=Path(sys.argv[1]);result=parse(p);out=Path(sys.argv[2]);out.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v for k,v in result.items()if k not in['layers','global_tags']}))
 print(json.dumps({'artboard_tags':[{'layer':l['name'],'bounds':l['bounds_top_left_bottom_right'],'tag':t}for l in result['layers']for t in l['tags']if t['key']in['artb','artd','abdd']],'global_artboard_tags':[t for t in result['global_tags']if t['key']in['artb','artd','abdd']]},indent=2))
