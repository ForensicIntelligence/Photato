# Source checkpoint 567

Native Swift 0.3.0, build 567, 18 November 2026. Promoting an 8-bit or 16-bit RGB or grayscale document to 32 bits now uses the supported tone curves from its current ICC profile.

The shared Swift path promotes integer samples through their ICC transfer curves. It uses a 15-bit working domain for nonlinear curves and stores a linearized version of the source profile. Sampled curves use a 4,097-point Float32 table. Power and the tested parametric curve use the measured direct or interpolated path. Explicit different destination profiles, other intents, and unsupported curves retain the existing ColorSync path.

All 1,976,832 samples from 54 supported cases match the files saved by Photoshop 2026 byte for byte on both tested architectures, using a separate Photoshop run on each architecture. Photoshop itself returned different values across architectures for 13,057 samples from the gamma and parametric cases. The Swift conversion matches the rounding observed on each architecture.

All 651 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The desktop conversion and the authenticated Photato command produce the same stored samples and both Undo correctly. Both universal app slices passed offscreen checks.

The comparison covers opaque, same-mode precision promotion. Cross-mode color conversion, arbitrary color profiles, other rendering intents, transparent sample parity, and full PSD file identity still need testing. The app’s gamma 0.5 conversion remains open. A standalone Swift probe matched all 32,896 saved samples on each architecture and provides a reference for integrating that special case.

[Development record](DEVLOG.md#dev-step-567) · [Validation data](SDR_TO_HDR_CONVERSION_567.json) · [Frozen source](SOURCE_SNAPSHOT_567.json)
