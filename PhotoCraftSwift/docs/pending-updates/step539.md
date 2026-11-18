<a id="dev-step-539"></a>

## 2026-11-17 — Process Brush coverage and output by tile

A macOS sampling profile of the build 538 full-size Brush showed repeated coverage tile lookups and exclusivity checks, followed by per-pixel writes and a full copy during the merge. BrushPainter.swift now collects each dab's weights in a reusable tile buffer and applies them to the destination tile together. Retained strokes still copy shared coverage before changing it and only mark a tile dirty when coverage increases. The complete renderer adopts new coverage tiles when merging and runs the post-deposition pass when dual tips or whole-stroke texture need it.

Surface.swift adds a tile writer for complete Brush output. It reads the original tile once, applies the existing quantization and writes the finished tile once. Float32 linear writes share the existing conversion that retains unchanged channel bits. The writer ignores padding and preserves untouched owned or mapped tiles. Completed strokes still publish as one transaction.

BrushDynamicsTests.swift compares the tile writer against individual setters on partial tiles in owned and mapped RGB8, RGB16, encoded Float32 and linear Float32 surfaces. The current benchmark uses 5,000 px color-dynamics and soft dabs from both optimized engine builds. It hashes the complete 5,408 × 5,408 output and measures software rendering independently of the packaged workspace launch.

All 198 focused tests and seven retained compositing tests pass in Debug, optimized Apple Silicon and Intel under Rosetta. Both extracted universal executables passed the offscreen workspace check. The complete 5,000 px color-dynamics dab rendered in 0.52 seconds on Apple Silicon, down from 1.99. Both large-dab scenarios reproduced the same bytes in all four optimized build and architecture combinations. All 32 stored RGBA cases have the same bytes as build 538 within each architecture. Six linear Float32 cases differ between architectures in both builds. [Qualification](SOURCE_PUBLICATION_539.md).
