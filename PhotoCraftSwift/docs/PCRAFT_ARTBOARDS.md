# Editable artboard project import

Open an original `.pcraft` project with File → Open, or upload it through the optional Photato API. Supported top-level artboard groups retain editable bounds, background, preset, hierarchy, blending, protection and child layers. White, black, transparent and admitted custom RGB/grayscale backgrounds are supported within the existing RGB-project import path.

Negative board positions expand and reframe the physical canvas while retaining logical coordinates. Original source files and the retained manifest stay unchanged. Saved Smart Object pixels, originals, captured placement/filter programs and caches survive canvas reframing and single-board extraction; stale appearances remain stale. Cached point type keeps its layout identity.

Select the Artboard tool from the Move tool group and choose Properties to edit a board. Imported preset names appear in Size and survive native/API configure. Existing Cancel, Undo/Redo, native Save As/reopen and Artboards to Files/PDF use the same native model. Save to `.photato` to preserve editable content; the original project is an import format.

The permissioned `POST /v1/documents/import` accepts the existing `pcraft` format and `application/vnd.photocraft.project` media type. Existing `artboard.edit`, `artboard.export`, history and native-download commands require their usual sharing, transfer and revision permissions. Discovery describes artboard admission and limitations. No new command, schema or archive version was introduced: native 92, Actions 60, 271 typed commands.

The Photato resource-job interface accepts this existing source-format extension. Adobe-compatible jobs continue rejecting it; no Adobe input type or endpoint was added. The separate published artboard-creation workflow remains unchanged.

Unknown fields, nested/clipped boards, unsupported originals and native capacity/color/metadata limits reject the import atomically. Qualified RGB PSD/PSB artboard interchange is now available; see [the current workflow](PSD_ARTBOARDS.md). The regular Properties panel still presents a generic group; use Artboard tool Properties. Full source migration, uncached render fidelity, Photoshop defaults/output, physical platforms, dense document capacity and performance remain open. [Build 515 evidence](PCRAFT_ARTBOARDS_515.json).
