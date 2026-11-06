# Color Lookup export formats

Use **File > Export > Color Lookup Tables** with the existing supported global RGB adjustment stack above a Background layer. Choose Description, optional Copyright, base filename, grid points and one or more output formats. The native multiple-document exporter receives named files from a single shared stack bake. Exporting does not change document pixels, dirty state, Undo or recorded Actions.

| Format | Output | Range |
| --- | --- | --- |
| CUBE | Existing red-fast floating grid | Extended values retained |
| 3DL | Flame-style blue-fast 12-bit integer table | 0–1 required |
| CSP | CineSpace 3D floating grid and identity input shapers | Extended values retained |
| ICC Profile | ICC4.4 RGB→RGB device link, 16-bit CLUT | 0–1 required |

The ICC file is a device link, not a working profile for assignment to a document. Copyright uses `© Copyright <UTC year> <text>`. Creation time defaults to the request time. Integer formats reject out-of-range samples without silently clipping them. The original empty-copyright CUBE bytes remain unchanged. Some legacy 3DL readers infer scale from the maximum stored value; dark-table compatibility is not universal. Photato's explicit scale comment preserves its own 3DL imports.

The optional Photato API accepts these GET routes using existing authentication, document sharing and transfers permission:

```
/v1/documents/{id}/color-lookup.cube
/v1/documents/{id}/color-lookup.3dl
/v1/documents/{id}/color-lookup.csp
/v1/documents/{id}/color-lookup.icc
/v1/documents/{id}/color-lookup.zip
```

Requests have an empty body. Single-file routes return `application/octet-stream`; ZIP returns `application/zip` with named entries in canonical format order. The ZIP defaults to all four formats; select a subset with `X-Photato-LUT-Formats: cube,csp`. A formats header on a single-file route is rejected.

| Header | Meaning |
| --- | --- |
| `X-Photato-LUT-Grid-Points` | Integer 2–129, default 32 |
| `X-Photato-LUT-Description` | Optional percent-encoded UTF-8, at most 1024 bytes, no controls |
| `X-Photato-LUT-Copyright` | Optional percent-encoded UTF-8, at most 1024 bytes, no controls |
| `X-Photato-LUT-Filename` | Optional percent-encoded safe base filename, 1–120 UTF-8 bytes; no separators, colon or controls |
| `X-Photato-LUT-Created` | Optional ISO8601 date, default request time; pin for reproducible ICC metadata |
| `X-Photato-Revision` | Optional current document revision |

State/capability discovery includes selected/active formats, workspace state and operation ID. `image.export.cancel` cancels only the matching operation. Busy, revoked-share, changed-source, cancelled, disabled-transfer and stale-revision paths return no old export. Native and API requests with the same metadata use the same file bytes. Existing 250 typed commands, native archive86, Actions49, settings4 and menu/shortcut identities are unchanged; these are additional transfer routes. The pinned Adobe v2 contract has no dedicated LUT-export endpoint. No unqualified action descriptor or Adobe route is invented.

The current limits remain 2–129 grid points, 64MiB per file and 256MiB+8192 bytes per ZIP. Full256 grids/streaming, LAB/CMYK profile conversion, general CSP/ICC import, quality presets and exact Photoshop output/defaults remain functional or acceptance work. Existing spatial masks, groups/pixel overlays, clipping, dither/Dissolve, Grain and neighborhood effects remain unsupported in the global export path. Full I05 remains open.

Checkpoint431 passes all34 focused Debug tests, including eight new methods. OpenColorIO2.4.2 reads the owned CUBE/CSP/3DL transform; LittleCMS reads the owned ICC transform at30 vertices/interior samples. Apple ColorSync verifies the ICC profile without errors or warnings. These checks establish the selected file semantics, not Photoshop equivalence. The offscreen native controls and controlled FileWrapper output were checked; live save-panel filename/overwrite/partial-error behavior still needs physical validation. Source01's test-only compiler failure and the independent reader's library-discovery failure are retained before repair. No old fixture or tolerance was weakened. Current optimized/universal/full-suite/physical qualification is unclaimed; the latest optimized/private-source batch is430. [Evidence](COLOR_LOOKUP_FORMATS_431.json).
