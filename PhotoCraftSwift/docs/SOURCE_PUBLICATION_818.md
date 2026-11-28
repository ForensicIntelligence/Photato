# Source checkpoint 818

Camera Raw HDR Merge now uses disk-backed raster bands for large brackets and processes deghost coverage in scratch storage. The authenticated command streams its DNG in bounded chunks. Opening the result in the filmstrip retains editable tone settings.

The native filmstrip merged three 8,192 × 5,120 exposures with alignment and High deghosting. Its 251,753,964-byte DNG matched the authenticated Photato download byte for byte. All three originals kept their hashes. Four small DNG controls matched the previous engine byte for byte across the deghost settings.

Adobe Camera Raw 18.1.1 merged the same three exposures using Align, Auto Settings and High deghosting. Both files retained 8,192 × 5,120 raw sample dimensions. Adobe stored a compressed tiled image and an 8,179 × 5,112 display crop. Adobe Camera Raw reopened Photato’s uncompressed full-size DNG and read its +0.52 Exposure adjustment. [Adobe Camera Raw limits](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

The existing `raw.mergeHDR` endpoint advertises the larger merge and download limits in the capabilities response. Mapped embedded RAW originals use the separate local source budget. Undo and the document revision were preserved.

Xcode built the app. All 58 focused tests and one large native and HTTP workflow check passed. Both optimized architectures passed all 432 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The working limits are 96 MP per exposure and 384 MP across the bracket. The large test covered 41.94 MP per exposure. Larger RAW panoramas, resource limits on other Mac configurations, Adobe alignment and deghost fidelity, and Adobe file equality remain open.

The Universal ZIP targets macOS 14 and later. It contains 80,115,813 bytes with SHA-256 `ffc158c6c0c288023631fe60affd76ec6c0defb658f52584efe8042b5102c051`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_818.json) · [Development record](DEVLOG.md#dev-step-818).
