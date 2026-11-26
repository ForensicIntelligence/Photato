# Source checkpoint 743

Vanishing Point Brush and Stamp can continue across linked faces. The desktop uses Allow Multi-surface Operations. The Photato API accepts `wrap: true` on individual strokes, and destination clipping remains independent. Aligned Stamp carries the donor displacement across the hinge. The desktop and API commit each edit through the same Undo transaction.

On two owned perspective guides, Brush and Stamp reached both faces with wrapping enabled. The same Brush path reached only the starting face with wrapping disabled. The healed Brush path reached both faces. All eight clipped replays respected the exact visible face bounds in the measured RGB outputs and each committed one Undo. One-pixel Core coverage verifies that a seam dab does not deposit twice. An additional native probe passed all four coplanar hinge orientations at three depths each.

All 48 focused Xcode tests passed. Optimized Apple Silicon and Intel under Rosetta each passed 862 of 864 selected tests, including all four new tests. The two existing color-profile and layer-effect failures repeated the same diagnostics as build 742. All eight owned replay PNGs were byte-identical across Debug and both optimized builds.

Photoshop showed both relevant menu options checked on the tilted guide. Its Filter menu stopped responding after the options menu was dismissed, so this checkpoint has no captured Photoshop stroke raster. Exact dab placement, coverage and color against Adobe remain open. Shift-constrained painting, Marquee-constrained Brush and wider platform coverage are also open.

The tracked Universal ZIP contains the optimized, ad-hoc signed `Photato Preview.app`. Its `arm64` and `x86_64` slices both target macOS 14.0. The extracted signature verified, and both slices produced offscreen workspace snapshots on the development Mac. The ZIP is 77,676,644 bytes. Its SHA-256 is `33331c06f138609245e10444bb84d3f3d36d509dc5f05ecf5b383440d30afe46`. App Store approval is a separate manual step.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable qualification](SOURCE_PUBLICATION_743.json) · [Development record](DEVLOG.md#dev-step-743) · [Photoshop reference observations](VANISHING_POINT_REFERENCES.json).
