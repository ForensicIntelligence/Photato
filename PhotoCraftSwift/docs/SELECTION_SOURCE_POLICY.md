# Selection sources

Object and People selection preparation now reads the selected layer when Sample All Layers is off. Type, shape and fill layers use the existing renderer in document coordinates, including ordinary masks and transforms. Raster layers and Smart Object previews keep their existing current-layer path. Hidden and locked sources can be read without changing source pixels.

Sample All Layers explicitly uses the visible composite. Groups and adjustments currently require that choice; a missing or unsupported current source produces an availability/error result instead of silently selecting unrelated pixels. Full Photoshop source-kind eligibility still needs qualification.

Magic Wand Options now includes Select Subject. It uses Magic Wand’s own Sample All Layers flag. Object/Quick and Properties/Menu settings remain independent. Select Subject still requires an eligible raster or Smart Object source and uses the existing optional on-device detector. The new source renderer does not broaden its eligibility to type or shapes.

## API and history

The existing `selection.subject` command accepts captured `sampleAllLayers`. Object Finder, People and point selection use shared selection preparation. Capability discovery names each tool’s sampling field, including `magicWand.settings.sampleAllLayers`. Source preparation and settings do not change document pixels/history; a committed selection uses the existing single Undo transaction and native archive support. Stale/busy requests, cancellation and revoked sharing cannot publish partial work. No new Firefly route, Adobe desktop runtime or third-party plug-in support is claimed.

## Validation

All 82 selected Debug methods pass. Normal optimized tests run the same 83 methods on Apple Silicon and translated Intel, including all 23 new methods from checkpoints 465 and 466. The twelve new source/workflow methods cover rich source families, three depths, masks/transforms, source choice, object/person caches, HTTP/native equivalence, archive/history and cancellation. The extra optimized method is the existing 240-case point-sampling oracle.

A separate literal reference matches all 4,608 bytes of captured red-current/green-composite input on Debug and both optimized architectures. The previous averaged-Wand reference also matches all 74,263 bytes on all three. These own-input and mask checks are not Photoshop or model-output oracles. Seven older independent Photoshop RGB32 methods and nine cursor methods pass within their existing scope.

In the isolated Debug app, W/Shift-W reached Magic Wand and the new Options button ran Apple Vision on an owned mascot image. A visible subject mask appeared; menu Undo/Redo/Undo restored clean state, the owned tab closed, and Quit terminated the validation process. The initial computer-use pipe failure and recovery are recorded. The optimized universal package passes minimum macOS14 metadata, entitlements, signature, extracted-ZIP and compiled-payload checks; it has not been launched or installed.

Full S03, detailed face segmentation, exact Photoshop defaults/output/source-kind eligibility, unsupported color/target/capacity contexts, physical platforms, 60fps and earlier failures remain open. Work moves to Select and Mask, then pixel/vector masks. [Evidence](SELECTION_SOURCE_POLICY_466.json).
