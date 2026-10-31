#!/usr/bin/env python3
"""Owned PSD/PSB vectors from Adobe's public file-format specification; Python stdlib only."""
from pathlib import Path
import hashlib,json,struct,zlib
root=Path(__file__).resolve().parents[1]
out=root/'Tests/PhotoCraftImagingTests/Fixtures/psb-paged';out.mkdir(parents=True,exist_ok=True)
u16=lambda n:struct.pack('>H',n)
u32=lambda n:struct.pack('>I',n)
u64=lambda n:struct.pack('>Q',n)
def sample(x,y,c,depth):
    if c==3:return [0.,.25,.5,1.][(x+y)%4]
    if depth==32:return [-0.,-.25,.5,2.,4.][(x*3+y+c)%5]
    return ((x*17+y*29+c*43)%256)/255

def plane(w,h,c,depth,mask=False):
    data=bytearray()
    for y in range(h):
        for x in range(w):
            v=((x+y)%5)/4 if mask else sample(x,y,c,depth)
            data+=bytes([round(v*255)]) if depth==8 else struct.pack('>H',round(v*65535)) if depth==16 else struct.pack('>f',v)
    return bytes(data)
def predict(raw,w,depth):
    result=bytearray();row=w*(depth//8)
    for start in range(0,len(raw),row):
        b=bytearray(raw[start:start+row])
        if depth==16:
            for x in range(w-1,0,-1):
                a=int.from_bytes(b[x*2:x*2+2],'big');v=int.from_bytes(b[x*2-2:x*2],'big');b[x*2:x*2+2]=((a-v)&65535).to_bytes(2,'big')
        else:
            if depth==32:b=bytearray(b''.join(b[k::4] for k in range(4)))
            for x in range(len(b)-1,0,-1):b[x]=(b[x]-b[x-1])&255
        result+=b
    return bytes(result)
def channel(raw,w,h,depth,compression,channels=1):
    if compression==0:return u16(0)+raw
    if compression in (2,3):return u16(compression)+zlib.compress(predict(raw,w,depth) if compression==3 else raw)
    row=w*(depth//8);packed=[]
    for y in range(h*channels):
        b=raw[y*row:(y+1)*row];p=b''.join(bytes([len(b[x:x+128])-1])+b[x:x+128] for x in range(0,row,128));packed.append(p)
    return u16(1)+b''.join(u32(len(p))for p in packed)+b''.join(packed)
def make(w,h,depth,compression,layered,flat_alpha=False):
    raw=[plane(w,h,c,depth) for c in range(4)]
    header=b'8BPS'+u16(2)+bytes(6)+u16(4 if layered or flat_alpha else 3)+u32(h)+u32(w)+u16(depth)+u16(3)+u32(0)+u32(0)
    if layered:
        mask=plane(w,h,0,depth,True)
        channels=[channel(p,w,h,depth,compression)for p in raw+[mask]]
        maskdata=struct.pack('>iiiiBBH',0,0,h,w,255,0,0)
        name=b'Python owned';extra=u32(len(maskdata))+maskdata+u32(0)+bytes([len(name)])+name;extra+=bytes((-len(extra))%4)
        record=struct.pack('>iiiiH',0,0,h,w,5)+b''.join(struct.pack('>h',c)+u64(len(p))for c,p in zip([0,1,2,-1,-2],channels))+b'8BIMnorm'+bytes([255,0,0,0])+u32(len(extra))+extra
        info=struct.pack('>h',-1)+record+b''.join(channels);info+=bytes((-len(info))%4)
        body=u64(len(info))+info+u32(0) if depth==8 else u64(0)+u32(0)+b'8BIM'+(b'Lr16'if depth==16 else b'Lr32')+u64(len(info))+info
    elif flat_alpha:
        key=b'Mtrn' if depth==8 else b'Mt16' if depth==16 else b'Mt32'
        body=u64(0)+u32(0)+b'8BIM'+key+u64(0)
    else:body=b''
    # Flat vectors deliberately retain HDR/negative-zero data with opaque alpha;
    # no transparency resource means no white-matte conversion is requested.
    merged=channel(b''.join(raw if layered or flat_alpha else raw[:3]),w,h,depth,compression,4 if layered or flat_alpha else 3)
    return header+u64(len(body))+body+merged
cases=[]
for depth in [8,16,32]:
    for compression in range(4):
        for layered in [False,True]:
            w,h=129,65;name=f'{"layers-mask"if layered else "flat"}-{depth}-{compression}.psb';data=make(w,h,depth,compression,layered);(out/name).write_bytes(data)
            cases.append({'file':name,'width':w,'height':h,'depth':depth,'compression':compression,'layered':layered,'sha256':hashlib.sha256(data).hexdigest()})
for depth in [8,16,32]:
    for compression in range(4):
        w,h=129,65;name=f'flat-alpha-{depth}-{compression}.psb';data=make(w,h,depth,compression,False,True);(out/name).write_bytes(data)
        cases.append({'file':name,'width':w,'height':h,'depth':depth,'compression':compression,'layered':False,'sha256':hashlib.sha256(data).hexdigest()})
record={'license':'MIT OR Apache-2.0, same as this fork','generator':'scripts/generate-paged-psb-fixtures.py','generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'provenance':'Owned procedural samples, framing/prediction/RLE/ZIP from Adobe public PSD/PSB specification; Python struct/zlib, no Photoshop implementation or native encoder used. These are format vectors, not Photoshop output comparisons.','specification':'https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/','cases':cases}
(out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({'cases':len(cases),'bytes':sum((out/c['file']).stat().st_size for c in cases)},indent=2))
