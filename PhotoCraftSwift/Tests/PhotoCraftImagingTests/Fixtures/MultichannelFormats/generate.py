"""Owned mode7 fixtures; independent compression by MIT psd-tools1.26.0.
Run with its installed directory as argv[1]. No Photoshop implementation inspected.
"""
import sys, struct, json, hashlib
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import psd_tools
from psd_tools.compression import compress
from psd_tools.constants import Compression
assert psd_tools.__version__ == '1.26.0'
root = Path(__file__).parent
names = ['Orange 🟠', 'Hue ink', 'Process ink', 'Lab ink', 'Gray ink', 'Protected mask', 'Selected mask']
records = [(0, [65535, 16384, 0, 0], 37, 2), (1, [32768, 60000, 50000, 0], 0, 2),
           (2, [1234, 32768, 50000, 65535], 50, 2), (7, [5500, 2500, 63536, 0], 100, 2),
           (8, [4321, 0, 0, 0], 10, 2), (0, [65535, 0, 0, 0], 50, 1), (0, [0, 0, 65535, 0], 25, 0)]
def resource(key, data):
    return b'8BIM' + struct.pack('>H2xI', key, len(data)) + data + b'\0' * (len(data) % 2)
display = struct.pack('>I', 1) + b''.join(struct.pack('>6HB', s, *c, opacity, kind) for s,c,opacity,kind in records)
unicode = b''.join(struct.pack('>I', len(n.encode('utf-16-be'))//2) + n.encode('utf-16-be') for n in names)
resources = resource(1045, unicode) + resource(1077, display)
resources += resource(1005, struct.pack('>IHHIHH', 300*65536, 1, 1, 300*65536, 1, 1))
fixtures=[]
for version in [1, 2]:
    for depth in [8,16]:
        maximum = (1 << depth)-1
        stored = [[(i * 977 + c * 71) & maximum for i in range(12)] for c in range(len(names))]
        stored[0][:5] = [0,1,maximum//2,maximum-1,maximum]
        raw = b''.join(struct.pack('>B' if depth == 8 else '>H', v) for channel in stored for v in channel)
        for compression in Compression:
            header = b'8BPS'+struct.pack('>H6xHIIHH',version,len(names),3,4,depth,7)
            data = header+struct.pack('>I',0)+struct.pack('>I',len(resources))+resources+b'\0'*(4 if version==1 else 8)
            data += struct.pack('>H', int(compression)) + compress(raw, compression, 4, 3*len(names), depth, version)
            filename=f'multichannel-{depth}-{compression.name.lower()}.{"psd" if version==1 else "psb"}'
            (root/filename).write_bytes(data)
            fixtures.append({'file':filename,'depth':depth,'fileSamples':stored,'sha256':hashlib.sha256(data).hexdigest()})
manifest={'source':'Owned synthetic images; Adobe public file specification and independent MIT psd-tools1.26.0 compressor',
 'references':['https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/','https://github.com/psd-tools/psd-tools/tree/v1.26.0'],
 'photoshopGenerated':False,'names':names,'displayHex':display.hex(),'fixtures':fixtures}
(root/'provenance.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'fixtures':len(fixtures),'decoder':psd_tools.__version__}))
