# Source checkpoint 566

Native Swift 0.3.0, build 566, 18 November 2026. PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background.

The writer uses the stored grayscale samples for the merged image and leaves out the redundant transparency plane. Saved auxiliary channels still follow the grayscale plane. Build 565 wrote 24 of 192 samples as 1.4999998807907104 where Photoshop saved 1.5. It also wrote a fully opaque alpha plane. The layer data already held the right samples.

An independent reader checked every sample of the 16 × 12 test image against a raw PSD saved by Photoshop 2026 at checkpoint 511. All 192 merged samples match byte for byte in PSD and PSB in all four compression modes. The comparison covers the grayscale plane and the channel count. [Original Photoshop reference](SOURCE_PUBLICATION_511.md).

All 629 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The tests also cover a saved auxiliary channel, hidden Background, both API encoders, and authenticated Photato downloads. Both universal app slices passed offscreen checks. The first qualification attempt stopped before compilation because the workspace sandbox denied access to Xcode’s module cache. The second attempt used the local Xcode cache and also extended the existing compression test to compress the merged image with each codec.

Exact output for multilayer Gray32 composites and RGB32 and Gray32 color-conversion workflows still needs verification. The independent reference covers one owned image and excludes container metadata such as the ICC profile.

[Development record](DEVLOG.md#dev-step-566) · [Validation data](GRAY32_MERGED_SAMPLES_566.json) · [Frozen source](SOURCE_SNAPSHOT_566.json)
