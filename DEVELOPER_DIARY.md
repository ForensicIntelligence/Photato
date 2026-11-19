# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **573** · The 10 most recent entries, newest first.

## 2026-11-18 — Step 573 — Match HDR Normal rounding at the Float32 underflow boundary

On Intel, very small color contributions can disappear during 32-bit Normal compositing. Photato now matches the measured rounding, including products just below the smallest normal Float32 value. The Apple Silicon build keeps its fused calculation.

The new tests compare 57,504 straight color and alpha words with separately saved Photoshop results on each architecture. An ordinary opaque source that covers the canvas retains its original colors over uniform backdrop alpha. Grouped clipping can preserve those colors even when the base alpha varies. All 708 selected tests passed in all three configurations. The local universal archive passed both offscreen workspace checks. The translucent test also exposed a difference in Merge Visible that remains open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_573.md).

## 2026-11-18 — Step 572 — Match Intel HDR Normal layer and group compositing

Photoshop's Intel build rounds the multiply and add separately when compositing 32-bit Normal layers. On Apple Silicon it uses a fused operation. Photato now follows those results for color, alpha and the opacity of supported groups. The tests use separately captured Photoshop results for each architecture.

The tested results match 264,192 Photoshop sample words on each architecture. That includes the masked Display P3 conversion that differed on Intel in build 571. All 705 selected tests passed in each configuration. Independent HDR clipping still differs.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_572.md).

## 2026-11-18 — Step 571 — Fix HDR PSD and PSB compression for Photoshop

Photoshop was reading plain ZIP as predicted ZIP on 32-bit layers. This could corrupt HDR colors when opening a PSD or PSB exported by Photato. New exports use the prediction expected for those layers. ZIP requests for the merged preview write raw data because Photoshop refused ZIP in that section. Photato still reads its older files.

Photoshop opened the tested files on Apple Silicon and Intel under Rosetta. The saved 32-bit grayscale samples match across both formats and save encodings. All 694 selected tests passed in each of three build configurations. The local universal archive passed both offscreen workspace checks. A separate mismatch remains in the Intel masked merge.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_571.md).

## 2026-11-18 — Step 570 — Preserve the working profile when merging before conversion

Merging eligible RGB layers before an Image Mode change now uses their working-profile samples. If the composite is already a single full-canvas layer, the conversion uses its original color and alpha planes. The existing Normal merge routine handles integer rounding for supported RGB stacks before promotion to 32 Bits/Channel.

All 35,840 words in the three valid Photoshop references match on each optimized architecture. All 678 selected tests passed in each build configuration. The two external HDR merge cases still need readable references.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_570.md).

## 2026-11-18 — Step 569 — Match HDR grayscale conversion and ICC gamma boundaries

32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

All 8,510,976 samples in 257 tested precision promotions and 194,560 samples in 38 RGB32-to-Gray32 cases match Photoshop on each architecture. All 661 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

Follow-up testing measured 4,410 rounding thresholds for 16-bit grayscale. Separate Float32 luminance products ordered all of the samples correctly. A 4,096-interval curve fits the measured thresholds, but its exact endpoint calculation remains open. Build 569 continues to use ColorSync for this conversion.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-569) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_569.md).

## 2026-11-18 — Step 568 — Match half-gamma promotion and Gray32 PSD layer stacks

RGB and grayscale gamma 0.5 profiles now promote to 32 Bits/Channel using the measured rounding on each architecture. PSD and PSB use native gray samples for supported 32-bit layer stacks.

All 2,142,336 stored samples from 59 tested conversion cases match the corresponding Photoshop files on each architecture. Five Gray32 layer stacks match all 960 merged words under each of four compression modes in PSD and PSB. All 657 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-568) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_568.md).

## 2026-11-18 — Step 567 — Use the source tone curves for 32-bit RGB and Gray

Promoting an 8-bit or 16-bit RGB or grayscale document to 32 bits now uses the supported tone curves from its current ICC profile.

All 1,976,832 samples from 54 supported cases match the files saved by Photoshop 2026 byte for byte on both tested architectures, using a separate Photoshop run on each architecture. Photoshop itself returned different values across architectures for 13,057 samples from the gamma and parametric cases. The Swift conversion matches the rounding observed on each architecture. All 651 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The desktop conversion and the authenticated Photato command produce the same stored samples and both Undo correctly. Both universal app slices passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-567) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_567.md).

## 2026-11-18 — Step 566 — Preserve opaque Gray32 merged samples in PSD and PSB

PSD and PSB exports now preserve all 32-bit grayscale samples when the document contains one visible, opaque Background. The writer uses the stored grayscale samples for the merged image and leaves out the redundant transparency plane. Saved auxiliary channels still follow the grayscale plane.

An independent reader checked every sample of the 16 × 12 test image against a raw PSD saved by Photoshop 2026 at checkpoint 511. All 192 merged samples match byte for byte in PSD and PSB in all four compression modes. The comparison covers the grayscale plane and the channel count. All 629 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The tests also cover a saved auxiliary channel, hidden Background, both API encoders, and authenticated Photato downloads. Both universal app slices passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-566) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_566.md).

## 2026-11-18 — Step 565 — Add Allow Tool Recording to Actions

The Actions menu now controls whether a new recording captures Brush and other supported painting and retouching gestures. Tool gestures still edit pixels and appear in Undo when the setting is off.

All 608 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. In 52 channel-stroke sequences, both recording settings produced the same raw samples as direct editing and the same per-architecture output as build 564. Forty older Brush step encodings also matched. Both universal slices passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-565) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_565.md).

## 2026-11-18 — Step 564 — Record Brush Actions for color channels

Photato Actions can record Brush strokes on process color components, Duotone gray, and Multichannel ink plates. Playback resolves the recorded target against the current document, respects its selection, and takes one Undo to reverse.

All 583 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. On each architecture, 52 tested channel strokes replayed to the same samples as direct editing and matched build 563’s raw planes. Forty legacy Brush step encodings also matched. Both slices of the macOS 14+ validation archive passed offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-564) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_564.md).
