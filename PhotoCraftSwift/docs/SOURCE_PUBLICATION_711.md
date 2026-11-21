# Source checkpoint 711

Native Swift 0.3.0, build 711, 2026-11-21.

Harmonize adds Subtle, Balanced and Ambient colour, tone and contact-shadow variations for a pixel subject over a background. Use the contextual bar, Layer menu or Properties. The original subject and mask are retained. The group contains ordinary editable Curves and separate shadow layers. Properties switches alternatives and each change can be undone.

The native editor and Photato HTTP commands produced the same RGBA8 results from a selected pixel mask. All three variations and rendered samples survived native, PSD and PSB reopening in the RGB8, RGB16 and RGB32 test fixtures. On the 1,024 × 1,024 project mascot, all three formats reopened with identical rendered bytes. The independent reader matched all 8,388,608 merged RGBA bytes in the two Photoshop-format files to the PNG. A 300,000 × 28 file retained the original mask, editable variations and matching sampled regions through native and paged PSB reopening.

530 of 531 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same existing layer-effect reference method repeated its 118 assertions from build 710 in each configuration. The checked-in Xcode project built. Both signed preview slices opened offscreen and retain the previously bundled model assets. The native Properties variation picker was checked in a 1,300 × 800 offscreen workspace. The Layer menu binding was verified with no shortcut and with the command disabled when there is no eligible document.

Harmonize estimates the adjustment and shadow locally. Adobe documents its separate Firefly model. No corresponding public Harmonize request schema was found in the pinned Photoshop v2 contract. The installed Photoshop reported 27.2.0, but its document scripting timed out. Firefly output equivalence, direct Photoshop reopening, and live keyboard and assistive technology checks remain open.

[Harmonize in Adobe Photoshop](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/blend-subjects-with-harmonize.html) · [Adobe model inventory](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/guides-v2/execute-actions-models) · [Photoshop file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

[Harmonize guide](HARMONIZE.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_711.json)
