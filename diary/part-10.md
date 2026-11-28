[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-09.md)

## 2026-11-28 — Step 815 — Apply editable HDR automatic tone and color

Apply Auto Settings in Camera Raw HDR Merge now writes Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance and Saturation into the output DNG as editable Camera Raw settings. The dialog preview uses the same settings.

Across six owned scenes, mean Exposure error against Adobe fell from 0.73 to 0.26 stops. The other seven sliders averaged 10.5 points from Adobe, down from 31.5. The DNG sensor payload was byte-identical with Auto on and off in all six Photato scenes. Adobe also retained its compressed sensor payload with Auto on and off in the textured scene.

Adobe Camera Raw 18.1.1 wrote recipes for six owned 512 × 384 DNG brackets, including a terrace scene withheld while designing the adjustments. The independently read XMP and encoded sensor hashes are linked below. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode built the app and all 47 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 422 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

On the withheld terrace scene, the seven slider values improved on average, and Exposure diverged by 0.77 stops where the previous Exposure was 0.06 stops off. These results measure XMP settings and sensor payload preservation. Adobe-rendered pixels, real-world scenes, larger brackets and deghosting remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-815) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_815.md).

## 2026-11-28 — Step 814 — Fuse scene-linear HDR exposure brackets

Camera Raw merges linear sensor samples using shutter time, aperture and ISO. The middle exposure supplies the reference frame and white balance. Reliable samples recover highlight detail while the deghost mask can restore the reference where subjects move.

On one stationary synthetic bracket, the mean decoded RGB difference from Adobe fell from 0.08634 to 0.04297. On a textured bracket with known translations and motion, it fell from 0.08420 to 0.06289, and the merge corrected both known translations. A separate test confirmed that alignment keeps the stationary bracket stationary.

Adobe Camera Raw 18.1.1 produced the two reference DNGs from owned synthetic input. Decode comparison used the same Apple 8.dng decoder for both outputs. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and 43 focused application and imaging tests passed, including the existing HDR Pro cases and three new radiance, alignment and deghost cases. Both optimized architectures passed all 418 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tested Adobe files and decoded pixels still differ. The shifted fixture tests translation rather than perspective changes. Adobe deghost masks, the full Auto Settings recipe and higher-capacity HDR merges remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-814) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_814.md).

## 2026-11-28 — Step 813 — Merge Camera Raw exposures into editable HDR DNGs

Select two or more RAW brackets and use Merge to HDR. The preview supports alignment, automatic exposure, three deghost strengths and an overlay. The result returns to the filmstrip as an editable DNG.

Option–M opened the preview on three owned brackets, and Option–Shift–M opened the destination picker. The regular merge added a fourth photo and preserved all source bytes. Adobe Camera Raw rendered a Photato-generated linear DNG and allowed exposure edits. Native and authenticated API DNG downloads matched byte for byte with identical inputs and settings.

Adobe Camera Raw 18.1.1 confirmed Align Images and Apply Auto Settings as initial defaults, with Deghost Off. [Adobe Camera Raw shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Xcode and forty focused application and imaging tests passed, including the ten existing HDR merge workflow cases. Both optimized architectures passed all 415 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The merge kernel reuses Photato’s photographic HDR engine. Automatic settings currently embed a single calculated exposure adjustment. Adobe’s result used JPEG XL and multiple tone adjustments. The tested decoded RGB samples and complete file bytes differ from Adobe’s result. RAW-specific fusion, larger brackets and exact render parity remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-813) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_813.md).

## 2026-11-28 — Step 812 — Hide and reveal photos in Camera Raw sessions

Use the Photo menu or a thumbnail’s contextual menu to hide photos, isolate a selection, or reveal hidden photos. The filmstrip and Grid share visibility. A new Camera Raw session starts with every photo visible.

In the native app, Show Only This Photo isolated one of three test DNGs in both views. Hide Photo emptied Grid, and its empty-state button restored all three. Cancel preserved the source bytes.

Commands follow Adobe’s documented session visibility workflow. [Hide photos in Camera Raw](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/hide-photos-during-a-camera-raw-session.html).

Xcode built the app and all twenty-four focused application tests passed, including returning hidden photos with their filters and saving edits to a hidden DNG. Both optimized architectures passed all 401 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The current installed Adobe Camera Raw predates these commands. Native controls were tested on owned files, with the Adobe documentation as the reference. Stacks and automatic grouping remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-812) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_812.md).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-09.md)
