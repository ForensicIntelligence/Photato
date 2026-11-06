# Batch file naming

Open File > Automate > Batch. Select an action and sources, choose an output folder and format, then expand File Naming. Add up to six ordered fields: document names, extension, numbered or letter serials, dates and custom text. Reorder or remove fields, set the starting serial and check the example. Run captures a snapshot; edits made later cannot change an in-flight job. Numbered copies retains the earlier source/suffix style.

The selected format determines the extension. Numbers have a minimum width and never truncate; letters start A independently of the number. Native runs capture the date when Run is pressed. Names are normalized and validated before processing; duplicate planned names reject the batch. Unsafe names are reported instead of silently rewritten. Existing files and symlinks are never replaced. Cancellation and Stop on first error retain already completed copies.

Windows compatibility adds reserved-name/character checks. Windows or Mac OS compatibility checks case aliases. A safe single-filename baseline always applies, including when UNIX is unchecked. Alias detection is best effort; another process racing a differently cased alias on a case-sensitive filesystem is not covered by an all-files transaction.

## Optional API

Existing `actions.batch` accepts optional `naming`. For example, with the normal actionID, shared sources/current revisions and format parameters:

```json
{"elements":[{"kind":"documentName"},{"kind":"literal","text":"-"},{"kind":"serial4"},{"kind":"extensionLower"}],"startingSerial":1,"windows":true,"macOS":true,"unix":true,"date":"2026-11-05T00:30:00Z","timeZone":"UTC"}
```

Supply either naming or the legacy suffix. Omitting naming preserves the existing API naming contract. State includes the captured naming request while active and namingCapabilities with request/state schemas, limits, defaults and qualifications. Native256-source and shared API8-source limits remain. Both interfaces use the same planner, encoding and protected publication. No dedicated Adobe endpoint or proprietary action descriptor is asserted.

Checkpoint434 passes all25focused Debug tests, including eight new methods. Literal vectors cover all18public field types and date/number/letter boundaries. Tests also check collision preflight, existing files/symlinks, master bytes, cancellation/revocation, stable native bindings/run snapshots, native/API output bytes and invalid/stale/busy/permission errors. The initial panel-height failure was retained and fixed in production; its exact test bound was kept. The offscreen capture checks geometry, not physical UI appearance or Photoshop equivalence. Latest optimized universal/private-source qualification remains432.

Full Actions/Batch is still open: conditions, interactive dialogs, Open/Save overrides, all source/destination modes, subfolders/import/Bridge, ATN, droplets and Image Processor. Exact Photoshop naming/default/output semantics and platform/performance checks also remain open. [Evidence](BATCH_FILE_NAMING_434.json).
