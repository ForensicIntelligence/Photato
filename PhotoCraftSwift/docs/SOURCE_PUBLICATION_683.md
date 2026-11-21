# Source checkpoint 683

Native Swift 0.3.0, build 683, 2026-11-20.

Supported RGB8 and RGB16 shape layers retain their editable gradient fills and strokes in PSD and PSB. An unchanged import keeps its source descriptors and pixel cache.

All 300 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

An independent reader compared eight layer/file pairs. Their live descriptors and complete RGBA layer caches matched byte for byte. The original Photoshop gradient rectangle supplied two pairs. Four came from two gradient outlines isolated from a separate Photoshop file, and two came from a rectangle carrying a Photoshop-authored gradient stroke descriptor transplanted from a live line. Photato reversed the gradient on each shape, saved and reopened the edited files, and undid the edit. The six edited files matched byte for byte across all three builds.

The original file containing patterned shape paint and the original file containing unsupported pattern layer effects still reject. The derivative fixtures isolate shape metadata and leave pattern paint, line controls, seeded dither and whole-file compatibility open. An equivalent-angle native repaint differed in alpha by up to three 8-bit levels throughout a 32 × 32 interior sample. Its RGB values matched. A separate diagnostic shifted the gradient center by half a pixel and matched all 1,024 alpha samples in that window. Reopening the new files in a live Photoshop 2026 session remains unverified.

[Development record](EDITABLE_SHAPE_PAINT_683.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_683.json)
