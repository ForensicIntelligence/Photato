# Source checkpoint 808

Camera Raw can show a photo’s filename, format, size, camera, lens, capture time, caption and copyright. Sort by capture date, file type, camera or lens without changing the selected photos.

The native workspace sorted two owned DNGs by their actual capture instants across different time zones. Their displayed wall times run in the opposite order. Both originals remained byte-identical after inspection and sorting.

The field list follows Adobe’s Photo Info documentation. [Adobe Camera Raw overview](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html).

The authenticated `raw.inspect` response now includes `photoInformation` for an eligible RAW source. Reading it leaves the document revision and Undo history intact.

Xcode built the app. All eighteen focused application tests passed. Both optimized architectures passed all 395 selected tests. Intel ran under Rosetta. Both Universal slices rendered offscreen.

The tests used owned DNGs and the authenticated HTTP endpoint. Photo Info’s layout and sorting were not compared against Adobe’s newer full Grid workspace. Grid, Stacks and Adobe renderer comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 79,538,906 bytes with SHA-256 `86d23c8d0a736ee2e084dd7c8f21567da9a2eec39a260961483122f4dcfdcbb8`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_808.json) · [Development record](DEVLOG.md#dev-step-808).
