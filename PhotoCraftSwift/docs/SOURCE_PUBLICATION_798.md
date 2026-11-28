# Source checkpoint 798

Camera Raw Settings can apply Photato Default, Camera Settings or an XMP preset to new RAWs. Rules can match a model or a specific body serial number. Open and Place use the saved choice. Existing sidecar and embedded adjustments take priority.

The signed native app added a camera model from the synthetic Bayer DNG, loaded an XMP preset and opened the RAW with Exposure +1.25. The Sensor panel showed the camera decoder’s 0.9 shadow boost. Cancelling kept the original DNG bytes and created no companion XMP.

Adobe Camera Raw’s documented Raw Defaults include master, model and body overrides, plus presets. Photato exposes the native decoder’s supported sensor defaults under Camera Settings. [Adobe Raw Defaults](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/acr-raw-defaults.html).

Authenticated `GET` and `POST /v1/preferences/camera-raw` include the revisioned `rawDefaults` object. Send `master`, `useOverrides` and `rules` to replace the whole policy. Each choice has a `mode` of `photato`, `camera` or `preset`. A preset includes a `name` and base64 `xmp`. Each rule contains a `camera` with `make`, `model` and optional `serial`, plus its `choice`. Camera RAW uploads opt into desktop defaults with `X-Photato-Raw-Defaults: desktop`. Explicit upload XMP and embedded settings take priority. Desktop defaults are exposed through the Photato API.

Xcode built the app. All three new focused tests and six related tests passed, covering RAW Open and Place raster equivalence, stored settings, revision conflicts and authenticated upload precedence. Both optimized architectures passed all 371 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Camera Settings still differs from the Adobe reference at 18,044,832 of 18,048,000 Nikon RGB16 samples. Both TIFFs use the same dimensions, RGB16 sRGB profile and 300 ppi and were exported without output sharpening.

ISO-adaptive presets, Adobe camera profiles and byte-identical Adobe RAW output remain open. The built-in batch import workspaces still use their existing import policy.

The Universal ZIP targets macOS 14 and later. It contains 78,829,180 bytes with SHA-256 `4e025432a334f15ada5c67e7d9439e49396d4c8b2c903206f3de522bf0bc26dc`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_798.json) · [Development record](DEVLOG.md#dev-step-798).
