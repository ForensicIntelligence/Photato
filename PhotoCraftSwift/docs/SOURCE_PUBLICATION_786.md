# Source checkpoint 786

File Open and Place Embedded now read a same-name RAW XMP sidecar. If there is no usable sibling, Photato uses supported settings embedded in the source. The resulting RAW Smart Object retains the original sensor bytes and the chosen settings.

Photoshop Camera Raw 18.1.1 loaded the embedded DNG at Exposure +0.75 and Contrast +21. With a partial sibling it loaded Exposure +1.25 and left Contrast at the default 0. The sandboxed Photato app opened the same RAW file, selected by itself in the file picker, and reproduced that settings precedence.

Authenticated Photato RAW upload accepts base64 XMP through `X-Photato-Raw-XMP` up to 8 KiB decoded. An explicit packet supplies the initial settings. A RAW upload without that header uses embedded settings if present. The Adobe Firefly request contract is unchanged.

Xcode built the native app. All 3 focused workflow and authenticated HTTP tests passed. Both optimized architectures passed all 332 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

This compares opening settings and retained RAW source bytes. Pixel-level Camera Raw equivalence, writing settings back to DNG, automatic sidecar writes, and broader sensor models remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,279,671 bytes with SHA-256 `aaf9a6b5f8bd14bd3d64f492b6b3283fcafd827aad8227645bc014d711be5d52`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_786.json) · [Development record](DEVLOG.md#dev-step-786).
