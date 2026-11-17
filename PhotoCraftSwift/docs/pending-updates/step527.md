<a id="dev-step-527"></a>

## 2026-11-17 — Save format checks on large documents

Work resumed from public source build 526, commit 02c3597. The save format audit found that deciding whether a flat image could be saved as JPEG scanned every stored pixel on each call. Save As and the HTTP document summary each requested the same eligibility list twice. Opaque OpenEXR used the same uncached scan when transparency was disabled.

The save policy now uses the raster engine's existing exact opacity proof for JPEG and OpenEXR. The cold check reads each tile through a single buffer and excludes invisible edge padding. Alpha edits invalidate the proof through the existing copy-on-write rules. Save As reuses one filtered list and HTTP derives its filtered list from the already computed writable formats. This applies to Photato's current Save As and optional API without adding commands or changing the Adobe API contract.

Changes cover Surface.swift, DocumentSavePolicy.swift, SaveDialogFormats.swift, NativeDocument.swift, AutomationService.swift, AutomationDocumentSaving.swift and build metadata in scripts/Info.plist. SaveOpacityResponsivenessTests.swift checks owned and mapped storage, edge padding, copy-on-write invalidation, JPEG and OpenEXR admission, native/HTTP state after Undo, and synchronous costs on 24 and 36 megapixel fixtures.

The first two Debug runs each passed 64 of 65 tests, including all four new save cases. The inherited channel-separation HTTP test failed during connection teardown with the same idle-to-failed transition error on the retained 526 test binary in a full 61-test baseline run. All seven channel tests passed in isolation on both binaries. The broad failures and successful isolated replays are retained separately. The first replay command stopped before running because its shell variable was read-only. The replacement command used a distinct output directory and completed both replays.

The Debug timing fixtures allocate every tile on 24 and 36 megapixel opaque images. Two invocations of the previous sample predicate cost 5.80 and 8.88 seconds. The first current JPEG eligibility check took 1.98 and 3.07 seconds, and 120 subsequent reads took 1.79 and 1.82 milliseconds combined. These timings cover the opacity predicate and format eligibility. Encoding and physical display timing need separate measurements.

[Adobe file formats](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/image-file-formats-supported-in-photoshop.html) distinguishes JPEG's lack of transparency and OpenEXR's support for 32-bit images with alpha. Photato's existing ordinary Save and Save a Copy rules continue to govern these routes. Adobe also documents JPEG matte and depth-conversion workflows that are separate from this change.

Combined build 528 passes all 69 selected methods, including eight new tests, in Debug, optimized Apple Silicon and translated Intel. The universal candidate passes macOS 14 metadata, signature, entitlements, native resource, executable payload and extracted archive checks. The optimized timing table, reference limitations and source hashes are in [Source checkpoint 528](SOURCE_PUBLICATION_528.md).
