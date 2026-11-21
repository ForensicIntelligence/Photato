# Source checkpoint 693

Native Swift 0.3.0, build 693, 2026-11-21.

Pattern Fill layers and Pattern Overlays share prepared source texels across patches of the same composition.

The 5 × 5 and 512 × 512 oblique sources matched build 692 byte for byte in both optimized architectures. Native Fit and soft proof for the separate 70,000 × 520 reference document produced the same PNGs as build 692. Tests covered negative wrap, transparent texels, linked origins, RGB8 reduced grids, source replacement and the cache budget.

460 of 463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 692's assertions. Four additional storage tests passed in Debug. Both signed macOS 14+ preview slices launched offscreen. Xcode built the corrected project directly in arm64 Debug with signing disabled, then the built app opened a workspace offscreen.

Wide nonperiodic fit still evaluates each source pixel. Interactive timing on fully covered maximum-size documents and Photoshop zoom comparison remain open. The local Photoshop document query timed out.

[Development record](PATTERN_SAMPLING_693.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_693.json)
