# Source checkpoint 710

Native Swift 0.3.0, build 710, 2026-11-21.

After Remove Background, the contextual bar and Properties offer Background Color and Import Background. Photato adds an editable Solid Color layer or an embedded Smart Object below the masked subject. Import supports Fill Canvas, Fit Inside Canvas and Original Size. Both actions work without a model and take one Undo step.

Desktop and Photato HTTP edits produced identical RGBA8 samples and preserved the subject layer. Solid Color remained editable through native, PSD and PSB round trips at RGB8, RGB16 and RGB32. Imported artwork retained the original bytes and exact rendered samples in all three formats for the tested placement modes. A 300,000 × 8 PSB reopened through the native file opener with opaque outer edges and the unmodified subject mask. Four 576 × 376 PSD and PSB merged previews matched all 3,465,216 RGBA bytes in the corresponding PNGs using an independent reader.

526 of 527 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The known layer-effect fixture repeated the same 118 assertions from build 709 in each configuration. Xcode built the app and both signed preview slices opened offscreen. A signed sandbox harness wrote both editable background types. The preview retains the exact People Parts and Local Upscale resources from build 709. All 19 Apple Intelligence background tests and all 12 foreground workflow tests passed, including the Adobe-compatible colour output. The 1,000 × 650 native workspace snapshot showed all three background controls with the subject’s mask thumbnail selected.

Installed Photoshop identified itself as 27.2.0. Its scripting interface timed out on both owned reopen probes and a read-only JavaScript version probe. Photoshop reopening, reference placement and interpolation fidelity, interactive colour panel and Import dialog behavior, and non-RGB contexts still need qualification. The editable background placement marker is supported starting with Photato build 710. The manual background workflow has no dedicated Adobe v2 route in the referenced contract. The existing Adobe-compatible remove-background colour output and create-composite layer operations remain available.

[Adobe desktop background workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/replace-background-with-generate-background.html) · [Adobe Photoshop file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/getting-started/v2-ga/)

[Background controls](LOCAL_GENERATIVE_FILL.md#use-colour-or-an-imported-image) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_710.json)
