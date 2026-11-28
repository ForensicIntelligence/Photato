# Source checkpoint 794

Camera Raw offers Open Image, Open Object and Open Copy. Image and Copy create an editable Background. Object retains the embedded sensor data and editable development settings. Image and Object save source settings using the current file policy. Copy leaves the original and its sidecar intact.

Photoshop 2026 with Camera Raw 18.1.1 and the signed Photato test app opened identical Nikon inputs as 3,008 × 2,000 RGB16 documents. Command–O and Shift–Command–O saved +1.00 and +0.75 Exposure to matching sidecars. Option–Command–O opened +1.50 with no sidecar. All original NEF bytes stayed identical.

Send `X-Photato-Raw-Open-Mode: image|object|copy` to `POST /v1/documents/import`. Image and Copy create a Background. Object remains the upload default so existing clients retain embedded source data. All upload modes keep their inputs in memory. `GET /v1/preferences/camera-raw` exposes `openAsSmartObject`, and authorized revisioned POST can update it on its own or with `dngStorage`.

Xcode built the app and all five focused tests passed. Coverage includes exact stored RGB16 samples, current integer raster rounding, aborting a stale source write, protected original files, and authenticated API behavior. Both optimized architectures passed all 361 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Photoshop output ICC, dimensions, sharpening, and full pixel/file equivalence remain open. Photato’s current RGB16 compositor applies integer Normal rounding to Background layers, while eligible RAW objects can retain the original decoded values.

The Universal ZIP targets macOS 14 and later. It contains 78,597,980 bytes with SHA-256 `ddc52c1690f09be3284c297fa5a2c9404d586b6981af7144a997cef1ba4feba1`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_794.json) · [Development record](DEVLOG.md#dev-step-794).
