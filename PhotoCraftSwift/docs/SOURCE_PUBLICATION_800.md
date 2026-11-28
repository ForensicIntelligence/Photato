# Source checkpoint 800

Photato now opens larger camera RAW files and keeps their sensor pixels in disk-backed tiles. Local originals above 64 MiB are snapshotted into a mapped private file. Camera Raw keeps a reduced overview for the dialog and the full sensor data for Open, Place Embedded and edits.

Photato opened both the uncompressed and packed versions of the 8,192 × 5,120 synthetic DNG. The uncompressed source retained all 83,886,726 original bytes. The signed app opened the same file in Camera Raw at full sensor dimensions. The synthetic archive test round-tripped the RAW Smart Object and matching edit samples.

Adobe Camera Raw 18.1.1 opened the owned 42-megapixel reference. Adobe documents a 65,000-pixel side limit and a 512-megapixel area limit. [Adobe Camera Raw limits](https://helpx.adobe.com/in/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

Authenticated `capabilities.rawDevelopment` describes the local source, sensor and spatial adjustment limits. The desktop and native authorized opening path share the new decoder behavior. The separate binary HTTP upload still uses the established 64 MiB transport limit.

Xcode built the app. All four new focused checks and twelve related checks passed. The tests covered mapped storage, large RAW Smart Object persistence, exact pointwise edit samples, bounded DNG XMP writes API discovery and rejection of reduced decoder output. Both optimized architectures passed all 381 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The 65,000-pixel and 512-megapixel admission bounds still depend on the decoder. The signed app was verified at 41,943,040 pixels. At the published boundaries, Apple reported reduced dimensions for the canonical synthetic DNGs. Photato now rejects those reduced outputs. Spatial Camera Raw adjustments still use the 36-megapixel limit. Adobe RAW pixel and file-byte parity remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,871,026 bytes with SHA-256 `5340fd3859743e2852341568ae7ff00994acd1af3de3d0b1c4a5beff27d2d3b7`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_800.json) · [Development record](DEVLOG.md#dev-step-800).
