# Source checkpoint 593

Native Swift 0.3.0, build 593, 19 November 2026. Vector masks accept Feather through 1,000 px and keep their paths editable in native documents, PSD and PSB.

The complete sparse 300,000 × 300,000 control runs in four patches, including contours beyond the canvas edge. A separate 1,000 px nonuniform mask renders within a small viewport on the same logical canvas size. The bounded short-radius path matches all 56,244 sampled legacy coverage words. [Adobe Feather range](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/) · [PSD/PSB structure](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

All 904 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted universal app passed offscreen checks. The archive declares macOS 14 as its minimum. Live mouse and keyboard interaction, dense wide-mask performance, physical Intel and macOS 14 validation remain open.

Measurements from the archived Photoshop 2026 RGB32 PSD show distinct edge responses at 1.5 px and 2 px. A separable model fits the measured corner samples with less than 0.000001 normalized error. Photato’s current short-radius approximation differs by up to 0.014 on these normalized edge profiles. The installed Photoshop session timed out on its document-count request, so wider radii still need fresh reference files.

[Developer record](DEVLOG.md#dev-step-593) · [Validation data and source fingerprints](VECTOR_MASK_FEATHER_593.json).
