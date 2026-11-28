# Source checkpoint 793

Repeated RGB adjustments can reuse the native sensor raster from the current Camera Raw workspace. Open and OK can reuse those samples before applying the same development command and document color conversion.

Three full Nikon D70s arm64 Debug trials measured median command preparation of 2.64 seconds with the same sensor raster and 6.38 seconds with a fresh decode. The processed command output, Float32 composite, and RGBA8 display bytes matched. The signed app made two exposure changes and opened the result as a 3,008 × 2,000 RGB16 document with the original NEF embedded.

The editor uses the same native RAW development transaction as the Photato API. Adobe-compatible and Photato requests retain their existing results and contracts. The cache belongs to the Camera Raw workspace and is not persisted or shared across API requests.

Xcode built the app and all three focused app tests passed, including color-managed masked output, exact cache key requirements, cancellation and history. Both optimized architectures passed all 356 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The benchmark covers command preparation in Debug. The first sensor decode and edits to sensor controls still require Core Image processing. Rendered Adobe equivalence and the 60 fps editing target remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,534,637 bytes with SHA-256 `25dd1046adca85eff5b6397d23e4f224aef1cf0800fbb3dda1315ccefda9eb69`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_793.json) · [Development record](DEVLOG.md#dev-step-793).
