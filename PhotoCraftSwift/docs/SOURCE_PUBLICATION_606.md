# Source checkpoint 606

Native Swift 0.3.0, build 606, 19 November 2026. Large RLE Photoshop layers retain their implicit color and store the edited tiles during import.

Photato reopened the 8.45 GB, 300,000 × 300,000 RGB8 PSB in 1.65 s on Apple Silicon and 2.61 s under Rosetta. Every raster bit matched and six tiles used 384 KiB of mapped sample storage. The independent decoder checked 900,000 layer and 900,000 merged row lengths per architecture, plus 72 sampled channel values.

The 300,000 × 131 RGB8 file went from 14,064 mapped tiles to four. RGB16 and RGB32 PSBs and RGB8 and RGB16 PSDs reopened with every raster bit preserved in the tested deep and legacy fixtures.

All 938 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-size control is an RGB8 Background with six isolated edits. Dense maximum-size imports, maximum-size raw and ZIP layers, arbitrary leading borders, live Photoshop cross-open, and physical Intel and macOS 14 runtime remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-606) · [Validation data](SPARSE_PSB_IMPORT_606.json).
