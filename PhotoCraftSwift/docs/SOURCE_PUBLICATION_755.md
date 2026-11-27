# Source checkpoint 755

Layered 8-bit RGB TIFFs can retain named saved selections alongside editable layer masks and the merged image’s transparency. Open and Save preserve the channel name, sampled values, and display polarity.

Photato’s native Save and authenticated file routes use the same codec. Ordinary Save preserves editable layers by default. Download or Save a Copy can keep layers with `tiffLayers: true`. The Adobe v2 TIFF schema continues to expose its published flattened output.

All 17 focused Debug checks passed. All 63 focused TIFF cases passed on each optimized architecture, including the three new regressions. The broader inventory discovered 5,952 cases per architecture. Results were 5,844 passed, 89 failed, 15 skipped and 4 incomplete on Apple Silicon, 5,835 passed, 98 failed, 15 skipped and 4 incomplete on Intel under Rosetta. Every failing case and incomplete verdict also occurred when replayed against the hash-verified public 754 source. The Intel video-cancellation case had variable diagnostics on repeat. The evidence names failed, skipped and incomplete cases. The earlier checkpoint used a narrower inventory.

An independent TIFF reader matched all 24,576 saved-selection bytes and all 98,304 process and opacity bytes across eight opaque and transparent output variants. The process and opacity comparison used the equivalent flat Photato export. The two Photoshop-authored files retained their editable layers, layer masks, and 6,144 exact saved-selection bytes. Photoshop reopened the Photato export and displayed its saved selection by name. Its TIFF re-export kept all 3,072 selection bytes. Across those three Adobe TIFFs, all 82,944 raw editable layer and mask samples matched the source PSD. The matched transparent exports differed by one byte value in 266 red, 54 blue, and 50 opacity samples. The Green and saved selection planes matched exactly. The test fixtures preserve the Photoshop image samples and layer blocks with unrelated file metadata removed. Complete file bytes, other channel depths, spot inks, and Quick Mask still require qualification.

The extracted Universal ZIP launched offscreen on both architectures. It targets macOS 14+ and is signed ad hoc. The 77,887,835-byte archive has SHA-256 `ba6613ab7b6f6ce4b2ea8ec965ec47e93b186f170889c4b8ddad96ab5343be6b`.

[Adobe’s TIFF options](https://helpx.adobe.com/photoshop/desktop/save-and-export/save-files/save-in-tiff-format.html) · [TIFF 6.0 specification](https://printtechnologies.org/standards/files/tiff-v6.pdf)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_755.json) · [Development record](DEVLOG.md#dev-step-755).
