# Source checkpoint 790

Camera Raw settings now control whether a local DNG writes XMP inside the source, writes a sibling, or opens and saves embedded settings while leaving the sibling alone. The default honors an existing companion before saving settings in the DNG.

The installed Adobe Camera Raw 18.1.1 File Handling panel exposed the three DNG Sidecars choices and selected embedded XMP by default. The signed Photato replay wrote +1.75 to a new sibling and kept the DNG byte-identical. The embedded-only mode read +0.75 from the DNG despite a sidecar at +2.50. After saving +0.50 in the DNG, the companion and source sensor payload stayed byte-identical. Adobe read Photato’s DNG sidecar at +1.75 and the embedded-only copy at +0.50.

Authenticated clients can read `GET /v1/preferences/camera-raw` and update it with a revision and `dngStorage` by POST. The values are `embedXMP`, `sidecarXMP` and `ignoreSidecarXMP`. Updates use the existing native file-preference permission. A local source captures the choice when it opens, and `raw.saveSourceSettings` honors that choice even if the application preference later changes.

Xcode built the app. Nine focused imaging cases and two app and HTTP cases passed. Both optimized architectures passed all 349 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Embedded preview regeneration, camera-specific defaults, Camera Raw database routing, physical Intel testing and exact Adobe render equivalence remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,508,764 bytes with SHA-256 `c028cb207bb01bd0051f9c9404ef6af97345ef560f5131aa9ffa13ae3e189b06`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_790.json) · [Development record](DEVLOG.md#dev-step-790).
