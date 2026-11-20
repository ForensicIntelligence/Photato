# Source checkpoint 659

Native Swift 0.3.0, build 659, 20 November 2026.

Properties and Free Transform now use the original geometry of linked artwork when a reopened PSD or PSB has only a cached preview. The Photato API reports the same source transform, rotation and bounds.

All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

In the native Properties accessibility tree, the same owned linked PSD now reads 30.00° where build 658 read 0.00°. The position and dimensions also match the bounds calculated from the PSD's stored placement. The native position-field test separately checked moving a transformed preview by its artwork's bounds, preserving fractional placement and producing one Undo.

The installed Photoshop session timed out. Exact Adobe Properties values, rounding, handle orientation, physical Intel, a macOS 14 runtime and full assistive-technology behavior remain unverified.

[Development record](LINKED_SMART_OBJECT_GEOMETRY_659.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_659.json)
