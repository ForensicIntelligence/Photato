# Source checkpoint 664

Native Swift 0.3.0, build 664, 20 November 2026.

Photoshop document manifests can include JPEG or PNG layer previews and exact copies of embedded Smart Object originals. The assets use Photato's authenticated local download URLs.

1,502 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

The manifest tests verified PNG crop geometry, thumbnail nesting, blank adjustment previews, JPEG frames, exact PSB Smart Object bytes, shared-instance URLs, authorization, expiry and the combined storage budget.

Direct Adobe-hosted comparison of thumbnail geometry, defaults and bytes remains open. The native encoder chooses its progressive JPEG scan count. Intel tests ran under Rosetta.

[Development record](ADOBE_MANIFEST_ASSETS_664.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_664.json)
