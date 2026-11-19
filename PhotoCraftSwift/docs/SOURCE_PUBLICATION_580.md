# Source checkpoint 580

Native Swift 0.3.0, build 580, 18 November 2026. Screen clips now participate in supported RGB8 and RGB16 merges and stamps. In-place stamps create an Undo step even when the stored pixels stay identical. The native editor, Photato HTTP API and both Adobe-compatible job routes share the tested operations. [Adobe layer commands](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

The saved-layer comparisons cover RGB8 and RGB16, with 24 small fixtures saved by Photoshop on both architectures and 12 larger references saved on Apple Silicon. Stored samples match for Merge Clipping Mask, Stamp Group and Merge Down on the first clip. Both Photato architectures are checked against the larger Apple Silicon references. A Photoshop shutdown problem prevented the larger Intel capture.

All 77 focused Debug methods and 765 selected methods per configuration passed. The extracted signed universal archive passed offscreen checks in both slices and declares macOS 14 as the minimum.

Adjacent upper clips, independent clipping, other blend modes, live keyboard dispatch and physical platform tests remain open.

[Developer record](DEVLOG.md#dev-step-580) · [Validation data and source fingerprints](SCREEN_CLIPPING_REFERENCES_580.json).
