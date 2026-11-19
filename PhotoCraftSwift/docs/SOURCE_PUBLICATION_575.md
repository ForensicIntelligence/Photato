# Source checkpoint 575

Native Swift 0.3.0, build 575, 18 November 2026. Stamp Layers and Stamp Visible now schedule render patches using translated raster bounds and allocated tiles. When a tile has no local changes, the renderer uses the correct implicit pixel from the original stack. In the separated-layer and simple grouped tests, a 300,000 × 300,000 document needed two patches. The previous full traversal had 689,136 potential patches.

The tests verify source layers, placement, exposed transparent RGB and stored samples at 8, 16 and 32 bits per channel. They include an implicit translucent full-canvas backdrop. An independent rectangle model matched the scheduled tiles and the first uncovered tile in all 3,500 fixed-seed cases. The existing ActionJSON job routes also match their Photoshop stamp samples for tagged and untagged RGB8 and RGB16 inputs.

All 61 focused Debug tests and all 749 selected tests per configuration passed in Debug, optimized Apple Silicon and Intel under Rosetta. The extracted universal archive passed both offscreen checks and declares a macOS 14 minimum. Interactive shortcut dispatch, complex sparse sources, physical Intel and macOS 14 runtime checks remain open.

[Developer record](DEVLOG.md#dev-step-575) · [Validation data and source fingerprints](SPARSE_LAYER_STAMP_REFERENCES_575.json)
