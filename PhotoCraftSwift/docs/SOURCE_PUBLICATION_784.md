# Source checkpoint 784

Lossless layered TIFF and BigTIFF now reopen in Quick Mask mode when the mask was active at Save. The temporary mask stays editable. Composite opacity, saved alpha and spots retain their independent controls.

All 20,962 independent RGB16 auxiliary samples matched the Adobe references through both classic and BigTIFF saves. In a separate test, both apps opened a 19,000 × 19,000, 4.34 GB layered RGB16 BigTIFF with two editable raster layers, one saved alpha and one spot channel. LibTIFF verified distant strip samples and a first directory beyond 4 GiB.

Native open and save, both TIFF import paths and authenticated Photato download share the codec. The existing `tiffLayers` option selects layered output. Adobe v2 TIFF output fields remain unchanged.

Xcode built the native app. All 8 focused imaging and 5 focused app and HTTP tests passed. Both optimized architectures passed all 303 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

The active Quick Mask comparisons cover owned RGB16 references with and without composite opacity. Flattened copies omit the temporary mask. Whole-file equality, other Photoshop color and depth combinations, and a multi-gigabyte editable layer payload still need independent comparison.

The Universal ZIP targets macOS 14 and later. It contains 78,226,757 bytes with SHA-256 `3899ee7836802b8c06c67e809287d7550a6082938f66c835597496d8f83322bc`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_784.json) · [Development record](DEVLOG.md#dev-step-784).
