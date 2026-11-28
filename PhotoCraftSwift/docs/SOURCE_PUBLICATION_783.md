# Source checkpoint 783

Save Transparency off now uses Photoshop’s RGB16 working grid for aligned Normal raster layers. Layer opacity is promoted before compositing. The white matte is applied to the merged image, and layered output keeps the original editable RGB16 pixels and opacity.

Independent libtiff decoding matched all 82,557 distinct RGB16 samples in two Photoshop 27.2 patterned files and the earlier spot-only copy. The latter also matched all 2,881 spot samples. The patterned files match through classic and BigTIFF output, including the tested planar ZIP variant. A separate opaque Debug benchmark saved byte-identical files and took 15.60 seconds versus 25.62 seconds on the same host.

The native TIFF Save Transparency control and the existing Photato `tiffTransparency: false` option share the calculation. Authenticated downloads match native file bytes. Adobe-compatible resource input uses the existing TIFF reader. Adobe v2 output fields remain unchanged.

Xcode built the native app. All 7 focused imaging and 4 focused app and HTTP tests passed. Both optimized architectures passed all 301 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The measured path covers aligned Normal RGB16 raster layers without masks. Other blend modes, masks, transformed or grouped layers, and full Photoshop file serialization still require independent comparison.

The Universal ZIP targets macOS 14 and later. It contains 78,225,407 bytes with SHA-256 `a20857b499ed90a57b1807d9dcbbaaa4c7cf190de0ee1e7e4fdf746dd33fe265`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_783.json) · [Development record](DEVLOG.md#dev-step-783).
