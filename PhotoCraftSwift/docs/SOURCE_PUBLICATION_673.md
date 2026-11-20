# Source checkpoint 673

Native Swift 0.3.0, build 673, 20 November 2026.

Direct Selection now previews and selects anchors inside a dragged marquee. Shift adds to the selection. The same operation is available through the Photato API.

All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

New tests exercise reverse drags, Shift, Escape, focus loss, existing pixel selection, Command-T and authenticated path selection. All 12 earlier whole-layer vector mask outputs matched byte for byte in each configuration.

A 4,096-anchor Core benchmark measured 0.231 ms p95 for additive selection on Apple Silicon and 0.363 ms under Intel Rosetta. Canvas painting and display refresh were outside this measurement.

The marquee operates on the active path. Simultaneous path selection across layers and exact Photoshop hit testing, modifiers and cursor comparisons remain open.

[Development record](DIRECT_SELECTION_MARQUEE_673.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_673.json)
