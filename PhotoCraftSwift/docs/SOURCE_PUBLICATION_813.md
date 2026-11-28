# Source checkpoint 813

Select two or more RAW brackets and use Merge to HDR. The preview supports alignment, automatic exposure, three deghost strengths and an overlay. The result returns to the filmstrip as an editable DNG.

Option–M opened the preview on three owned brackets, and Option–Shift–M opened the destination picker. The regular merge added a fourth photo and preserved all source bytes. Adobe Camera Raw rendered a Photato-generated linear DNG and allowed exposure edits. Native and authenticated API DNG downloads matched byte for byte with identical inputs and settings.

Adobe Camera Raw 18.1.1 confirmed Align Images and Apply Auto Settings as initial defaults, with Deghost Off. [Adobe Camera Raw shortcuts](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/default-keyboard-shortcuts.html).

Authenticated `raw.mergeHDR` takes distinct shared RAW Smart Object layer IDs plus optional `align`, `autoSettings` and `deghost`. It downloads `image/x-adobe-dng` and leaves source documents and Undo unchanged.

Xcode and forty focused application and imaging tests passed, including the ten existing HDR merge workflow cases. Both optimized architectures passed all 415 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The merge kernel reuses Photato’s photographic HDR engine. Automatic settings currently embed a single calculated exposure adjustment. Adobe’s result used JPEG XL and multiple tone adjustments. The tested decoded RGB samples and complete file bytes differ from Adobe’s result. RAW-specific fusion, larger brackets and exact render parity remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,827,161 bytes with SHA-256 `54a9ac8dcf247920a8568d6b627067ca00f62b1e799091986a6b1b6710b31237`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_813.json) · [Development record](DEVLOG.md#dev-step-813).
