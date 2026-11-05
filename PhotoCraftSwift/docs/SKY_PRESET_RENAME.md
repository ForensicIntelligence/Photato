# Rename a sky preset

In Sky Replacement, select an imported sky and choose **Rename…**. The dialog starts with its current name. **OK** saves through the same library operation as the API; **Cancel** leaves the library unchanged. Names must satisfy the existing nonempty, 255 UTF-16-unit limit. Validation and storage errors remain visible in the dialog so the name can be corrected or saving retried.

Renaming retains the preset’s ID, position and original image bytes. The preview is refreshed so a later replacement uses the new name. It changes neither document pixels nor document/local-preview Undo history. Sky-library changes persist even if Sky Replacement is subsequently cancelled, matching the existing library import/removal behavior.

The dialog captures its selected sky, workspace state and library revision. Selection/settings changes, another library edit, preset removal, workspace closure or a superseding dialog prevent an old confirmation from renaming another item. The parent workspace cannot commit a replacement while Rename is open.

The existing Photato operation is `sky.library` with `operation: rename`, `skyID` and `name`. Explicit API requests do not display dialogs. Sky state adds `libraryRenameOpen` and `canRenameSelectedSky`; capability metadata describes the shared library operation and native availability. No command, archive or Actions version changes. The pinned Adobe API has no dedicated sky-preset route, so no endpoint is invented.

[Adobe’s sky-preset documentation](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/select-and-manage-sky-presets.html), updated 23 February 2026, includes Rename Sky. Exact current Photoshop dialog layout/defaults, grouped libraries, recents, default skies, multi-selection and `.sky` transport remain open.

The baseline passes 26 selected Sky/Adjustment Brush tests on each preserved normal architecture. Current rename tests cover native/API library bytes, RGB8/16/32 source and preview preservation, persistence/Cancel, Unicode name limits, failed storage with retry, stale contexts and dialog/schema discovery. [Checkpoint 419](SKY_PRESET_RENAME_419.json) records current attempts and qualification. All 57 focused Debug tests pass, including the three new rename regressions. A test-only missing-try compile correction left the production code and application binary unchanged. Normal 419, physical UI, complete Sky Replacement and independent Photoshop output qualification remain open.
