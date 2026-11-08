> Integrated into the source-delivery diary on 8 November 2026 UTC from the retained checkpoint493 working record. Status statements below describe that checkpoint. Local raw logs, user documents, reference sessions and app bundles are excluded from the public repository. The canonical historical-evidence audit is still pending; see the [delivery record](../SOURCE_PUBLICATION_500.md).

#493 — Profile changes on large documents

8 November 2026. Current working record; canonical delivery is pending.

Assign Profile and Convert to Profile used to reject documents above eight megapixels. The shared native engine now handles larger rasters in bounded tiles and retains authoritative RGB, CMYK, Grayscale and Lab components. Assignment preserves numeric samples. Conversion retains the existing ColorSync arithmetic, rendering intents, black-point compensation and alpha handling.

The native preview reduces the converted composite to a bounded display size. Apply makes one history transaction. Cancel, document read and close retire work, and an edit followed by Undo cannot make an old preview eligible to commit. The Photato API uses the same transaction and checks the native profile target. Adobe-compatible output ICC conversion also uses this implementation.

All 65 selected Debug tests and all 65 optimized Apple Silicon tests pass. Translated Intel passes 64 of 65. The remaining test compares against the frozen Apple Silicon color corpus. Intel's dense and streamed paths match each other exactly. A separate probe linked against our retained pre-change492 modules produces the same Intel bytes and all the same errors, confirming that the difference predates this change. The failing reference assertion is preserved.

The checks include sparse 300,000 × 300,000 documents, a fully populated mapped image above eight megapixels, native preview/commit/Undo, native saving, cancellation, stale previews, real HTTP requests and output-profile conversion. The corpus contains 1,984,272 bytes from 336 successful programs and 32 existing ColorSync failures. Those failures remain unresolved. These are native regression results, not proof of Photoshop output equivalence.

A universal validation package passes minimum macOS14 metadata, entitlements, signing, complete payload and extracted-ZIP checks. It is explicitly a partial validation candidate with the Intel reference failure recorded. It has not been installed, uploaded or released.

In the running isolated app, Assign Profile opened normally. Choosing Display P3, cancelling, applying, Undo and Redo all worked on its owned blank document. The title read Photato - Untitled-1. Screenshots were displayed during the check.

A later attempt to create a 9001 × 1001 document reached the depth picker. After selecting16bit, the dialog could no longer be observed, the original document remained, and File commands were disabled. A read-only sample shows the app still in the New Document modal loop. Normal cancellation/default-button attempts did not recover it. Its cause is unproven; the process is preserved. Live conversion-sheet, large-document creation and clean-close checks remain open.

Full COL01 acceptance, the physical macOS14/Intel matrix, maximum dense capacity, 60fps and earlier failures remain open. The next major source audit is crash recovery and autosave durability. Recovery/index/salvage/preferences/admission and atomic fault paths already exist; parent-directory persistence is an explicitly documented remaining area to investigate.

The original checkpoint486 history audit is still running. The waiting 487–491 delivery batch is preserved, and this record describes the private current source rather than a completed canonical diary update. No old build, GitHub content or user document was removed. No App Store action or software release occurred.
