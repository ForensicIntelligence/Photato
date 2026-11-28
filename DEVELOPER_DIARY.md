# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **822** · The 10 most recent entries, newest first.

## 2026-11-28 — Step 822 — Add manual Camera Raw Geometry

Camera Raw can correct Vertical and Horizontal perspective, Rotate, change Aspect and Scale, and move the photo with Offset X and Offset Y. Constrain Crop trims geometry borders within the photo aspect. The native workspace saves the original sensor data and can Undo the corrections.

The native panel imported the seven Adobe XMP values. Editing Offset X to 11.25 and pressing Undo restored 7.5. Reset Geometry restored the neutral values. The Adobe and Photato TIFFs both measured 325 × 318. The mean absolute difference across 310,050 linear RGB components was 0.02608.

Camera Raw 18.1.1 exported eleven controlled transformations of an owned Bayer photo. Its saved crop constrained the photo at its original aspect ratio. [Adobe Camera Raw Geometry controls](https://helpx.adobe.com/in/camera-raw/desktop/edit-and-enhance-images/crop-rotate-and-geometry/automatic-perspective-correction-camera-raw.html).

Xcode built the app. All 62 focused checks and the separate authenticated interchange workflow passed. Both optimized architectures passed all 458 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The manual renderer uses a projective approximation. Adobe geometry and file bytes still differ. The automatic and Guided Upright tools, RAW Crop workspace and physical-platform checks remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-822) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_822.md).

## 2026-11-28 — Step 821 — Retain JPEG XL transparency in Camera Raw DNG imports

Camera Raw restores transparent edges from tiled 8-bit JPEG XL masks in supported panorama DNGs. Image I/O decodes the original grayscale samples. The full mask uses mapped scratch storage.

The desktop RAW engine reopened a 6,135 × 4,509 Adobe panorama. All 27,662,715 alpha samples matched the reconstructed transparency plane. An additional 735 × 402 test retained all 295,470 samples through both authenticated API interfaces.

The large reference came from Camera Raw 18.1.1 and used thirty 1,024 × 912 JPEG XL mask tiles. The Photato build before this change read the five sampled points as opaque. The new DNG import preserves their stored alpha. [Adobe DNG specification](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html).

Xcode built the app. All 58 focused checks passed, plus the two-interface API workflow. Both optimized architectures passed all 454 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Image I/O cleared the trailing sample of some small odd-size fixtures. The current decoder rejects odd-size tiles below 65,536 pixels. The current evidence covers opacity. Adobe color, crop, RAW encoding and physical Intel and macOS 14 qualification remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-821) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_821.md).

## 2026-11-28 — Step 820 — Fill edges on full-resolution Camera Raw panoramas

Camera Raw Fill Edges works on panoramas above the previous 4 MP limit, including results from HDR Panorama. Large scenes estimate donor patches from a bounded overview and sample the original detail into the gaps. The merge preview clears and disables Auto Crop while Fill Edges is on.

The Camera Raw filmstrip merged two 4,320 × 4,224 exposures. It filled 1,406,976 transparent or partly transparent pixels and preserved 26,910,720 covered pixels at exact Float32 RGB values. The 170,001,420-byte desktop DNG matched the authenticated download byte for byte. Both originals kept their hashes. Six small Fill Edges DNGs matched the previous build.

Adobe Camera Raw 18.1.1 cleared Auto Crop when Fill Edges was enabled and left it unchecked when the control became available again. Adobe merged the same sources at 6,142 × 4,606 and reopened the Photato DNG at 6,144 × 4,609. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

Xcode built the app. All 70 focused checks passed, plus the large desktop and HTTP workflow. Both optimized architectures passed all 453 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The full-size comparison covers one pair of owned sources. Adobe geometry, patch placement, color and compressed DNG bytes still differ. The advertised ceiling and physical Intel and macOS 14 operation need further qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-820) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_820.md).

## 2026-11-28 — Step 819 — Stitch full-resolution Camera Raw panoramas

Camera Raw panorama registration keeps its reduced feature analysis while projection, stitching and Boundary Warp process the original samples in disk-backed bands. Panoramas preserve full-canvas transparency and editable Auto Crop in DNG.

