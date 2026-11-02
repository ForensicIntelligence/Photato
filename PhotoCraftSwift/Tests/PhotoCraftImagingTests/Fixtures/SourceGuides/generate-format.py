from pathlib import Path
import struct
folder=Path(__file__).resolve().parent
pack=lambda fmt,*v:struct.pack('>'+fmt,*v)
resource=(folder/'guides-u8.resource1032').read_bytes()
for version in [1,2]:
 block=b'8BIM'+pack('H',1032)+b'\0\0'+pack('I',len(resource))+resource
 data=pack('4sH6sHIIHH',b'8BPS',version,b'\0'*6,3,3,5,8,3)+pack('I',0)+pack('I',len(block))+block+pack('Q'if version==2 else'I',0)+pack('H',0)+bytes([64]*15+[128]*15+[192]*15)
 (folder/('independent-guides.'+('psb'if version==2 else'psd'))).write_bytes(data)
