# Source checkpoint 788

Camera Raw’s Done button now saves changes into a locally opened DNG and closes the editor. If the image opened with an XMP sidecar, Photato embeds its metadata and backs up the sidecar before removing it when required by the sandbox. The source sensor bytes stay intact.

Photato and Adobe Camera Raw 18.1.1 saved Exposure +1.75 in the DNG sidecar test and preserved all 393,216 sensor bytes. Adobe reopened the updated Photato DNG. Photato also retained the separate sensor exposure through its own embedded settings.

The authenticated `raw.saveSourceSettings` command requires the original DNG layer, a current revision and the native Allow local document saving option. It uses the same coordinated write, checks for external changes and retains editor history and source layer bytes. A sandbox denial returns an error and rolls back the DNG if the output still matches the staged version.

Xcode built the app. Three focused imaging tests and one authenticated HTTP test passed. Both optimized architectures passed all 340 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

This covers the tested classic DNG settings. Other RAW sidecar writing, camera-specific defaults and settings databases, DNG preview regeneration, physical Intel testing, and pixel-level Adobe Camera Raw equivalence remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,450,774 bytes with SHA-256 `04eeada7fe6120a4269afe2aee09d9d6f0e03f26abd24b48ced9419e43350fe3`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_788.json) · [Development record](DEVLOG.md#dev-step-788).
