# Source checkpoint 694

Native Swift 0.3.0, build 694, 2026-11-21.

Advanced layer effects write their final pixels by tile. Ordinary raster writes also reuse an opacity result owned by a single surface.

Both tested wide oblique Pattern Overlay fits and the separate native Fit and soft-proof PNGs match build 693 byte for byte. The RGB8, RGB16 and RGB32 layer-style regression probe matched the previous build for all 138 cases in both direct rendering and imported-project rendering. The mapped-raster tests check that an edited copy and its original can certify opacity independently, and that tile writes reproduce scalar storage in each tested sample encoding and depth.

462 of 465 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The three inherited failures reproduced the same assertions: two outdated Automation count expectations and one strict original PhotoCraft effect fixture. All 27 additional Brush Dynamics and canvas diagnostics tests passed in Debug. The Xcode Debug build and both ad hoc signed macOS 14+ preview slices opened workspaces offscreen.

The installed Photoshop instance timed out on a document query. The saved Photoshop Pattern Overlay reference still passes. Live Photoshop Fit sampling and physical editing cadence remain open.

[Development record](STYLE_PIXEL_WRITES_694.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_694.json)