The native filmstrip merged two 4,320 × 4,224 exposures. Its 198,322,378-byte DNG matched the authenticated Photato download byte for byte. Reset Crop recovered the scene and sampled opacity. Both originals kept their hashes. Six small DNG controls matched the previous build across all three projections and both warp settings. A separate native engine probe fused four 18 MP exposures and reopened a 6,145 × 4,608 HDR panorama.

Adobe Camera Raw 18.1.1 merged the same exposures using Perspective, Boundary Warp 35, Auto Crop and Apply Auto Settings. Adobe displayed a 6,129 × 4,005 crop. Photato produced 6,144 × 4,093. Adobe Camera Raw reopened the Photato DNG with editable settings. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

Xcode built the app. All 69 focused checks passed, plus the large desktop and HTTP workflow. Both optimized architectures passed all 452 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The Camera Raw working limits are 96 MP per input and output and 384 MP across source positions. Fill Edges remains limited to 4 MP. The Adobe Fill Edges control reached 6,142 × 4,606. Adobe geometry, auto tone, compressed tiles, file equality and physical-platform performance remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-819) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_819.md).

## 2026-11-28 — Step 818 — Merge high-resolution Camera Raw HDR brackets

Camera Raw HDR Merge now uses disk-backed raster bands for large brackets and processes deghost coverage in scratch storage. The authenticated command streams its DNG in bounded chunks. Opening the result in the filmstrip retains editable tone settings.

The native filmstrip merged three 8,192 × 5,120 exposures with alignment and High deghosting. Its 251,753,964-byte DNG matched the authenticated Photato download byte for byte. All three originals kept their hashes. Four small DNG controls matched the previous engine byte for byte across the deghost settings.

Adobe Camera Raw 18.1.1 merged the same three exposures using Align, Auto Settings and High deghosting. Both files retained 8,192 × 5,120 raw sample dimensions. Adobe stored a compressed tiled image and an 8,179 × 5,112 display crop. Adobe Camera Raw reopened Photato’s uncompressed full-size DNG and read its +0.52 Exposure adjustment. [Adobe Camera Raw limits](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

Xcode built the app. All 58 focused tests and one large native and HTTP workflow check passed. Both optimized architectures passed all 432 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The working limits are 96 MP per exposure and 384 MP across the bracket. The large test covered 41.94 MP per exposure. Larger RAW panoramas, resource limits on other Mac configurations, Adobe alignment and deghost fidelity, and Adobe file equality remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-818) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_818.md).

## 2026-11-28 — Step 817 — Merge bracketed RAW photos into HDR panoramas

Use Merge to HDR Panorama from the Camera Raw filmstrip. Photato finds complete brackets in capture order, fuses each position onto the same scene-linear exposure scale, then stitches the panorama. The editable DNG retains highlight values, transparency, crop and optional automatic tone settings.

The nine-photo test grouped three exposures per position and preserved 444 pixels above reference white, reaching a peak scene sample of 1.956. In the fixed-order Perspective reference, Photato developed a 733 × 364 crop and Adobe produced 731 × 363. The mean absolute linear RGB difference was 0.0535 over their overlapping opaque crop with the same Apple decoder.

Adobe Camera Raw 18.1.1 accepted three brackets with equal exposure offsets and different base exposures. The live Photato menu merged the same nine originals into a tenth filmstrip photo. Adobe reopened the saved Photato DNG and showed its editable exposure. All nine original files retained their hashes. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

Xcode built the app. All 54 focused application and imaging checks passed, including three added tests. Both optimized architectures passed all 429 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Larger brackets, real camera and moving-subject comparisons, and exact Adobe pixel and projection fidelity remain open. The working limits are 16 MP per exposure, 32 MP per bracket, 32 MP across the fused positions and 16 MP for the panorama.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-817) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_817.md).

## 2026-11-28 — Step 816 — Stitch Camera Raw panoramas with an editable crop

Select overlapping RAW photos and press Command-M to preview a Spherical, Cylindrical or Perspective panorama. Boundary Warp and Fill Edges refine the edges. Auto Crop records an editable setting and retains the full stitched scene and transparency. Command-Shift-M goes to the save step with the remembered options.

