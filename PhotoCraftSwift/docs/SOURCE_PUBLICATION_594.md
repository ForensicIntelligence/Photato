# Source checkpoint 594

Native Swift 0.3.0, build 594, 19 November 2026. The 1.5 px and 2 px vector-mask Feather settings now reproduce the measured Photoshop step and corner responses. The sampled Photoshop corner response fits two separable passes, with denominators of 256 in each pass. [Fixture provenance](../Tests/PhotoCraftImagingTests/Fixtures/provenance.json) · [Adobe vector mask property](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/).

The dense renderer, whole paged canvas and paged viewports agreed bit for bit on the tested alpha coordinates. The maximum residual from the independently decoded, normalized Photoshop RGB32 reference was 8.04e-07. Independent decoding of the RGB merged planes from editable PSD exports found 91,724 exact words out of 110,592, up from 67,371 in build 593. The regression set retained the earlier curved and inverted masks, PSD/PSB round trips, HTTP editing and Undo, and the 1,000 px large-canvas viewport.

All 905 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed offscreen checks and declare macOS 14 as the minimum. Full Photoshop composite bytes, other Feather settings, full dense capacity, and physical Intel and macOS 14 runtime checks remain open.

[Development record](DEVLOG.md#dev-step-594) · [Validation data](MEASURED_VECTOR_FEATHER_594.json).
