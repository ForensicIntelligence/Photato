# Source checkpoint 816

Select overlapping RAW photos and press Command-M to preview a Spherical, Cylindrical or Perspective panorama. Boundary Warp and Fill Edges refine the edges. Auto Crop records an editable setting and retains the full stitched scene and transparency. Command-Shift-M goes to the save step with the remembered options.

Three owned RAW inputs registered with 173 matches. Adobe and Photato produced a 733 × 364 crop in the fixed-order perspective comparison. Both files were developed through the same Apple decoder for the comparison. Their mean absolute linear RGB difference was 0.0368. Photoshop Camera Raw also opened a separate Photato-saved DNG from the live workflow, with its 735 × 364 crop and the editable settings in place.

The native filmstrip opened Command-M, applied Perspective with Command-3, saved a fourth photo from three originals, and verified Reset Crop and Undo. Adobe Camera Raw 18.1.1 reopened the saved DNG. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

The authenticated `raw.mergePanorama` download matched the native saved DNG byte for byte in the workflow test. Capability discovery now exposes 301 commands, including panorama options and the `raw.develop` normalized crop setting.

Xcode built the app and 51 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 426 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

HDR Panorama, larger brackets and exact Adobe projection, edge synthesis and rendered samples remain open. Photo registration supports 16 MP per source, 32 MP combined and a 16 MP result. Fill Edges supports up to 4 MP. Photato reads its standard 8-bit uncompressed transparency plane. Adobe’s compressed transparency planes still need qualification.

The Universal ZIP targets macOS 14 and later. It contains 80,064,399 bytes with SHA-256 `96026e47145f26c4ba4eb4b97013dc9eb15d24a11d1f048259af47133631a749`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_816.json) · [Development record](DEVLOG.md#dev-step-816).
