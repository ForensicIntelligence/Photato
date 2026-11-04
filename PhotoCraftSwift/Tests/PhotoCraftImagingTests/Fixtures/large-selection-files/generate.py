"""Owned numeric PSD/PSB inputs; no Photato encoder or vendor artwork/code."""
from pathlib import Path
import struct,zlib,json,hashlib
folder=Path(__file__).parent
be=lambda value,size:int(value).to_bytes(size,'big')
def resource(identifier,data):
 return b'8BIM'+be(identifier,2)+b'\0\0'+be(len(data),4)+data+(b'\0'if len(data)%2 else b'')
def packbits(row):
 out=bytearray();at=0
 while at<len(row):
  end=at+1
  while end<len(row)and row[end]==row[at]and end-at<128:end+=1
  if end-at>=3:out.extend((257-(end-at),row[at]));at=end;continue
  start=at;at=end
  while at<len(row)and at-start<128:
   end=at+1
   while end<len(row)and row[end]==row[at]and end-at<128:end+=1
   if end-at>=3:break
   at=min(end,start+128)
  out.append(at-start-1);out.extend(row[start:at])
 return bytes(out)
def build(name,width,height,depth,version,compression,kind=1,ramp=False):
 maximum=(1<<depth)-1
 points=[{'x':x,'y':0,'word':x if depth==8 else(x*251+257)%65536}for x in range(min(width,256))]
 points += [{'x':17,'y':min(1,height-1),'word':maximum//3},{'x':width-1,'y':height-1,'word':maximum}]
 if ramp:points=[{'x':x,'y':0,'word':x}for x in range(width)]
 rows={}
 for p in points:rows.setdefault(p['y'],{})[p['x']]=p['word']
 display=be(1,4)+be(0,2)+be(65535,2)+b'\0'*6+be(50,2)+bytes([kind])
 title='Owned large selection'
 resources=resource(1006,bytes([len(title)])+title.encode('ascii'))+resource(1045,be(len(title)+1,4)+title.encode('utf-16-be')+b'\0\0')+resource(1077,display)+resource(1053,be(2,4))
 header=b'8BPS'+be(version,2)+b'\0'*6+be(1,2)+be(height,4)+be(width,4)+be(depth,2)+be(7,2)
 raw_hash=hashlib.sha256();encoded=[];row_sizes=[];zipper=zlib.compressobj();packed=bytearray()
 for y in range(height):
  row=bytearray(width*(depth//8))
  for x,word in rows.get(y,{}).items():row[x*(depth//8):(x+1)*(depth//8)]=be(word,depth//8)
  raw_hash.update(row)
  if compression==3:
   if depth==8:row=bytearray((row[i]-row[i-1])%256 if i else row[i]for i in range(len(row)))
   else:
    words=[int.from_bytes(row[i:i+2],'big')for i in range(0,len(row),2)]
    row=b''.join(be((words[i]-words[i-1])%65536 if i else words[i],2)for i in range(len(words)))
  if compression==0:packed.extend(row)
  elif compression==1:
   coded=packbits(row);row_sizes.append(len(coded));packed.extend(coded)
  else:packed.extend(zipper.compress(row))
 if compression>=2:packed.extend(zipper.flush())
 pixels=be(compression,2)+(b''.join(be(n,2 if version==1 else 4)for n in row_sizes)if compression==1 else b'')+packed
 data=header+be(0,4)+be(len(resources),4)+resources+be(0,4 if version==1 else 8)+pixels
 output=folder/(name+'.zlib');output.write_bytes(zlib.compress(data,9))
 item={'file':output.name,'name':name,'width':width,'height':height,'depth':depth,'version':version,'compression':compression,'kind':kind,'decodedFileBytes':len(data),'fileSHA256':hashlib.sha256(data).hexdigest(),'planeSHA256':raw_hash.hexdigest(),'allOtherWords':0,'points':points if not ramp else[],'ramp':ramp,'channelName':title}
 return item,data
cases=[];owned=None
for bits in [8,16]:
 for version in [1,2]:
  for compression in range(4):
   name=f'large-{bits}-v{version}-c{compression}.'+('psd'if version==1 else'psb')
   item,data=build(name,4096,2049,bits,version,compression);cases.append(item)
   if bits==8 and version==2 and compression==2:owned=data
for bits in [8,16]:
 item,_=build(f'max-side-{bits}.psb',300000,29,bits,2,2);cases.append(item)
item,_=build('above-dense-16.psb',9000,4500,16,2,2);cases.append(item)
item,_=build('all-u16-words.psb',65536,1,16,2,2,ramp=True);cases.append(item)
item,_=build('large-printing-plate.psb',4096,2049,8,2,2,kind=2);cases.append(item)
manifest={'provenance':'Owned deterministic numeric masks, independently constructed in Python using public PSD/PSB framing. No native Photato codec, vendor artwork or proprietary code. Outer zlib only reduces source fixture size; decoded input hashes are pinned.','specification':'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/','cases':cases}
(folder/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
run=Path(Path('/private/tmp/photato-374-run').read_text().strip());(run/'Photato374LargeSelection02.psb').write_bytes(owned);(run/'independent-input-manifest01.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'fixtures':len(cases),'compressed_total':sum((folder/x['file']).stat().st_size for x in cases),'owned_Photoshop_input':str(run/'Photato374LargeSelection02.psb')}))
