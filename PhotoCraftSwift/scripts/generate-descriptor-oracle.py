#!/usr/bin/env python3
"""Independent struct-packed ActionDescriptor covering Adobe/Rust descriptor types.
Original test data, MIT OR Apache-2.0. No Swift codec is used to create these bytes.
"""
from pathlib import Path
import struct

def u32(x): return struct.pack('>I', x)
def ident(s, code=True):
    b = s.encode('ascii')
    return u32(0 if len(b) == 4 and code else len(b)) + b
def text(units):
    if isinstance(units, str):
        b = units.encode('utf-16-be')
    else:
        b = b''.join(struct.pack('>H', u) for u in units)
    return u32(len(b)//2) + b
def cls(s): return text('') + ident(s)
def desc(s, items, name=''):
    return text(name) + ident(s) + u32(len(items)) + b''.join(ident(k) + v for k,v in items)
def value(t, b): return t.encode('ascii') + b
def number(x): return value('doub', struct.pack('>d', x))
def blob(t, b): return value(t, u32(len(b)) + b)
refs = [b'prop'+cls('Lyr ')+ident('Nm  '), b'Clss'+cls('Dcmn'),
    b'Enmr'+cls('Lyr ')+ident('Ordn')+ident('Trgt'),
    b'rele'+cls('Lyr ')+struct.pack('>i', -1), b'Idnt'+u32(7), b'indx'+u32(2),
    b'name'+cls('Lyr ')+text('Background')]
items = [('Nm  ', value('TEXT', text([0x41,0xd800,0,0]))),
    ('Opct', value('UntF', b'#Prc'+struct.pack('>d',75.5))),
    ('enab', value('bool',b'\1')), ('long', value('long',struct.pack('>i',-5))),
    ('comp', value('comp',struct.pack('>q', -(1<<48)))),
    ('nan ', value('doub',bytes.fromhex('7ff8000000000042'))),
    ('Md  ', value('enum',ident('BlnM',False)+ident('Mltp'))),
    ('rect', value('Objc', desc('classFloatRect',[('Top ', number(1.0))]))),
    ('list', value('VlLs',u32(2)+value('long',u32(1))+value('TEXT',text('x')))),
    ('null', value('obj ',u32(len(refs))+b''.join(refs))),
    ('type', value('type',cls('Clr '))), ('glbc', value('GlbC',cls('RGBC'))),
    ('glbo', value('GlbO',desc('null',[]))),
    ('alis', blob('alis',b'\1\2\3')), ('tdta', blob('tdta',b'\xde\xad')),
    ('pth ', blob('Pth ',b'\11\11')),
    ('ObAr', value('ObAr',u32(16)+desc('rationalPoint',[
      ('Hrzn',value('UnFl',b'#Pxl'+u32(2)+struct.pack('>dd',1.0,-0.0)))])))]
root = Path(__file__).resolve().parents[1]
out = root/'Tests/PhotoCraftImagingTests/Fixtures/descriptor-oracle.bin'
out.write_bytes(u32(16)+desc('null',items,'Oracle\0'))
print(f'{out.name}: {out.stat().st_size} bytes')
