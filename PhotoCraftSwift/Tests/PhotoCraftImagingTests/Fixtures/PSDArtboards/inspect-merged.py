from pathlib import Path
import importlib.util,json,struct,sys,zlib,hashlib
spec=importlib.util.spec_from_file_location('own516',Path(__file__).with_name('inspect-owned-psd.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def merged(path):
 raw=path.read_bytes();r=m.Reader(raw);r.read(4);version=r.n(2);r.read(6);channels=r.n(2);height=r.n(4);width=r.n(4);depth=r.n(2);mode=r.n(2);r.section();r.section();r.section(8 if version==2 else 4);compression=r.n(2);rowbytes=width*(depth//8);nrows=channels*height;rows=[]
 if compression==0:rows=[r.read(rowbytes)for _ in range(nrows)]
 elif compression==1:
  lengths=[r.n(4 if version==2 else 2)for _ in range(nrows)]
  for size in lengths:
   t=m.Reader(r.read(size));out=bytearray()
   while t.p<len(t.data):
    code=t.n(1,True)
    if code>=0:out+=t.read(code+1)
    elif code!=-128:out+=t.read(1)*(1-code)
   assert len(out)==rowbytes;rows.append(bytes(out))
 elif compression in[2,3]:
  data=zlib.decompress(r.read(len(r.data)-r.p));assert len(data)==nrows*rowbytes
  rows=[data[y*rowbytes:(y+1)*rowbytes]for y in range(nrows)]
  if compression==3:
   out=[]
   for row in rows:
    if depth==16:
     words=list(struct.unpack('>'+str(width)+'H',row))
     for x in range(1,width):words[x]=(words[x]+words[x-1])&65535
     out.append(struct.pack('>'+str(width)+'H',*words))
    else:
     row=bytearray(row)
     for x in range(1,rowbytes):row[x]=(row[x]+row[x-1])&255
     if depth==32:row=bytes(row[b*width+x]for x in range(width)for b in range(4))
     out.append(bytes(row))
   rows=out
 else:raise ValueError(compression)
 assert r.p==len(r.data)
 def sample(x,y):
  values=[]
  for c in range(channels):
   row=rows[c*height+y];start=x*(depth//8);p=row[start:start+depth//8];values.append(struct.unpack('>f',p)[0]if depth==32 else int.from_bytes(p,'big'))
  return values
 return {'width':width,'height':height,'depth':depth,'channels':channels,'compression':compression,'samples':{str((x,y)):sample(x,y)for x,y in [(5,5),(280,70),(200,30)]},'planar_sha256':hashlib.sha256(b''.join(rows)).hexdigest()},rows
if __name__=='__main__':
 for name in sys.argv[1:]:
  p=Path(name);summary,rows=merged(p);p.with_suffix(p.suffix+'.merged.json').write_text(json.dumps(summary,indent=2)+'\n');print(p.name,json.dumps(summary))
