# Nested Photoshop Smart Objects on worker threads

19 November 2026 · Development preview 643

A layered PSD returned by the Execute Actions Smart Filter workflow could terminate a Debug worker when it opened an embedded PSD. Builds 640–642 hit the stack guard in nested document validation. The build 642 ARM64 decoder reserved 160,096 bytes of local stack per call.

Build 643 parses each PSD or PSB container before resolving its embedded Photoshop sources. The reader stores pending parent documents in an array and attaches each completed child before finalizing its parent. The ARM64 dispatcher reserves 2,112 bytes of locals. The parser's larger frame is active for one container at a time. Preserved checks include channel and merged-data validation, source size and dimensions, layer-comp selection, Smart Filter restoration, file identity and the existing eight-level nesting limit. Compiled stack comparison (local evidence) · [Adobe Smart Filters](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/apply-and-manage-smart-filters.html)

The first split passed the original API crash test. A new worker-thread test still hit the stack guard deeper in the tree. The final iterative reader passed the same API job, opened an eight-link chain of alternating PSD and PSB sources with the original source identifiers and bytes intact, and returned a recoverable error for a ninth link. The existing file rejection test now confirms that an editable ellipse round-trips and uses a triangle to exercise the unsupported-shape result. Targeted verification (local evidence) · [Photoshop file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)

Create Composite found a matching stack problem when the writer converted an embedded native source to PSB. The writer now prepares the linked data before entering the main container writer. The ARM64 wrapper uses 304 bytes of local stack, down from 190,240 bytes in the previous entry point. All four targeted tests passed on the final build, including Execute Actions and Create Composite with editable embedded resources. Final targeted tests (local evidence) · Compiled stack comparison (local evidence)

An independent check on the final build matched the previously qualified shape layers, their pixel masks and the merged preview byte for byte. The width edit retained its original mask in both formats. Independent file comparison (local evidence)

Two older large-file tests requested ZIP for the merged preview. The writer uses raw preview samples for that request, following the existing Photoshop-compatible output policy. The resulting fixtures exceeded the 64 MiB HTTP upload budget. Those tests now omit the optional preview while exercising the same editable layer, mask and Smart Filter paths. The product's import and transfer limits stayed the same. Initial integration log (local evidence)

The 40-megapixel PSB test passed over the real HTTP and desktop paths, including editing and undo. It checks both original corner colors and the zero mapped raster bytes used by the uniform source. 40-megapixel workflow test (local evidence)

The broader Debug run passed 94 of 95 tests. One external linked Smart Object test reports an exact cached-pixel mismatch in PSD and PSB. A separate build 642 Debug run failed the same test earlier in the operation with an unsupported-source error, so that run cannot establish whether the same pixel mismatch was present. The preview and stable-build qualification are still pending. Broader Debug results (local evidence) · Build 642 comparison (local evidence)

Build 644 reproduced the sample mismatch on both optimized 643 binaries and repaired it. Its broader Debug run included the nested PSD regressions and the exact linked-cache test. [Build 644 results](LINKED_PREVIEW_644.md)