Three owned RAW inputs registered with 173 matches. Adobe and Photato produced a 733 × 364 crop in the fixed-order perspective comparison. Both files were developed through the same Apple decoder for the comparison. Their mean absolute linear RGB difference was 0.0368. Photoshop Camera Raw also opened a separate Photato-saved DNG from the live workflow, with its 735 × 364 crop and the editable settings in place.

The native filmstrip opened Command-M, applied Perspective with Command-3, saved a fourth photo from three originals, and verified Reset Crop and Undo. Adobe Camera Raw 18.1.1 reopened the saved DNG. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

Xcode built the app and 51 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 426 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

HDR Panorama, larger brackets and exact Adobe projection, edge synthesis and rendered samples remain open. Photo registration supports 16 MP per source, 32 MP combined and a 16 MP result. Fill Edges supports up to 4 MP. Photato reads its standard 8-bit uncompressed transparency plane. Adobe’s compressed transparency planes still need qualification.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-816) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_816.md).

## 2026-11-28 — Step 815 — Apply editable HDR automatic tone and color

Apply Auto Settings in Camera Raw HDR Merge now writes Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance and Saturation into the output DNG as editable Camera Raw settings. The dialog preview uses the same settings.

Across six owned scenes, mean Exposure error against Adobe fell from 0.73 to 0.26 stops. The other seven sliders averaged 10.5 points from Adobe, down from 31.5. The DNG sensor payload was byte-identical with Auto on and off in all six Photato scenes. Adobe also retained its compressed sensor payload with Auto on and off in the textured scene.

Adobe Camera Raw 18.1.1 wrote recipes for six owned 512 × 384 DNG brackets, including a terrace scene withheld while designing the adjustments. The independently read XMP and encoded sensor hashes are linked below. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode built the app and all 47 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 422 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

On the withheld terrace scene, the seven slider values improved on average, and Exposure diverged by 0.77 stops where the previous Exposure was 0.06 stops off. These results measure XMP settings and sensor payload preservation. Adobe-rendered pixels, real-world scenes, larger brackets and deghosting remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-815) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_815.md).

## 2026-11-28 — Step 814 — Fuse scene-linear HDR exposure brackets

Camera Raw merges linear sensor samples using shutter time, aperture and ISO. The middle exposure supplies the reference frame and white balance. Reliable samples recover highlight detail while the deghost mask can restore the reference where subjects move.

On one stationary synthetic bracket, the mean decoded RGB difference from Adobe fell from 0.08634 to 0.04297. On a textured bracket with known translations and motion, it fell from 0.08420 to 0.06289, and the merge corrected both known translations. A separate test confirmed that alignment keeps the stationary bracket stationary.

Adobe Camera Raw 18.1.1 produced the two reference DNGs from owned synthetic input. Decode comparison used the same Apple 8.dng decoder for both outputs. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and 43 focused application and imaging tests passed, including the existing HDR Pro cases and three new radiance, alignment and deghost cases. Both optimized architectures passed all 418 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tested Adobe files and decoded pixels still differ. The shifted fixture tests translation rather than perspective changes. Adobe deghost masks, the full Auto Settings recipe and higher-capacity HDR merges remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-814) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_814.md).

## 2026-11-28 — Step 813 — Merge Camera Raw exposures into editable HDR DNGs

Select two or more RAW brackets and use Merge to HDR. The preview supports alignment, automatic exposure, three deghost strengths and an overlay. The result returns to the filmstrip as an editable DNG.

Option–M opened the preview on three owned brackets, and Option–Shift–M opened the destination picker. The regular merge added a fourth photo and preserved all source bytes. Adobe Camera Raw rendered a Photato-generated linear DNG and allowed exposure edits. Native and authenticated API DNG downloads matched byte for byte with identical inputs and settings.

Adobe Camera Raw 18.1.1 confirmed Align Images and Apply Auto Settings as initial defaults, with Deghost Off. [Adobe Camera Raw shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and forty focused application and imaging tests passed, including the ten existing HDR merge workflow cases. Both optimized architectures passed all 415 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The merge kernel reuses Photato’s photographic HDR engine. Automatic settings currently embed a single calculated exposure adjustment. Adobe’s result used JPEG XL and multiple tone adjustments. The tested decoded RGB samples and complete file bytes differ from Adobe’s result. RAW-specific fusion, larger brackets and exact render parity remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-813) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_813.md).
