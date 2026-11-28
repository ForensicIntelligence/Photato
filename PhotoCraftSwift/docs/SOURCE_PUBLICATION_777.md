# Source checkpoint 777

TIFF Save and Save a Copy can use JPEG compression for opaque RGB8 and Gray8 images. Choose JPEG Quality from 0 through 12. Supported editable layers, profiles, storage orders and optional reduced-resolution previews are preserved.

Independent libtiff decoding opened the three JPEG TIFF outputs. Photoshop 27.2 reopened the grayscale TIFF and both RGB8 files with their editable overlay selected in the RGB cases. Photato produced identical file and Data output for the tested job. Quality settings changed the compressed bytes and the TIFF records the native encoder’s chroma layout. Photato also reopened 1 × 1 with all 13 settings and 30,000 × 33 at three settings.

Photato commands and downloads share the native TIFF writer. Set tiffCompression=jpeg and optionally tiffJPEGQuality=0…12. Authenticated download and document.saveAs use the same compression path as the native editor. The Adobe wire schema retains its published fields.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 263 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

JPEG changes the composite samples. Choose lossless compression to keep named selection channels. The exact Photoshop quality curve, JPEG output bytes and decoding differences remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,177,672 bytes with SHA-256 `a1d3b6a1d31ab23f8dbadfdaf2fccb383690d8d4962f280b98c594d1a17cad23`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_777.json) · [Development record](DEVLOG.md#dev-step-777).
