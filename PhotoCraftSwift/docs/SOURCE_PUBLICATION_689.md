# Source checkpoint 689

Native Swift 0.3.0, build 689, 2026-11-21.

The native editor and local API preview supported opaque Pattern Overlay on canvases up to 300,000 × 300,000.

Fit uses the area covered by each screen pixel. At 100% the preview reads the same samples as a full render. Painted pixels, aligned pixel masks and translated raster layers remain visible. Tests also checked isolated RGB channels, soft proofing, native Brush and Undo, and a 2,048 × 2,048 PNG from the local API.

451 of 454 selected tests passed in each of Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three inherited failures reproduced build 688’s assertions. Both signed macOS 14+ preview slices launched offscreen.

The preview requires supported axis-aligned pattern periods and bounded local changes. Other angles and nonperiodic scales still use ordinary rendering. Full-resolution export has its own capacity limits. Photoshop’s document-count query timed out, so live zoom and preview equivalence remain unverified.

[Development record](OPAQUE_PATTERN_PREVIEW_689.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_689.json)
