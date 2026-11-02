# Layer Comps

**Photoshop-file follow-up339:** Supported comp catalogues, inherited visibility/integer positions, embedded source choices and legacy opaque retention now share PSD/PSB IO. Native82 retains no-property/explicit-clear semantics. All 13 new cases pass. Source03 passes 408 of 409 affected optimized cases; one existing linked PSD/PSB cache case retains two strict failed assertions. Both diagnostic vectors match332. There are no unexpected errors or crashes. The separate reader verifies six output files across8/16/32-bit PSD/PSB metadata. These are native/independent-format checks, not Photoshop2026 execution or full-current-suite acceptance. [Details](PSD_LAYER_COMPS.md).

**Parent-comp follow-up338:** The fourth recording option, current-source preparation, Last Document State, shared API/history/exports and native 81 retention are implemented. All 13 new cases pass. The expanded optimized selection passes 377 of 378 cases, retaining one existing strict linked PSD/PSB cached-pixel case with two failed assertions, zero unexpected errors and no crashes. Its diagnostic vectors match checkpoint 332. Source02 freezes 6898 inputs and 926 production Swift files. No full-current-suite or Photoshop equivalence is claimed. [Details](PARENT_SMART_OBJECT_COMPS.md).

**Smart Object Properties follow-up337:** Per-instance source-comp choice and native80 persistence are implemented and the all14 new cases pass in Source04. The365-case affected run retains one known strict linked-cache failure. Parent Layer Comp recording of that choice and editable Photoshop comp resources remain open. See [Smart Object choices](SMART_OBJECT_LAYER_COMPS.md).

Photoshop 2026 is the reference. Layer Comps save design variations within one document; the Rust project does not determine this feature's scope. This implementation was written in Swift from the native document model and Adobe's published workflow. No Photoshop script implementation was copied.

## Current implementation — checkpoint336

The native floating panel opens from Window > Layer Comps. It captures named variations with comments and independent Visibility, Position and Appearance options. It can apply, update, duplicate, reorder and delete comps, cycle through them, and restore the state preceding the last application. Selecting a list row alone does not apply it. Changes share the editor command/history system.

Comps retain layer UUIDs and property records, not pixel copies. Position records integer offsets and affine translation while retaining the current rotation/scale. Appearance records opacity, blend mode, layer style/fill and group Pass Through. Raster pixels, text content, masks, layer order and unrecorded properties stay shared. Missing layer UUIDs remain warnings; application changes surviving layers and leaves new layers alone. Recapture replaces the saved properties. These are explicit implementation semantics, not fully qualified Photoshop behavior.

Native79 retains comps and the prior document state. Older documents retain their earlier feature version. Editable PSD/PSB writes reject comp-bearing documents until Photoshop comp resources are implemented. The comp export workflow deliberately removes comp metadata from non-native variations; ordinary save must not silently lose it. Commands that would discard comps reject atomically.

## Export

File > Export > Layer Comps to Files… supports PSD, PSB, PNG, JPEG, TIFF and Photato. The panel's Export menu also supports the selected comps. Each variation starts from the same immutable source, preserving unrecorded properties independently. Native outputs retain the library; other formats contain the applied result. Raster profile embedding is selectable. Existing codec/depth/rendering limits still apply.

The native workflow stages every file and manifest, then publishes a new `<prefix>-comps` folder without replacing an existing folder. API file output is a ZIP. Names use a safe prefix, ordinal and sanitized comp name. Missing-layer comps require review/recapture before export. Total output is bounded to128MiB; library metadata is bounded to64MiB,2048 comps and262144 layer-property records. These are current implementation budgets, not Photoshop capacity claims.

File > Export > Layer Comps to PDF… produces one composite page per selected comp in library order. Pages use canvas pixel dimensions as PDF points and the existing color-managed renderer. PDF output is raster content; PDF options, physical sizing, exact color/encoder equivalence and Photoshop presentation features remain unqualified.

## API

- `layerComps.edit`: capture/update/apply/restoreLast/duplicate/delete/reorder/clear. Capture accepts an optional explicit UUID; update can rename/comment without recapturing when options are unchanged. Each operation is atomic and undoable.
- `layerComps.export`: format, optional comp UUID list, prefix and raster ICC flag. Returns ZIP or multipage PDF; requires transfers and a current shared document revision. No filesystem paths are accepted.
- `layerComps.export.cancel`: matching active operation UUID. Sharing or transfer revocation cancels the shared worker and invalidates results.

The `layerComps` document state reports comp IDs/names/comments/options, current-property matches, missing-layer IDs, applied ID, last-state availability and active export ID. The command catalogue publishes parameter schemas and capabilities. Native downloads require `X-Photato-Archive-Version: 79` for comp-bearing documents. API operations share native commands and history; no dedicated Adobe route is invented. Layer Comp execute-actions descriptors remain unsupported.

## Qualification and remaining work

Source04 passes all260 affected optimized cases, including17 new cases, zero failed assertions/unexpected errors/crashes. Build111.52s and tests37.479s on6,887 frozen inputs/921 production Swift files. Two failed test compilations and the first runtime result257/260 remain preserved. No production changes were needed after the second compilation; later repairs correct test helper calls, native79 admission expectations and HTTP422 semantic errors. See [evidence](LAYER_COMPS_REFERENCES.json). Tests cover all seven property combinations at three depths, pixel/mask/transform sharing, style removal/restoration, atomic invalid edits, history, missing layers, native79, six file formats, independent CoreGraphics PDF page samples, API equality/permissions and factory menu bindings.

Photoshop is running but native inspection reports a locked Mac. No live controls, defaults or output comparison was performed at this checkpoint. Remaining scope includes Smart Object comp selection/propagation, editable Photoshop comp resources, complete warning handling for merge/conversion, geometry/mode/timeline interactions, selected-comp cycling, native dialog and panel docking/thumbnail/default equivalence, persistent options, Actions/ATN/Adobe descriptors, full suite and supported-platform/large-document/performance acceptance. The entire Layer Comps workflow remains open against Photoshop2026.

## References

- [Adobe feature catalogue](https://www.adobe.com/products/photoshop/features/all.html)
- [Create and manage layer comps](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/create-layer-compositions/create-and-manage-layer-comps.html), updated28September2026 and accessed1November2026. Defines recorded properties, panel operations, Smart Object selection, warning lifecycle and export.
- Factory native menu positions/titles and absent shortcuts are retained from the project's existing Photoshop menu catalogue. New physical verification remains pending.
