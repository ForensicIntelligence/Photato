# Source checkpoint 691

Native Swift 0.3.0, build 691, 2026-11-21.

Fit on Screen and the local PNG overview now handle eligible quarter-turn Pattern Overlays on canvases up to 300,000 × 300,000.

Actual-size crops from four parts of the canvas matched the ordinary compositor in RGB8, RGB16 and RGB32. Six angle, scale and phase combinations also matched an independent whole-period area control. The native test exercised Fit, pan, Brush, Undo and the authenticated overview. An owned 90° probe with a sparse edit produced identical fit and actual-size bytes across all three test configurations.

455 of 458 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 690’s assertions. Both signed macOS 14+ preview slices launched offscreen.

The optimization requires a dyadic scale and Float32-safe phase on both pattern axes. Integral-phase 100% placements that fail this proof and oblique angles retain the existing path. Large nonperiodic Fit on Screen and live Photoshop zoom comparison remain open. The installed Photoshop 2026 document-count query timed out.

[Development record](QUARTER_TURN_PATTERN_691.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_691.json)
