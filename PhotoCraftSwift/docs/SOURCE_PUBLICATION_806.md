# Source checkpoint 806

Save Images exports selected photos from the Camera Raw filmstrip to TIFF, JPEG, PNG or PSD. It uses each photo’s saved draft, the current Camera Raw output and the native encoding settings.

Command-S opened the native Save Developed Images chooser. The selected owned RAWs produced two 512 × 384 RGB16 TIFFs. The existing TIFF kept its bytes and the new file received a numbered name. The two original DNGs kept their hashes.

The format bytes were compared with separately encoded Photato files. [Adobe Camera Raw processing and export workflow](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/navigate-open-save-images-camera.html).

Authenticated `raw.exportBatch` develops the selected embedded RAW layers and returns a ZIP. It uses the same output and encoding options as the desktop and keeps the shared document and its Undo history intact. The API checks transfer permission, revision and the ZIP budget.

Xcode built the app. Thirteen focused application checks passed. The new cases verify collision-safe desktop output and byte-for-byte TIFF comparisons between the authenticated download and separately encoded outputs. Both optimized architectures passed all 390 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

RAW filmstrip ratings, Grid, Stacks and Adobe output comparisons remain open. The authenticated ZIP uses the advertised transfer budget. Desktop export stages each file on disk.

The Universal ZIP targets macOS 14 and later. It contains 79,347,880 bytes with SHA-256 `ac10889b777d8879fb5471634c02b65ffaa220677be717000d064e915b9cbb9c`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_806.json) · [Development record](DEVLOG.md#dev-step-806).
