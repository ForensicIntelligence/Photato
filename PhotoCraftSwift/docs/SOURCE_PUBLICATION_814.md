# Source checkpoint 814

Camera Raw merges linear sensor samples using shutter time, aperture and ISO. The middle exposure supplies the reference frame and white balance. Reliable samples recover highlight detail while the deghost mask can restore the reference where subjects move.

On one stationary synthetic bracket, the mean decoded RGB difference from Adobe fell from 0.08634 to 0.04297. On a textured bracket with known translations and motion, it fell from 0.08420 to 0.06289, and the merge corrected both known translations. A separate test confirmed that alignment keeps the stationary bracket stationary.

Adobe Camera Raw 18.1.1 produced the two reference DNGs from owned synthetic input. Decode comparison used the same Apple 8.dng decoder for both outputs. [Adobe Camera Raw HDR shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

The native workflow and authenticated `raw.mergeHDR` call the same scene-linear merge and DNG writer. The regression test reproduced the DNG bytes across both entry points using the same inputs.

Xcode and 43 focused application and imaging tests passed, including the existing HDR Pro cases and three new radiance, alignment and deghost cases. Both optimized architectures passed all 418 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tested Adobe files and decoded pixels still differ. The shifted fixture tests translation rather than perspective changes. Adobe deghost masks, the full Auto Settings recipe and higher-capacity HDR merges remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,845,865 bytes with SHA-256 `bafbd9e84aea8a1489291040b3b4649b6d2e2e435397752deec040bbe90ae636`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_814.json) · [Development record](DEVLOG.md#dev-step-814).
