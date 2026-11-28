# Source checkpoint 773

Photato writes editable TIFF layers to disk past the former 512 MiB layer limit. Native Save and Save a Copy use the staged writer with either small or paged merged images.

Two little-endian RLE TIFF saves retained 40 editable layers. Each carried 628 MB of editable layer data. An independent reader matched all 614.4 million authored RGB and opacity samples on each file, and Photato reopened both with layer names, positions and visibility intact. Sixteen small layered TIFF variants were identical between file and Data output and reopened with their saved selections.

Photato save commands use the native staged output. Authenticated TIFF downloads still use bounded Data and can retain layers when requested. The Adobe-compatible TIFF output schema stays flat and keeps its documented options.

Xcode built the native app. All 12 focused imaging and 8 app and HTTP tests passed. Both optimized architectures passed all 248 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

The capacity controls cover classic TIFF with editable RGB8 layers. Near-limit files, unsupported Photoshop descriptors, tiled input and broader direct Photoshop comparisons still need qualification.

The Universal ZIP targets macOS 14 and later. It contains 78,129,613 bytes with SHA-256 `751507ee737444b32695cb8ed693657fb6c7b75e7e205c2a52e6648ee41ee0f6`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_773.json) · [Development record](DEVLOG.md#dev-step-773).
