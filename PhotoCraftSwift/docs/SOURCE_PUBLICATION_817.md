# Source checkpoint 817

Use Merge to HDR Panorama from the Camera Raw filmstrip. Photato finds complete brackets in capture order, fuses each position onto the same scene-linear exposure scale, then stitches the panorama. The editable DNG retains highlight values, transparency, crop and optional automatic tone settings.

The nine-photo test grouped three exposures per position and preserved 444 pixels above reference white, reaching a peak scene sample of 1.956. In the fixed-order Perspective reference, Photato developed a 733 × 364 crop and Adobe produced 731 × 363. The mean absolute linear RGB difference was 0.0535 over their overlapping opaque crop with the same Apple decoder.

Adobe Camera Raw 18.1.1 accepted three brackets with equal exposure offsets and different base exposures. The live Photato menu merged the same nine originals into a tenth filmstrip photo. Adobe reopened the saved Photato DNG and showed its editable exposure. All nine original files retained their hashes. [Adobe Camera Raw panorama workflow](https://helpx.adobe.com/camera-raw/desktop/hdr-and-advanced-output/create-panoramas.html).

The authenticated `raw.mergeHDRPanorama` download matched the DNG from the native workspace in the workflow test. The API accepts an optional bracket size and reports the command in its 302-entry catalogue.

Xcode built the app. All 54 focused application and imaging checks passed, including three added tests. Both optimized architectures passed all 429 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Larger brackets, real camera and moving-subject comparisons, and exact Adobe pixel and projection fidelity remain open. The working limits are 16 MP per exposure, 32 MP per bracket, 32 MP across the fused positions and 16 MP for the panorama.

The Universal ZIP targets macOS 14 and later. It contains 80,096,126 bytes with SHA-256 `c9b6374ac1fde1063a30d421c9449cb013534ea545c9195994b80b7d809f6377`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_817.json) · [Development record](DEVLOG.md#dev-step-817).
