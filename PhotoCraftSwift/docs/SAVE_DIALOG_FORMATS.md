# Save dialog file formats

Edit > Customize Save Dialog File Formats controls which supported formats appear in native Save As and Save a Copy. Check or uncheck formats, then choose Done. Cancel leaves settings unchanged; Restore Defaults and Clear Formats change the draft until Done is selected. Photato currently offers its six document output formats: Photato, PSD, PSB, PNG, JPEG and TIFF. Additional Photoshop codecs remain planned work.

Save As also checks whether a format can preserve the current editable content. The setting changes the dialog list; it does not remove encoders or block ordinary Save, recovery, explicit API output or downloads. An empty or incompatible list cancels native panel creation with guidance for restoring choices. It does not silently insert a hidden format. Exact Photoshop zero-selection behavior, menu placement and factory selections remain unqualified while live reference access awaits Mac unlock.

The list is stored atomically with existing File Handling settings. Settings archive 4 requires a valid explicit list; older archives 1–3 load with all currently supported formats visible and are not rewritten merely by reading. Unknown/duplicate/invalid values or malformed version 4 files are preserved and rejected. Stale revisions, active file operations, external changes and failed writes do not publish new settings. Recovery intervals, compression and recent files retain their values. Native document archive 86 and Actions 49 are unchanged.

## Optional API

Use the existing authenticated application-preference endpoint and its separate native write permission:

```http
POST /v1/preferences/photoshop-file-handling
Content-Type: application/json
```

```json
{"revision":"<current preference UUID>","saveDialogFormats":["psd","png"]}
```

GET returns the current preference revision and list in stable format order. A POST may change the list, `disablePSDCompression`, or both. Revision plus at least one setting is required. The list accepts unique known format IDs and may be empty. Errors retain the existing 400/401/403/409/415/422 contract. The permission is off at each server start/stop. No published Adobe desktop-preferences endpoint is invented.

Document state separately reports `saveDialogFormats`, `copyDialogFormats` and `fileHandlingPreferencesRevision`. Existing `saveFormats` still describes encoder/persistence eligibility. Explicit API output ignores dialog visibility; clients continue to negotiate native archive output with `X-Photato-Archive-Version`.

All 101 focused Debug tests pass, including seven new methods covering all 64 lists at RGB 8/16/32, preserved native bytes and existing output, legacy/strict migration, recent files, stale/busy/failed writes, native/API equivalence and owned offscreen layout. Both optimized architectures pass the same 101 selected cases, including all seven new methods, with no failures or crashes. The universal package passes both minimum-macOS-14 slices, signature and ZIP checks. These are module/affected checks; earlier full-suite and checkpoint 425 residual failures are retained. Full D01, current physical UI/Photoshop defaults, all format codecs and supported physical-platform/performance qualification remain open. [Evidence](SAVE_DIALOG_FORMATS_426.json).
