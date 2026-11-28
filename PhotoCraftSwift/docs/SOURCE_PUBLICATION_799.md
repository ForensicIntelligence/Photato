# Source checkpoint 799

Camera Raw can use an XMP preset that varies supported numerical adjustments with the source photo’s ISO. Select it as the master or a camera override. The Sensor panel shows the recorded ISO when available.

Adobe Camera Raw 18.1.1 generated the reference with Exposure 0 at ISO 400 and +2 at ISO 1600. Photato opened the synthetic ISO 800 DNG with Exposure +1. Adobe’s Load Settings command used the fixed top-level values on the Adobe reference. Photato keeps that fixed behavior in its separate Load Settings command.

Adobe documents a midpoint of 5 for Luminance Noise Reduction at ISO 800 when the endpoints are 0 at ISO 400 and 10 at ISO 1600. [Adobe ISO-adaptive preset documentation](https://helpx.adobe.com/lightroom-classic/desktop/help/iso-adaptive-presets.html).

Authenticated `/v1/preferences/camera-raw` accepts adaptive preset XMP in its existing revisioned `rawDefaults` object. Use `X-Photato-Raw-Defaults: desktop` for RAW uploads that should apply it. `raw.inspect` reports ISO when recorded. Uploaded explicit XMP and stored image adjustments retain priority. The capability response describes the adaptive preset path.

Xcode built the app. All three new tests and nine related tests passed, covering EXIF ISO, endpoint clamping, the documented midpoint, fixed XMP overrides, validation and matching Photato raster samples. Both optimized architectures passed all 374 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Creating adaptive presets from a Photato filmstrip, adaptive categorical adjustments, and byte-identical Adobe RAW output remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,846,500 bytes with SHA-256 `558ad42c1905df32232e7e121bfc5340d75c07b2324456fe5ac7740757e415e1`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_799.json) · [Development record](DEVLOG.md#dev-step-799).
