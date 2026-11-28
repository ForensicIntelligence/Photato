# Source checkpoint 821

Camera Raw restores transparent edges from tiled 8-bit JPEG XL masks in supported panorama DNGs. Image I/O decodes the original grayscale samples. The full mask uses mapped scratch storage.

The desktop RAW engine reopened a 6,135 × 4,509 Adobe panorama. All 27,662,715 alpha samples matched the reconstructed transparency plane. An additional 735 × 402 test retained all 295,470 samples through both authenticated API interfaces.

The large reference came from Camera Raw 18.1.1 and used thirty 1,024 × 912 JPEG XL mask tiles. The Photato build before this change read the five sampled points as opaque. The new DNG import preserves their stored alpha. [Adobe DNG specification](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html).

The Photato RAW import and Adobe-compatible edit use the same native decoder. The Photato capability `rawDevelopment.preservesJPEGXLDNGTransparency` reports decoder availability.

Xcode built the app. All 58 focused checks passed, plus the two-interface API workflow. Both optimized architectures passed all 454 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Image I/O cleared the trailing sample of some small odd-size fixtures. The current decoder rejects odd-size tiles below 65,536 pixels. The current evidence covers opacity. Adobe color, crop, RAW encoding and physical Intel and macOS 14 qualification remain open.

The Universal ZIP targets macOS 14 and later. It contains 80,162,457 bytes with SHA-256 `25e405b6055f406562ec0f90dcbfbc59bca495ca499acefc9180347ccb34e00a`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_821.json) · [Development record](DEVLOG.md#dev-step-821).
