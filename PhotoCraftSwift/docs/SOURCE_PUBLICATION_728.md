# Source checkpoint 728

Vanishing Point opens from the ready editor composite when it matches the current document. A local correction on a plain top pixel layer updates only its coverage. Apply commits the prepared preview as one editable history step.

The 24-megapixel native canvas kept its full-resolution preview. The 48-megapixel case used a 2,048 × 1,536 overview. Both edited preview buffers matched their independent full renders. Local Undo restored the earlier preview. Apply kept the accepted layer ID, and the authenticated API produced the same selected crop. Protecting the source, native save and reopen, and document Undo also passed.

The first 24-megapixel edit from a cold workspace took 1.49 s on Apple Silicon and 2.88 s under Rosetta. The adjacent build 727 measurements were 2.94 s and 5.26 s. With the editor composite ready, the first 24-megapixel stamp took 519 ms on Apple Silicon. The second edit preview took 1.2 ms. The first edit in the 48-megapixel overview took 64 ms.

820 of 822 selected tests passed on each optimized architecture, with Intel tested under Rosetta. All four new regressions passed on both architectures. The existing layer-effect and color-profile fixtures repeated their earlier differences, and the paired color-profile outputs matched build 727 byte for byte. Xcode built the project, all 28 focused Debug tests passed, and both signed macOS 14+ slices opened offscreen.

The 48-megapixel repair used the same explicit camera projection as the 24-megapixel control. A narrow stamp on the larger fixture with default camera inference produced no sampled correction in builds 727 and 728. Its projected footprint and direct Photoshop output still need qualification. The timings measure software preview publication on one host. [Adobe Vanishing Point Stamp workflow](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/paint-in-vanishing-point.html)

Build inputs **9,423**. Source digest `c5f045d750982b2d41d7fae59a711abe28b6f07e87f98d302b93ce66b1ab2067`. Local universal preview SHA-256 `d1af45ffba6f58aabfcb3835ad6edd6371b0d6ab3b1f27e87f7fb101105ffd23`.

[Retouch guide](RETOUCH_SAMPLE_REUSE.md) · [Development record](DEVLOG.md#dev-step-728) · [Evidence hashes](SOURCE_PUBLICATION_728.json)
