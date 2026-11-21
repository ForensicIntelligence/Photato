# Source checkpoint 685

Native Swift 0.3.0, build 685, 2026-11-20.

Plain Normal RGB8 shape layers round effective and accumulated alpha at each layer. Supported legacy pattern shapes retain editable phase and the original reference point in PSD and PSB.

All 310 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The original Photoshop stroke fixture’s regenerated preview dropped from 331 to 90 differing RGB bytes. The three translucent ellipses match every merged alpha byte and have 69 differing RGB bytes. The largest residual is one level in both files. Both original legacy pattern files keep their shape descriptors, layer caches, embedded tiles and merged planes byte for byte. After repeat-preserving edits, all 9,309 opaque interior pixels matched in each of four unscaled pattern cases and in the 50% case.

Scaled pattern repaint at 200%, 56%, and 25% still differs. Independent sampling matched the 200% fixture with a half-pixel coordinate shift and the 25% fixture with two rounded 2 × 2 reductions. Masked, styled, transformed and other depth or blend cases have separate acceptance requirements. Reopening in a live Photoshop 2026 session remains unverified.

[Development record](SHAPE_EDGE_COMPOSITING_685.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_685.json)
