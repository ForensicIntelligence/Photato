# Source checkpoint 822

Camera Raw can correct Vertical and Horizontal perspective, Rotate, change Aspect and Scale, and move the photo with Offset X and Offset Y. Constrain Crop trims geometry borders within the photo aspect. The native workspace saves the original sensor data and can Undo the corrections.

The native panel imported the seven Adobe XMP values. Editing Offset X to 11.25 and pressing Undo restored 7.5. Reset Geometry restored the neutral values. The Adobe and Photato TIFFs both measured 325 × 318. The mean absolute difference across 310,050 linear RGB components was 0.02608.

Camera Raw 18.1.1 exported eleven controlled transformations of an owned Bayer photo. Its saved crop constrained the photo at its original aspect ratio. [Adobe Camera Raw Geometry controls](https://helpx.adobe.com/in/camera-raw/desktop/edit-and-enhance-images/crop-rotate-and-geometry/automatic-perspective-correction-camera-raw.html).

Photato RAW development and synchronization expose the manual settings. Photato RAW import and the Adobe-compatible edit route also apply settings already stored on an input DNG.

Xcode built the app. All 62 focused checks and the separate authenticated interchange workflow passed. Both optimized architectures passed all 458 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The manual renderer uses a projective approximation. Adobe geometry and file bytes still differ. The automatic and Guided Upright tools, RAW Crop workspace and physical-platform checks remain open.

The Universal ZIP targets macOS 14 and later. It contains 80,207,531 bytes with SHA-256 `759aca13aa2a9acbbd711c3fe913c58d6e0f48f0fd5514a54eda60508d17d5e2`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_822.json) · [Development record](DEVLOG.md#dev-step-822).
