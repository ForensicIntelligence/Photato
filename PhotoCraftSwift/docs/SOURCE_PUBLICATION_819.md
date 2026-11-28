# Source checkpoint 819

Camera Raw panorama registration keeps its reduced feature analysis while projection, stitching and Boundary Warp process the original samples in disk-backed bands. Panoramas preserve full-canvas transparency and editable Auto Crop in DNG.

The native filmstrip merged two 4,320 × 4,224 exposures. Its 198,322,378-byte DNG matched the authenticated Photato download byte for byte. Reset Crop recovered the scene and sampled opacity. Both originals kept their hashes. Six small DNG controls matched the previous build across all three projections and both warp settings. A separate native engine probe fused four 18 MP exposures and reopened a 6,145 × 4,608 HDR panorama.

Adobe Camera Raw 18.1.1 merged the same exposures using Perspective, Boundary Warp 35, Auto Crop and Apply Auto Settings. Adobe displayed a 6,129 × 4,005 crop. Photato produced 6,144 × 4,093. Adobe Camera Raw reopened the Photato DNG with editable settings. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

The existing `raw.mergePanorama` and `raw.mergeHDRPanorama` commands use the same paged registration pipeline. The authenticated download preserves document history and includes the exact Content-Length.

Xcode built the app. All 69 focused checks passed, plus the large desktop and HTTP workflow. Both optimized architectures passed all 452 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The Camera Raw working limits are 96 MP per input and output and 384 MP across source positions. Fill Edges remains limited to 4 MP. The Adobe Fill Edges control reached 6,142 × 4,606. Adobe geometry, auto tone, compressed tiles, file equality and physical-platform performance remain open.

The Universal ZIP targets macOS 14 and later. It contains 80,142,201 bytes with SHA-256 `b64d49fe2ce9ec5b052b08f7b56475e3f50b4113dd58d730bd5021b341447bdd`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_819.json) · [Development record](DEVLOG.md#dev-step-819).
