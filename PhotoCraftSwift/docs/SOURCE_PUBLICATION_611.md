# Source checkpoint 611

Native Swift 0.3.0, build 611, 19 November 2026. Large Raw and PackBits PSD and PSB imports retain saved alpha, spot, and Quick Mask planes as implicit gray and edited tiles.

The native reader opened a synthetic 300,000 × 300,000 grayscale PSB in 4.22 seconds in one Apple Silicon Debug run. All 9,216 stored alpha samples and both editable grayscale layer samples matched the authored input. The saved alpha used 192 KiB of mapped sample storage.

A smaller 1,201 × 30,001 PSB retained all 10,593 checked alpha samples within a 768 KiB scratch allowance. Build 610 exceeded that allowance. The test set covers RGB8 Raw and PackBits and RGB16 and RGB32 PackBits.

All 958 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The Debug run reached the harness deadline after 825 passing cases. The remaining 133 passed in a second batch from the same binary. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-size file was independently generated. Live Photoshop exchange and dense and ZIP-compressed channel checks remain open. [Adobe Large Document Format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-611) · [Validation data](PSD_SPARSE_AUXILIARY_IMPORT_611.json).
