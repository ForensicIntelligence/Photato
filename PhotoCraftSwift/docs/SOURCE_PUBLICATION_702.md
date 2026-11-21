# Source checkpoint 702

Native Swift 0.3.0, build 702, 2026-11-21.

Prompted Generative Fill can now keep up to three results in one editable masked layer. Choose a variation in Properties or through the Photato API. The original generation takes one Undo step.

Synthetic RGB8, RGB16 and RGB32 tests preserved exact rendered samples, mask coverage and the selected variation after reopening Photato, PSD and PSB files in Photato. The real Core ML model generated identical first results through the editor and HTTP at the tested seed. A separate sandboxed test generated three different results and preserved all 49,283 pixels outside the selection in each. Each of those real variations also matched its original RGBA bytes after reopening in all three formats in Photato. Cancelling during prompted inference preserved the document and empty Undo stack and removed the temporary job. The native prompt sheet and Properties picker were captured offscreen. The picker was inspected in Light and Dark.

482 of 483 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 701 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug.

Generating more results into the same layer, Generate Similar, the Adobe Execute Actions descriptor, and Firefly pixel equivalence remain open. The installed Photoshop session timed out on two read-only scripting queries. Adobe's desktop documentation confirms variation selection in Properties.

[Model setup](LOCAL_GENERATIVE_FILL.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_702.json)
