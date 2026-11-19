# Source checkpoint 574

Native Swift 0.3.0, build 574, 18 November 2026. Stamp Layers composites the selected artwork and inserts the resulting raster just above the highest selected layer. Stamp Visible composites the visible document and inserts the raster just above the active layer, including when that layer is inside a group. Both use a single Undo and preserve the original artwork, selection and document resources.

The native Layer menu exposes the Option alternates. Option-Command-E stamps selected layers, and Shift-Option-Command-E stamps visible layers. Holding Option on Merge Visible in the Layers panel also requests a stamp. Recorded Actions retain the stamp operation and resolve the artwork in the playback document. The Photato API adds two operations to `layer.merge`. The existing compatible ActionJSON parser accepts the installed merge descriptors' duplicate flag through the same compositor. [Adobe layer stamping](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

The exact sample regression compares both commands with 16 Photoshop 27.2.0 reference stamps per architecture. The fixtures cover RGB8, RGB16 and RGB32, including locked inputs, hidden selected rows, clipping, duplicate layer names and selections across groups. Ordinary integer-depth stamps use the existing merge working grid. Uncovered RGB32 pixels use transparent white and preserve hidden color at covered raster coordinates. The first completed Debug candidate differed at 36 RGB words in 12 transparent pixels. The separate 16-bit checks found 925 one-step alpha differences per command in that earlier candidate.

The corrected source passed all 57 focused Debug tests and 745 selected tests per configuration in Debug, optimized Apple Silicon and Intel under Rosetta. Both architecture slices of the extracted local validation archive passed strict signature and offscreen workspace checks. The archive declares a macOS 14 minimum.

The UI tests checked AppKit menu registration and bindings. Interactive shortcut dispatch, maximum-size sparse stamp performance, broader compositing modes and formats, physical Intel and macOS 14 execution remain open.

[Developer record](DEVLOG.md#dev-step-574) · [Validation data and source fingerprints](LAYER_STAMP_REFERENCES_574.json)
