"""Generate owned classic TIFF 6.0 strip controls for component paging."""
from hashlib import sha256
import json
from pathlib import Path
import struct
import zlib

root=Path(__file__).resolve().parent
versions=(
    ('gray16-36mp-zip', 6000,6000,16,1,(14911,),False,1,0),
    ('gray8-9mp-associated-planar',3001,2800,8,0,(215,128),True,6,1),
    ('gray8-small-associated-planar',33,21,8,0,(215,128),True,6,1),
    ('cmyk16-9mp-zip-planar',3001,2800,16,5,(2000,55000,32768,12345),True,1,0),
)
cases={}
for name,width,height,bits,photo,fill,planar,orientation,alpha_tag in versions:
    channels=len(fill); rows=16; order='>' if bits==16 else '<'
    word='H' if bits==16 else 'B'
    points={
        (0,0): tuple(i//3 for i in fill),
        (width-1,0): tuple(i//4 for i in fill),
        (23,height//2): tuple(i//5 for i in fill),
        (width-1,height-1): tuple(i//7 for i in fill),
    }
    if alpha_tag:
        points[(0,0)]=(224,64)
        points[(width-1,0)]=(255,0)
        points[(23,height//2)]=(219,110)
        points[(width-1,height-1)]=(244,22)
    if order=='>':
        file=bytearray(b'MM\x00\x2a\x00\x00\x00\x00')
    else:
        file=bytearray(b'II\x2a\x00\x00\x00\x00\x00')
    offsets=[];counts=[]
    for plane in range(channels if planar else 1):
        default=struct.pack(order+word,fill[plane]) if planar else struct.pack(order+word*channels,*fill)
        line_bytes=default*width
        for top in range(0,height,rows):
            raw=bytearray(line_bytes*min(rows,height-top))
            for (x,y),samples in points.items():
                if top<=y<top+rows:
                    start=((y-top)*width+x)*len(default)
                    raw[start:start+len(default)]=(struct.pack(order+word,samples[plane]) if planar
                                                   else struct.pack(order+word*channels,*samples))
            packed=zlib.compress(raw)
            offsets.append(len(file));counts.append(len(packed));file.extend(packed)
    tags={
        256:(4,[width]),257:(4,[height]),258:(3,[bits]*channels),259:(3,[8]),
        262:(3,[photo]),273:(4,offsets),274:(3,[orientation]),277:(3,[channels]),
        278:(4,[rows]),279:(4,counts),284:(3,[2 if planar else 1]),
        296:(3,[2]),339:(3,[1]*channels),
    }
    if alpha_tag: tags[338]=(3,[alpha_tag])
    if photo==5: tags[332]=(3,[1])
    if len(file)%2:file.append(0)
    directory=len(file)
    struct.pack_into(order+'I',file,4,directory)
    file.extend(struct.pack(order+'H',len(tags)))
    tail=bytearray()
    first_extended=directory+2+12*len(tags)+4
    for tag,(kind,values) in sorted(tags.items()):
        value_bytes=struct.pack(order+('H' if kind==3 else 'I')*len(values),*values)
        entry=struct.pack(order+'HHI',tag,kind,len(values))
        if len(value_bytes)<=4:
            file.extend(entry+value_bytes.ljust(4,b'\x00'))
        else:
            file.extend(entry+struct.pack(order+'I',first_extended+len(tail)))
            tail.extend(value_bytes)
    file.extend(bytes(4));file.extend(tail)
    path=root/f'{name}.tif'
    path.write_bytes(file)
    cases[name]={'width':width,'height':height,'bits':bits,'photo':photo,'orientation':orientation,
                 'planar':planar,'rawDefaults':fill,'rawChanges':[[x,y,*values] for (x,y),values in points.items()],
                 'alphaTag':alpha_tag,'unpacked':width*height*channels*bits//8,'bytes':len(file),'sha256':sha256(file).hexdigest()}
(root/'source-manifest.json').write_text(json.dumps(cases,indent=2)+'\n')
for name,description in cases.items():
    print(f'{name}: {description["width"]*description["height"]:,} px; {description["bytes"]:,} encoded bytes')
