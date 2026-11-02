from pathlib import Path
import struct,json,hashlib,sys,shutil,io
from psd_tools.compression import compress
from psd_tools.constants import Compression
from psd_tools.psd import PSD
r=Path('/Users/johnczlonka/Desktop/notadobe/notphotoshop/-');run=Path(Path('/private/tmp/photato-329-run').read_text());out=r/'Tests/PhotoCraftImagingTests/Fixtures/PSDAuxiliary';out.mkdir(exist_ok=False)
pack=lambda fmt,*v:struct.pack('>'+fmt,*v)
def block(identifier,data):return b'8BIM'+pack('H',identifier)+b'\0\0'+pack('I',len(data))+data+b'\0'*(len(data)%2)
def plane(values,depth):
 if depth==8:return bytes(values)
 if depth==16:return b''.join(pack('H',v)for v in values)
 return b''.join(pack('I',v)for v in values)
def file(mode,depth,version,compression,extras,resources):
 process={1:1,3:3,4:4,9:3}[mode];width,height=5,3
 samples=[]
 for c in range(process):
  if depth==8:values=[(32+c*57+x*3)%256 for x in range(15)]
  elif depth==16:values=[(8192+c*12000+x*997)%65536 for x in range(15)]
  else:values=[struct.unpack('>I',pack('f',0.125+c*0.125+x/64))[0]for x in range(15)]
  samples.append(plane(values,depth))
 data=b''.join(samples+extras);channels=process+len(extras)
 header=pack('4sH6sHIIHH',b'8BPS',version,b'\0'*6,channels,height,width,depth,mode)
 result=header+pack('I',0)+pack('I',len(resources))+resources+pack('Q'if version==2 else'I',0)+pack('H',compression)+compress(data,Compression(compression),width,height*channels,depth,version)
 p=PSD.read(io.BytesIO(result));assert p.image_data.get_data(p.header)==samples+extras
 return result
names=['Mask α','Ink Ω','Quick Mask'];unicode=b''.join(pack('I',len(n.encode('utf-16-be'))//2+1)+n.encode('utf-16-be')+b'\0\0'for n in names)
display=pack('I',1)+pack('H4HHB',0,65535,0,0,0,50,1)+pack('H4HHB',0,16384,32768,65535,0,25,2)+pack('H4HHB',0,65535,0,0,0,75,0)
rows=[]
for mode,depths in [(3,[8,16,32]),(1,[8,16,32]),(4,[8,16]),(9,[8,16])]:
 for depth in depths:
  raw=[]
  for c in range(3):
   if depth==8:values=[(c*53+x*19)%256 for x in range(15)]
   elif depth==16:values=[(c*13001+x*4001)%65536 for x in range(15)]
   else:
    known=[0x80000000,0,0x3dcccccd,0x3eaaaaab,0x3f000001,0x3f7fffff,0x3f800000,0xbf000000,0x3fc00000]
    values=[known[(x+c)%len(known)]for x in range(15)]
   raw.append(plane(values,depth))
  refs=[]
  for c,data in enumerate(raw):
   name=f'm{mode}-d{depth}-channel{c}.bin';(out/name).write_bytes(data);refs.append(name)
  process={1:1,3:3,4:4,9:3}[mode];resource=block(1045,unicode)+block(1077,display)+block(1053,pack('3I',41,73,99))+block(1022,pack('HB',process+2,1))
  for version in [1,2]:
   for compression in range(4):
    name=f'm{mode}-d{depth}-v{version}-c{compression}.'+('psb'if version==2 else'psd');data=file(mode,depth,version,compression,raw,resource);(out/name).write_bytes(data)
    rows.append({'file':name,'mode':mode,'depth':depth,'version':version,'compression':compression,'width':5,'height':3,'names':names,'planes':refs,'identifiers':[41,73,99],'quickInitiallyEmpty':True})
# An independently maintained public corpus case (opaque CMYK plus3 spots).
name='independent-cmyk-spot.psd';shutil.copy2(run/'cmyk-spot.psd',out/name)
with (out/name).open('rb')as f:p=PSD.read(f)
data=p.image_data.get_data(p.header);process=4;refs=[]
for i,raw in enumerate(data[process:]):
 ref=f'independent-cmyk-spot-channel{i}.bin';(out/ref).write_bytes(raw);refs.append(ref)
rows.append({'file':name,'mode':4,'depth':8,'version':1,'compression':int(p.image_data.compression),'width':p.header.width,'height':p.header.height,'names':list(p.image_resources[1006].data),'planes':refs,'independentCorpus':True})
(out/'cases.json').write_text(json.dumps(rows,indent=2)+'\n');shutil.copy2('/private/tmp/photato-generate-psdaux329.py',out/'generate.py');shutil.copy2(r/'Tests/PhotoCraftImagingTests/Fixtures/LICENSE-psd-tools',out/'LICENSE-psd-tools')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();record={'generator':'generate.py','generator_sha256':sha(out/'generate.py'),'artwork':'Owned procedural5×3 cases; one MIT-licensed psd-tools1.26.0 corpus case, attributed in LICENSE-psd-tools.','reference_engine':'psd-tools1.26.0 compression and independent low-level decode; hand-built public-format headers/resources. No native Swift code or Photoshop output is used to generate expected words.','owned_cases':80,'independent_corpus_cases':1,'input_planes_per_case':3,'photoshop2026_verified':False,'public_corpus':json.loads((run/'independent-inputs01.json').read_text())['files'][0],'files':{p.name:sha(p)for p in sorted(out.iterdir())if p.is_file()}}
(out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'cases':len(rows),'owned':80,'corpus':1,'fixture_files':len(record['files'])+1,'bytes':sum(p.stat().st_size for p in out.iterdir())},indent=2))
