# Source checkpoint 815

Apply Auto Settings in Camera Raw HDR Merge now writes Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance and Saturation into the output DNG as editable Camera Raw settings. The dialog preview uses the same settings.

Across six owned scenes, mean Exposure error against Adobe fell from 0.73 to 0.26 stops. The other seven sliders averaged 10.5 points from Adobe, down from 31.5. The DNG sensor payload was byte-identical with Auto on and off in all six Photato scenes. Adobe also retained its compressed sensor payload with Auto on and off in the textured scene.

Adobe Camera Raw 18.1.1 wrote recipes for six owned 512 × 384 DNG brackets, including a terrace scene withheld while designing the adjustments. The independently read XMP and encoded sensor hashes are linked below. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

`raw.mergeHDR` with `autoSettings: true` uses the same tone and color calculation as the Camera Raw filmstrip. The authenticated download matched the native DNG byte for byte on the tested exposure bracket.

Xcode built the app and all 47 focused application and imaging checks passed, including four added checks. Both optimized architectures passed all 422 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

On the withheld terrace scene, the seven slider values improved on average, and Exposure diverged by 0.77 stops where the previous Exposure was 0.06 stops off. These results measure XMP settings and sensor payload preservation. Adobe-rendered pixels, real-world scenes, larger brackets and deghosting remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,849,115 bytes with SHA-256 `f77ebef5d14fcb5c9f2e7c161cc0972cda6c9581dde47ba03f6c1318003a4e9a`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_815.json) · [Development record](DEVLOG.md#dev-step-815).
