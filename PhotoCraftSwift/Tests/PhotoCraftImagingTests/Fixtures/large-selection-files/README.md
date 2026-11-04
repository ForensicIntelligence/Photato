# Large saved-selection files

These deterministic numeric masks are our test data. `generate.py` independently builds PSD/PSB framing and raw/RLE/ZIP/predicted image data using Python's standard library and Adobe's public file-format specification. It does not call Photato's encoder or copy Adobe implementation code or artwork.

The outer `.zlib` wrapper keeps raw test files small in source control. Tests inflate that transport and verify the complete decoded file SHA before testing the PSD decoder. All unspecified mask samples are zero. The manifest pins dimensions, integer words and the entire raw big-endian plane digest. Cases include the old 8,388,608-pixel boundary, 40.5MP, 300,000-pixel sides and every UInt16 word.

`photoshop-reference.json` records an independent parse of two owned 4096×2049 RGB-free mask files opened/saved in Photoshop2026 27.2.0. Each full 8-bit plane matches all 8,392,704 numeric samples. Saved Photoshop documents and full metadata remain local evidence; this fixture records numeric and whitelisted resource facts. Photoshop accepted the canonical RLE PSD and saved PSD/PSB. Two ZIP PSB input probes were rejected; all-compression codec checks are public-format/numeric evidence, not a claim that current Photoshop accepts every variant. Neither maximum dense capacity nor all-platform/output parity is established.
