#!/usr/bin/env python3
"""Deterministic independent PSD compression vectors (Python stdlib, no app codec)."""
import base64, json, struct, zlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
vectors=[]
for depth in (8,16,32):
    width,height,channels=7,3,3
    values=[]
    for c in range(channels):
        for y in range(height):
            for x in range(width):
                i=c*width*height+y*width+x
                values.append(((i*1013)%65536)/65535 if depth!=32 else [-.25,0,.0001,.125,.5,1,2.75][(i+y)%7])
    fmt={8:'B',16:'H',32:'f'}[depth]
    maximum={8:255,16:65535,32:1}[depth]
    raw=b''.join(struct.pack('>'+fmt,round(v*maximum) if depth!=32 else v) for v in values)
    row_bytes=width*depth//8
    predicted=bytearray()
    rle_rows=[]
    for start in range(0,len(raw),row_bytes):
        row=raw[start:start+row_bytes]
        # Literal-only PackBits is independent of the Swift decoder's packet logic.
        packed=b''.join(bytes([len(row[i:i+128])-1])+row[i:i+128] for i in range(0,len(row),128))
        rle_rows.append(packed)
        if depth==16:
            samples=struct.unpack('>'+str(width)+'H',row)
            predicted.extend(struct.pack('>'+str(width)+'H', samples[0], *((samples[i]-samples[i-1])%65536 for i in range(1,width))))
        else:
            shuffled = b''.join(row[k::4] for k in range(4)) if depth==32 else row
            predicted.extend(bytes([shuffled[0]])+bytes((a-b)%256 for a,b in zip(shuffled[1:],shuffled)))
    payloads=[raw,b''.join(struct.pack('>H',len(r)) for r in rle_rows)+b''.join(rle_rows),zlib.compress(raw),zlib.compress(predicted)]
    for method,payload in enumerate(payloads):
        vectors.append(dict(depth=depth,width=width,height=height,channels=channels,compression=method,raw=base64.b64encode(raw).decode(),encoded=base64.b64encode(struct.pack('>H',method)+payload).decode()))
path=root/'Tests/PhotoCraftImagingTests/Fixtures/psd-channel-oracles.json'
path.write_text(json.dumps(dict(provenance='Generated with Python struct/zlib by scripts/generate-psd-channel-oracles.py; original test data, MIT OR Apache-2.0.',vectors=vectors),indent=2)+'\n')
print(path)
