#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);model=root/'PeopleParts.mlmodelc'
manifest=json.loads((root/'PeopleParts.provenance.json').read_text())
assert manifest['format']==1 and manifest['model']=='people-parts-v1'
assert manifest['sourceSHA256']=='c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0'
assert manifest['license']=='Apache-2.0' and manifest['validation']['passed'] is True
paths=[p for p in model.rglob('*') if p.is_file()]
assert paths and not any(p.is_symlink() for p in model.rglob('*'))
actual={str(p.relative_to(model)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
assert actual==manifest['files'],'Person model resource differs from its validated manifest.'
