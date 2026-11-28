# Source checkpoint 805

Select several Camera RAW files in File → Open to edit them together. The filmstrip keeps an independent settings draft for each source, applies changed controls to the selection, and copies chosen settings groups from the active photo.

Command-A selected the three owned DNGs. Option-S opened Synchronize Settings, and Command-Option-O opened three editable RGB16 Background tabs. The RAWs and existing sidecar kept their original hashes. The focused tests also check selected-copy pixels, Undo and Redo, and atomic API validation.

The selected and active controls follow the documented Adobe multi-image editing workflow. [Adobe Camera Raw filmstrip](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Authenticated `raw.synchronize` takes a source layer or explicit settings, a list of RAW target layers in the shared document, and settings groups. The entire edit uses one Undo step. Unsupported sensor options and decoder identity stay with each target.

Xcode built the app. All eleven focused application tests passed. Both optimized architectures passed all 388 selected cases, including the filmstrip and authenticated API checks. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The filmstrip opens when every selected file is Camera RAW. Batch developed-image export, rating and stacking controls, and the direct Adobe pixel comparison remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,296,136 bytes with SHA-256 `5afe46c8ced9fd197e0bb21f931e4a47c0f0e7022791dea6634cb4c3e3f5bed3`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_805.json) · [Development record](DEVLOG.md#dev-step-805).
