# Source checkpoint 775

Save Image Pyramid is available for classic RGB, Grayscale, CMYK and Lab TIFFs. Photato saves three smaller previews alongside the original image and optional editable layers.

The native compact writer matched all 3,945,867 reduced RGB8 samples in three Photoshop 27.2 references, with matching dimensions, density and primary pixels. The staged writer separately matched all 776,832 preview samples on its reference. An Adobe two-pixel control also kept three one-pixel previews. Photoshop opened the Photato wide output at full document dimensions.

The native save accessory and Photato encoding options share the pyramid writer. The HTTP download matched the expected TIFF. The Adobe wire schema retains its published fields.

Xcode built the native app. All 2 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 255 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

Direct Photoshop sample comparisons cover opaque RGB8. Wider HDR, profile, alpha and component-mode comparisons, Indexed/Bitmap pyramids and complete file-layout equivalence remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,158,212 bytes with SHA-256 `4725bcc41aceb44cd98d75212a7f5a1387fd37fc1a12b0f425547821fdb0f9bd`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_775.json) · [Development record](DEVLOG.md#dev-step-775).
