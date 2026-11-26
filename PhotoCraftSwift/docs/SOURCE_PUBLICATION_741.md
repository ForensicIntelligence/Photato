# Source checkpoint 741

Photato saves editable Vanishing Point folds in PSD and PSB using the orientation observed in Photoshop's own files. Photoshop reopened the newly written 45° PSD, 135° PSB and 90° files at their intended angles. Photato reads either oblique guide with the same off-centre camera as the related 90° guide. A separate oblique PSD recovered a focal length of 5,593.261 pixels, within 0.008 pixels of the independently fitted Photoshop VPE camera.

At 45°, 90° and 135°, unedited Photoshop guide records and all 3,240,000 merged RGB bytes survived native PSD and PSB round trips. All ten re-authored test files reopened in Photato. A right angle with a nearly parallel seam needed the earlier canvas-centred camera fallback to account for the finite-ray approximation. The checked-in Xcode project built, all 26 focused Core checks and 17 App and HTTP checks passed.

The linked Marquee replay on the corrected guide matches the horizontal patch extent to one pixel on the measured row. Interior samples and edge coverage still differ with and without Feather. Camera calibration on other parallel seams, other hinge orientations and exact scene and raster output remain open.

Both optimized architectures passed 857 of 859 selected tests. The two inherited color-profile and layer-effect tests repeated the same diagnostics as build 740. All twenty tested PSD and PSB outputs match byte for byte across Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed preview target macOS 14 and opened offscreen on macOS 27.2.1.

Build inputs **9,429**. Source digest `72ea6f8abee0f1dae28146c2489ae8b19ed25d5b07ecdea92169e4da466be979`. Local preview SHA-256 `ee5d67b81dc63d7a6ff0165545c8e1d9332ac1d17baec4ac8906948f1afc8bb4`.

[Development record](DEVLOG.md#dev-step-741) · [Evidence hashes](SOURCE_PUBLICATION_741.json) · [Photoshop reference observations](VANISHING_POINT_REFERENCES.json).
