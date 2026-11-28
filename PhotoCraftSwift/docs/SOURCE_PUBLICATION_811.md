# Source checkpoint 811

Done saves the changed photos across the Camera Raw session, including photos currently deselected or filtered out. Photato leaves files with unchanged settings and marks untouched.

Adobe Camera Raw 18.1.1 wrote a four-star rating and a red label to an owned DNG after a different photo was selected. The selected, unedited original was byte-identical. A Photato test reproduced those XMP values when a filter left no visible selection and verified the original sensor payload and unedited file bytes.

The live Adobe comparison tested Done and inspected both file hashes and XMP fields after closing the dialog. [Adobe Camera Raw save workflow](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

The authenticated source-settings API continues to save the explicitly authorized single RAW source. The change applies to Done in the native multi-photo workspace.

Xcode built the app and all twenty-two focused application tests passed. Both optimized architectures passed all 399 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

Open Image and Open as Object have their existing selected-photo behavior. Adobe’s persistence rules for deselected photos when opening images, and the dedicated Hide Photo controls, still need separate qualification.

The Universal ZIP targets macOS 14 and later. It contains 79,631,061 bytes with SHA-256 `5e84cd62ee979557c8d886b601c42686aaf716d67664a3562d29a625e632592e`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_811.json) · [Development record](DEVLOG.md#dev-step-811).
