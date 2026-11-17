<a id="dev-step-528"></a>

## 2026-11-17 — Open JPEG XL still images

Adobe lists JPEG XL among its supported 32-bit Save As formats. A source audit found that Photato's File > Open selector, document declarations and upload types did not advertise JPEG XL. The installed macOS 27.2 reader identifies both a raw bitstream and a container. The installed system format list lists reading only, so export and its settings require separate work.

JPEGXLInput.swift records the two signatures and queries the system reader at runtime. RasterIO.swift uses the installed ImageIO decoder, checks the decoded size before image allocation, rejects incomplete input and rejects multi-image sources reported by ImageIO. DocumentOpenFormat.swift, DocumentIO.swift and the bundle declaration expose the still format to native Open. The active reader controls the Open selector, readable type list and HTTP import format/capabilities. POST /v1/documents/import accepts image/jxl or an explicit jxl format header for an octet-stream body. Existing transfer permissions, native archive saving and supported export formats apply. The app adds no Adobe API methods for this source format.

The desktop budget is 1 GiB of estimated RGBA raster data, with a 128 MiB API admission check. Those are decoder-specific budgets. Other document formats maintain their existing limits. JPEG XL layer, animation, profile, fractional alpha, HDR and write fidelity need dedicated coverage.

The fixtures use two owned 7×5 sample grids. cjxl 0.12.0 produced a lossless RGB8 raw stream and an RGBA16 container. djxl decoded both, and an independent PNG reader matched all 280 authored sample words to the manifest. libjxl is a fixture tool outside the application. JPEGXLImportWorkflowTests.swift verifies format discovery, file signature despite extension, exact native samples, new document ownership, archive Save As, typed/untyped HTTP import, permissions and mismatch/truncation rejection.

Reference: [Adobe Photoshop file format overview](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/photoshop-file-formats-overview.html) and [Apple ImageIO format discovery](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_basics/ikpg_basics.html), consulted 17 November 2026.


The initial combined Debug run passed 67 of 68 tests. The three new JPEG XL tests passed, including all 280 sample values and the native archive round trip. The failure was a prior archive API test expecting version 87 to return HTTP 400. The same assertion fails on the retained build 526 binary. The production archive supports version 87 and newer versions through 92. DocumentIOWorkflowTests.swift now checks that 87 successfully returns exact decodable bytes and uses 93 as the unsupported upper-bound example. The remaining corruption and history assertions are retained.

An independent two-frame JPEG XL probe identified a data-loss risk: on this host, ImageIO reports one image and no animation for the encoded two-frame input. JPEGXLInput.swift now inspects the initial codestream metadata before decoding. It reads at most 32 bytes of codestream data and supports complete streams and ordered container fragments. Animated files are rejected before either the native or HTTP path can silently reduce them to one frame. JPEGXLImportWorkflowTests.swift exercises the same animation in raw, boxed and fragmented form. The earlier program and test binary are retained in the Debug01 evidence. Debug02 stopped at the whitespace preflight before launching a compiler. The trailing space came from removing an earlier diary status sentence. Debug03 resumes the same native inputs.

Codestream size fields and the animation flag were cross-checked against the public JPEG XL reference implementation: [size and preview header](https://github.com/libjxl/libjxl/blob/v0.12.0/lib/jxl/headers.cc) and [image metadata](https://github.com/libjxl/libjxl/blob/v0.12.0/lib/jxl/image_metadata.cc). The Swift reader only checks the header. ImageIO decodes the samples.


Debug03 passed the archive-version test and the three still-image cases. The new animation test failed before invoking the decoder because its fixture extractor assumed a complete jxlc box. The original cjxl animation has two jxlp boxes. Debug04 corrects the fixture extraction and exercises the original file, reconstructed raw and complete-box forms, and a deliberately short first fragment. The HTTP guard now also receives the independently verified animation. Production inputs remain byte-identical to Debug03. Both test binaries and the unsuccessful assertions are kept separately.


Debug04 passes all 69 selected methods, including eight new methods across 527–528. No skips or signals are reported. The application executable matches Debug03 by SHA-256, confirming the final animation fixture correction is test-only. The exact 280-sample still comparison and animation rejection pass.

The installed Adobe Photoshop 2026, version 27.2.0, launched into its application window. Its native Open dialog resolved the fixture folder, but confirming the path reset the chooser field instead of opening it. No image opened and no Photoshop output was collected. Public Adobe documentation and the independently decoded fixture words support separate parts of the evidence.

Combined build 528 passes all 69 selected methods, including eight new tests, in Debug, optimized Apple Silicon and translated Intel. The universal candidate passes macOS 14 metadata, signature, entitlements, native resource, executable payload and extracted archive checks. The optimized timing table, reference limitations and source hashes are in [Source checkpoint 528](SOURCE_PUBLICATION_528.md).

The universal validation package passed its static and round-trip checks. Native desktop automation expired before returning a launch state for build 528. Live Photato interaction and normal Quit remain unverified.
