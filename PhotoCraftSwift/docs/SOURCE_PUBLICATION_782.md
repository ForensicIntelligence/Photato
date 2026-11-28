# Source checkpoint 782

Native TIFF Save and Save a Copy offer separate Alpha Channels and Spot Colors checkboxes. Both start checked when present, and either channel type can survive a flattened TIFF or BigTIFF.

Photato saved an RGB16 spot-only copy and kept its layered source open. Photato and Photoshop 27.2 reopened the copy with only the named spot plate. Photoshop also reopened the flattened Float32 BigTIFF with both named channels and its separate opacity sample. LibTIFF matched all 25,929 measured alpha and spot samples exactly.

Lossless Photato TIFF output accepts independent `tiffAlphaChannels` and `tiffSpotColors` booleans. When omitted, their defaults still follow `tiffLayers`. Both existing API input paths decode named channels in flat or layered TIFF. Adobe v2 output retains its published options.

Xcode built the native app. All 6 focused imaging and 3 focused app and HTTP tests passed. Both optimized architectures passed all 299 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

In the live RGB16 comparison, 5,474 of 8,643 process-color words differed by one code. Quick Mask and dense multi-gigabyte layered interchange also remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,225,706 bytes with SHA-256 `3026e09ddce6a67cc7f835f6c5678a8da474b338058cfb09404d798053c57e95`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_782.json) · [Development record](DEVLOG.md#dev-step-782).
