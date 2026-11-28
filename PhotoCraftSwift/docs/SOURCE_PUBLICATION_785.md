# Source checkpoint 785

Camera Raw Load Settings accepts XMP presets for sensor RAW and rendered RGB. Save Settings includes Camera Raw XMP and Photato JSON. XMP applies supported fields to the current draft, with preview and Undo. The sensor source remains editable and its original bytes are preserved.

Adobe Camera Raw 18.1.1 loaded both Photato presets. On the DNG the sensor white balance was 6800 K with tint −4 and Exposure +1.25. The rendered example retained Exposure −0.35 and relative temperature +31 and tint −24. Adobe re-exported 75 matching fields, including a custom curve point and vignette style. It omitted eight inactive subcontrols.

The authenticated Photato `cameraRaw.settings.convert` command converts XMP text and typed Photato settings in `raw` or `rendered` mode. `raw.develop` also applies XMP directly through the native redevelopment transaction. The Adobe Firefly input contract and the native document format are unchanged.

Xcode built the native app. All 5 focused workspace and authenticated HTTP tests passed. Both optimized architectures passed all 329 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The comparison covers settings values. Adobe and Photato rendering, automatic same-name sidecars, DNG-embedded settings, color profiles and local masks need separate testing and support.

The Universal ZIP targets macOS 14 and later. It contains 78,272,381 bytes with SHA-256 `2dc3f788c08eb62af40e5ebea3f9aac5ef5cef2e532ce458eea15f8cc1974e1f`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_785.json) · [Development record](DEVLOG.md#dev-step-785).
