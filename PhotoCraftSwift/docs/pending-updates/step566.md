<a id="dev-step-566"></a>

## 2026-11-18 — Preserve opaque Gray32 merged samples in PSD and PSB

PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background. The writer uses the stored grayscale samples for the merged image and leaves out the redundant transparency plane. Saved auxiliary channels still follow the grayscale plane.

Build 565 wrote 24 of 192 samples as 1.4999998807907104 where Photoshop saved 1.5. It also wrote a fully opaque alpha plane. The layer data already held the right samples. The exporter sent the grayscale data through the display projection and back to grayscale before writing the merged image. `Sources/PhotoCraftImaging/PSDCodec.swift` now reads directly from the document’s validated Gray32 sample plane in this case. The native layer encoding, HDR toning metadata, and normal compositor for other stacks retain their existing behavior.

An independent reader checked every sample of the 16 × 12 test image against a raw PSD saved by Photoshop 2026 at checkpoint 511. All 192 merged samples match byte for byte in PSD and PSB in all four compression modes. The comparison covers the grayscale plane and the channel count. The reference fixture includes only grayscale samples from an owned procedural image. [Original Photoshop reference](SOURCE_PUBLICATION_511.md).

The existing Save family, authenticated Photato PSD/PSB downloads, and resource-job output for both API interfaces use the shared writer. `Sources/PhotoCraft/AutomationDocumentTransfers.swift` advertises the output behavior. `Tests/PhotoCraftImagingTests/PSDGray32MetadataTests.swift` checks actual merged bytes and channel placement. `Tests/PhotoCraftAppTests/Gray32ExportWorkflowTests.swift` checks the output channel count on each API path.

All 629 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The tests also cover a saved auxiliary channel, hidden Background, both API encoders, and authenticated Photato downloads. Both universal app slices passed offscreen checks. The first qualification attempt stopped before compilation because the workspace sandbox denied access to Xcode’s module cache. The second attempt used the local Xcode cache and also extended the existing compression test to compress the merged image with each codec.

Exact output for multilayer Gray32 composites and RGB32 and Gray32 color-conversion workflows still needs verification. The independent reference covers one owned image and excludes container metadata such as the ICC profile. [Qualification](SOURCE_PUBLICATION_566.md).
