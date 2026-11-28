# Source checkpoint 792

The Camera Raw engine applies exposure, relative color temperature and tint together in one tile pass for eligible RGB8 and RGB16 images. It reuses exact gain calculations for integer sample codes and evaluates other retained samples with the original arithmetic.

The same Nikon exposure test took 6.38 seconds for RAW develop command preparation, compared with 13.93 seconds in build 791’s arm64 Debug probe. The full preview buffers matched byte for byte. The signed app opened the adjusted Nikon as a 3,008 × 2,000 RGB16 document with its embedded RAW intact. Closing without saving preserved the source.

Camera Raw Filter, the Photato RAW development command, and applicable Adobe-compatible edits use the same native kernel. The optimized path preserves stored samples, alpha, and HTTP contracts.

Xcode built the app and both focused core tests passed. They cover every RGB8 and RGB16 sample code, archived raster tiles, alpha, and legacy off-grid values. Both optimized architectures passed all 353 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The timings cover command preparation in Debug. Rendered Adobe equivalence and broad real-time editing remain open. RGB32 and multi-stage settings retain the existing development path.

The Universal ZIP targets macOS 14 and later. It contains 78,529,635 bytes with SHA-256 `20d0a4a78f814ad3628e6c79e1c5102fe857531f1920aacc41eb4f1984b424bf`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_792.json) · [Development record](DEVLOG.md#dev-step-792).
