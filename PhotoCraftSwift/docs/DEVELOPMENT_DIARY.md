# Photato development diary

<!-- process-note:start -->
## How we build a Photoshop work-alike

Photato is an independent native Swift implementation, with licensed code ported from the open-source PhotoCraft project. We aim to reproduce useful workflows and compatible behavior while recording where code, specifications and test evidence come from.

1. **Start with attributable sources.** Audit PhotoCraft’s Rust source and retain its MIT/Apache licensing and credits. Use public Adobe documentation for published menus, tools, shortcuts, file formats and API contracts. Record the source and license of each port, dependency and fixture.
2. **Specify observable behavior.** Use Photoshop through its normal interface with our own test artwork. Record controls, defaults, shortcuts and results, then inspect saved files to understand interoperability. The diary also identifies compatibility facts obtained from installed metadata and script definitions; we record those references as sources of compatibility facts and do not incorporate Adobe’s script code.
3. **Implement the native application.** Translate licensed PhotoCraft components where suitable and write independent Swift code for the editing engine, macOS interface and automation APIs. We have not decompiled or disassembled Photoshop executables, extracted proprietary algorithm code, or copied Adobe’s proprietary implementation into Photato.
4. **Test against independent evidence.** Compare outputs using original Rust fixtures, public format specifications and Photoshop-generated test files. Exercise document editing, previews, cancellation, undo/redo, saving and APIs. Claim byte-identical results only for cases actually demonstrated; keep mismatches and untested behavior visible.
5. **Keep the development trail.** Preserve source and build hashes, attribution, test commands, failed attempts, repairs and known limits. Clearly distinguish working features from full Photoshop parity.

**Terminology matters.** This is independent implementation with black-box compatibility research. Specification research and implementation have taken place within the same project; the record does not establish a formal separation between research and implementation teams. Observing behavior and analyzing saved files are disclosed parts of the process, so we do not make the broader claim that no reverse engineering of any kind occurred. The restriction on decompiling, disassembling or copying Photoshop’s proprietary implementation remains explicit.

<!-- process-note:end -->

**Release policy — updated 28 October 2026:** Photato will be a free and open-source release under MIT OR Apache-2.0, without tips, donations, in-app purchases, subscriptions or paid feature unlocks. The repository stays private during development and becomes public on release day. Earlier entries describe the former purchase experiment as history; step237 records its removal.

**Source published (step254):** The complete qualified step253 source is committed and pushed to private GitHub main as [`4b3fdb6`](https://github.com/ForensicIntelligence/Photato/commit/4b3fdb6cd08c07a32d8f47f627c4687c838f10d3). All2374 published qualification inputs match the tested candidate;1057 original Rust files are unchanged. Native source, tests/fixtures, Xcode project, scripts, assets and development records are included. Generated model/cache files, builds, runtime logs and private working documents are excluded. GitHub confirms the commit and private visibility. The source passed2660 full optimized tests; no new app installation or binary upload accompanies this source delivery. [Receipt](SOURCE_PUBLICATION_254.json).

**Earlier native checkpoint (step277):** Nine native retouch tools now record semantic Actions21 and share retouch.stroke in the optional Photato API. Playback resamples portable layer/source recipes, with explicit external-source admission and atomic history. All 88 focused and 2801 full optimized tests pass on2484 frozen inputs; native Actions recording/playback and separate Preview277 delivery are verified. Full Photoshop/Adobe descriptors/ATN, physical60fps and platform qualification remain open.

**Previous pause (step276):** Paused at the maintainer’s request on stable Preview275. All2791 full tests previously passed;2478 compiler/test inputs and the delivered app/ZIP hashes are reverified unchanged. Retouch Actions/API investigation is saved, with no implementation started. No new application build or test run was needed for this documentation-only handoff. [Resume record](PAUSE_CHECKPOINT_276.json).

**Latest implementation (step275):** Clone Stamp, Dodge/Burn/Sponge and Blur/Sharpen/Smudge now retain validated preview work through release, appending only unseen samples. On the owned 24 MP fixture, eligible release commitment improves from 12–40 ms to 0.8–1.0 ms with exact native command pixels and one history entry. All 50 focused and 2791 full optimized tests pass on 2478 frozen inputs. Native painting/history and separate Preview 275 packaging are verified. Healing final processing, retouch Actions/direct APIs, physical 60 fps and full Photoshop/platform parity remain open.

**Earlier native keyframe milestone (step234):** Native video Timeline creation and Position/Opacity/Transform/Style keyframes, automatic capture, Linear/Hold interpolation, native53 and shared API editing pass 65 focused and 2,450 full optimized tests on 2,302 unchanged inputs. Independent PNG checks match 1,920 analytic RGBA8 channel values. Clip groups/splitting, transitions, audio, Render Video and full exact/live/platform parity remain open. Installed build221 and private universal build232 are unchanged.

**Standalone diary (step228):** The developer diary is now a single HTML file that opens offline, with embedded styles, scripts, logos and downloads. Native verification is recorded separately below; the full Photoshop goal is still active. Saved copies are snapshots refreshed after source records change.

**Earlier work (step226):** Persistent working RGB/CMYK/Gray profiles, native Color Settings and shared API defaults pass28 initial focused and2,374 full optimized tests, including10 new settings regressions. All2,253 source03 inputs are unchanged. Import/paste policies, working proof integration, presets/Spot/advanced blending and exact/live/platform COL01 acceptance remain open. Installed221 and qualified/uploaded224 are unchanged.

**Previous work (step224):** Step224 native Print/Print One Copy, physical layout, ICC output, hard proofs, ink separations, PDF and five shared API commands pass65 focused tests. Actual AppKit-to-PDF pagination passes; physical printer/live/exact/platform qualification remains open. All2,351 full optimized tests pass on2,239 unchanged inputs. Universal build224 is verified and uploaded as a private draft; installed221 is unchanged.

**Previous work (step223):** Native soft proofing, gamut warnings, plate previews and custom ICC controls now share the optional API. All75 focused tests and2,330 full optimized tests pass. Independent tests also found and repaired an ICC Lab normalization error. Native printing is next; full proofing/HDR/preferences and exact/live parity remain open.

**Earlier window handoff (step209):** The screenshot was identified as the obsolete159 test app, which remains open. Corrected Photato Verified209 is installed separately; its signature and retained artwork hashes verify unchanged. The latest desktop inventory explicitly reports the Mac locked. Manual unlock and the same-document zoom/pan/scroll/resize check remain pending. Current317-test focused validation includes canvas containment and document windows; no new live acceptance is claimed. [Latest handoff evidence](../artifacts/runs/20261028T101734Z-221-indexed-bitmap/window-handoff05.json).

**In progress (step221):** Indexed/Bitmap controls, Color Table/ACT, stored-sample geometry, clipboard and semantic Actions19 now share native history and APIs (132 typed commands). All523 combined focused Debug regressions pass;34 final checks pass after adding the API response schema, including12 new Actions workflow tests. Earlier independent format evidence covers37 inputs and42 outputs. Full tool contexts, Adobe restricted/clipboard descriptors and exact/live/platform qualification remain open. Build220 is the latest qualified package. [Working checkpoint](WORKING_CHECKPOINT_221.json), [restricted-mode evidence](RESTRICTED_MODE_REFERENCES.json).

**In progress (step220):** Native RGB/Grayscale/CMYK/Lab creation, conversion, Channels, file interchange and both API integrations now pass2,173 full optimized tests, including79 new mode tests, plus46 final focused regressions. Seven PSD files independently verify24 layer planes; fourteen TIFFs verify48 composite and24 layer planes. The universal macOS14+ package verifies and is available as a private GitHub draft.118 typed commands/native46 remain. Indexed Color, Bitmap, Duotone, Multichannel, full tools/Actions and exact Photoshop parity are still open. [Qualified checkpoint](ACTIVE_CHECKPOINT_220.json), [mode evidence](DOCUMENT_MODE_REFERENCES.json).

**Development active (step219).** Shadows/Highlights, HDR Toning, Match Color, Replace Color and Equalize now have native controls/previews, history and shared Photato APIs. Shadows/Highlights supports editable Smart Filters/native45; ordinary tone operations use Actions18. All 161 focused Debug and 2,094 full optimized tests pass; 12 original-Rust RGB8 references match byte-for-byte. The universal macOS14+ package verifies after fresh extraction. Exact Photoshop/ICC behavior, Adobe descriptors/presets, HDR semantic Actions and live/platform checks remain open. Full A03 stays in progress. [Current checkpoint](ACTIVE_CHECKPOINT_219.json), [tone/color evidence](CLASSIC_TONE_REFERENCES.json). Next: document color modes and separations. The downloadable private draft remains the separately verified209 build.

**Window corrections and Lens Blur (steps208/207):** Window titles now read `Photato - <current doc name>`, and zoomed/panned canvas drawing stays inside its viewport. Live checks passed on a separate current Debug app. Lens Blur adds depth/iris/highlight/noise controls, preview/history, native38/Actions10 and shared APIs. All 59 focused Debug and 1,991 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Exact Lens Blur Photoshop output/interchange and broader platform qualification remain open. [Window evidence](WINDOW_PRESENTATION_REFERENCES.json), [Lens Blur evidence](LENS_BLUR_REFERENCES.json). Next: major distortion workflows.

**Native photo detail workflows (step206):** Smart Sharpen now offers Gaussian/Lens/Motion removal, noise suppression and tonal fade controls. Reduce Noise adds luma/chroma/detail/JPEG and per-channel controls. Native preview/Undo, Smart Filters, native37/Actions9 and APIs share the engine. All45 final focused Debug and1980 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Exact Photoshop output/defaults, Adobe descriptors/editable PSD and live/platform checks remain open. [Evidence](PHOTO_DETAIL_REFERENCES.json). Next major workflow: Lens Blur depth of field.

**Native Filter Gallery (step203):** All47 artistic effects across six categories now have a native thumbnail browser, effect stack/parameters/colors, preview/Cancel/Undo, editable Smart Filters, native36/Actions8 and shared APIs. All42 focused Debug and1973 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Original Rust default fixtures match47/47 exactly; Adobe descriptors/editable PSD, exact Photoshop/live/platform and full F06 parity remain open. Next major workflow: Smart Sharpen and Reduce Noise. See [gallery evidence](FILTER_GALLERY_REFERENCES.json).

**Editable shaped text (step202):** Text on/inside paths, fifteen preset warps and Dynamic Block/Circle/Arch/Bow now retain editable type through a native preview workspace, Cancel/Undo, native35/Actions7 saving and shared APIs. All 89 focused Debug and 1966 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Exact fit/composers, vertical shaped type, live delimiter editing, editable PSD and full T04 parity remain open. Next major workflow: Filter Gallery. See [shaped text evidence](SHAPED_TEXT_REFERENCES.json).

**Native advanced typography (step201):** Vertical text, installed OpenType features, variable axes and a Glyphs panel now retain editable text, history and native34/Actions6 metadata. Both APIs share the native text engine; the published adapter adds vertical/small-caps fields and editable PSD output. All 70 focused Debug and 1959 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Full T02, exact composers, font/PSD variants and live/platform parity remain open. Next major workflow: text on paths and warped text (T04). See [typography evidence](ADVANCED_TYPOGRAPHY_REFERENCES.json).

**Native Pen and Paths (step200):** Freeform/Curvature Pen, editable fitted paths, selection tracing, foreground fill/current-brush stroke, Paths panel controls, five APIs and Undo/native persistence now work together. All100 focused Debug and1951 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Magnetic/multiple-anchor/advanced path options, clipping export, semantic Actions and exact/live/platform/full G04 parity remain open. Next major workflow: multilingual/OpenType typography. See [path evidence](PATH_WORKFLOW_REFERENCES.json).

**Native live shapes (step199):** Seven drawing tools, editable corners/polygons/stars/lines-arrows/custom paths, shared fills/strokes, compound components, shape/path/pixels outputs, native presets and three APIs now share history and native33 persistence. All80 focused Debug and1944 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. Actions5 retains shape/pattern resources. Editable PSD/CSH, exact/live/platform and full G03 parity remain open. Next major workflow: Pen and Paths. See [shape evidence](SHAPE_REFERENCES.json).

**Native person-feature selection (step198):** Hair, face/body skin, clothing and accessories now have native Core ML masks, per-person picker/hover, multi-feature selection, refinement/history/Actions and expanded API coverage. All61 focused Debug and1933 full optimized tests pass. The universal macOS14+ package includes197 Select People and the native feature model; fresh extraction verifies both architectures, signature and model provenance. Xcode Debug build also passes. Actual Swift inference and save/Undo pass on one/two-person photos. Eyes/lips/beard and exact/live/platform parity remain open. Next major workflow: live shape drawing. See [feature evidence](PEOPLE_FEATURE_REFERENCES.json).

**Native Select People (step197):** Person-specific on-device detection, thumbnails, hover preview, multi-person selection, four modes/Hard Edge, Select and Mask handoff, Undo/Actions and three APIs now work together. All46 focused Debug and46 optimized tests pass;9 optimized menu checks also pass. Real local Vision finds1 person in a portrait and2 in an overlapping two-person photo; selection, source retention, native save and Undo/Redo succeed. Latest full1920-test/universal baseline196 excludes197. Semantic hair/skin/facial features, exact/live/platform and full S03 parity remain open. Next: verified on-device feature segmentation. See [people evidence](PEOPLE_SELECTION_REFERENCES.json).

**Native Object Finder (step196):** Cached local instance detection, actual hover masks, click selection, four modes/Hard Edge, refresh/Escape cancellation, source invalidation and three APIs now work together. All70 final focused Debug and1920 full optimized tests pass. The universal macOS14+ package verifies and includes195 Mask All Objects. Real local Vision detect/hit/select/save/Undo succeeds. Full model/default/control/live/S03 parity remains open. Next: Select People. See [Object Finder evidence](OBJECT_FINDER_REFERENCES.json).

**Native Mask All Objects (step195):** One on-device inference creates a separate editable masked group per foreground object, preserving the source and clipping hierarchy. Layer/context menus, targeted adjustments, Undo/native saving and shared API work together. All82 focused Debug and82 optimized tests pass. Real Apple Vision inference succeeds on the1024×1024 icon with source retention and Undo/Redo. Latest full/universal baseline194 has1903 passing tests and excludes195. Full model/Actions/exact/live/S03 parity remains open. Next: Object Finder. See [evidence](MASK_ALL_OBJECTS_REFERENCES.json).

**Native Focus Area (step194):** Sharp-region detection, Auto/range/noise controls, manual Add/Subtract correction, six outputs, preview/history and Select and Mask handoff now share a native workflow and API. All83 final focused Debug and1903 full optimized tests pass. The universal macOS14+ package verifies and includes193 Sky workflows. Exact/model/default/live/platform and full S02 parity remain open. Next: Mask All Objects. See [Focus Area evidence](FOCUS_AREA_REFERENCES.json).

**Native Sky Selection and Sky Replacement (step193):** Automatic sky masks, imported/existing-layer skies, manual brush/move controls, editable color/light layers, preview/Undo and three shared API commands now work together. All113 focused Debug and113 optimized tests pass. The universal macOS14+ package verifies. Last full regression is1876 passing tests at192; the next major batch will broaden again. Exact/model/preset/Actions/live/platform parity remains open. Next: Focus Area selection. See [sky evidence](SKY_REFERENCES.json).

**Native selection tools (step192):** Object Selection rectangle/lasso/click, Quick Selection and Selection Brush now have native controls, real previews, Undo, recorded coverage and four shared API commands. All155 broad focused Debug checks,7 final dedicated workflow checks and1876 full optimized tests pass. The universal macOS14+ package verifies and includes191 Adjustment Brush. Full S03/model/exact/live/platform parity remains open. Next: Sky Selection and Sky Replacement. See [selection-tool evidence](SELECTION_TOOL_REFERENCES.json).

**Native Adjustment Brush (step191):** Fifteen editable adjustment types, Add/Subtract painting, on-device object targeting, overlay/mask controls, Undo, recorded Actions and four shared API commands now work together. All156 focused Debug and156 focused optimized checks pass. Subsequent step192 includes191 in1876 passing full optimized tests and the verified universal package. Exact/live/model/platform and full B08 parity remain open. Next: Object Selection, Quick Selection and Selection Brush. See [Adjustment Brush evidence](ADJUSTMENT_BRUSH_REFERENCES.json).

**Native paint and eraser tools (step190):** Pencil, Color Replacement, Mixer Brush, Pattern Stamp, Background Eraser and Magic Eraser now have native controls, actual preview, Undo and three shared Photato APIs. Brush/Pencil create a paint layer over nonraster content. All 184 focused Debug and 1851 full optimized tests pass. The universal macOS 14+ package verifies. New-tool Actions/Adobe job/exact/live/platform parity remains open. Next major workflow: Adjustment Brush. See [paint-tool evidence](PAINT_TOOL_REFERENCES.json).

**Native Brush Settings and presets (step189):** Modeless settings/preset panels, sampled/dynamic brushes, actual canvas preview, mask/channel painting, Undo and three Photato APIs now work together. All 103 focused Debug and 1834 full optimized tests pass. The universal macOS 14+ package verifies. Native presets and version 2 recorded strokes retain settings. Full ABR/Adobe job/physical bristle/exact/live/platform parity remains open. Next: missing major painting and eraser tools. See [brush evidence](BRUSH_REFERENCES.json).

**Native Vanishing Point (step188):** Saved and connected perspective planes, paste/clone/brush, native preview/history and shared API are implemented. All117 focused Debug and1816 full optimized tests pass. The universal macOS14+ package verifies. This batch includes Lens Correction and Adaptive Wide Angle. Native32 retains plane metadata. Secondary tools, exact/live/PSD parity remain open. Next: major Brush Settings and presets. See [Vanishing Point evidence](VANISHING_POINT_REFERENCES.json).

**Native Adaptive Wide Angle (step187):** Line/polygon straightening, per-edge orientations, five projection choices and focal/crop/scale now have a native preview workspace, local/document Undo, editable Smart Filters/native31 and shared API/Actions/Batch. All107 focused Debug tests pass. Subsequent step188 includes it in1816 passing full optimized tests and the verified universal package. Exact/profile/live/PSD parity remains open. See [Wide Angle evidence](WIDE_ANGLE_REFERENCES.json).

**Native Lens Correction (step186):** Distortion/fringe/vignette/perspective controls, custom/generic profiles, straighten/autoscale/edge handling, native preview/history/settings, editable Smart Filters/native30 and shared API/Actions/Batch now pass97 focused Debug tests. Subsequent step188 includes it in1816 passing full optimized tests and the verified universal package. Manufacturer profiles, editable PSD and exact/live/platform parity remain open. See [Lens evidence](LENS_CORRECTION_REFERENCES.json).

**Native Blur Gallery (step185):** Field, Iris, Tilt-Shift, Path and Spin blur now have native pins/paths, preview, local/document Undo, bokeh/noise/strobes, editable Smart Filters/native29 and shared API coverage. All90 focused Debug and90 optimized tests pass. The universal macOS14+ package verifies. Exact/live/platform and editable PSD parity remain open. Next major family: Lens Correction. See [Blur Gallery evidence](BLUR_GALLERY_REFERENCES.json).

**Native Frames (step184):** Frame/K, shape placeholders, frame-from-layers/type/shape, embedded replacement, fitting, independent frame/content transforms and strokes now share the native engine, history, native28 and two Photato APIs. All140 focused Debug and1782 full optimized tests pass. The universal macOS14+ package verifies. PSD/linked/generative frame contexts and full parity remain open. Next major family: Blur Gallery. See [Frame evidence](FRAME_REFERENCES.json).

**Native Artboards (step183):** Creation/from layers or groups, drag/move/resize, properties, clipping, guides, native27 persistence and per-board image/native or multipage PDF export now share the native engine. Photato editing/export and the bounded Adobe create-artboard job route are integrated. All149 focused Debug and149 optimized regression tests pass. The universal macOS14+ package verifies. Frames is next; editable PSD artboards, live/exact/platform parity and L07 remain open. See [Artboard evidence](ARTBOARD_REFERENCES.json).

**Actions and Batch (step182):** Native recording, reusable action sets, step controls, import/export and one-step playback now share history with the API. Batch processes files, folders or open-document snapshots into separate outputs with progress, cancellation and per-file errors. All64 focused Debug and1759 full optimized tests pass. The universal macOS14+ package verifies. Adobe .atn/complete recording coverage and live/platform qualification remain open. Next major workflow: Artboards and Frames. See [Actions and Batch evidence](ACTIONS_BATCH_REFERENCES.json).

**Native Perspective Warp (step181):** Linked Layout/Warp planes, corner dragging/snapping, automatic straightening and persistent edge locks now have native preview/Cancel, local/document Undo, editable Smart Filters/native26 and Photato API coverage. All92 focused Debug and92 optimized focused tests pass. The universal macOS14+ package verifies. Exact/live/platform parity, richer contexts and editable PSD interchange remain open. Next major workflow: Actions and Batch processing. See [Perspective Warp evidence](PERSPECTIVE_REFERENCES.json).

**Native Puppet Warp (step180):** Pins, local rotation/depth, three mesh modes/densities and expansion now drive a native preview with Cancel, local/document Undo, editable Smart Filters and native25 saving. Photato filter.apply and smartFilter.set share the engine. All84 focused Debug and1736 full optimized tests pass. The universal macOS14+ package verifies. Exact/live/platform parity, richer contexts and editable PSD interchange remain open. Next: Perspective Warp. See [Puppet Warp evidence](PUPPET_REFERENCES.json).

**Native Warp (step179):** Fifteen presets and a draggable Bézier mesh now have grid/split controls, preview/Cancel, local/document Undo, editable Smart Object source retention, native24 saving and `layer.warp` API support. All55 focused Debug and1727 full optimized tests pass. The universal macOS14+ package verifies. Selections/vector masks, editable PSD interchange, exact/live/platform parity and G02 remain open. Next: Puppet Warp, then Perspective Warp. See [Warp evidence](WARP_REFERENCES.json).

**Editable image stacks (step178):** Load Files into Stack, Statistics and all eleven Smart Object modes now retain editable photo sources, optional alignment, native23 saving and undoable per-instance edits. Native dialogs and both API paths share the engine. All79 focused Debug and1720 full optimized tests pass. The universal macOS14+ package verifies. Exact/live/platform parity and remaining RAW02 requirements stay open. Next: native Warp workflows. See [stack evidence](IMAGE_STACK_REFERENCES.json).

**Merge to HDR Pro (step177):** Native bracket alignment, response/radiance recovery, ghost removal, four tone operators and32/16/8-bit output now have file/open-document preview controls and matching creation/cancellation APIs. All67 Debug and67 final optimized focused tests pass. The universal macOS14+ package verifies. Exact/live/platform parity and the rest of RAW02 remain open. Next: Smart Object stack statistics. See [HDR evidence](HDR_MERGE_REFERENCES.json).

**Photomerge (step176):** Files, folders and open documents now feed a native panorama preview with six layouts, expanded canvas, profile conversion, blending/fill and a new editable document. Photato creation/cancellation APIs share the engine. All 65 focused Debug and 1,697 final full optimized tests pass. The universal macOS 14+ package verifies. Exact/live/platform parity and the rest of RAW02 remain open. Next: Merge to HDR Pro. See [Photomerge evidence](PHOTOMERGE_REFERENCES.json).

**Auto-Align Layers (step175):** Overlapping photos now register through six projection choices, native preview/Cancel/OK, transformed pixels and masks, Undo/Redo and both API paths. All 56 final Debug and 56 optimized focused tests pass. The universal macOS 14+ package verifies. Lens corrections, exact/live/platform qualification and the rest of RAW02 remain open. Next: Photomerge, then HDR. See [alignment evidence](PHOTO_ALIGN_REFERENCES.json).

Photato began as a native macOS port of the Rust application PhotoCraft and grew into a project to reproduce Photoshop workflows in Swift. This diary explains how the application, its requirements, and its validation developed. It covers the recorded work from 7–26 October 2026, from the initial source audit through the verified JPEG work and the original PhotoCraft migration now in progress.

**This readable account was reconstructed on 20 October 2026.** The detailed [development log](DEVLOG.md) remains the authoritative running diary. Its dated entries preserve investigations, additions, changes, removals, failures, repairs, tests and remaining gaps. The [complete chronological index](#complete-chronological-index) below links every numbered milestone available at this reconstruction. Dates follow the existing records; an exact edit time is not inferred when none was recorded.

## The brief and the decisions that shaped the project

The original brief was to inspect PhotoCraft, plan the port, implement it module by module, and test each module. The target became Photoshop 2026 functionality in a fully native Swift application for macOS 14 and later, with a universal application for Apple Silicon and Intel. Optional Apple AI belongs behind platform and availability checks. Reaching PhotoCraft parity is an intermediate milestone, not the end of the project.

The maintainer then made several decisions that continue to govern development:

- Use Photoshop's interface, menu structure and factory shortcuts by default. A visible menu item does not establish that its function is implemented.
- Allow Apple's Private Cloud Compute as well as eligible on-device features, and describe which service is actually used.
- Release the work as an open-source fork with clear PhotoCraft attribution. Name the application **Photato**, and use the supplied icon.
- Offer optional support through App Store in-app purchases. Tips must not unlock editing features.
- Include a native Xcode project alongside the package-based build and test workflow.
- Maintain both the Photato API and an interface compatible with the published Adobe Photoshop API wherever that contract defines the operation. Desktop and API operations share the native engine.
- Record every development change, including failures and removals, from the beginning.
- Complete **major functions, then minor functions, then final details**. The UI, menus, shortcuts, APIs and tests needed to finish a major workflow belong to that workflow.

These decisions were made at different points. The dated account below preserves those changes instead of rewriting the past as though the final requirements existed from day one.

## 7 October 2026

### Establishing the native application

The first audit inventoried 24 Rust crates and 626 unique source menu identifiers. The Swift project separated the editing model, imaging and PSD support, optional AI, and native application. Early implementation covered sparse raster storage, blending, documents, commands and history, basic tools, native storage, and a deliberately limited PSD reader and writer. The initial milestone recorded 40 passing tests and a universal build targeting macOS 14. It also recorded repairs to canvas redraw, preview tone mapping, imported-file protection, gesture history, and signing affected by Desktop synchronization. The initial sequence was later expanded retrospectively; it is not a recovered edit-by-edit transcript. [Initial source audit and port](DEVLOG.md#dev-step-001)

A professional-workflow plan distinguished source parity from Photoshop parity. Inspection of the source corrected several earlier descriptions of supposedly missing Rust functionality, so those implementations remained part of the porting obligation. Inspection of the running Photoshop interface then guided a native workspace with grouped tools, document tabs, options, layers, adjustments, rulers and scrollers. Unsupported tools stayed visibly unavailable. [Workflow plan](DEVLOG.md#dev-step-002), [first workspace](DEVLOG.md#dev-step-003)

### Correcting the AI policy

An early platform policy excluded Image Playground where it would use cloud computation. At the maintainer's request, that exclusion was removed and Private Cloud Compute was re-enabled subject to Apple's actual availability checks. The UI was changed so cloud-generated results would not be described as on-device. Local prompt refinement remained a separate capability. At that checkpoint the services were unavailable or still preparing on the test machine; live generation was not claimed. [Private Cloud Compute change](DEVLOG.md#dev-step-004)

### Geometry, selections, masks and editable documents

The port gained Free Transform, image and canvas sizing, resolution handling, resampling and undoable whole-canvas geometry. Selections expanded to coverage masks, ellipses, freehand and polygon tools, combinations, inversion and feathering. Direct pixel-mask editing, independent mask transforms, density, feather, enable/link state and PSD mask interchange followed. Independent Photoshop files exposed ordering and mask details that native round trips could not reveal. [Geometry](DEVLOG.md#dev-step-005), [selection coverage](DEVLOG.md#dev-step-006), [independent masks](DEVLOG.md#dev-step-007)

PSD support expanded to compressed channels and higher bit depths. Photoshop comparisons revealed that float PSD samples require linear-light handling, leading to corrections in storage and composition. Layer groups, clipping, editable paths and vector masks followed. Further work covered editable solid fills, edge feathering, mask commands, the clipboard and more compact native raster archives. The entries preserve measured residual errors rather than calling the whole format equivalent. [High-depth PSD](DEVLOG.md#dev-step-009), [groups](DEVLOG.md#dev-step-010), [paths and vectors](DEVLOG.md#dev-step-011), [solid fills](DEVLOG.md#dev-step-012), [mask and clipboard sequence](DEVLOG.md#dev-step-015), [archive changes](DEVLOG.md#dev-step-018)

### Attribution, support and the Photato name

Open-source attribution, bundled licenses and optional project/support links were introduced first. The App Store requirement then changed the support design: external donation destinations were replaced with StoreKit consumable tips, the external funding template was removed, and legacy donation metadata was ignored. Simulated StoreKit tests covered purchase and transaction recovery paths, while production registration, prices and release qualification remained open. The application was renamed Photato without removing upstream PhotoCraft credit or silently renaming every internal module. [Fork and attribution](DEVLOG.md#dev-step-008), [tips and removals](DEVLOG.md#dev-step-013), [Photato branding](DEVLOG.md#dev-step-014)

### Adjustments and independent references

The adjustment sequence added manual Levels, histograms and automatic correction, Curves, Hue/Saturation, Desaturate and Color Balance. The work included editable adjustment layers, destructive preview/apply paths, masks, history and PSD records. External Photoshop-produced fixtures exposed Hue/Saturation and Colorize differences that required corrections. The diary keeps source-algorithm agreement separate from Photoshop-output agreement. [Levels](DEVLOG.md#dev-step-019), [histograms](DEVLOG.md#dev-step-020), [Curves](DEVLOG.md#dev-step-021), [Hue/Saturation](DEVLOG.md#dev-step-022), [Color Balance](DEVLOG.md#dev-step-023), [reference-driven correction](DEVLOG.md#dev-step-024)

## 8 October 2026

### Retouching, painting and rendering

Work continued on Hue/Saturation behavior, Threshold and Posterize. Clone Stamp gained source slots, cross-document and mask sampling, alignment and transform controls. Regional rendering and immutable preview caching supported these interactions. Expanding cropped paint targets required careful preservation of existing pixels and mask coordinates. Healing Brush, Spot Healing, patch completion, Dodge, Burn, Sponge, Blur, Sharpen, Smudge, Magic Wand and Paint Bucket were then implemented or expanded through the shared native engine. These are recorded modules with their own limits, not a declaration that every Photoshop variant of those tools is complete. [Adjustment corrections](DEVLOG.md#dev-step-025), [Clone Stamp](DEVLOG.md#dev-step-027), [regional rendering](DEVLOG.md#dev-step-028), [healing](DEVLOG.md#dev-step-030), [toning and focus tools](DEVLOG.md#dev-step-032), [wand and bucket](DEVLOG.md#dev-step-034)

### Patterns and gradients

A persistent pattern library and PAT interchange led to editable Pattern Fill layers and embedded PSD patterns. Profiling then guided CPU rendering improvements. Gradient work introduced retained stops, multiple shapes and interpolation modes, editable Gradient Fill, live and Classic Gradient tools, preset libraries, Gradient Map, and Stripes. Storage, clipboard, previews, history and PSD interchange were extended alongside the features. [Patterns](DEVLOG.md#dev-step-035), [Pattern Fill](DEVLOG.md#dev-step-036), [rendering optimization](DEVLOG.md#dev-step-037), [gradient foundation](DEVLOG.md#dev-step-038), [Gradient Fill](DEVLOG.md#dev-step-039), [tools and presets](DEVLOG.md#dev-step-040), [Gradient Map](DEVLOG.md#dev-step-042), [Stripes](DEVLOG.md#dev-step-043)

Several subsequent milestones were research and correction rather than new tools. Photoshop-saved references were used to investigate RGB16 transparency, Smooth interpolation, neighboring stops, color conversion, stop limits, tone coordinates and Classic arithmetic. Some candidates matched bounded reference sets; remaining mismatches and unsupported Smooth behavior stayed open. This sequence is particularly important to the record: a failed hypothesis or an unresolved numerical difference must remain visible. [RGB16 transparency correction](DEVLOG.md#dev-step-045), [Smooth investigation](DEVLOG.md#dev-step-046), [stop preservation](DEVLOG.md#dev-step-048), [tone coordinates](DEVLOG.md#dev-step-050), [Classic candidate](DEVLOG.md#dev-step-052)

### Recording the work and matching menus

A dedicated documentation audit introduced stable milestone identifiers, the oldest-first index, explicit retrospective corrections, preservation rules and a hashed evidence inventory. It identified overwritten early logs and refused to manufacture missing timestamps or commits. [First development-history audit](DEVLOG.md#dev-step-044)

Layer alignment and distribution were investigated against Photoshop and then connected to native controls. Menu alignment and factory shortcut evidence were treated separately: the default bindings were corrected from the installed factory preset, including primary and alternate shortcuts. Layer via Copy/Cut and merging/flattening followed. The requested pause was taken at version 0.2.0, with the version change distinguished from fresh application test evidence. [Layer layout](DEVLOG.md#dev-step-053), [menu alignment](DEVLOG.md#dev-step-055), [factory shortcuts](DEVLOG.md#dev-step-056), [Copy/Cut](DEVLOG.md#dev-step-057), [merging](DEVLOG.md#dev-step-058), [version and pause](DEVLOG.md#dev-step-059)

### Native workspace organization

After resumption under the then-current UI-first priorities, work addressed workspace visibility, native document windows, tab dragging, the shared application frame, floating canvases, zoom entry, compact layouts, saved workspaces and editable panel groups. These were prerequisites for a usable native editor rather than evidence of complete Photoshop tool coverage. [Resumed priorities](DEVLOG.md#dev-step-060), [document windows](DEVLOG.md#dev-step-061), [shared frame](DEVLOG.md#dev-step-063), [saved workspaces](DEVLOG.md#dev-step-066), [dock groups](DEVLOG.md#dev-step-067)

## 9 October 2026

### Panels and layer interactions

Panel work continued with floating hosts, tear-off, stacks, columns, and retained History and Clone Source panels. Layer workflows gained New Layer, New Group and duplication dialogs, panel commands, inline naming, delete confirmation, color labels, visibility interactions, group disclosure and active-layer reveal. Thumbnail options, mask gestures, layout repairs, absolute positions and numeric-editing lifecycle followed. The detailed entries distinguish automated checks from live checks that could not run while the Mac was locked. [Floating panels](DEVLOG.md#dev-step-068), [panel columns](DEVLOG.md#dev-step-071), [layer dialogs](DEVLOG.md#dev-step-073), [layer menu and naming](DEVLOG.md#dev-step-076), [visibility](DEVLOG.md#dev-step-078), [thumbnail options](DEVLOG.md#dev-step-082), [mask gestures](DEVLOG.md#dev-step-084), [numeric editing](DEVLOG.md#dev-step-087)

### Xcode and the outstanding-work inventory

A native `Photato.xcodeproj` was added beside the Swift package, with application and module targets, shared schemes, universal Release configuration, resources and the macOS 14 deployment target. Channels and component previews were developed next. At the maintainer's request, implementation paused for a comprehensive parity inventory: 105 work packages, explicit gaps, dependencies and effort estimates. The estimates were engineering judgments, not promised completion dates, and some full-equivalence requirements had no defensible ETA. [Xcode project](DEVLOG.md#dev-step-088), [Channels panel](DEVLOG.md#dev-step-089), [parity inventory and estimates](DEVLOG.md#dev-step-090)

### Optional APIs and the product webpage

The optional native automation API and browser client were added as separately authorized work. Native transactions, permissions, document sharing and endpoint state were part of that increment. Subsequent decisions made API coverage mandatory for new features and established the published Adobe Photoshop v2 contract as a separate compatibility target. Both interfaces were retained over one Swift engine. Local server authentication and supported operations were not represented as Adobe's identity service or complete hosted-service compatibility. [Initial API](DEVLOG.md#dev-step-091), [API completion rule](DEVLOG.md#dev-step-094), [Adobe contract requirement](DEVLOG.md#dev-step-095), [both APIs](DEVLOG.md#dev-step-096)

The Photato product webpage was created at `nusite/index.html`, following the existing forensicintelligence.ca style and showing provenance and development status. This was a separate presentation task during a pause in native feature development. [Webpage record](DEVLOG.md#dev-step-097)

## 13 October 2026

### Accessibility, channels and recorded actions

Resumed work repaired native panel menu accessibility and qualified floating-panel input. Channel research distinguished visibility from the selected editing target, leading to independent RGB visibility and API state. Component-editing references and transaction design then supported recorded Photoshop actions and component integration. Failed attempts and subsequent qualification were preserved before another requested pause. [Accessibility](DEVLOG.md#dev-step-098), [floating-panel input](DEVLOG.md#dev-step-099), [channel behavior](DEVLOG.md#dev-step-100), [RGB visibility](DEVLOG.md#dev-step-101), [component research](DEVLOG.md#dev-step-102), [recorded actions](DEVLOG.md#dev-step-103), [pause](DEVLOG.md#dev-step-104)

## 19 October 2026

### Component editing and a new implementation order

The component integration resumed with native controls and both public API paths. Independent Photoshop fixtures were exercised through the shared workflow. Testing caught stale catalogue expectations and UI/context problems; repairs and repeat qualification were recorded before the requested pause. The maintainer then changed the scheduling order to major functions, minor functions, and final details. The backlog was reorganized around that order without reducing the parity requirements. [Investigation and pause](DEVLOG.md#dev-step-105), [component/API integration](DEVLOG.md#dev-step-106), [verified pause](DEVLOG.md#dev-step-107), [priority change](DEVLOG.md#dev-step-108), [major-workflow backlog](DEVLOG.md#dev-step-109)

### Documents, color and file preservation

The major document workflow expanded through persistence, the `.photato` extension, source-format preservation and source-format Save. Work on exact RGB32 samples, linear HDR editing, retained working profiles, Normal composition and grouped/clipped documents used independent references to distinguish actual precision fixes from unqualified rendering behavior. PSB integration and bounded PSD/PSB row and file decoding followed, then streamed output and safe saving. [Persistence](DEVLOG.md#dev-step-110), [file extension](DEVLOG.md#dev-step-111), [source formats](DEVLOG.md#dev-step-112), [float samples](DEVLOG.md#dev-step-114), [working profiles](DEVLOG.md#dev-step-116), [Normal rendering](DEVLOG.md#dev-step-117), [groups and clipping](DEVLOG.md#dev-step-118), [PSB](DEVLOG.md#dev-step-119), [streamed saving](DEVLOG.md#dev-step-122)

### History, recovery and interruption handling

Scratch-backed undo, native archive streaming and shared tile storage addressed history and memory use. Cancellable asynchronous history navigation was followed by crash recovery, background backup writing, recovery preferences, atomic persistence and source-identity checks. The purpose was to make large documents and interrupted workflows safer without silently losing content, overwriting changed originals, or publishing stale background results. [Scratch history](DEVLOG.md#dev-step-123), [archive streaming](DEVLOG.md#dev-step-124), [asynchronous history](DEVLOG.md#dev-step-126), [recovery lifecycle](DEVLOG.md#dev-step-127), [preferences](DEVLOG.md#dev-step-129), [atomic persistence](DEVLOG.md#dev-step-130), [source identity](DEVLOG.md#dev-step-131)

## 20 October 2026

### Opening, closing and recovery management

Recovery discovery became independent of the original document location. Coordinated closing, background opening, persistent recent files and queued opens were added or expanded. Recovery maintenance, explicit salvage, damaged-index reset, background discovery and memory admission followed. These workflows include native and API behavior, preservation of backups, cancellation and failure cases. Automatic memory admission remains an estimate, not a claim of a complete paging system. [Recovery discovery](DEVLOG.md#dev-step-132), [closing](DEVLOG.md#dev-step-133), [opening](DEVLOG.md#dev-step-134), [recent files](DEVLOG.md#dev-step-135), [backup maintenance](DEVLOG.md#dev-step-136), [salvage](DEVLOG.md#dev-step-137), [background discovery](DEVLOG.md#dev-step-138), [memory admission](DEVLOG.md#dev-step-139)

### Saving options and TIFF interoperability

Shared native/API encoding options started with PNG and TIFF settings, then PSD/PSB compression and file-compression preferences. TIFF work addressed float preservation, byte order, channel layout and prediction, layered import, editable layered output, numeric adjustments, vector masks and global mask-display metadata. An unreliable generic descriptor conversion draft was removed from production and preserved with the conflicting reference evidence. An independent parser's limitations were also documented and handled separately; they were not used to justify weakening the application checks. [Shared encoding options](DEVLOG.md#dev-step-140), [PSD/PSB compression](DEVLOG.md#dev-step-141), [file preferences](DEVLOG.md#dev-step-142), [float TIFF](DEVLOG.md#dev-step-143), [storage options](DEVLOG.md#dev-step-144), [layer import](DEVLOG.md#dev-step-145), [layer output](DEVLOG.md#dev-step-146), [rich records and rejected draft](DEVLOG.md#dev-step-147)

At verified checkpoint 147, the record reports 1,390 passing Debug tests and 1,390 passing Release tests, independent output inspection, universal packaging and native Release save checks on Apple Silicon and Rosetta. This is a qualified checkpoint, not a completed Photoshop clone. All major workflow gates remain open. [Checkpoint 147](ACTIVE_CHECKPOINT_147.json)

### JPEG work in progress at reconstruction

Milestone 148 is developing JPEG quality, format, matte and color-profile controls with shared native/API output. The recorded investigation distinguishes Adobe's published quality choices from Photato-specific options and keeps Photoshop quantization and progressive scan-count equivalence open. At this diary snapshot, the observed focused attempts include a compiler failure followed by a run with 47 tests and six failures. The latter exposed restart-marker handling and an incorrect assumption that the platform always embeds sRGB ICC data. Those are findings under repair, not a successful release claim. Consult the running entry for subsequent results. [Current JPEG entry](DEVLOG.md#dev-step-148)

## Changes of direction and removals

The diary records removal as deliberately as addition. Important examples include removing the earlier Private Cloud Compute exclusion; replacing external donation integration with StoreKit and deleting the funding template; correcting menu and shortcut defaults from factory evidence; removing stale format metadata where edits invalidate it; and withdrawing the unqualified TIFF descriptor-conversion draft from production. Rejected experiments remain evidence even when they do not become application code. [AI policy](DEVLOG.md#dev-step-004), [support replacement](DEVLOG.md#dev-step-013), [shortcuts](DEVLOG.md#dev-step-056), [metadata handling](DEVLOG.md#dev-step-026), [withdrawn draft](DEVLOG.md#dev-step-147)

## How the diary stays current

Every meaningful addition, modification, deletion, rename, rollback or replacement must be recorded as work proceeds. Related edits may share an entry, but the entry must identify what changed, the affected paths or modules, why it changed, its user-visible or API effect, and how it was checked. A removal must name what was removed and whether anything replaces it. Investigation, failed tests, rejected approaches, repairs and remaining gaps belong in the same record; a final successful test count cannot replace them.

The detailed entry is written in [DEVLOG](DEVLOG.md) under a stable milestone anchor. Unique run folders preserve before/after identities and test evidence. At a completed checkpoint, this readable diary receives the new chronology and any material change to the narrative. The [evidence inventory](DEVELOPMENT_HISTORY.json) connects the records to surviving files. These obligations are part of [the repository instructions](../AGENTS.md) and [the contribution requirements](../CONTRIBUTING.md#development-record).

The original extracted Rust snapshot has no preserved upstream Git history, and some early logs were overwritten. The surviving record therefore cannot prove every historical keystroke or deleted intermediate file. Missing detail stays unknown. Neither this reconstruction nor the evidence audit creates an initial commit, recovers absent files, or certifies Photoshop parity.

### JPEG checkpoint verified after the reconstruction

**Update recorded 20 October 2026 after checkpoint148.** The failures above were retained and repaired: Swift matte conversion was disambiguated, nonzero JPEG restart intervals were supported, explicit ICC insertion/removal was added, and an invalid transparent ordinary-save test was corrected without relaxing the application guard. Native Save/Copy, Photato output and Adobe-defined JPEG job quality choices now share the encoder. All1,398 Debug and1,398 Release tests pass, with independent libjpeg-turbo coefficient/sample checks, universal packaging and public Release saves on Apple Silicon/Rosetta. Default JPEG outputs and161 retained prior exports remain byte-identical to147. Five live Photoshop references establish that quality8 quantization/chroma sampling and progressive schedules still differ. The original Photoshop Untitled-1 was restored. All major gates stay open. [Verified checkpoint148](ACTIVE_CHECKPOINT_148.json), [detailed repairs and live evidence](DEVLOG.md#dev-step-148)

### Reading original PhotoCraft containers in Swift

Step149 adds the container groundwork for editable `.pcraft` migration: ZIP framing, Zstandard entropy decoding and BLAKE3 content verification. Procedural fixtures generated by the original Rust source cover 8-, 16- and 32-bit documents with layers and masks. The decoder verifies 42 tile addresses and 42 blob streams; an independent Zstandard encoder supplies 48 further cases, with official hash vectors and malformed-input tests. A repeat using the original dependency lock produces identical fixture bytes.

The first Swift compile failed on missing error propagation in ZIP checks. A later focused run exposed an invalid hand-built Huffman fixture; the external decoder rejected it too. Both failures remain recorded, and the repaired fixture retains its invalid predecessor as a rejection case. Final qualification passes 1,408 Debug and 1,408 Release tests, universal packaging and matching optimized decoder probes on Apple Silicon and Intel under Rosetta. Existing production modules were retained; seven internal decoder modules, one test module and attributed fixtures were added. Notices and the development records were updated.

This completes a tested dependency, not editable project import. Manifest mapping, directory bundles, desktop/API integration and full migration remain open under major item I03. No new user-facing command or API capability is advertised. The installed app and user documents/settings remain preserved. [Container foundation](DEVLOG.md#dev-step-149), [checkpoint149](ACTIVE_CHECKPOINT_149.json)

### Preserving the complete source project graph before native mapping

Step150 found that direct import would lose source semantics: separate pixel/transparency/position locks, unbounded raster defaults, rich text, Smart Objects and other document features are not fully represented by the native model. The increment therefore adds an internal graph and payload reader, keeping original JSON and exact numeric tokens rather than prematurely converting those features. Known source surfaces retain signed tile positions, encoded defaults and sample bytes; known blob references are verified. Guarded directory reads complement ZIP input, and linked external Smart Object files are never opened.

Three rich fixtures use the original Rust test generator, extended with layer comps, video defaults and large IDs. The first caller asserted full equality and failed because the source loader intentionally remaps extreme IDs. A second caller and manifest comparison establish that only identities and comp links change. All48 source surfaces and222 stored payloads receive independent ZIP/JSON/zstd inventory checks. Intel qualification initially fails because SwiftPM discovers tests in an arm64 process; explicitly running the existing x86_64 bundle under Rosetta repairs the harness without source changes. Focused tests pass, then a source review adds the maximum-depth empty-group boundary regression before the final freeze. Final qualification passes1,422 Debug and1,422 Release tests,24 focused tests under Rosetta and universal package checks;692 prior output/reference files remain unchanged.

Three production modules, one test module and five attributed fixture files are added; prior application/Core/AI/API/menu sources are retained. No functionality is removed, no new public import capability is advertised, and all major gates remain open. Next is native partial-lock behavior and the editable adapter with matching UI/API/history/persistence tests. [Project reader record](DEVLOG.md#dev-step-150), [checkpoint150](ACTIVE_CHECKPOINT_150.json)

### Separating Photoshop's protection settings

Step151 verified the lock behavior on a disposable procedural document in Photoshop2026.
Transparency, Image, Position, Prevent auto-nest and All produce distinct stored flags; All
uses a high bit that the old native writer omits. A fully locked layer can still be renamed.
Image forces Transparency checked, and the Command-/ shortcut differs from clearing All
inside the dialog. Independent Python PSD/PackBits decoding checks nine saved states,
including a black fill that preserves every alpha byte. The user's original document remains
untouched. An initial parser offset mistake and custom-dialog accessibility failures are
recorded alongside successful repairs. The first Intel build-tests attempt omitted
testable imports in Release; a retained retry adds the compiler flag without source changes.

The native changes add isolated value, PSD record and Adobe field parsers, three test modules
and eleven fixture/provenance files. The current official Adobe contract matches the pinned
version and confirms contextual omitted/null/empty protection semantics. These modules remain
inactive: changing import interpretation before all command guards migrate could expose
protected content to unintended editing. Model/archive migration, painting, groups/masks,
desktop controls and both APIs are still required together. No existing functionality is
removed or replaced, and no new executable API capability is claimed.

All10 focused,1,432 Debug,1,432 Release and10 Rosetta-focused tests pass, as do universal package
checks. All1,109 previous inputs and692 previous exported/reference files remain unchanged.
Seventeen files are added. Installed117 and user settings remain preserved. The checkpoint
records the six-part activation plan; all major gates remain open.
[Protection record](DEVLOG.md#dev-step-151), [checkpoint151](ACTIVE_CHECKPOINT_151.json)

### 2026-10-20 — protection reaches editing and both APIs (step152)

The previous isolated protection model now governs actual native edits and file persistence. Painting preserves the existing alpha stencil; Photoshop’s explicit selected Clear removes pixels. Image and position locks block their respective operations, while full-lock Rename and grouping follow the observed reference. The native dialog, layer buttons, shortcut and both API paths share those transactions. Version12 prevents older readers from silently losing partial protection; compatible existing files retain their prior version.

The first two compilations exposed test inference and initialization errors. Full01 later found94 failed assertions, mostly90 repetitions of the old TIFF partial-to-full collapse. An independent byte inventory proved all30 TIFF fixtures contain transparency-only protection. Focused06 also exposed a known unsupported little-endian opaque metadata block; the test now distinguishes that limitation from protection-only output. Later review also corrected API-only flag transitions and a reproduced protected-Fill integer quantization defect; both interrupted validations and the failing regression are preserved. Live testing then exposed initial checkbox enablement overridden during SwiftUI installation; a hosted-control regression reproduced five failures before the environment-state fix. Final59 focused,1,442 Debug,1,442 Release and20 Rosetta tests pass, with universal packaging and an owned native UI probe. This is bounded integration, not complete Photoshop parity; all major gates remain open.

[Runtime development record](DEVLOG.md#dev-step-152), [checkpoint152](ACTIVE_CHECKPOINT_152.json)

Step153 completes the first editable original-project migration subset. Source-generated RGB8/16/32 fixtures retain raster/group/mask/path/selection/protection data through native Open, API editing and Photato persistence. Empty-selection and file-registration regressions were reproduced and repaired; all 1,455 Debug/Release tests,13 Rosetta cases,universal packaging and an owned live workflow pass. Rich source features and all major gates remain open. See [the detailed step153 record](DEVLOG.md#dev-step-153).

Step154 adds independent source/Photoshop rendering comparisons and repairs off-canvas raster-mask edge handling. The first broad cropped-mask hypothesis was disproved by controls; the final change follows the measured layer-boundary distinction. All 1,460 Debug/Release tests, 14 Rosetta cases and native/UI/API/package checks pass. Gaussian/vector/full byte parity remains open. See [step154](DEVLOG.md#dev-step-154).

## 26 October 2026

Step155 resumes the feather experiment begun on20October. Controlled identical-byte tests identify a filesystem visibility defect behind misleading Photoshop import errors. The first core repair passes while end-to-end tests expose AppKit staging as a second boundary; the final change carries destination visibility through both. All1,471 Debug/Release,33 focused and22 Rosetta tests pass, and direct Photoshop Open accepts native UI and generated outputs without byte changes. The atlas independently records16 radii, with exploratory exact fits at4/5/10; general feather parity remains unfinished. Historical pauses, failed tests/harnesses and both current-source builds are preserved. See [step155](DEVLOG.md#dev-step-155).

### 26 October: major features before numerical refinement

Step156 captures 48 independent transparent feather controls, but fractional radii invalidate the first simple kernel hypothesis. The maintainer asks to prioritize missing major functionality. Research and reference files are preserved; no feather algorithm is changed. [Deferred research](DEVLOG.md#dev-step-156)

Step157 adds a shared Swift raster-filter workflow: Gaussian/Box/Motion Blur, Unsharp Mask, High Pass, Add Noise, Mosaic and Average. Native preview sheets, Cancel/OK, selection and locks, one undoable edit, existing file persistence, the Photato command and both resource-job interfaces are integrated together. All59 focused Debug and1,483 full Release tests pass, along with24 functional cases on arm64 and x86_64 under Rosetta. The universal macOS14+ candidate and live UI checks verify; installed117 remains unchanged. Failed fixture/old synchronous-test assumptions and outdated API-count assertions are retained with their repairs. Exact Photoshop filter pixels and Smart Filters remain open. [Filter workflow](DEVLOG.md#dev-step-157)

## Complete chronological index

Every numbered milestone in the source diary at this reconstruction appears below. The link opens the full account of its changes, failures, tests and remaining work. An index entry is a record of activity; research and pause entries are not completed features.

| Date | Milestone | Recorded development |
|---|---:|---|
| 2026-10-07 | 001 | [native Swift migration milestone 1](DEVLOG.md#dev-step-001) |
| 2026-10-07 | 002 | [ordered parity and professional workflow gates](DEVLOG.md#dev-step-002) |
| 2026-10-07 | 003 | [Photoshop 2026 workspace replication](DEVLOG.md#dev-step-003) |
| 2026-10-07 | 004 | [Private Cloud Compute re-enabled](DEVLOG.md#dev-step-004) |
| 2026-10-07 | 005 | [native geometry module](DEVLOG.md#dev-step-005) |
| 2026-10-07 | 006 | [coverage selections and direct mask editing](DEVLOG.md#dev-step-006) |
| 2026-10-07 | 007 | [independent layer masks and PSD interoperability](DEVLOG.md#dev-step-007) |
| 2026-10-07 | 008 | [open-source fork and optional support](DEVLOG.md#dev-step-008) |
| 2026-10-07 | 009 | [compressed and high-depth PSD interchange](DEVLOG.md#dev-step-009) |
| 2026-10-07 | 010 | [native layer groups and clipping masks](DEVLOG.md#dev-step-010) |
| 2026-10-07 | 011 | [native paths and vector masks](DEVLOG.md#dev-step-011) |
| 2026-10-07 | 012 | [editable PSD solid fills and exactness measurements](DEVLOG.md#dev-step-012) |
| 2026-10-07 | 013 | [native App Store tips](DEVLOG.md#dev-step-013) |
| 2026-10-07 | 014 | [Photato branding](DEVLOG.md#dev-step-014) |
| 2026-10-07 | 015 | [feathered pixel masks at canvas boundaries](DEVLOG.md#dev-step-015) |
| 2026-10-07 | 016 | [native mask commands and isolated vector-alpha diagnostics](DEVLOG.md#dev-step-016) |
| 2026-10-07 | 017 | [native image and layer clipboard](DEVLOG.md#dev-step-017) |
| 2026-10-07 | 018 | [compact raster archives and faster pixel packing](DEVLOG.md#dev-step-018) |
| 2026-10-07 | 019 | [manual RGB Levels](DEVLOG.md#dev-step-019) |
| 2026-10-07 | 020 | [Levels histograms, presets and automatic correction](DEVLOG.md#dev-step-020) |
| 2026-10-07 | 021 | [RGB Curves editing and interchange](DEVLOG.md#dev-step-021) |
| 2026-10-07 | 022 | [Hue/Saturation, color ranges and Desaturate](DEVLOG.md#dev-step-022) |
| 2026-10-07 | 023 | [Color Balance workflow and PSD storage](DEVLOG.md#dev-step-023) |
| 2026-10-07 | 024 | [real Hue/Saturation PSD references and Colorize correction](DEVLOG.md#dev-step-024) |
| 2026-10-08 | 025 | [Hue/Saturation range transfer correction](DEVLOG.md#dev-step-025) |
| 2026-10-08 | 026 | [Threshold and Posterize](DEVLOG.md#dev-step-026) |
| 2026-10-08 | 027 | [native Clone Stamp workflow](DEVLOG.md#dev-step-027) |
| 2026-10-08 | 028 | [regional composition and immutable preview cache](DEVLOG.md#dev-step-028) |
| 2026-10-08 | 029 | [expandable Clone Stamp targets and mask sources](DEVLOG.md#dev-step-029) |
| 2026-10-08 | 030 | [sampled Healing Brush in native Swift](DEVLOG.md#dev-step-030) |
| 2026-10-08 | 031 | [automatic Spot Healing and native patch completion](DEVLOG.md#dev-step-031) |
| 2026-10-08 | 032 | [Dodge, Burn and Sponge](DEVLOG.md#dev-step-032) |
| 2026-10-08 | 033 | [Blur, Sharpen and Smudge](DEVLOG.md#dev-step-033) |
| 2026-10-08 | 034 | [Magic Wand and foreground Paint Bucket](DEVLOG.md#dev-step-034) |
| 2026-10-08 | 035 | [native patterns and PAT interchange](DEVLOG.md#dev-step-035) |
| 2026-10-08 | 036 | [editable Pattern Fill layers and embedded PSD patterns](DEVLOG.md#dev-step-036) |
| 2026-10-08 | 037 | [exact CPU rendering and Pattern Fill picking optimizations](DEVLOG.md#dev-step-037) |
| 2026-10-08 | 038 | [Gradient engine and preset foundation](DEVLOG.md#dev-step-038) |
| 2026-10-08 | 039 | [Editable Gradient Fill and PSD merged transparency](DEVLOG.md#dev-step-039) |
| 2026-10-08 | 040 | [native live and Classic Gradient tools](DEVLOG.md#dev-step-040) |
| 2026-10-08 | 041 | [persistent native gradient preset library](DEVLOG.md#dev-step-041) |
| 2026-10-08 | 042 | [native Gradient Map and Photoshop 2026 reference acquisition](DEVLOG.md#dev-step-042) |
| 2026-10-08 | 043 | [Stripes gradients and Photoshop depth/import compatibility](DEVLOG.md#dev-step-043) |
| 2026-10-08 | 044 | [development record audit and documentation discipline](DEVLOG.md#dev-step-044) |
| 2026-10-08 | 045 | [RGB16 merged transparency correction](DEVLOG.md#dev-step-045) |
| 2026-10-08 | 046 | [Smooth gradient reference acquisition and analysis](DEVLOG.md#dev-step-046) |
| 2026-10-08 | 047 | [Smooth neighboring-stop investigation](DEVLOG.md#dev-step-047) |
| 2026-10-08 | 048 | [Gradient Map stop preservation and Smooth color probes](DEVLOG.md#dev-step-048) |
| 2026-10-08 | 049 | [Bounded Smooth color-conversion references](DEVLOG.md#dev-step-049) |
| 2026-10-08 | 050 | [Native RGB16 Gradient Map tone coordinates](DEVLOG.md#dev-step-050) |
| 2026-10-08 | 051 | [Classic gradient lookup investigation](DEVLOG.md#dev-step-051) |
| 2026-10-08 | 052 | [Classic native arithmetic candidate](DEVLOG.md#dev-step-052) |
| 2026-10-08 | 053 | [Layer alignment and distribution reference qualification](DEVLOG.md#dev-step-053) |
| 2026-10-08 | 054 | [Native layer layout commands and controls](DEVLOG.md#dev-step-054) |
| 2026-10-08 | 055 | [Photoshop 2026 menu structure alignment](DEVLOG.md#dev-step-055) |
| 2026-10-08 | 056 | [Photoshop factory menu and shortcut defaults](DEVLOG.md#dev-step-056) |
| 2026-10-08 | 057 | [Layer via Copy and Cut](DEVLOG.md#dev-step-057) |
| 2026-10-08 | 058 | [Layer merging and flattening](DEVLOG.md#dev-step-058) |
| 2026-10-08 | 059 | [Minor version 0.2.0 and requested pause](DEVLOG.md#dev-step-059) |
| 2026-10-08 | 060 | [Workspace visibility and resumed UI priority](DEVLOG.md#dev-step-060) |
| 2026-10-08 | 061 | [Native document windows and Window menu](DEVLOG.md#dev-step-061) |
| 2026-10-08 | 062 | [Native tab drag and drop](DEVLOG.md#dev-step-062) |
| 2026-10-08 | 063 | [Shared application frame and floating canvases](DEVLOG.md#dev-step-063) |
| 2026-10-08 | 064 | [Native viewport zoom and percentage entry](DEVLOG.md#dev-step-064) |
| 2026-10-08 | 065 | [Compact workspace layout](DEVLOG.md#dev-step-065) |
| 2026-10-08 | 066 | [Shared saved workspaces](DEVLOG.md#dev-step-066) |
| 2026-10-08 | 067 | [Editable panel dock groups](DEVLOG.md#dev-step-067) |
| 2026-10-09 | 068 | [Native floating panel hosts](DEVLOG.md#dev-step-068) |
| 2026-10-09 | 069 | [Native panel tear-off](DEVLOG.md#dev-step-069) |
| 2026-10-09 | 070 | [Native floating panel stacks](DEVLOG.md#dev-step-070) |
| 2026-10-09 | 071 | [Native dock columns](DEVLOG.md#dev-step-071) |
| 2026-10-09 | 072 | [Retained History and Clone Source panels](DEVLOG.md#dev-step-072) |
| 2026-10-09 | 073 | [Native New Layer dialog](DEVLOG.md#dev-step-073) |
| 2026-10-09 | 074 | [Native New Group workflows](DEVLOG.md#dev-step-074) |
| 2026-10-09 | 075 | [Native Duplicate Layer and Group workflows](DEVLOG.md#dev-step-075) |
| 2026-10-09 | 076 | [Layers panel commands and inline renaming](DEVLOG.md#dev-step-076) |
| 2026-10-09 | 077 | [Layer text editing and delete confirmation UX](DEVLOG.md#dev-step-077) |
| 2026-10-09 | 078 | [Layer color labels and visibility workflows](DEVLOG.md#dev-step-078) |
| 2026-10-09 | 079 | [Native Layers eye-column dragging](DEVLOG.md#dev-step-079) |
| 2026-10-09 | 080 | [Group disclosure and collapse-all view state](DEVLOG.md#dev-step-080) |
| 2026-10-09 | 081 | [Active-layer reveal and minimal scrolling](DEVLOG.md#dev-step-081) |
| 2026-10-09 | 082 | [Native Layers Panel Options and thumbnails](DEVLOG.md#dev-step-082) |
| 2026-10-09 | 083 | [Thumbnail coverage and mask preview geometry](DEVLOG.md#dev-step-083) |
| 2026-10-09 | 084 | [Mask-thumbnail gestures and mask canvas views](DEVLOG.md#dev-step-084) |
| 2026-10-09 | 085 | [Workspace layout lifecycle investigation and reveal repair](DEVLOG.md#dev-step-085) |
| 2026-10-09 | 086 | [Compact field layout and absolute position editing](DEVLOG.md#dev-step-086) |
| 2026-10-09 | 087 | [Native numeric editing lifecycle](DEVLOG.md#dev-step-087) |
| 2026-10-09 | 088 | [Native Xcode application project](DEVLOG.md#dev-step-088) |
| 2026-10-09 | 089 | [Channels panel and component previews](DEVLOG.md#dev-step-089) |
| 2026-10-09 | 090 | [User-requested pause, comprehensive parity inventory and estimates](DEVLOG.md#dev-step-090) |
| 2026-10-09 | 091 | [Optional native automation API and browser client](DEVLOG.md#dev-step-091) |
| 2026-10-09 | 092 | [Sheet lifecycle and panel organization validation](DEVLOG.md#dev-step-092) |
| 2026-10-09 | 093 | [User-requested pause after verified current increment](DEVLOG.md#dev-step-093) |
| 2026-10-09 | 094 | [Require API coverage with every new capability](DEVLOG.md#dev-step-094) |
| 2026-10-09 | 095 | [Published Adobe Photoshop API v2 compatibility requirement](DEVLOG.md#dev-step-095) |
| 2026-10-09 | 096 | [Maintain Photato and Adobe-compatible APIs together](DEVLOG.md#dev-step-096) |
| 2026-10-09 | 097 | [Photato product webpage and public provenance](DEVLOG.md#dev-step-097) |
| 2026-10-13 | 098 | [Resumed native panel menu accessibility](DEVLOG.md#dev-step-098) |
| 2026-10-13 | 099 | [Floating panel input qualification](DEVLOG.md#dev-step-099) |
| 2026-10-13 | 100 | [Channel interaction reference qualification](DEVLOG.md#dev-step-100) |
| 2026-10-13 | 101 | [RGB channel visibility and API](DEVLOG.md#dev-step-101) |
| 2026-10-13 | 102 | [Component editing reference and transaction design](DEVLOG.md#dev-step-102) |
| 2026-10-13 | 103 | [Recorded Photoshop actions and component integration](DEVLOG.md#dev-step-103) |
| 2026-10-13 | 104 | [Verified pause after latest debugging](DEVLOG.md#dev-step-104) |
| 2026-10-19 | 105 | [Component integration investigation and verified pause](DEVLOG.md#dev-step-105) |
| 2026-10-19 | 106 | [Native component editing and public API integration](DEVLOG.md#dev-step-106) |
| 2026-10-19 | 107 | [Verified pause after component and API debugging](DEVLOG.md#dev-step-107) |
| 2026-10-19 | 108 | [Major-function-first completion order](DEVLOG.md#dev-step-108) |
| 2026-10-19 | 109 | [Major-function backlog and native document workflow](DEVLOG.md#dev-step-109) |
| 2026-10-19 | 110 | [Document persistence workflow](DEVLOG.md#dev-step-110) |
| 2026-10-19 | 111 | [Native .photato file extension](DEVLOG.md#dev-step-111) |
| 2026-10-19 | 112 | [Source-format preservation](DEVLOG.md#dev-step-112) |
| 2026-10-19 | 113 | [Source-format Save workflow](DEVLOG.md#dev-step-113) |
| 2026-10-19 | 114 | [Exact RGB32 sample preservation](DEVLOG.md#dev-step-114) |
| 2026-10-19 | 115 | [Direct linear HDR editing and composite qualification](DEVLOG.md#dev-step-115) |
| 2026-10-19 | 116 | [Retained working colour profiles](DEVLOG.md#dev-step-116) |
| 2026-10-19 | 117 | [RGB32 Normal rendering and PSD merged output](DEVLOG.md#dev-step-117) |
| 2026-10-19 | 118 | [RGB32 grouped and clipped document qualification](DEVLOG.md#dev-step-118) |
| 2026-10-19 | 119 | [PSB document-format integration](DEVLOG.md#dev-step-119) |
| 2026-10-19 | 120 | [bounded PSD/PSB row decoding](DEVLOG.md#dev-step-120) |
| 2026-10-19 | 121 | [bounded PSD/PSB file input](DEVLOG.md#dev-step-121) |
| 2026-10-19 | 122 | [streamed PSD/PSB output and safe saving](DEVLOG.md#dev-step-122) |
| 2026-10-19 | 123 | [scratch-backed undo history](DEVLOG.md#dev-step-123) |
| 2026-10-19 | 124 | [native archive streaming](DEVLOG.md#dev-step-124) |
| 2026-10-19 | 125 | [shared tile storage during history restoration](DEVLOG.md#dev-step-125) |
| 2026-10-19 | 126 | [cancellable asynchronous history navigation](DEVLOG.md#dev-step-126) |
| 2026-10-19 | 127 | [crash recovery lifecycle](DEVLOG.md#dev-step-127) |
| 2026-10-19 | 128 | [background recovery writing](DEVLOG.md#dev-step-128) |
| 2026-10-19 | 129 | [recovery preferences](DEVLOG.md#dev-step-129) |
| 2026-10-19 | 130 | [atomic persistence and interruption handling](DEVLOG.md#dev-step-130) |
| 2026-10-19 | 131 | [recovery source identity](DEVLOG.md#dev-step-131) |
| 2026-10-20 | 132 | [independent recovery discovery](DEVLOG.md#dev-step-132) |
| 2026-10-20 | 133 | [coordinated document closing](DEVLOG.md#dev-step-133) |
| 2026-10-20 | 134 | [format-aware background document opening](DEVLOG.md#dev-step-134) |
| 2026-10-20 | 135 | [persistent recent files and queued document opens](DEVLOG.md#dev-step-135) |
| 2026-10-20 | 136 | [recovery backup review and maintenance](DEVLOG.md#dev-step-136) |
| 2026-10-20 | 137 | [explicit recovery salvage and index reset](DEVLOG.md#dev-step-137) |
| 2026-10-20 | 138 | [background startup recovery](DEVLOG.md#dev-step-138) |
| 2026-10-20 | 139 | [recovery memory admission](DEVLOG.md#dev-step-139) |
| 2026-10-20 | 140 | [shared format-specific save and export options](DEVLOG.md#dev-step-140) |
| 2026-10-20 | 141 | [PSD and PSB compression](DEVLOG.md#dev-step-141) |
| 2026-10-20 | 142 | [Photoshop file compression preferences](DEVLOG.md#dev-step-142) |
| 2026-10-20 | 143 | [TIFF floating-point preservation](DEVLOG.md#dev-step-143) |
| 2026-10-20 | 144 | [TIFF storage options](DEVLOG.md#dev-step-144) |
| 2026-10-20 | 145 | [Layered TIFF interoperability](DEVLOG.md#dev-step-145) |
| 2026-10-20 | 146 | [Editable layered TIFF output](DEVLOG.md#dev-step-146) |
| 2026-10-20 | 147 | [TIFF rich records and global mask metadata](DEVLOG.md#dev-step-147) |
| 2026-10-20 | 148 | [JPEG native and API save controls](DEVLOG.md#dev-step-148) |
| 2026-10-20 | 149 | [Original PhotoCraft container foundation](DEVLOG.md#dev-step-149) |
| 2026-10-20 | 150 | [Original PhotoCraft project graph and payload reader](DEVLOG.md#dev-step-150) |
| 2026-10-20 | 151 | [Layer protection references and model](DEVLOG.md#dev-step-151) |
| 2026-10-20 | 152 | [Layer protection runtime integration](DEVLOG.md#dev-step-152) |
| 2026-10-20 | 153 | [Editable original PhotoCraft project adapter](DEVLOG.md#dev-step-153) |
| 2026-10-20 | 154 | [Source comparison and off-canvas mask correction](DEVLOG.md#dev-step-154) |
| 2026-10-26 | 155 | [File visibility repair and feather reference measurements](DEVLOG.md#dev-step-155) |
| 2026-10-26 | 156 | [Feather research deferred for major functions](DEVLOG.md#dev-step-156) |
| 2026-10-26 | 157 | [Native raster-filter workflow](DEVLOG.md#dev-step-157) |
| 2026-10-26 | 158 | [Editable layer styles](DEVLOG.md#dev-step-158) |
| 2026-10-26 | 159 | [Automatic subject selection and background removal](DEVLOG.md#dev-step-159) |
| 2026-10-26 | 160 | [Embedded Smart Object workflow](DEVLOG.md#dev-step-160) |
| 2026-10-26 | 161 | [Editable Smart Filter stacks](DEVLOG.md#dev-step-161) |
| 2026-10-26 | 162 | [Native text editing](DEVLOG.md#dev-step-162) |
| 2026-10-26 | 163 | [Classic adjustment workflows](DEVLOG.md#dev-step-163) |
| 2026-10-26 | 164 | [Color Lookup workflow](DEVLOG.md#dev-step-164) |
| 2026-10-26 | 165 | [Native Liquify workspace](DEVLOG.md#dev-step-165) |
| 2026-10-26 | 166 | [Native Select and Mask workspace](DEVLOG.md#dev-step-166) |
| 2026-10-26 | 167 | [Alpha channels and Quick Mask](DEVLOG.md#dev-step-167) |
| 2026-10-26 | 168 | [Content-Aware Fill workspace](DEVLOG.md#dev-step-168) |
| 2026-10-26 | 169 | [Content-Aware Scale](DEVLOG.md#dev-step-169) |
| 2026-10-26 | 170 | [Crop and content-aware edges](DEVLOG.md#dev-step-170) |
| 2026-10-26 | 171 | [Native retouching tools](DEVLOG.md#dev-step-171) |
| 2026-10-26 | 172 | [Camera Raw Filter](DEVLOG.md#dev-step-172) |
| 2026-10-26 | 173 | [Sensor RAW development](DEVLOG.md#dev-step-173) |
| 2026-10-26 | 174 | [Photo blending and focus stacking](DEVLOG.md#dev-step-174) |
| 2026-10-26 | 175 | [Native Auto-Align Layers](DEVLOG.md#dev-step-175) |
| 2026-10-26 | 176 | [Native Photomerge workflow](DEVLOG.md#dev-step-176) |
| 2026-10-26 | 177 | [Native HDR merge workflow](DEVLOG.md#dev-step-177) |
| 2026-10-26 | 178 | [Native editable Smart Object image stacks](DEVLOG.md#dev-step-178) |
| 2026-10-26 | 179 | [Native Warp workflow](DEVLOG.md#dev-step-179) |
| 2026-10-27 | 180 | [Native Puppet Warp workflow](DEVLOG.md#dev-step-180) |
| 2026-10-27 | 181 | [Native Perspective Warp workflow](DEVLOG.md#dev-step-181) |
| 2026-10-27 | 182 | [Native Actions and Batch workflows](DEVLOG.md#dev-step-182) |
| 2026-10-27 | 183 | [Native Artboards workflow](DEVLOG.md#dev-step-183) |
| 2026-10-27 | 184 | [Native Frames workflow](DEVLOG.md#dev-step-184) |
| 2026-10-27 | 185 | [Native Blur Gallery](DEVLOG.md#dev-step-185) |
| 2026-10-27 | 186 | [Native Lens Correction](DEVLOG.md#dev-step-186) |
| 2026-10-27 | 187 | [Native Adaptive Wide Angle](DEVLOG.md#dev-step-187) |
| 2026-10-27 | 188 | [Native Vanishing Point](DEVLOG.md#dev-step-188) |
| 2026-10-27 | 189 | [Native Brush Settings and presets](DEVLOG.md#dev-step-189) |
| 2026-10-27 | 190 | [Native painting and eraser tools](DEVLOG.md#dev-step-190) |
| 2026-10-27 | 191 | [Native Adjustment Brush](DEVLOG.md#dev-step-191) |
| 2026-10-27 | 192 | [Native selection tools](DEVLOG.md#dev-step-192) |
| 2026-10-27 | 193 | [Native Sky Selection and Sky Replacement](DEVLOG.md#dev-step-193) |
| 2026-10-27 | 194 | [Native Focus Area](DEVLOG.md#dev-step-194) |
| 2026-10-27 | 195 | [Native Mask All Objects](DEVLOG.md#dev-step-195) |
| 2026-10-27 | 196 | [Native Object Finder](DEVLOG.md#dev-step-196) |
| 2026-10-27 | 197 | [Native Select People](DEVLOG.md#dev-step-197) |
| 2026-10-27 | 198 | [People feature segmentation](DEVLOG.md#dev-step-198) |
| 2026-10-27 | 199 | [Native live shapes](DEVLOG.md#dev-step-199) |
| 2026-10-27 | 200 | [Native Pen and Paths](DEVLOG.md#dev-step-200) |
| 2026-10-27 | 201 | [Native advanced typography](DEVLOG.md#dev-step-201) |
| 2026-10-27 | 202 | [Editable shaped text](DEVLOG.md#dev-step-202) |
| 2026-10-27 | 203 | [Native Filter Gallery](DEVLOG.md#dev-step-203) |
| 2026-10-27 | 204 | [Pause and current progress dashboard](DEVLOG.md#dev-step-204) |
| 2026-10-27 | 205 | [Photo detail investigation and requested pause](DEVLOG.md#dev-step-205) |
| 2026-10-27 | 206 | [Native photo detail workflows](DEVLOG.md#dev-step-206) |
| 2026-10-27 | 207 | [Native Lens Blur](DEVLOG.md#dev-step-207) |
| 2026-10-27 | 208 | [Document title and canvas containment](DEVLOG.md#dev-step-208) |
| 2026-10-27 | 209 | [Photato identity cleanup](DEVLOG.md#dev-step-209) |
| 2026-10-27 | 210 | [Website developer diary and source link](DEVLOG.md#dev-step-210) |
| 2026-10-27 | 211 | [Private GitHub development build](DEVLOG.md#dev-step-211) |
| 2026-10-27 | 212 | [Native distortion workflows and window-build handoff](DEVLOG.md#dev-step-212) |
| 2026-10-27 | 213 | [Native Pixelate workflows](DEVLOG.md#dev-step-213) |
| 2026-10-27 | 214 | [Native Stylize workflows](DEVLOG.md#dev-step-214) |
| 2026-10-27 | 215 | [Native procedural Render filters](DEVLOG.md#dev-step-215) |
| 2026-10-27 | 216 | [Native Flame, Tree and Picture Frame](DEVLOG.md#dev-step-216) |
| 2026-10-27 | 217 | [Native Other and Video filter workflows](DEVLOG.md#dev-step-217) |
| 2026-10-27 | 218 | [Native Blur, Noise and Sharpen workflows](DEVLOG.md#dev-step-218) |
| 2026-10-27 | 219 | [Classic tone and color adjustments](DEVLOG.md#dev-step-219) |
| 2026-10-27 | 220 | [Document color modes — in progress](DEVLOG.md#dev-step-220) |
| 221 | 2026-10-28 | [Native Indexed Color and Bitmap — in progress](DEVLOG.md#dev-step-221) |
| 222 | 2026-10-28 | [Duotone and Multichannel — in progress](DEVLOG.md#dev-step-222) |
| 2026-10-28 | 223 | [Native proofing and print workflows — in progress](DEVLOG.md#dev-step-223) |
| 2026-10-28 | 224 | [Native printing and hard proofs — in progress](DEVLOG.md#dev-step-224) |
| 2026-10-28 | 225 | [Native color profile workflows — in progress](DEVLOG.md#dev-step-225) |
| 2026-10-28 | 226 | [Persistent working color settings — in progress](DEVLOG.md#dev-step-226) |
| 2026-10-28 | 227 | [Opening and paste color policies, working proof](DEVLOG.md#dev-step-227) |
| 2026-10-28 | 228 | [A portable, single-file developer diary](DEVLOG.md#dev-step-228) |
| 2026-10-28 | 229 | [Editable frame animation and Timeline](DEVLOG.md#dev-step-229) |
| 2026-10-28 | 230 | [Native animated GIF interchange](DEVLOG.md#dev-step-230) |
| 2026-10-28 | 231 | [Native video layers and PNG sequences](DEVLOG.md#dev-step-231) |
| 2026-10-28 | 232 | [Native image-sequence export](DEVLOG.md#dev-step-232) |
| 2026-10-28 | 233 | [Native movie import and video-layer placement](DEVLOG.md#dev-step-233) |
| 2026-10-28 | 234 | [Editable video Timeline keyframes](DEVLOG.md#dev-step-234) |
| 2026-10-28 | 235 | [Video editing investigation — implementation pending](DEVLOG.md#dev-step-235) |
| 2026-10-28 | 236 | [A master homepage for Forensic Intelligence](DEVLOG.md#dev-step-236) |
| 2026-10-28 | 237 | [A pure FOSS release, without purchases](DEVLOG.md#dev-step-237) |
| 2026-10-28 | 238 | [Video arrangement and precise splitting](DEVLOG.md#dev-step-238) |
| 2026-10-28 | 239 | [Graphical Timeline and editable transitions](DEVLOG.md#dev-step-239) |
| 2026-10-28 | 240 | [Native Timeline audio](DEVLOG.md#dev-step-240) |
| 2026-10-28 | 241 | [Native Render Video](DEVLOG.md#dev-step-241) |
| 2026-10-28 | 242 | [Timeline work areas and onion-skin previews](DEVLOG.md#dev-step-242) |
| 2026-10-28 | 243 | [Universal Timeline preview qualification](DEVLOG.md#dev-step-243) |
| 2026-10-29 | 244 | [Timeline work-area trimming](DEVLOG.md#dev-step-244) |
| 2026-10-29 | 245 | [Frame-to-video Timeline conversion](DEVLOG.md#dev-step-245) |
| 2026-10-29 | 246 | [Video-to-frame conversion and original recovery](DEVLOG.md#dev-step-246) |
| 2026-10-29 | 247 | [Variables and data-driven graphics](DEVLOG.md#dev-step-247) |
| 2026-10-29 | 248 | [Contact Sheet II](DEVLOG.md#dev-step-248) |
| 2026-10-29 | 249 | [Crop and Straighten Photos](DEVLOG.md#dev-step-249) |
| 2026-10-29 | 250 | [Image Processor](DEVLOG.md#dev-step-250) |
| 2026-10-29 | 251 | [Video Frames to Layers](DEVLOG.md#dev-step-251) |
| 2026-10-29 | 252 | [Native PDF page import](DEVLOG.md#dev-step-252) |
| 2026-10-29 | 253 | [Embedded PDF images](DEVLOG.md#dev-step-253) |
| 2026-10-29 | 254 | [Stable source publication](DEVLOG.md#dev-step-254) |
| 2026-10-29 | 255 | [Native PDF Smart Object placement](DEVLOG.md#dev-step-255) |
| 2026-10-29 | 256 | [Publish qualified PDF Smart Object source](DEVLOG.md#dev-step-256) |
| 2026-10-29 | 257 | [General embedded placement workflow](DEVLOG.md#dev-step-257) |
| 2026-10-29 | 258 | [Publish qualified embedded placement source](DEVLOG.md#dev-step-258) |
| 2026-10-29 | 259 | [PDF source editing and completion dashboard repair](DEVLOG.md#dev-step-259) |
| 2026-10-29 | 260 | [Retained PDF page PSD/PSB interchange](DEVLOG.md#dev-step-260) |
| 2026-10-29 | 261 | [Linked-source work, preserved and parked](DEVLOG.md#dev-step-261) |
| 2026-10-29 | 262 | [Interactive painting responsiveness](DEVLOG.md#dev-step-262) |
| 2026-10-29 | 263 | [Interactive retouching responsiveness](DEVLOG.md#dev-step-263) |
| 2026-10-29 | 264 | [Large-image toning responsiveness](DEVLOG.md#dev-step-264) |
| 2026-10-29 | 265 | [Retained Focus-tool feedback](DEVLOG.md#dev-step-265) |
| 2026-10-29 | 266 | [Faster stroke startup](DEVLOG.md#dev-step-266) |
| 2026-10-29 | 267 | [Prepare the canvas at the right zoom](DEVLOG.md#dev-step-267) |
| 2026-10-29 | 268 | [Redraw only changing feedback](DEVLOG.md#dev-step-268) |
| 2026-10-29 | 269 | [Measure native editing feedback](DEVLOG.md#dev-step-269) |
| 2026-10-30 | 270 | [Present accepted editing previews](DEVLOG.md#dev-step-270) |
| 2026-10-30 | 271 | [Use the current preview and restore tool focus](DEVLOG.md#dev-step-271) |
| 2026-10-30 | 272 | [Layer opacity slider](DEVLOG.md#dev-step-272) |
| 2026-10-30 | 273 | [Held-pointer brush smoothing](DEVLOG.md#dev-step-273) |
| 2026-10-30 | 274 | [Brush release responsiveness](DEVLOG.md#dev-step-274) |
| 2026-10-30 | 275 | [Retouch release responsiveness](DEVLOG.md#dev-step-275) |
| 2026-10-30 | 276 | [Stable preview pause and retouch automation handoff](DEVLOG.md#dev-step-276) |
| 2026-10-30 | 277 | [Semantic retouch Actions and API](DEVLOG.md#dev-step-277) |
| 2026-10-30 | 278 | [Large-document architecture](DEVLOG.md#dev-step-278) |
| 2026-10-30 | 279 | [Disk-backed dense raster input](DEVLOG.md#dev-step-279) |
| 2026-10-30 | 280 | [Paged native persistence and large file IO](DEVLOG.md#dev-step-280) |
| 2026-10-30 | 281 | [Publish qualified native source280](DEVLOG.md#dev-step-281) |
| 2026-10-30 | 282 | [Indexed native archives](DEVLOG.md#dev-step-282) |
| 2026-10-30 | 283 | [Modifier-aware tool cursors](DEVLOG.md#dev-step-283) |
| 2026-10-30 | 284 | [Paged runtime tile index (under test)](DEVLOG.md#dev-step-284) |
| 2026-10-30 | 285 | [Persistent native tile ordinal reuse (software qualified; UI pending)](DEVLOG.md#dev-step-285) |
| 2026-10-30 | 286 | [Large PSD/PSB file workflows (software qualified; UI pending)](DEVLOG.md#dev-step-286) |
| 2026-10-30 | 287 | [Paged document geometry (software qualified; native acceptance pending)](DEVLOG.md#dev-step-287) |
| 2026-10-31 | 288 | [Paged selections and bounded channel views (software qualified)](DEVLOG.md#dev-step-288) |
| 2026-10-31 | 289 | [Publish qualified source288](DEVLOG.md#dev-step-289) |
| 2026-10-31 | 290 | [Paged layer-stack composition (software qualified)](DEVLOG.md#dev-step-290) |
| 2026-10-31 | 291 | [Paged vector-mask preparation (software qualified)](DEVLOG.md#dev-step-291) |
| 2026-10-31 | 292 | [Paged basic raster filters (software qualified)](DEVLOG.md#dev-step-292) |
| 2026-10-31 | 293 | [Paged Smart Filter workflows (software qualified)](DEVLOG.md#dev-step-293) |
| 2026-10-31 | 294 | [Private qualified-source backup](DEVLOG.md#dev-step-294) |


## 2026-10-26 — Step158: editable layer effects

Major-feature breadth continues with ten native effect kinds, a style editor, copy/paste/clear, native persistence and both APIs. Six effect kinds have bounded PSD interchange. Live numeric editing exposed an exclusivity crash that model-only tests missed; the setter was repaired and a regression added. A command-matrix writing error was recovered from preserved evidence; eight filter evidence sentences are explicitly reconstructed. All55 focused Debug and1,498 full Release tests pass, plus30 cases each on arm64/Rosetta and universal package verification. The repaired native workflow passes. Fine contour matching, advanced variants and full Photoshop parity remain open. See [the complete record](DEVLOG.md#dev-step-158).

## 2026-10-26 — Step159: automatic subjects and backgrounds

The next broad workflow uses Apple's local Vision model to select foreground subjects or create an editable layer mask. Original pixels stay editable; native history and both API interfaces use the same engine.56 focused checks pass, including cancellation and revoked sharing. The real model removes the icon background and native Select Subject/Undo works. A mask-focus callback guard found by testing was repaired. The Mac locked before the remaining live mask check; all1,510 full Release tests and the universal macOS14+ package verify. Final parser/default repair passes26 focused tests, with platform model results preserved separately. Intricate edges and the rest of object/sky/people selection remain open. See [the development record](DEVLOG.md#dev-step-159).

## 2026-10-26 — Step160: embedded Smart Objects

The next major workflow preserves the original source behind a rendered layer. Resize/rotate retains source samples; ordinary copies share content, while New Smart Object via Copy stays independent. Native Edit Contents opens a child document and Save updates its parent through Undo. Placement, replacement, source export, native14 persistence and an affine PSD/PSB subset share the Photato/Adobe API engine.57 integration tests and14 final focused tests pass. All1,524 full Release tests,36 checks per architecture and the universal macOS14+ package verify. The Mac remains locked for live checks; no independent Photoshop Smart Object fidelity claim is made. Linked sources, warp, richer source formats and Smart Filters remain open. [Complete record](DEVLOG.md#dev-step-160).

## 2026-10-26 — Step161: editable Smart Filters

Eight native filters now remain editable over original Smart Object sources. Layers expose filter settings, per-filter blending/visibility/order and a shared paintable mask; ordinary layers retain baked filters. Native15, history, Photato automation and published Adobe execute-actions share the same engine. Seven filter types have bounded PSD/PSB descriptor/cache mappings; unsupported exports fail explicitly.67 integration checks pass. All1,536 final Release tests,87 checks per architecture and the universal macOS14+ package verify. The first Release run exposed one outdated archive-version test; its two expectations were corrected before the passing full rerun. All failed compile attempts remain recorded; no independent Photoshop or live UI claim while the Mac is locked. The next major workflow is native text editing; numerical refinements remain deferred. [Complete record](DEVLOG.md#dev-step-161).

## 2026-10-26 — Step162: native text editing

The basic text stamp is now a native point/paragraph editor with caret selection, mixed character formatting, paragraph controls, local typing Undo and a single committed document edit. Native16, two Photato commands and a published Adobe create-composite subset preserve editable content. A bounded Swift port of upstream TySh/EngineData supports native-generated PSD/PSB round trips. Compilation and runtime failures are preserved, including a missing NSTextView text system initially mistaken for a Redo failure; an explicitly owned TextKit stack repaired it. All54 integration tests pass. All1,548 final Release tests and48 checks per architecture pass, and the universal macOS14+ package verifies. The first full Release run exposed one obsolete PSD type-rejection test, corrected before the passing rerun. Independent Photoshop/live UI and advanced typography remain open; major-feature breadth continues with classic adjustments. [Complete record](DEVLOG.md#dev-step-162).

## 2026-10-26 — Step163: Classic adjustment workflows

Five missing classic adjustments now share native Properties/dialog controls, selection masks, history, native17 saving and three typed Photato commands. The source approximations were translated from Rust with explicit validation. Nine factory menu commands are newly bound; the newer Color and vibrance layer remains open because its white-balance controls are additional functionality. PSD/PSB carries editable supported records; Adobe action jobs and the published /v2/edit color subset use the same Swift engine. Test failures exposed an omitted archive-header version discriminator and stale catalogue/fixture expectations; each attempt is retained. All46 integration tests pass. All1,559 final Release tests and90 checks per architecture pass; universal macOS14+ packaging verifies. The first full run found11 stale catalogue/version expectations. Those were corrected, and a review also added a missing prepared API creation-limit check with an atomicity test;36 final focused checks pass. Exact Photoshop output, richer Photo Filter transport and live UI remain open. [Complete record](DEVLOG.md#dev-step-163).

## 2026-10-26 — Step164: Color Lookup workflow

Color Lookup now has a usable native grading workflow: import Cube/3DL/LOOK, choose generated Photato looks, preview or create editable layers, and retain masks/settings/history in native18. Source-domain and nonuniform shaper information survive import and save. Photato APIs upload bounded LUTs, create/set/apply adjustments and download original LUT files; Adobe execute-actions uses the shared native engine for a bounded inline descriptor subset. PSD/PSB supports loaded Trilinear LUTs. No Adobe preset files are redistributed. Two compile failures and an incorrect Adobe test-request envelope were repaired with their logs retained. All34 focused tests pass; 1,569 full Release tests passed, followed by a PSD name/format metadata correction,35 final focused Release checks and27 cases per architecture. The final universal macOS14+ package verifies. Both source snapshots and packages are retained. Live UI, exact Photoshop grading, ICC/CSP and richer interchange remain open. [Complete record](DEVLOG.md#dev-step-164).

## 2026-10-26 — Step165: Native Liquify workspace

The major-feature queue moves to Liquify. PhotoCraft’s inverse displacement grid now has native Swift brushes, freeze masks, reconstruction and mesh-program persistence, alongside a dedicated macOS workspace. Local Vision landmarks feed independent face controls. Pixel-layer editing and editable Smart Filters use shared history, native19 saving and the typed API; face detection is a read-only API command. Compilation/test fixture failures and their repairs are preserved in DEVLOG. All53 Debug focused,1,583 full Release tests before identity repair,71 final Release checks and29 public checks per architecture pass; the universal macOS14+ package verifies. Real local Vision requests on a nonface image complete on both architectures; portrait quality remains unqualified. Photoshop mesh files/PSD descriptors, Adobe Liquify actions, exact numerical behavior and live checks stay open. [Liquify development record](DEVLOG.md#dev-step-165)

## 2026-10-26 — Step170: Crop and content-aware edges

The Crop tool now has an expandable boundary, rotation/straighten line, common aspect ratios, retained/deleted raster pixels and transparent/background/content-aware extension. Preview, cancellation, one-step undo and API use the same native implementation. Generated edge pixels remain on an editable layer; interior transparency is retained. A redundant mask-coordinate calculation and a synthetic event-coordinate test were repaired; all 47 focused tests pass. The first full run exposed two outdated API counts; these and the shared Image > Crop integration are covered by the final 1,637 passing Release tests. The universal macOS 14+ package verifies. Exact Photoshop rendering, advanced presets/settings and live/platform checks remain open. Patch, Content-Aware Move and Red Eye are next. [Complete development record](DEVLOG.md#dev-step-170).

## 2026-10-26 — Step169: Content-Aware Scale

Native seam carving now shrinks or enlarges a raster layer or selected pixels while retaining protected content. The existing canvas transform controls add reference-point, Amount, saved alpha-channel and skin-tone options; preview, cancellation and one-step undo share the engine with the API. The factory shortcut is connected. A compile-time error-property assignment was repaired, and all 25 focused engine, desktop/API, menu and transform tests pass. A procedural output comparison was inspected. The universal macOS14+ package verifies. Photoshop numerical equality, nonlinear mask deformation and live/platform qualification remain open. Content-aware crop fill is next. [Complete development record](DEVLOG.md#dev-step-169).

## 2026-10-26 — Step168: Content-Aware Fill workspace

The next major workflow now has native sampling and selection brushes, a preview, color/rotation/scale/mirror adaptation, current/new/duplicate-layer outputs, cancellation and undo. The desktop and `contentAware.fill` API share the Swift implementation derived from the licensed Rust source. A compile error and an AppKit test-controller initialization crash were repaired; all 30 final focused tests pass. A procedural before/after image was inspected. The universal macOS14+ package verifies. Exact Photoshop output, live interaction, cross-document sampling and finer workspace controls remain open. Content-Aware Scale and crop fill are next. [Complete development record](DEVLOG.md#dev-step-168).

## 2026-10-26 — Step167: Alpha channels and Quick Mask

The maintainer reinforced breadth over fine fidelity. Persistent grayscale channels, saved selections, painting/filtering, Quick Mask, native20 saving and history now work through the native UI and two typed API operations. Three Select commands and Q are connected. Three compile failures and repairs are retained;47 initial and73 final focused tests pass. The final universal macOS14+ package and28 refresh-repair tests pass. PSD/spot channels, cross-document operations and independent/live fidelity remain open. Full-suite and platform qualification are batched. Content-Aware Fill is next. [Complete development record](DEVLOG.md#dev-step-167).

## 2026-10-26 — Step166: Native Select and Mask workspace

A major selection workflow now has a native Swift matting engine and workspace: guided edge detection, global refinements, decontamination, brushes/lasso, subject selection, local history and six output choices. The factory menu/shortcut and existing selection/mask controls open it. The Photato API shares the engine and prepared document history; new-document outputs require transfer permission and leave the source untouched. Compilation repairs, the missing decontamination-preview correction and their passing focused tests are preserved. Offscreen captures have unreliable native-control compositing and are not accepted visual qualification; live work awaits unlock. All47 initial/12 repaired focused checks and1597 final full Release tests and54 checks per architecture pass; the universal macOS14+ package verifies. Adobe proprietary hair/Object Aware algorithms, action descriptors, exact output and broader contexts remain open. Next major workflow: channels, saved selections and Quick Mask. [Complete development record](DEVLOG.md#dev-step-166).


## 2026-10-26 — Step171: Native retouching tools

Patch, Content-Aware Move/Extend and Red Eye now share native prepared edits with toolbar controls, history and three API operations. The implementation reuses the source-port healing/fill foundations. Tests exposed nested-array inference, a mutable concurrency capture, integer-depth/linear-buffer confusion and a full-coverage Float32 rounding defect; each failure and repair is retained. All 123 focused/regression tests pass. All 39 optimized focused checks also pass, and the universal macOS 14+ package verifies. Independent Photoshop algorithms and live/platform parity remain unqualified. The next major family is Camera Raw. [Complete development record](DEVLOG.md#dev-step-171).

## 2026-10-26 — Step172: Camera Raw Filter

**Camera Raw Filter (step172):** Light, color, curves, mixer/grading, detail and effects now have a native workspace with preview, settings files, local/document history, editable Smart Filters and both API paths. All 67 final focused/regression and 1,659 full optimized tests pass. The universal macOS 14+ package verifies. Sensor RAW/DNG import, lens corrections, local masks, XMP, exact Adobe output and live/platform qualification remain open. Next: actual sensor RAW development. See [Camera Raw evidence](CAMERA_RAW_REFERENCES.json). The first build caught multi-variable observation declarations; the next test run caught obsolete all-filter assumptions and a test ID changed by Smart Object conversion. All failed attempts and repairs are retained. This increment implements RGB development; sensor decoding is a separate next step, not a completed RAW01 claim. [Complete development record](DEVLOG.md#dev-step-172).


## 2026-10-26 — Step173: sensor RAW development

**Sensor RAW development (step173):** Supported camera RAW/DNG files now retain their original source in editable Smart Objects, with native sensor controls, preview, history, native22 saving and both API paths. All 96 final focused and 96 optimized focused tests pass. The universal macOS 14+ package verifies. Camera-specific qualification, local RAW masks/XMP, editable PSD RAW interchange and exact Photoshop output remain open. Next major family: photo alignment and merging. See [RAW evidence](RAW_DEVELOPMENT_REFERENCES.json). The generated Bayer DNG has no embedded preview. Independent Core Image comparisons exposed a strip row-order error; it was repaired before the final 96-case pass. Empty small-fixture decoder probes, compilation failures and failing assertions remain recorded. Offscreen native workspace tests cover preview and local/document history; they are not live UI qualification. See [the complete record](DEVLOG.md#dev-step-173).


## 2026-10-26 — Step174: photo blending and focus stacking

**Auto-Blend Layers (step174):** Panorama seams and focus stacking now have native preview/Cancel/OK, editable masks, multiband blending, transparent-area fill, Undo/Redo and both API paths. All 69 focused/regression and 69 optimized focused tests pass. The universal macOS 14+ package verifies. All 15 follow-up catalogue checks pass after test-only expectation updates. Auto-Align, Photomerge, HDR and exact/live/platform qualification remain open. Next: native Auto-Align Layers. See [blend evidence](PHOTO_BLEND_REFERENCES.json). The Swift pyramid translation matches an independently compiled original-Rust fixture. Installed Photoshop source establishes the bounded panorama action descriptor vocabulary; no Adobe code was executed or copied. Compilation and two fixture failures were repaired with previous attempts retained. Source pixels remain unchanged; masks are editable and a merged output hides the originals to preserve alpha. Masks-only output retains layer selection. This does not establish Adobe algorithm, visual or factory-dialog equivalence. See [the complete record](DEVLOG.md#dev-step-174).

### 26 October: editable statistical stacks

The major-feature pass added file/folder/open-document loading and statistical Smart Objects. All eleven PhotoCraft operators preserve original photo layers; changing or removing a mode is undoable, and editing the source refreshes each shared instance with its own mode. The native Statistics/Load Layers dialogs include optional shared alignment and preview/cancel. Native23 retains mode metadata, and unsupported editable PSD export fails explicitly. Three Photato commands and the installed Adobe renderer descriptor use the same engine. Original-Rust and analytical checks distinguish source-port correctness from unqualified Photoshop equality. The failed adapter/compiler/test assumptions and passing repairs are retained in [step178](DEVLOG.md#dev-step-178).

## 2026-10-27 — Step183: native Artboards

Artboards now form a complete basic multi-layout workflow: create, convert layers/groups, move/resize/duplicate, edit backgrounds/guides, save native27, and export separate files or a multipage PDF. Native controls, Photato commands and published Adobe jobs share the core metadata/clipping engine. Negative coordinates rebase physical pixels without resampling; extraction retains source layers and gradients. Compilation repairs and an outdated archive-version test expectation are preserved in the detailed record. Exact Photoshop output, richer contexts, PSD interchange and Frames remain open. No live interaction is claimed while the desktop is locked. [Full development record](DEVLOG.md#dev-step-183).

## 2026-10-27 — Step184: native Frames

Frames now retain an editable boundary separately from image contents. Native K tool drawing, type/shape conversion, fitting, replacement and independent transformations share one-step history and API commands. Closed text contours preserve counters, empty frames show placeholders and optional strokes, and source bytes survive transforms. Native28 preserves metadata; PSD writes reject instead of dropping it. Three compilation attempts exposed accessor/visibility/glyph/concurrency issues and their preserved repairs preceded passing module and140 integration checks. No live desktop pass is claimed. Minor refinements are deferred while major workflows remain missing; Blur Gallery is next. [Full record](DEVLOG.md#dev-step-184).

## 2026-10-27 — Step185: native Blur Gallery

All five Blur Gallery tools now share editable source-relative geometry, a native preview workspace, local/document history and Smart Filter persistence with the API. Spatial blur follows the original Rust Gaussian-level approach; path/spin use premultiplied sampling. Bokeh/noise and bounded spin strobes extend the core workflow. Compiler integration failures, stale archive/PSD tests and an action descriptor that incorrectly accepted defaults were repaired and preserved. A single-flash invariant exposed a sampling edge case and drove a functional repair. Offscreen layout was inspected but does not prove live behavior. Exact Photoshop output and richer subfunctions remain open while work proceeds to major lens/perspective workspaces. [Full record](DEVLOG.md#dev-step-185).

## 2026-10-27 — Step186: native Lens Correction

Lens Correction now shares its typed Swift geometry and settings across native controls, Smart Filters, direct API edits and recorded Actions/Batch. The workspace includes correction/profile controls, straighten/distortion gestures, grid/navigation, preview/Cancel and local/document history. The original Rust calibration estimates are labelled as generic; no manufacturer database is claimed. The vignette midpoint follows the documented Adobe direction. Integration repaired a throwing loop, value-access conflict, a test-only Equatable assumption and legacy tests that wrongly expected identity defaults to change pixels. Smart Object geometry now resolves the actual placed/prior-filter input. All97 final focused Debug tests pass. Broader packaging is batched with Adaptive Wide Angle and Vanishing Point; the current universal candidate remains step185. Exact/live/platform/profile/PSD gaps remain open. [Full record](DEVLOG.md#dev-step-186).

## 2026-10-27 — Step187: native Adaptive Wide Angle

Straightening now works through a native constraint workspace with lines, polygons, individual edge orientations and five projection choices. The Swift solver ports the source camera/mesh approach, with an explicit cylindrical panorama and bounded geometry cache. A shared input helper keeps Lens and Wide Angle coordinates aligned with placed Smart Objects and preceding filters. Native controls, history, native31 persistence, direct API and recorded Actions/Batch share the same correction engine. The first integrated17 tests and final107 focused regression tests all pass; catalogue archive/identity/unsupported-PSD expectations were updated before broad regression. No failed test attempts occurred. The offscreen image verifies preview/overlay/layout only. Exact/live/profile/PSD and performance qualification remain open, with optimized/universal work batched after Vanishing Point. [Full record](DEVLOG.md#dev-step-187).

## 2026-10-27 — Step188: native Vanishing Point

Perspective planes, related-plane edits, perspective paste/clone/brush, local preview/history, native32 and a typed API now share a Swift prepared edit. Seven new source/test files and18 changed files are enumerated in the run manifest; none removed. The core derives from the original Rust plane and paste/clone geometry with native brush support. Failed attempts exposed a conversion-signature error, an Observation declaration restriction, a cross-test-target helper reference and a Float32 renderer/document-depth mismatch; all repairs and failure logs are preserved. The final117 focused Debug checks pass, including native/API agreement and cancellation. The full1816-test optimized suite and universal package subsequently pass for steps186–188. A documentation helper used the wrong CSV field name; its partial output was retained, the complete matrix restored and the edit reapplied without touching frozen build inputs. Secondary tool/Actions/PSD and exact/live/platform gaps stay open. The offscreen view is layout evidence only. [Full record](DEVLOG.md#dev-step-188).

## 2026-10-27 — Step189: native brush workflow

The circular painter now has an optional native dynamics engine, with seeded spacing, custom tips, shape/scatter/color/transfer/texture/dual behavior, flow, smoothing, pose, symmetry and timed airbrush strokes. Modeless Brush Settings and Brushes windows, factory menus/F5 and the options bar make the configuration usable while painting. Canvas previews render the same frozen stroke as the final undoable edit, preserving selections, placement and supported mask/channel targets. Presets save atomically in the native format or the supported ABR subset; twelve generated presets contain no Adobe-owned assets. New typed APIs expose configuration, preset management and painting; advanced Actions use version 2 to prevent old readers from silently dropping settings.

Validation found and repaired analytic test expectations, an API schema concurrency error, invalid Smart Object/mask fixtures, a preview scheduling race and a genuine nested-command stack overflow caused by large inline brush settings. Immutable indirect settings preserve value semantics and the wire format while keeping command values small. Every failed attempt and the crash report remain saved. All 103 focused Debug and 1834 full optimized tests pass. The universal macOS 14+ package verifies. Offscreen layout and synthetic AppKit events are separate from live desktop/tablet evidence; the desktop remains locked. The current Adobe brush-resource job path, physical bristle simulation and exact Photoshop output remain open. Next major batch: Pencil, Mixer Brush, Color Replacement, Pattern Stamp and the two missing erasers. No source publication, installed/root app replacement or user-settings change occurred.

[Development details](DEVLOG.md#dev-step-189), [checkpoint189](ACTIVE_CHECKPOINT_189.json), [brush references](BRUSH_REFERENCES.json).

## 2026-10-27 — Step190: six native painting tools

Pencil/Auto Erase, Color Replacement, Mixer Brush, Pattern Stamp, Background Eraser and Magic Eraser now use the shared native brush, selection, layer protection and history infrastructure. Factory B/S/E toolbar groups expose their controls. Mixer paint wells update only after successful commit; sampling, load/clean and automatic choices share native/API behavior. Aligned Pattern Stamp retains its phase. Brush/Pencil create an ordinary transparent layer when painting above nonraster content. Masks and grayscale channels work where applicable, including transformed Smart Filter mask coordinates.

Three typed API commands expose configuration, painting and Mixer state. Tests cover visible previews, Cancel, Undo, source preservation, archives, settings, protected/transformed targets, native/API equivalence and invalid/busy/stale/revoked requests. Validation repaired a real no-op tile allocation, an existing sampler visibility boundary and two erroneous test helper/target assumptions; failed logs are retained. All 184 focused Debug and 1851 full optimized tests pass. The universal macOS 14+ package verifies. The original Rust, root/installed app and user settings remain unchanged. The desktop remains locked, so offscreen and synthetic-event tests are not live UI qualification. Full Adobe brush-resource jobs, new-tool Actions/Batch recording, physical wet-media behavior and exact Photoshop output remain open. Major feature breadth continues with Adjustment Brush; secondary controls and numerical/cosmetic refinements wait.

[Development details](DEVLOG.md#dev-step-190), [checkpoint190](ACTIVE_CHECKPOINT_190.json), [paint-tool references](PAINT_TOOL_REFERENCES.json).

## 2026-10-27 — Step191: editable local adjustments

Adjustment Brush creates a masked adjustment on its first stroke and paints further coverage onto that editable mask. Fifteen native adjustment types reuse the existing engines and Properties editors. Add/Subtract, object clicks, overlays, inversion, replacement, New Adjustment, density/feather and brush controls form one native workflow. Original pixels remain unchanged. The on-device Vision integration selects the foreground instance at the clicked point; synthetic detector/label-buffer tests validate the new path without claiming live inference qualification.

Four Photato commands share the native engine, strict schemas, session state and transaction/history behavior. Native/API mask refinements are equivalent. Recorded Actions version3 preserves brush requests, semantic layer references, explicit object coverage and replacement operations; older action files remain readable. The captured factory Frame/K binding is retained despite conflicting newer Adobe prose; Adjustment Brush has no invented shortcut. No dedicated Adobe masked-paint endpoint is claimed.

Validation found and fixed a missing shared const-schema rule, outdated command-count assertions and an out-of-canvas test fixture. Final API review corrected an assumed mask endpoint by adding density/feather operations and updated action-library version descriptions. Failed attempts remain saved. All156 focused Debug and156 focused optimized checks pass. Full regression and universal packaging are batched with the next major selection increment; the last verified package190 does not contain191. All1444 frozen inputs,754 original Rust files and four protected files verify. Photato.xcodeproj remains present/unchanged. The desktop remains locked; no live UI comparison or physical platform qualification is claimed. Full presets, newer adjustment types, exact pixels/models and richer Adobe compatibility remain open. Major feature work continues with Object Selection, Quick Selection and Selection Brush; fine numeric/cosmetic work waits.

[Development details](DEVLOG.md#dev-step-191), [checkpoint191](ACTIVE_CHECKPOINT_191.json), [Adjustment Brush evidence](ADJUSTMENT_BRUSH_REFERENCES.json).

## 2026-10-27 — Step192: three major selection tools

Object Selection now supports rectangle/lasso initialization through native graph cut and clicked-object targeting through Apple's local Vision adapter. Quick Selection follows image boundaries from painted seeds. Selection Brush paints editable soft coverage with a colored overlay. The graph, mixture model, geodesic costs and boundary refinement were translated from the preserved MIT/Apache PhotoCraft sources into Swift, with attribution and native cancellation/work limits. Source images remain unchanged; existing masks, history and Select and Mask workflows consume the result.

Four typed API commands expose configuration and all three tools through the same native transaction, with discoverable state/result schemas and request lifecycle guards. Actions version4 retains explicit coverage on its original canvas; replay does not silently redetect objects. Native archives remain32. Tests include independent exhaustive small-graph cuts, textured segmentation fixtures, reduced-resolution recut, offscreen/synthetic interaction, soft coverage at8/16/32-bit, current/composite sampling, cancellation and native/HTTP equality. No test attempt failed; one stale-context patch made no changes and was reapplied correctly. Validation also corrected stale overlays on tool changes and the API's omitted Object Selection mode fallback.

All155 broad focused Debug checks,7 final dedicated workflow checks and1876 full optimized tests pass. The universal macOS14+ package verifies and includes191 Adjustment Brush. All1455 frozen inputs, four protected files and754 original Rust hashes verify. The Xcode project remains present and unchanged. Source deltas, build/signature evidence and prior attempts are retained. No live desktop qualification was possible because the last authoritative desktop state remains locked. Photoshop byte/model equivalence, broader finder/People workflows and platform qualification remain open. Continue major workflow breadth with Sky Selection and Sky Replacement.

[Development details](DEVLOG.md#dev-step-192), [checkpoint192](ACTIVE_CHECKPOINT_192.json), [selection references](SELECTION_TOOL_REFERENCES.json).

## 2026-10-27 — Step193: Sky Selection and Sky Replacement

Select > Sky now runs the source-derived detector in Swift. Edit > Sky Replacement opens a native preview with imported skies or a raster layer source, sky placement, manual Add/Subtract mask brushing, edge refinement, sky brightness/temperature and foreground color/light controls. Output preserves the original layers and either adds editable masks/transforms/adjustments or a merged duplicate. The user sky library persists atomically and reports invalid files instead of overwriting them. The classical detector is not represented as Adobe AI, and no proprietary sky assets were copied.

Three Photato commands expose selection, replacement and sky-library management with strict discovery schemas, observable state, document/library revisions and the same prepared history path as the desktop. Select Sky records explicit coverage in Actions4; replacement recording remains visibly unsupported. The Adobe contract has no dedicated sky route. Native archive32 and the Xcode project remain unchanged.

The development record preserves failed compilation, test assumptions and a metadata-validation defect that blocked output. The attempted arbitrary sourceTags metadata was removed; existing native layers retain editability. Follow-up tests verify no-sky/manual fallback, all depths, canvas gestures, preview/local/document Undo, read/close cancellation, native/API equality, valid source-layer strokes, selection combinations, library corruption and stale/busy/revoked requests. The only retained numerical discrepancy is Float32 duplicate recomposition at up to2.98e-8 in the synthetic fixture; integer-depth samples match. The functional tolerance is1e-7, with exact bytes explicitly deferred under the maintainer's major-first priority. The renderer was not changed to chase that detail.

A documentation helper used the wrong CSV column and partially wrote the command matrix. The partial file was preserved; reconstruction from earlier backups/update blocks exactly matched final192's recorded hash before applying the one intended change atomically. All645 prior rows remain. The first recovery attempt stopped before writing because an obsolete626-row assertion failed; both helpers remain evidence.

All113 focused Debug and113 optimized tests pass. The universal macOS14+ package verifies. Last full regression is1876 passing tests at192; the next major batch will broaden again. All1464 frozen inputs, four protected files and754 original Rust hashes verify. Fresh package extraction confirms both architectures, macOS14 minimum, ad-hoc signature, licenses and icon. The offscreen synthetic preview is readable; no live desktop test was performed because the latest authoritative desktop state remains locked. Exact/model/preset/Actions/full-context/platform requirements remain open. Next is Focus Area, followed by Mask All Objects; numerical and cosmetic work stays deferred.

[Development details](DEVLOG.md#dev-step-193), [checkpoint193](ACTIVE_CHECKPOINT_193.json), [sky references](SKY_REFERENCES.json).

## 2026-10-27 — Step194: Focus Area

Focus Area now selects sharp regions using a native Swift translation of PhotoCraft's local Laplacian-energy detector, normalization, guided cleanup and upsampling. The source's range direction contradicted Adobe's documented interface, so the native controls deliberately increase strictness as range rises; manual zero selects the entire image. Auto range/noise estimates are transparent native heuristics, with exact Adobe algorithms/defaults still unqualified. Attribution preserves the original MIT/Apache provenance.

The existing refinement workspace supplies the preview, Add/Subtract brushes, view modes, local history and six selection/mask/layer/document outputs. Focus controls add Auto/manual range/noise and Soften Edge. Turning Auto off preserves the displayed estimate. Preview can show the unmodified image. Select and Mask handoff keeps corrected coverage in the draft without changing the source until OK. Native document reload/close cancels pending analysis and cannot commit late results.

Select > Focus Area is bound in the captured menu position. The new selection.focus API uses strict settings/stroke schemas, requested/effective workspace state, shared native preparation/history and existing new-document permission/revision/lifecycle guards. Selection output records coverage in Actions4; nonselection output remains explicitly unsupported for recording. Native archive32 and the Xcode project are unchanged. No dedicated Adobe endpoint or focus actionJSON conformance is claimed.

The first core and integration runs passed. Expanded controls exposed a Swift exclusivity compile error; the failed attempt is preserved and the settings copy repaired. Code review also found hard-mask output could resurrect discarded tiny components at the soft-field threshold; hard output now uses cleaned binary labels, with a focused regression. Six core and seven new workflow tests cover sharp/blur/noise/flat/depth/cancellation, six native/API outputs, source and archive preservation, transforms/locks, sampling independent of prior selection, controls/brush/handoff, new-document/read/close lifecycle and invalid/stale/busy/revoked requests. The offscreen synthetic preview is readable; it is not live desktop evidence.

All83 final focused Debug and1903 full optimized tests pass. The universal macOS14+ package verifies and includes193 Sky workflows. All1470 frozen inputs, four protected files and754 original Rust hashes verify. Fresh extraction checks both architectures, macOS14 minimum, signature, version, licenses and icon. No installed/root app replacement, publication, commit or user settings change occurred. The original full Photoshop objective remains active. Next: Mask All Objects with separate editable per-object mask groups, followed by broader object-selection workflows; numerical/cosmetic refinements remain deferred.

[Development details](DEVLOG.md#dev-step-194), [checkpoint194](ACTIVE_CHECKPOINT_194.json), [Focus Area references](FOCUS_AREA_REFERENCES.json).

## 2026-10-27 — Step195: Mask All Objects

Mask All Objects now creates one editable masked group per locally detected foreground instance. This advances beyond the source Rust implementation, which explicitly combines all objects into a single mask. The native Vision adapter performs one inference and requests each actual instance independently. Groups are empty Pass Through folders above the original clipping family, ready for a targeted adjustment; original pixels, masks, hierarchy and document selection remain intact. Source layers may remain locked, but locked parents reject insertion.

The captured Layer menu and layer context menu now invoke the shared native command. The new layer.maskAllObjects API brings the catalogue to90 and exposes schemas, availability, limits and created group IDs. Both paths use prepared history transactions and preserve atomic failure on cancellation, revocation, invalid masks and resource limits. Native32 archives retain editable groups. Recorded Actions reports explicit unsupported status; no Adobe route or actionJSON conformance is invented.

Seven new workflow tests exercise multiple injected instances, all three native depths, source retention, targeted adjustments, archive/Undo/Redo, nested clipping placement, transformed inputs/locks, menus/context, native cancellation/reload and actual HTTP equivalence/schema/error/lifecycle/resource cases. The first test build failed on throwing/actor test syntax and was repaired. The second run had one partial-schema-helper assertion failure; the result envelope was correct, and its declared extension fields now validate independently. Both failed attempts remain preserved. A code review added a conservative padded-tile memory budget for thin canvases.

All82 focused Debug and82 optimized tests pass. Real Apple Vision inference succeeds on the1024×1024 icon with source retention and Undo/Redo. Latest full/universal baseline194 has1903 passing tests and excludes195. The real-model mask was inspected as the expected Photato icon silhouette; it is neither a real-photo multi-object accuracy study nor live Photoshop evidence. All1475 frozen inputs,754 original Rust files and four protected hashes verify. Five source/test files were added,12 inputs modified, none removed; exact lists are in changes01. No installed/root app replacement, publication, commit or settings mutation occurred. The Xcode project and version remain unchanged. Full qualification will be batched after the next major selection workflow.

Next is Object Finder with cached hover highlighting/click selection, refresh/cancellation, source invalidation, controls and API. People/body-part workflows and exact parity remain open. [Details](DEVLOG.md#dev-step-195), [checkpoint](ACTIVE_CHECKPOINT_195.json), [references](MASK_ALL_OBJECTS_REFERENCES.json).

## 2026-10-27 — Step196: Object Finder

Object Finder now runs one local Vision instance analysis and reuses its masks while the pointer moves. The canvas shows the actual hovered mask; clicking selects it with New/Add/Subtract/Intersect modes and optional Hard Edge. A click during inference waits for the matching source. Selection-only changes reuse detection, while source edits, layer/tool switches, sample mode, refresh and document replacement invalidate it. The native options add Finder, Hard Edge, refresh, highlight color and cancellation; Escape also cancels detection. Manual rectangle/lasso and the earlier direct point detector remain available.

Three APIs expose detection, temporary hover and cached selection, including optional bounded raw masks for clients that draw their own overlay. Configuration and result/state schemas are discoverable. Cache identity prevents stale selection; native and HTTP paths share selection/history/Actions. Detection and hover never dirty the document. Native32 remains unchanged and recorded Actions4 stores resulting coverage, not an unverified adaptive detector. No new Adobe endpoint or semantic-model equivalence is claimed.

Three imaging tests and seven workflow tests cover hit testing, source/cache keys, hard edges/modes, repeated hover without repeated inference, native click/Undo/Redo/Actions, pending clicks, source/sample/tool/lifecycle invalidation, model failure, actual HTTP schemas/mask export/configuration/hover/select and invalid/stale/busy/refreshed/cancelled/revoked requests. The first build caught two test-helper access mistakes, preserved and repaired.70 focused tests pass. Escape received a dedicated synthetic event check. The offscreen canvas visibly shows the expected enlarged blue mask; several unshown native option controls still have blank interiors in snapshots, so complete control/live rendering remains unqualified and cosmetic work is deferred.

All70 final focused Debug and1920 full optimized tests pass. The universal macOS14+ package verifies and includes195 Mask All Objects. Real local Vision detect/hit/select/save/Undo succeeds. All1480 frozen inputs,754 Rust source hashes and four protected files verify. Five code/test files were added,13 inputs modified and none removed. Universal extraction verifies arm64/x86_64, macOS14 minimum, signature, version, licenses and icon. The Xcode project, root/installed app, user settings and version remain unchanged. Source and package identities are recorded in checkpoint196;195 evidence is annotated with this subsequent full qualification while its original checkpoint stays immutable.

The next major workflow is Select People. Adobe’s February23 workflow describes a thumbnail picker and whole-person/feature selection; the public Apple SDK supports person-instance masks on macOS14. It does not itself provide semantic hair/beard/skin parts. The saved plan requires capability/model verification and honest unavailable parts rather than generic shapes presented as precise selection. No live desktop re-probe occurred while the desktop remains locked.

[Development details](DEVLOG.md#dev-step-196), [checkpoint](ACTIVE_CHECKPOINT_196.json), [references](OBJECT_FINDER_REFERENCES.json).

## 2026-10-27 — Step197: Select People

The native Object Selection options now open a person picker backed by Apple's macOS14 person-instance request. It detects people separately from ordinary foreground objects, creates bounded thumbnails and previews actual masks on the canvas. Choose one or several people, apply New/Add/Subtract/Intersect with optional Hard Edge, or hand the resulting selection to Select and Mask for manual refinement. Hover, detection and picker state do not dirty the document; applying the union uses one Undo and Actions4 explicit coverage. Native32 remains unchanged.

Three matching APIs expose detection, hover and selection, with optional full-canvas UInt8 mask export and96px PNG thumbnails. Strict cache IDs, source/sample/layer/tool invalidation and cancellation/read/close/revocation guards keep results tied to the current image. Empty detections return an empty ready list; model failures remain visible. Hair/skin/facial features are explicitly unavailable because the Apple request does not provide those semantic labels. No new Adobe route or model equality is claimed.

The first compile found a SwiftUI binding through an immutable workspace reference. A mistakenly gated repair command did not apply before the second attempt; both failed logs remain. Explicit get/set binding repaired it. Seven new imaging/workflow tests plus shared selection/API regression coverage pass. Offscreen overlays are readable, but some unshown native controls remain blank, so full live/control rendering is not qualified. The desktop remains locked and was not re-probed.

All46 focused Debug and46 optimized tests pass;9 optimized menu checks also pass. Real local Vision finds1 person in a portrait and2 in an overlapping two-person photo; selection, source retention, native save and Undo/Redo succeed. Latest full1920-test/universal baseline196 excludes197. Timings in the model report include selection/archive/overlay work, not just inference. NASA images stay in local evidence with attribution/use provenance; they are not bundled or published. All1485 frozen inputs,754 original Rust hashes and four protected files verify. Five files added, nine modified inputs, none removed. Xcode project/version/root and installed apps/settings remain unchanged. Broad/full/universal qualification stays batched. Next: evaluate and verify a suitably licensed semantic model through native Core ML before exposing hair/skin/clothes classes; fine cosmetic/numerical details stay deferred.

[Development details](DEVLOG.md#dev-step-197), [checkpoint](ACTIVE_CHECKPOINT_197.json), [references](PEOPLE_SELECTION_REFERENCES.json).

## 2026-10-27 — Step198: people feature segmentation

The native person picker now selects hair, face skin, body skin, clothes and accessories, independently or together, for selected people. Feature probability maps intersect Vision person instances; the existing selection modes, Hard Edge, refinement, Undo/Redo, Actions4 and native32 archive paths remain shared with the API. Missing or failing optional model resources leave whole-person selection available and disclose feature availability/errors. Fine facial labels remain unavailable.

Google's official Apache2.0 MediaPipe multiclass256 model was pinned by source SHA, with embedded class, normalization and SOFTMAX metadata verified. An independent bounded graph converter produces a macOS14 Core ML MLProgram; the deployed app uses only Swift and Apple frameworks. Offline Python/TensorFlow tools regenerate the ignored resource and record provenance. Twelve comparisons, including photographs on CPU/all compute, match original-runtime classifications within declared numerical tolerances. The first converter failed on a scalar reduction axis; the first Swift build failed actor isolation. Both failures and passing repairs are preserved. Actual Swift inference matches original photo probabilities within0.000006974, and one/two-person selection/save/Undo checks pass. Native overlays were inspected; no pixel-perfect Adobe or live-desktop claim is made.

All61 focused Debug and1933 full optimized tests pass. The universal macOS14+ package includes197 Select People and the native feature model; fresh extraction verifies both architectures, signature and model provenance. Xcode Debug build also passes. All1502 frozen inputs match the workspace/isolation. Seventeen newly covered inputs include existing NOTICE/.gitignore, generated native resources and new tooling; ten previously covered inputs changed and none were removed. NOTICE/.gitignore were modified, not newly created. The Xcode project deliberately gains a verified optional model resource phase; original bytes are retained. Root app/ZIP, user settings and754 original Rust hashes remain unchanged. No version change, publication or installation occurred. Independent platform, exact/model/default/persistence and live UI qualification remain open.

Next is G03 live shape drawing/editing, with native UI, history, persistence and API as one workflow. Existing rectangle/ellipse/path foundations and original Rust live-shape code can be reused; proprietary shape-library assets will not be copied. Fine semantic-mask and numerical/cosmetic refinement remains deferred under the major-first scheduling instruction.

[Development details](DEVLOG.md#dev-step-198), [checkpoint](ACTIVE_CHECKPOINT_198.json), [references](PEOPLE_FEATURE_REFERENCES.json).

## 2026-10-27 — Step199: native live shapes

The legacy rectangle/ellipse fill-only mouse-up path now uses native live geometry shared by seven tools: rectangle, ellipse, triangle, polygon, star, line/arrows and custom shapes. Retained components support boolean drawing, individual corners and parameter editing; fills and strokes support none, solid, gradient and embedded pattern paints, with alignment/dash/cap/join controls. Native properties preview and cancellation, shape/path/pixel output, custom preset definition/import/export, U-group integration, native33 saving and Actions5 shape recording accompany three API commands. Rasterize Shape uses the existing native raster/API engine. Rust geometry provenance remains explicit; no Adobe artwork/presets are redistributed.

Initial compiler/fixture failures were preserved and repaired. A background stack overflow revealed that nested Frame commands allocated the large primitive command dispatcher twice; indirect shape enum storage helped but did not resolve it. Separating modular dispatch from the primitive switch fixed the underlying nesting problem without dropping protection validation. A reused dictionary-only API decoder also raised an Objective-C exception for mode strings; the shape decoder now explicitly supports typed JSON fragments. All failed runs and diagnostic stacks remain in the199 evidence directory.

All80 focused Debug and1944 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1511 frozen inputs match the workspace and isolation;9 files added,26 changed and0 removed. Root app/ZIP, Xcode project, workspace preferences and754 original Rust source hashes remain unchanged. Native events and offscreen snapshots demonstrate functional integration; locked-session native chrome/text does not fully render in those snapshots, so no live visual qualification is claimed. Full editable PSD/.csh/gradient cross-profile transfers and precise Adobe output/default parity remain open. No version bump, installation, publication or commit occurred.

Next is the missing major Pen/Paths workflow. Fine shape rasterization/default/cosmetic refinements remain deferred under the maintainer's major-first instruction.

[Development details](DEVLOG.md#dev-step-199), [checkpoint](ACTIVE_CHECKPOINT_199.json), [references](SHAPE_REFERENCES.json).

## 2026-10-27 — Step200: native Pen and Paths

Freeform and Curvature Pen now join the P tool group. Freeform previews sampled geometry, fits editable cubic handles on release, extends endpoints and cancels without history. Curvature clicks interpolate smooth anchors, double-click toggles corners, clicking the first point closes a contour and anchors remain draggable. The Paths panel exposes selection tracing with tolerance, foreground fill and current-brush stroke with optional pressure simulation. All share existing saved/work paths, vector masks, native persistence and Undo. Five typed API commands expose the same engines, geometry, settings and state. Rust marching squares/fitting provenance is recorded.

Two compile attempts caught a shadowed error assignment and a test whitespace error. The first runtime suite exposed a shared API guard that rejected selected paths; a narrowly scoped path-context option repaired that without removing channel/mask/busy/revocation protection. Preserved failed attempts remain under the200 run directory.

All100 focused Debug and1951 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1518 frozen inputs match workspace/isolation;7 additions,12 modifications and0 removals are enumerated in changes01.json. Protected root app/ZIP, Xcode project, workspace preferences and754 original Rust hashes remain unchanged. Synthetic native events are functional evidence; the locked desktop was not re-probed. Full G04, exact Photoshop curve/pressure kernels, magnetic pen, multiple-anchor editing, advanced Fill/Stroke options, clipping exports and semantic Actions remain open. Next major breadth is multilingual/OpenType typography. No installation/publication/commit or version bump occurred.

[Development details](DEVLOG.md#dev-step-200), [checkpoint](ACTIVE_CHECKPOINT_200.json), [references](PATH_WORKFLOW_REFERENCES.json).

## 2026-10-27 — Step201: native advanced typography

Vertical Type joins the T tool group with native editable point/paragraph text. Properties exposes OpenType features, variable axes and a language tag; the Glyphs panel pages installed fonts and inserts retained glyph identities at the text cursor. Font discovery and glyph insertion have typed APIs, while text creation/editing exposes the same options. The published Adobe text adapter accepts vertical orientation and small capitals through existing contract fields. Native34 and Actions6 retain advanced metadata; the bounded PSD subset retains orientation and represented flags and rejects metadata it cannot preserve.

The first two compile attempts caught CoreText option-set syntax and API range-type conversions. Focused runtime tests caught missing version34 reader allowlists. An initial ligature expectation used a font that did not provide that substitution on this host; an independent six-font probe established HelveticaNeue as the valid regression font. A new downgrade test needed property-list parsing. Final review repaired paragraph formatting loss on glyph insertion through shared desktop/API construction. Failed attempts and repairs remain individually saved.

All 70 focused Debug and 1959 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1524 source inputs match workspace/isolation;6 additions/23 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Tests prove host native rendering, metadata/Undo/API behavior and source-derived codec round trips; no live desktop, independent Photoshop output or physical platform certification is claimed. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. T04 path/warp text is next; minor utilities and exact/cosmetic refinements remain deferred.

[Development details](DEVLOG.md#dev-step-201), [checkpoint](ACTIVE_CHECKPOINT_201.json), [references](ADVANCED_TYPOGRAPHY_REFERENCES.json).

## 2026-10-27 — Step202: editable shaped text

Text can follow a saved path, fit inside a closed shape, use fifteen preset warps, or dynamically fit Block, Circle, Arch and Bow layouts. A native workspace retains rich text beside the curved preview, layout controls, local Undo, canvas preview and one document transaction. Logical-origin compensation prevents normalized glyph bounds from moving the text anchor or its mask. The native API exposes the same layout engine through text.layout and complete text descriptions. Native35 and Actions7 retain geometry; unsupported editable PSD output fails explicitly.

The first five compile attempts caught Core Foundation casting, a test initializer, Observation declarations/initialization, a mutable detached-task capture and API helper mismatches. Runtime checks then found two inconsistent HTTP input error codes and an older test still rejecting newly supported archive35. Each attempt and repair is retained. Offscreen diagnostics show all seven layouts; the hidden-window native sheet is synthetic evidence, not a live desktop check.

All 89 focused Debug and 1966 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1530 frozen inputs match workspace/isolation;6 additions/27 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. Full T04/Photoshop equality remains open. Filter Gallery is the next major family; minor typography utilities and numerical/cosmetic refinements remain deferred.

[Development details](DEVLOG.md#dev-step-202), [checkpoint](ACTIVE_CHECKPOINT_202.json), [references](SHAPED_TEXT_REFERENCES.json).

## 2026-10-27 — Step203: native Filter Gallery

The47 original artistic effects are now Swift kernels with a native gallery workspace: category thumbnails rendered from the actual layer, parameter and color controls, effect ordering/visibility, before-after preview/zoom, local Undo and one document commit. Smart Objects retain source pixels and editable effects. Existing native filter APIs and Actions/Batch share the same command; native36 and Actions8 prevent older formats from silently discarding Gallery metadata. Exact Adobe ActionJSON and editable PSD mappings remain explicitly unsupported.

The first compile found a duplicate decoder variable. New engine/workspace/API tests then passed; broader regression checks found older assumptions that every filter used native15 or supported Adobe/PSD descriptors. Those qualification lists were corrected. An independent adapter executed the original unmodified Rust kernels and helper bodies, producing47 synthetic default fixtures: the Swift results match every RGBA8 byte. This is source-port evidence, not Photoshop equality. A hidden-window image verifies readable controls and layout; it is not a live desktop check.

All42 focused Debug and1973 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1589 frozen inputs match workspace/isolation;59 additions/20 modifications/0 removals are listed in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged; no installation, publication or commit. The next major family is Smart Sharpen/Reduce Noise; minor variants and exact numerical/cosmetic polishing stay deferred.

[Development details](DEVLOG.md#dev-step-203), [checkpoint](ACTIVE_CHECKPOINT_203.json), [references](FILTER_GALLERY_REFERENCES.json).

## 2026-10-27 — Step204: paused with a current dashboard

The maintainer paused development after the verified Filter Gallery checkpoint and asked to see remaining work. The master goal is paused. Preserved exact package/source identity and the next Smart Sharpen/Reduce Noise plan. A current expandable dashboard distinguishes81 major,21 minor and3 final broad packages from285 partial/360 pending command statuses and282 wired/443 unavailable menu commands. Existing functions still need qualification inside those broad packages, so these are not percentage-complete estimates. The October9 snapshot remains unchanged. No application source or package changed.

[Pause checkpoint](PAUSE_CHECKPOINT_204.json), [development record](DEVLOG.md#dev-step-204).

## 2026-10-27 — Step205: investigation paused, live dashboard reopened

A brief resumed Smart Sharpen/Reduce Noise source investigation produced no application changes or new builds. The maintainer requested pause again; the goal is paused and checkpoint203 remains the last verified implementation. Saved the exact next-major work and opened the existing live dashboard against the current project. Its105 open broad packages include implemented capabilities still awaiting strict parity qualification. Source and package hashes remain unchanged.

[Pause checkpoint](PAUSE_CHECKPOINT_205.json), [development record](DEVLOG.md#dev-step-205).

## 2026-10-27 — Step206: native photo detail workflows

The maintainer explicitly resumed development. Smart Sharpen and Reduce Noise now have native controls, preview at Fit/100%, Cancel/local Undo, one document commit and editable Smart Filters. Gaussian sharpening and guided denoising follow the original Rust approach; Lens/Motion use actual native disk/line deconvolution. Tonal fades, JPEG-grid softening and additional RGB channel denoising are available. Native37/Actions9 and the shared Photato API retain the new settings. Exact Adobe descriptors and editable PSD remain unqualified and reject explicitly.

The first compile exposed grouped Observation properties; splitting them repaired it. Integration tests initially referenced two wrong API names; these were corrected with failures retained. All45 focused checks pass, including noise/edge behavior, blur direction, depth/alpha, desktop/API equivalence, history, persistence, cancellation and rejection guards. Both offscreen panels were inspected. An API review also caught unnecessary internal fields in the preview-state payload. The first full build was stopped and retained, then the payload and a public round-trip check were repaired before restarting. All45 final focused Debug and1980 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1595 frozen inputs match the tested source;6 additions/19 modifications/0 removals are listed in changes02.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged. The next major workflow plan covers Lens Blur depth maps and iris controls.

[Development record](DEVLOG.md#dev-step-206), [scope and evidence](PHOTO_DETAIL_REFERENCES.json).

[Verified checkpoint206](ACTIVE_CHECKPOINT_206.json).

## 2026-10-27 — Step207: native Lens Blur

Implemented iris/depth/highlight/noise controls with native preview, focus picking, local history, one commit and API support. Live mask/channel references remain editable; invalid sources or source deletion reject. Native38 and Actions10 preserve settings. Adobe excludes Lens Blur from Smart Filters, so Photato's editable version is explicitly a native extension.

All53 focused and1990 full optimized tests pass. Early failures, including a real background stack overflow in nested Smart Filter mask dispatch, were preserved and repaired. Offscreen layout was inspected. Production packaging was batched with the user's208 title/overflow fixes; the combined208 universal package now verifies. Full Photoshop parity remains open. [Evidence](LENS_BLUR_REFERENCES.json).

## 2026-10-27 — Step208: title and viewport corrections

The user requested `Photato - <current doc name>` and supplied a screenshot of canvas content covering window controls. Read-only live inspection and a failing pixel-boundary regression confirmed the overflow. Added view/layer clipping and a saved CGContext clip around the full draw pass. Window titles now update with active tabs and document names; native API state exposes the same title. The first resized fixture misinterpreted bitmap Y coordinates; its repaired rerun proves no pixels escape the viewport. Failure evidence is preserved.

All 59 focused Debug and 1,991 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1,601 frozen inputs match workspace/isolation; one test file added, six files modified, none removed. Four protected files and754 original Rust hashes remain unchanged. Separate current Debug live checks cover title,200% zoom, horizontal/vertical scrolling and actual native window resizing. No user document input/edit/save; validation app exited. Application0.2.0build2 and Xcode project unchanged. The current Lens Blur work is included in this package. [Evidence](WINDOW_PRESENTATION_REFERENCES.json), [checkpoint208](ACTIVE_CHECKPOINT_208.json).

## 2026-10-27 — Step209: Photato identity cleanup

At the maintainer’s request, removed the retired family identity from About, demo names, project documentation, the diary and archived text copies. Photato retains its own name, supplied icon and original PhotoCraft attribution. Renamed owned TIFF fixture group metadata without changing image samples. All50 focused checks pass, including TIFF decoding/pixels, gradient presets, support links and window/viewport regressions. The refreshed universal macOS14+ app verifies after extraction; its contents have no retired branding. Earlier208 full1991-test results remain historical. Archived signed binaries and screenshots are retained as historical evidence. The repository stays private until the software’s release day, when it will become public.

## 2026-10-27 — Step210: the developer diary on the website

The maintainer requested an elegant way to read the developer diary from the Photato website. The website now presents210 dated, expandable entries with local search, chronological sorting, keyboard access, stable per-entry links and a downloadable narrative diary. The existing Forensic Intelligence visual style is retained. Desktop and320/390px mobile views were inspected; search, empty state, sorting, permalinks and mobile navigation pass with no browser warnings/errors. The GitHub repository already exists; it remains private during development and will become public on the same day the software is released. The website is saved locally for the maintainer to publish.

## 2026-10-27 — Step211: private GitHub development build

At the maintainer's request, the verified universal macOS 14+ development build is now attached to a private GitHub draft release. It includes Lens Blur, the document window title and canvas containment fixes, and the current branding cleanup. The repository remains private until software release day.

A fresh extraction verifies the signature, executable hash and both architectures. All four uploaded assets were downloaded again and their hashes match. The package is ad-hoc signed, not notarized or App Store signed. The 50 focused tests apply to this snapshot; the preceding 1,991-test full run is historical. Full Photoshop parity and the physical platform matrix remain open. The release notes explicitly state that local build sources are newer than GitHub main; this build-only upload does not push source changes. [Private draft release](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-04479448d8da0ffe8270). [Development record](DEVLOG.md#dev-step-211).

## 2026-10-27 — Step212: distortion workflows and window-build handoff

Displace, Shear, Wave, Pinch, Spherize, Twirl, Ripple, Polar Coordinates and ZigZag now have native Swift settings, previews, Cancel/Undo and editable Smart Filters. Displacement maps stay embedded with the document; Shear curves can be edited directly. The Photato API shares the same operations. Native39 and Actions11 preserve the new settings. The first integration attempts exposed a Swift getter, a test comparison and missing archive negotiation paths; each failed attempt was preserved and repaired. The full run also found two outdated version expectations, corrected before the final run.

All45 focused checks and2,003 final full optimized tests pass. The universal macOS14+ package verifies after fresh extraction. Adobe's observed dialogs informed controls and parameter ranges; exact Photoshop pixels, action descriptors, editable PSD interchange, live native filters and the physical platform matrix remain unqualified. Other major F02 filter families remain open.

The maintainer's recurring workspace-overlap screenshot was traced to an older test app still running before the clipping fix. Its document was saved separately, and the verified corrected build was installed alongside it. The title appears correctly, but the Mac locked before the same-document zoom/scroll check and handoff could finish. That live check remains pending; automated containment checks pass.

The diary overview was checked at desktop and phone widths, with five readable numbered steps and no horizontal page overflow. At the maintainer’s request, it explains the actual engineering process, licensed PhotoCraft provenance, public specifications, black-box comparisons and saved-file analysis. It explicitly excludes decompiling/disassembling Photoshop or copying proprietary Adobe implementation code. It does not assert a formal clean-room separation or the unsupported broader statement that no reverse engineering of any kind occurred. [Development record](DEVLOG.md#dev-step-212).

## 2026-10-27 — Step213: native Pixelate workflows

Color Halftone, Crystallize, Facet, Fragment, Mezzotint and Pointillize now run in native Swift. Facet and Fragment apply immediately; the other four have settings, previews and local Undo. Smart Filters keep their source and editable parameters. Native40 and Actions12 save those settings, and the Photato API uses the same commands as the desktop. Pointillize captures the current background color; seeded patterns make repeatable renders possible.

Eighteen synthetic reference images produced by the original, unmodified Rust filter source match byte-for-byte. The first focused run exposed unnecessary sparse-tile allocation on an unchanged white image; that was repaired without changing expected pixel output. All68 final focused checks and2,015 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction. Hosted workspace images were inspected; they are not live interaction evidence.

Adobe's published API lists these filter families but requires recorded action descriptors. Those mappings and editable PSD interchange remain incomplete. Exact Photoshop pixels/defaults/depth availability, live interactions and the physical platform matrix also remain open. Other major F02 workflows are still outstanding; the next family is Stylize.

The recurring workspace-overlap report remains a delivery handoff in progress. The older test app is still running; the corrected installed build and saved copy of its document retain their verified hashes. Automated canvas-containment checks pass. The Mac remains locked, so reopening that document, checking zoom/scroll/resize and safely closing the obsolete test window still await unlock. No new live pass is claimed. [Development record](DEVLOG.md#dev-step-213).

## 2026-10-27 — Step214: native Stylize workflows

Diffuse, Emboss, Extrude, Find Edges, Oil Paint, Solarize, Tiles, Trace Contour and Wind now run in native Swift. Find Edges and Solarize apply immediately; the other seven offer native settings, preview and local Undo. The same commands power the desktop and Photato API. Editable Smart Filters retain the original pixels, parameters and masks through native41 and Actions13 saving. Emboss also has PSD descriptor round-trip coverage using the licensed PhotoCraft mapping.

Twenty-seven synthetic reference images generated with the original Rust source match byte-for-byte. The first run exposed three test setup issues: tiny Tiles settings legitimately produced no change, an HDR fixture used encoded instead of linear storage, and a wide Oil Paint reference used whole-image processing instead of the original application's default256-pixel tiles. A separate original-Rust experiment reproduced the tile-dependent difference. The corrected fixtures retain exact assertions and preserve the failed evidence; no editing algorithm was changed to make these tests pass.

All 80 final focused checks and 2,027 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction. Oil Paint, Extrude and Tiles workspace renderings were inspected for layout; they are offscreen evidence. Adobe actionJSON support, wider editable PSD interoperability, exact Photoshop output/defaults/depth behavior, live interaction and physical platform qualification remain open. F02 is still in progress; Render workflows are next.

For the recurring window-overlap report, the corrected installed app and saved document still match their verified checksums. The older test app remains running. Current canvas-containment tests pass, but the locked Mac prevents the same-document zoom, scroll and resize handoff. The obsolete window will remain open until that handoff can safely finish. [Development record](DEVLOG.md#dev-step-214).

## 2026-10-27 — Step215: native procedural Render filters

Clouds, Difference Clouds, Fibers and Lens Flare now run in native Swift. Clouds and Difference Clouds use immediate menu commands; Fibers and Lens Flare offer native previews and local Undo. Lens Flare can be positioned directly in the preview. Generated textures fill the selected canvas region even on empty or cropped pixel layers while retaining transforms, masks and transparency locks. Editable Smart Filters preserve the source and captured settings through native42 and Actions14 saving. The Photato API uses the same commands, history and validation.

Twelve synthetic images produced using the licensed original Rust functions match byte-for-byte. The first attempt stopped at a test typing error. The second exposed a real Lens Flare porting mistake: the original helper handles reversed smoothstep edges with a hard step, while the initial translation used a smooth ramp. The implementation was corrected without changing the expected reference images. Two further assertions differed only because separately created Smart Filters received different identifiers; those comparisons now normalize that identifier while checking the complete document. Both failed attempts and their repairs remain preserved.

All 94 final focused checks and 2,041 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction. Fibers and Lens Flare workspace images were inspected for layout; they are offscreen evidence. Adobe actionJSON and editable PSD mappings, exact Photoshop output/defaults/depth contexts, live interaction and physical platform qualification remain open. F02 remains in progress. Flame, Tree and Picture Frame are the next major Render workflows. Lighting Effects exists in the licensed source but is absent from the captured current Photoshop menu; its reference context needs separate review.

The recurring window-overlap report still requires a live handoff. The older test app remains running; the corrected installed app and saved document retain their verified hashes. Current canvas-containment tests pass. The Mac remains locked, so the same-document zoom, scroll and resize check and safe closure of the old window remain pending. The private GitHub development build remains209; this215 package is local. [Development record](DEVLOG.md#dev-step-215).

## 2026-10-27 — Step216: native Flame, Tree and Picture Frame

Three more Render workflows now run in Swift. Flame follows a chosen document path and exposes the six source modes, shape, style and flame controls. Tree offers34 source designs, leaf/branch/light controls and a draggable base. Picture Frame offers16 source designs, line/spacing/color and fade settings. Each has a native preview, local Undo, Cancel, one document Undo on commit and optional new-layer output. Selection, transparency locks, cropped storage and mask placement are retained. The three Photato API commands use those same transactions. Actions15 records settings, portable target layers and actual Flame paths; generated raster pixels use existing native and PSD persistence.

The first core run stopped at incorrect persistence helper names in a new test. After that repair,70 original-Rust reference comparisons exposed89 channel samples differing by one eight-bit level across36 cases. Diagnostic paint-buffer comparisons traced this to the floating-point PI constant: Swift's Float.pi rounds down, whereas the source Rust constant rounds to nearest. Using the explicit source bit pattern fixes every reference without changing expected images or weakening assertions. The first app-integration compile then caught grouped declarations unsupported by Swift Observation and an error-variable shadowing mistake; those were repaired. Failed attempts remain available in the development record.

All109 focused tests and2,055 full optimized tests pass. The universal macOS14+ package verifies after fresh extraction. All70 original-Rust RGB8 cases match byte-for-byte in both focused and optimized tests. The three hosted dialog images were inspected for containment and layout; that is offscreen evidence. These results do not prove Photoshop pixel equivalence. Exact Photoshop settings, output/depth contexts, Adobe raster ActionJSON/ATN compatibility, live interaction and physical platform qualification remain open. The original-source fallback arc is not substituted when Flame lacks a real path. F02 stays open; remaining Other/Video workflows are next, with Lighting Effects' current availability still requiring a separate audit.

The workspace-overlap handoff remains unfinished. The old test app is still running alongside the corrected installed209 app. All23 dedicated window/containment checks pass, as do the window cases in the full suite. The installed executable and saved document match their verified copies, but native app access reports the Mac locked. Same-document zoom, scrolling, resizing and safe closure of the obsolete window remain pending. The private downloadable build remains209; this216 package is local. The inherited Actions import-description version hint also remains a small metadata follow-up, while the actual decoder/discovery state correctly supports Actions15. [Development record](DEVLOG.md#dev-step-216).

## 2026-10-27 — Step217: native Other and Video filter workflows

Seven more Photoshop menu operations now have working native Swift implementations: Custom, HSB/HSL, Maximum, Minimum, Offset, De-Interlace and NTSC Colors. Custom offers a 5×5 matrix with scale and offset plus portable JSON presets. Maximum and Minimum support square and round neighborhoods. Offset handles wrapping, repeated edges and transparency in the selected region or canvas. De-Interlace offers field order and duplication/interpolation choices. Settings, previews, Cancel and local/document Undo share the same transactions as the Photato API. Editable Smart Filters retain their sources through native43 and Actions16 saving; ordinary raster results also survive PSD saving.

The reference generator initially needed a Copy annotation on its Rust adapter and a fresh output directory. Three early Swift builds caught spacing, missing error propagation and a test fixture using a read-only store property. The next run exposed eight old generic interchange expectations that incorrectly included filters whose Adobe descriptors are explicitly unsupported, plus a busy-request test that had not selected its newly created layer. Those tests now distinguish qualified operations and check that a preview really opened. The full suite then caught two older archive expectations: discovery still ended at42 and the invalid-version list contained the now-supported43. Those now use readable1–43 and unsupported44. Every failed attempt remains preserved. No expected reference pixels were changed.

All 124 focused tests and 2,068 full optimized tests pass. All 44 synthetic original-Rust RGB8 outputs match byte-for-byte. Fresh extraction verifies the universal macOS14+ package. Hosted dialog images were inspected for layout; these are offscreen checks. Photoshop output/defaults, Adobe ACF presets, ActionJSON/ATN and editable PSD descriptors, fractional Roundness behavior and live/platform qualification remain open. Full F02 is still in progress. The next major breadth work is the remaining Blur, Noise and Sharpen operations.

The older window from the overlap screenshot is still running. Selecting the corrected installed app again reports the Mac locked, so the same-document zoom, scrolling, resizing and safe closure of the old window remain pending. The private downloadable build remains209; this217 package is local. The stale Actions import-help version hint noted in216 is now corrected to1–16, matching the actual decoder and discovery state. The diary overview was also brought forward from its stale211 summary to this verified checkpoint. [Development record](DEVLOG.md#dev-step-217).

## 2026-10-27 — Step218: native Blur, Noise and Sharpen workflows

Twelve more factory menu operations now work in native Swift: Blur, Blur More, Radial Blur, Shape Blur, Smart Blur, Surface Blur, Despeckle, Dust & Scratches, Median, Sharpen, Sharpen Edges and Sharpen More. Six apply immediately; the other six open settings and previews with Cancel and local Undo. Radial Blur has Spin/Zoom, quality and a draggable center. Shape Blur offers nine built-in kernels. Smart Blur has quality and three output modes. The family shares document Undo, selection/transparency handling, cropped pixel and mask placement, editable Smart Filters, native44/Actions17 saving and the Photato API. Known Adobe bit-depth restrictions are enforced in desktop and API execution.

The Rust reference harness initially failed because unused large-Gaussian helpers referenced Rayon. A sequential iterator adapter repaired the harness while preserving the selected original algorithm bodies. All 44 resulting RGB8 test images match byte-for-byte. The first native focused run passed all 149 tests; the only later production change clarified the aggregate API description of unsupported editable PSD interchange. The complete optimized suite then passed all 2,082 tests. Fresh extraction verifies the universal macOS14+ package. Hosted settings-dialog images were inspected for control placement; these are offscreen checks, not live user interactions.

This is F01 functional breadth; the initial working note classified it as F02, which is corrected in the current ledger. Both packages remain open. Exact Photoshop output/defaults, imported or custom Shape presets beyond the nine source kernels, Adobe ActionJSON/ATN/editable PSD descriptors, large-document processing budgets and live/platform qualification remain outstanding. Radial Draft/Good use native sample budgets derived from the source Best path; no Adobe quality-kernel equivalence is claimed. Next major breadth work is the remaining classic adjustment family.

The overlap screenshot still corresponds to the old159 app. The corrected209 app and retained document keep their verified hashes and signature. A new native app selection returned no window, and the follow-up inventory explicitly reported the Mac locked. No input was sent and no same-document live handoff is claimed. Canvas pixel-containment and document-window regressions pass in the full suite; opening the saved artwork, zooming, scrolling, resizing and safely closing the old window remain pending manual unlock. The private downloadable build remains209; this218 package stays local. [Development record](DEVLOG.md#dev-step-218).

## 2026-10-27 — Step219: classic tone and color adjustments

Five previously unavailable Image > Adjustments workflows now run in native Swift. Shadows/Highlights includes tonal widths, radii, clipping and color/midtone controls, and can remain editable on Smart Objects. HDR Toning offers four methods, a curve and a flattened result with one Undo restoring the source layers. Match Color can read an open source document or layer with selection-weighted Lab statistics. Replace Color supports additive/subtractive samples, localized clusters and selection-mask preview. Equalize supports selected-area mapping or whole-target mapping based on the selected sample. Native previews, local history, cancellation and document Undo share the same engine with two new API commands.

The implementation translates the licensed PhotoCraft tone, Gaussian, Lab, HSL and Equalize behavior. Twelve independently generated original-Rust RGB8 references match byte-for-byte. They are not Photoshop output. The first compile found a missing API-schema bracket; the next regression found outdated generic command/version/interchange expectations. Both failures and repairs remain in the evidence record. A final API review corrected the statistics depth schema to match its actual string payload. All161 focused tests and2,094 full optimized tests pass, followed by fresh-extraction universal package verification. Four hosted dialog renders were inspected for contained previews and readable controls, with longer HDR controls in a scrollable panel. These are offscreen checks, not live interaction acceptance.

There are112 typed Photato commands. Statistics are read only through a shared source document route and are portable values for a separate target request. Editable Shadows/Highlights uses native45; ordinary tone Actions use18. Semantic HDR Actions, Adobe STA/presets/ActionJSON/ATN and editable PSD descriptors remain unsupported. Exact Photoshop output/defaults/depth behavior and ICC-specific processing remain unqualified, as do physical Intel/macOS14/macOS26 and live workflows. Full A03 is still open. The next major breadth work is native document color modes and separations.

The old159 test window from the overlap report remains running. The installed corrected209 app and retained artwork are preserved. Current native UI access returned no window; no new live handoff or safe closure of the old app is claimed. Canvas containment and document-window regressions pass in the full suite. The pending handoff is to open the retained artwork in Photato Verified, check title/zoom/pan/scroll/resize and review unsaved state before closing the obsolete window. The private downloadable build remains209; this219 package stays local. [Development record](DEVLOG.md#dev-step-219).


## 2026-10-27 — Step220: document color modes, in progress

Photato now retains actual RGB, Grayscale, CMYK and Lab component planes, including independent black ink, ICC profiles and floating-point HDR. Native format46 and history preserve these samples; existing RGB tools use a derived display/editing cache. Conversion has a native preview dialog, profile/depth/intent controls, local Undo, Cancel and one document Undo. Seven Image > Mode entries follow the existing Photoshop menu inventory. Merging rich layers and clipping HDR values are explicit choices. Three Photato API operations expose conversion and bounded numerical component reads/writes through the same engine.

All91 focused Debug tests pass, including28 new mode tests, HTTP native-file reopen, menu/window regressions, API equivalence and stale/busy/protected errors. Two new-test compile mistakes were repaired and their logs retained. An earlier373-test run failed in the existing Layers rename lifecycle test. The same focus issue reproduces in freshly built219 Debug while its optimized binary passes; additional zero-size assertions remain unqualified. An attempted focus repair was ineffective and withdrawn byte-for-byte. No live desktop check or new universal package is claimed.

The next implementation stage adds real mode-aware PSD/PSB raster/group/mask interchange. All182 selected mode/PSD/TIFF checks pass. Seven files also pass independent decoding: psd-tools recovers24 layer planes byte-for-byte, and Apple ImageIO reads each merged cache. A new mask test initially compared internal Surface layout; its16-bit fixture and bounded sample assertions were corrected, with both failed and passing runs retained. Existing RGB Photoshop reference tests still pass. Merged CMYK/Lab previews currently use the RGB compositor and are not proof of native ink/blend equivalence.

The TIFF stage now retains Gray/CMYK/Lab channels, profiles, alpha and orientation, with both byte orders, pixel/channel layouts, lossless compression and Float32 prediction. Native Save, Photato transfers and both asynchronous job interfaces use the same serializer. All192 focused tests pass, including ten new TIFF tests. Independent readers check14 files:48 composite planes follow the documented TIFF encoding, and24 embedded layer planes preserve the original bytes. Apple ImageIO reads all14 at the expected mode and depth. Flattened Lab16 chroma is rounded to the format’s signed1/256 scale; layered components remain exact. An initial external verifier used the wrong temporary wrapper for8-bit layer records; its repair and failed log are preserved. These checks do not prove Photoshop color or blend parity.

The Channels stage now shows the real components of RGB, Grayscale, CMYK and Lab documents. Visibility and editing targets are separate; numerical fill, brush/erase, Invert and eight filters preserve untouched channels and transparency through preview/Cancel and one Undo. High-depth RGB is included; the older qualified RGB8 path remains. Three new Photato APIs bring the catalogue to118 commands, with matching state and preview images.305 broader tests and126 final focused tests pass, including13 new component tests. Two schema-helper compile failures were repaired and retained. Hosted captures show the mode rows and footer within the panel; these are offscreen checks, not live Photoshop comparisons. Rich-effect previews still separate the RGB composite, so ink-space blend fidelity remains open.

File New and API jobs now share native blank-document creation in RGB, Grayscale, CMYK and Lab. Mode, supported bit depth, resolution, background and ICC profiles reach the same engine. Adobe create-composite accepts its published image-parameter subset; the Photato action-job API adds the same option while Adobe execute-actions keeps URL input. Custom profiles are checked before use, blank jobs fetch no image, and revocation prevents late publication. All124 focused tests pass, including nine new creation/HTTP/profile/layout/target cases. Earlier attempts exposed mistaken RGB PSD test expectations, a correctly enforced job quota and a2point label overflow; each failure and repair is preserved. Offscreen bounds pass, but native button interiors are not captured, so no live visual approval is implied.

Fourteen examples validate against the pinned image and selected PSD-output schemas and our local discoverable schema. Full strict request validation exposed an ambiguity in Adobe's published output union: its branches do not constrain mediaType. The original schema remains unchanged and this limitation is recorded. Other named profiles, nonpixel units/scales, guide-only solidColor fills and exact working-profile/color behavior remain open.

The next integration connects both job APIs to native channel editing and mode conversion. Gray, CMYK, Lab and higher-depth RGB targets support neutral Fill, Invert and eight filters; target state survives multiple action resources, while untouched planes and transparency stay intact. Conversion preserves layer selection and working-profile primaries, with explicit merging for rich content and no implicit HDR reduction. The legacy RGB8 byte-exact Fill path remains.158 focused tests pass, including11 new tests and actual desktop/API output equality. Independent readers recheck14 current TIFFs with48 composite and24 layer planes.

A failing merge test exposed an encoded Float32 compositor buffer being treated as linear solely because its storage was floating point. The shared conversion now respects its actual color encoding; direct ColorSync component checks cover the repair. New channel names use a plugin author's public observation on Adobe's developer forum, while conversion identifiers come from installed public scripting interfaces and official documentation. These are disclosed references, not proof of current Photoshop2026 numerical or descriptor equivalence. The integrated source has now completed full optimized and universal-package qualification; the next major work is Indexed Color and Bitmap, followed by the remaining ink modes.

The repeated window-overlap report was traced to the older test app still running beside the corrected installed build. All 34 current canvas, viewport and document-window regressions pass. The installed app and retained artwork verify unchanged. The Mac is locked, so reopening the artwork, checking zoom/pan/scroll/resize and safely closing the old window still require manual unlock; no new live acceptance is claimed.

Full qualification exposed one outdated test that still expected RGB32 component Fill to fail. It now checks actual channel values, untouched green/blue/alpha bytes, Undo/Redo and equality across the desktop and both HTTP interfaces. All46 focused regressions and all2,173 optimized tests pass. The failed attempt remains preserved. Independent readers verify seven current PSD files and fourteen TIFFs; the universal package passes fresh-extraction, signature, resources, architecture, minimum-OS and optional-AI weak-link checks.

The [private development build220](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-3913ac56396348d02611) contains the verified ZIP, checksums and source-input provenance; all uploaded assets match their downloaded copies. It is built from the local frozen source, which is newer than remote main. No source changes were pushed and repository visibility remains private. The existing Debug-only Layers focus issue, physical platform checks and the locked-desktop window handoff remain open.

This increment is unfinished. Full native component tool/menu/shortcut coverage, complete Adobe component descriptor variants, TIFF storage variants, editable non-RGB rich PSD/TIFF content and restricted color modes still need implementation. Mode-native blend/filter fidelity, semantic Actions and independent Photoshop color comparisons remain open. The corrected209 app and retained artwork are preserved; the old159 overlapping window still awaits the previously requested manual-unlock handoff. The latest qualified local package and private GitHub draft are220. The already-installed corrected window build remains209 until a safe live handoff. [Working checkpoint](WORKING_CHECKPOINT_220.json), [development record](DEVLOG.md#dev-step-220).

Window follow-up on October28 confirmed the corrected installed executable and preserved artwork are unchanged. The Mac still reports locked, so the old test window has been left intact and the same-document handoff remains pending. No additional clipping change or live acceptance is claimed.


## Step221 — Native Indexed Color and Bitmap (in progress,2026-10-28)

**Tested development build:** The integrated Indexed Color and Bitmap workflows now pass all2,259 optimized tests and package as a universal macOS14+ app. A painting regression exposed previews whose stored color samples were stale. The shared preparation step now reconciles those samples before preview or commit, preserving untouched colors and duplicate palette indices. Six new workflow tests cover12 mode/depth contexts and84 tool/context combinations, native cancellation/history, automatic layers/masks, HTTP painting and reopening; all39 final focused checks pass. The failed reproduction and one API test-fixture correction remain documented. API capabilities and the diary reflect the fix. Build221 is saved locally;220 remains the uploaded private build. Same-artwork window acceptance still needs an unlocked desktop. Exact Photoshop output, full tool contexts and other parity gaps remain open; Duotone/Multichannel are the next major workflow.

**Window follow-up:** The reported overlap still comes from the older test app. The corrected app is installed and its signature verifies, but switching the artwork into it is unfinished: the desktop is locked. The document remains preserved; same-document zoom, scroll and resize acceptance stays open pending manual unlock. No new window code or live success is claimed. Separately, the painting regression reproduced stale stored samples in prepared previews across six modes; the repair and final qualification are recorded above.

**Latest Actions checkpoint:** Recorded conversions now keep their settings and apply them to each playback image. Copy, Copy Merged, Cut and Paste share a private playback clipboard, with native publication only after success. The same engine runs native Actions, API playback and Batch. Master palettes use immutable source snapshots; Previous and Color Table retain palette data without embedding source images. Actions19 reads older libraries and rejects falsely downgraded files. All523 combined regressions pass;34 final checks verify the exposed API response schema. Twelve new workflow tests cover native controls, portable replay, HTTP recording/output, Batch file changes, palette retention, history, cancellation, failed clipboard writes and stale sources. Earlier compile and assertion failures remain documented. This is still a development checkpoint; complete tools, Adobe descriptors, exact Photoshop output and live/platform/release qualification remain open.

The window-overlap follow-up confirms that the older test app remains open alongside the installed corrected app. The current317-test result includes canvas containment and document-window checks, and the app/artwork hashes remain unchanged. The live handoff is still pending the requested manual unlock; the bug stays open until that same artwork passes zoom, pan, scrolling and resizing in the corrected app.

Build220 is qualified and available privately. The next major workflow adds genuine palette-index and monochrome-bit storage, conversion settings, Color Table editing, native history/files and corresponding APIs. Work begins with licensed quantization algorithms and independent Rust fixtures. No new restricted mode is exposed or qualified yet; full Photoshop parity remains open.

Window follow-up: the reported screenshot is from the obsolete159 test app, which is still running. The corrected installed build and saved artwork verify unchanged, and the current tested source retains viewport clipping. A fresh UI attempt reports the Mac locked, so the same-document handoff remains pending; no new live pass is claimed. That window investigation changed no product or API code. [Evidence](../artifacts/runs/20261028T101734Z-221-indexed-bitmap/window-handoff01.json).

The core now retains actual palette indices and packed one-bit pixels, including duplicate palette identity, transparency, profiles and canonical row padding. Conversion, Color Table changes and ordinary painting preserve Undo/Redo, and native47 files restore their display caches from the retained samples. Shared adapters require explicit flattening consent and handle grayscale prerequisites, master palette profiles and Bitmap output resolution.

All94 focused integration tests pass, including18 new restricted-mode tests. The unchanged licensed Rust algorithms independently supply124 indexed and21 bitmap reference cases; all match byte-for-byte. One compile failure and one real regression in Adobe creation validation were preserved and repaired. Adding the model enum had accidentally made an unfinished mode parse successfully; the component-only menus, schemas and parsers are now explicit. These results do not establish Photoshop numerical equality.

This increment remains unfinished: native controls, Color Table UX, real PSD/PNG/TIFF storage, full tool/geometry context, both API integrations and broad/live qualification remain. The existing118 commands remain, with accurate restricted mode/depth state when such a native document is present; no new restricted conversion command is advertised. Build220 remains the latest qualified downloadable package. [Working checkpoint](WORKING_CHECKPOINT_221.json).

The next format stage has draft PSD/PSB and PNG codecs and dedicated fixtures. It is not compiled or tested yet; the94 passing tests above apply to the preceding core checkpoint. The renewed overlap report was checked first: the corrected app and retained artwork verify unchanged, but the locked desktop prevents the live handoff. No window code changed in this follow-up.


The file-interchange stage is now tested: PSD/PSB retain actual index or one-bit planes; PNG retains palettes and bit polarity through interlace/filter decoding; TIFF retains packed samples, palette identity, transparency, profiles and resolution through lossless compression and both byte orders. Native Save/Save As uses flat TIFF for these modes, and JPEG ordinary Save is excluded because it cannot retain the mode. HTTP downloads explicitly negotiate native47, and both existing action-job routes share the same codec path.

All166 combined focused tests pass, including33 restricted-mode tests and a separate Lab-profile stability regression. The independent incoming corpus contains37 files from Pillow/tifffile/imagecodecs; independent readers verify42 final exports and11,934 stored samples. Failures exposed a Swift slice typo, an overly strict PackBits row boundary, an outdated job header guard and a system Lab-profile timestamp change; each failure and repair is preserved. The Lab fix retains one default profile per process without altering imported profiles.

These are focused Debug and independent format checks, not full Photoshop equivalence or a new qualified release. Conversion/Color Table UI and typed APIs, complete mode-aware tools/Actions, unsupported file variants and live/platform qualification remain. The earlier unqualified codec draft is superseded by this tested checkpoint. The window handoff still awaits the existing manual unlock request; no additional desktop poll occurred.


The workflow now reaches the native interface. Image → Mode opens Indexed Color and Bitmap conversion previews; Color Table edits individual entries without changing pixel indices. Palette/dither/transparency/halftone/resolution controls, custom ACT tables and threshold tiles feed the same native preparation used by six new automation commands. Local Undo/Redo and Cancel leave the original untouched until OK; accepted edits have one document Undo. Index/Bitmap channel rows and API state report the stored mode rather than the RGB display cache. Remembered save defaults adapt after conversion, while explicit API output options retain validation.

Tests found and repaired an ACT base64 length guard, an omitted ellipsis in the Indexed Color menu binding, and a master-palette source race. The last repair checks captured document contents as well as revision tokens before accepting a result. Nine new workflow tests exercise these failures, stale/busy requests, native/API equivalence, palette identity through real files, history, closing and saved options. All215 combined focused tests pass. Three native-window-hosted offscreen captures show readable controls and contained previews; they do not qualify live input or Photoshop appearance.

This is a working development checkpoint, not a new release or full Indexed/Bitmap parity claim. Adobe restricted conversion descriptors, semantic Actions, full tool/clipboard/geometry behavior, exact Photoshop outputs and live/platform checks remain. Build220 stays the last qualified package; the existing window handoff still needs an unlocked Mac.

The next editing stage now transforms the stored palette indices and bitmap bits directly. Crop, Image Size, Canvas Size and canvas turns preserve duplicate palette entries for exact grid/nearest operations. Extension fills stay within the flat document and map to its existing colors. Four additional API commands use the desktop transaction path, bringing the total to128. Native archive, PSD/PSB, PNG and TIFF checks retain the changed samples.

A focused test caught crop fill attempting to install the compositor’s floating-point surface in an8-bit indexed document; the repair fills the original8-bit expansion. All68 geometry-focused tests and260 combined focused tests now pass, including nine new geometry tests and the existing window containment regressions. These are development checks, not a new release, a live overlap acceptance or proof of Photoshop pixel equality. Clipboard/tool contexts, semantic Actions, Adobe geometry descriptors and broad qualification remain open. The old test window is still open; the locked desktop prevents safely finishing the handoff to the installed corrected app.

Clipboard work now preserves the data that Indexed Color and Bitmap actually store. Native copies retain palette indices or packed bits alongside selection transparency. Paste changes the existing flat image, and a matching opaque copy retains duplicate palette identities. Cut preserves the flat layer and uses transparency where available, or the chosen background color. New from Clipboard keeps the original mode when its coverage fits that mode; fractional transparency remains RGB.

Four explicit clipboard API commands share these operations without reading or writing the Mac system clipboard. Transfers check encoded and decoded size, current revisions, sharing and document lifecycle. Oversized or revoked operations leave documents unchanged. No-op desktop edits now leave the modified flag alone.

The earlier clipboard checkpoint passed317 combined focused tests, including16 new clipboard regressions. Failed compile attempts, a test-document cleanup leak and its correction remain in the technical log. The API has132 typed commands. The Actions work described above follows that checkpoint; complete tool contexts, Adobe clipboard descriptors, large API transfers and exact/live/platform behavior still need work. Build220 remains the latest qualified package. The existing live window handoff still awaits manual unlock; this stage made no new desktop access attempt.

## Step222 — Duotone and Multichannel (in progress,2026-10-28)

The next major workflow is editable ink separations. Work starts with authoritative grayscale samples, ordered ink curves and independent ink plates, followed by native controls, history, files and shared APIs. Build221 remains the qualified development preview. No Duotone/Multichannel feature or Photoshop equivalence is claimed at this initial stage.

Eight focused core tests now pass, including exact sample comparisons with the licensed Rust ink implementation. These are internal foundations; document, controls, persistence and API integration remain unfinished.

A repeated window-overlap report revealed that the obsolete test app is still running. The current canvas fix passes34 focused window/viewport checks. The qualified221 application is now installed at the usual Photato location, with its executable unchanged and signature verified. Existing running apps and saved artwork were preserved. The Mac is locked, so switching the user's document into the corrected app and checking live zoom, scrolling and resizing still await unlock. This delivery check does not claim a new rendering fix or completed live acceptance.

The ink data now lives in real documents. Duotone retains its gray source and ink curves; Multichannel retains separate8/16-bit plates without an artificial RGB layer. Native48 files and scratch-backed Undo retain exact samples. Conversion reads an opaque CMYK layer directly, preserving its black plate, and geometry transforms every plate along with saved masks and selections.

All40 focused integration tests pass, including file/API save, import, geometry and Undo. One test needed an async assertion repair; another still expected the newly supported archive48 to be rejected and now checks49. Both failed attempts remain recorded. The full optimized run now passes all2,284 tests, with the tested source unchanged. The next work is the actual ink-control workspace and complete channel/API editing, then print and file interchange. This is an internal implementation checkpoint, not a completed Photoshop ink workflow or a newly packaged release.

The public PSD specification leaves the Duotone color-mode block undocumented, and the licensed Rust importer retains that block while showing grayscale. That fallback does not meet the goal of editable ink interchange. It remains an explicit open item; documented Multichannel storage and usable ink controls/API work can proceed independently.

**Native ink controls and automation:** Duotone now has a native preview dialog for ink count, names, colors, density curves and overprint colors, with settings files and local Undo. Multichannel conversion asks before flattening layered artwork. Both commands appear in their existing Photoshop menu positions. Three matching Photato API operations read and change the same settings through the shared transaction engine; Actions20 records the conversion without baking in an image snapshot.

All 88 focused tests pass, including preview/Cancel, saved settings, native reopening, history, stale requests and API revocation. Review also caught source-specific channel identities in recorded Multichannel playback; playback now adapts them to the destination's channels, and tests cover Grayscale, CMYK16 and Duotone input. Hosted snapshots show the preview and layout, but native controls are incomplete in cached rendering, so live visual acceptance remains open. The full optimized run now passes all 2,293 tests, with all tested source inputs unchanged. Complete Channels editing and ink file/print interchange are next; this is not a completed Photoshop ink workflow.


**Real ink Channels:** The panel now shows Duotone's gray source or the actual Multichannel plates. Select and view individual inks, paint or erase, fill, invert, filter with a preview, load a selection, and create/reorder/duplicate/delete or change spot options. Other plates keep their original samples. Six matching API operations expose the same edits, raw sample pages and view state, with Undo and native reopening.

The integrated tests caught two real adapter mismatches: desktop brush seeds exceeded the API's exact numeric range, and channel selection loading used the wrong default name. Both are repaired. A later failure came from a test mask at the wrong bit depth; document validation stayed intact. All93 focused tests and all 2,307 optimized tests now pass. Hosted panel images are offscreen evidence, not live acceptance. The full ink workflow still needs interchange/printing, more tool and clipboard contexts, semantic channel Actions and Adobe compatibility. The obsolete-window handoff remains pending unlock; current apps and user artwork remain preserved.

The completion question is recorded separately from regression results. Qualified build221 connects350 of725 menu actions (48.3%); the current ledger marks355 of645 tracked commands partially implemented (55.0%) and290 pending. These measure implementation breadth, not fully qualified Photoshop functionality. Every broad parity package still has open acceptance requirements; a single overall completion percentage would require a weighted workflow audit.


**Multichannel Photoshop files:** Native Save/Open and the two API interfaces now preserve8/16-bit ink and alpha samples in PSD and PSB. Channel names, spot colors and solidity travel with the planes. The parser accepts modern and legacy display records and retains unchanged imported RGB, HSB, CMYK, Lab and gray color records. Changed display colors use the file format's16-bit precision and solidity uses whole percentages. Printing and the complete color-book workflow remain open.

Independent fixtures exposed a five-channel limit in the shared compression code; API tests exposed an older color-mode admission rule. Both now admit supported Multichannel files while retaining memory and transfer limits. Test-only mistakes—a helper name and comparisons of sparse storage layouts instead of image samples—are recorded separately. All52 focused tests and all2,316 full optimized tests pass. An independent PSD reader verifies16 exported files and768 sample values exactly. This is file-format evidence, not a live Photoshop acceptance test or proof of full rendering equality. No new packaged build is claimed; qualified221 and uploaded220 remain separate.

To follow the requested major-feature priority, the next major workflow is native proofing and printing. The source currently has its factory menu entries without a matching proof/print implementation. Remaining ink presets, tools and format gaps stay on the backlog; this scheduling move does not mark color-mode parity complete.


## 2026-10-28 — Proofing without changing the artwork

Soft proofing now previews the chosen output profile through native ColorSync. The Custom sheet offers rendering intent, Preserve Numbers, black-point compensation and paper/black simulation, with ICC selection and native JSON presets. Proof Colors and Gamut Warning use the factory shortcuts. CMYK plate previews and sRGB/monitor presets use the same view state as the optional API; ordinary exports and Undo remain unchanged.

The tests exposed an existing Lab problem that a same-path round trip had hidden: CoreGraphics reports different chroma coordinates for its built-in Lab space and a space loaded from the identical ICC profile. An independent Swift probe demonstrated the exact range mapping. Correcting that boundary makes literal neutral Lab remain neutral while preserving stored file samples. Failed builds, diagnostics and the repaired reference tests remain in DEVLOG step223.

All75 focused checks and41 repaired optimized-focused checks pass. The offscreen proof sheet fits its allotted space, but the bitmap capture is incomplete and is not visual acceptance evidence. All2,330 full optimized tests now pass on2,234 unchanged inputs. Installed build221 and private uploaded build220 remain unchanged. Native printing/page setup comes next; HDR/EDR, working-space preferences, Adobe presets, exact Photoshop output and live/platform checks stay open.


## 2026-10-28 — Step224: native printing and hard proofs

Photato now has native Print and Print One Copy commands with physical page layout, printer settings, profile-managed output, hard proofs and individual ink plates. The PDF route and printer use the same native renderer; the API adds five commands and a separate opt-in for physical printing. Output settings stay outside image pixels and undo history.

Tests caught an AppKit dirty-state effect from assigning NSDocument.printInfo, an invalid test controller startup order and a printerless-preview regression; each failed attempt and repair is retained. All 65 focused tests now pass. The real AppKit print path also wrote four distinct separation pages to an owned PDF without contacting a printer. An independent PDF reader confirms16-bit CMYK/gray image data and embedded profiles. All2,351 full optimized tests also pass on the same unchanged source. Universal macOS14+ build224 is verified and uploaded as a private draft; all four downloaded assets match their SHA256 hashes.

The830×640 offscreen layout check passes, but the captured controls are incomplete; it is not a live UI pass. Physical printers, exact Photoshop color/marks, print Actions, some driver controls and the broader HDR/color workflow remain open. Installed221 is unchanged. [Private development build224](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-eb1707be7963cebfe0c5). [Detailed record](DEVLOG.md#dev-step-224), [printing evidence](PRINTING_REFERENCES.json).


## 2026-10-28 — Step225: native color profile workflows

Assign Profile now changes color interpretation without changing numerical samples. Convert to Profile transforms colors through Apple ColorSync, with rendering intent, black point compensation, optional flattening and a live draft preview. Both operations share Undo and the optional API. Supported RGB text, solid fill and shape layers remain editable; complex conversions ask for explicit flattening. Negative and HDR float colors, alpha and transparent pixel colors are tested.

Untagged documents retain their interpretation internally and omit profile tags when exported. Native49 preserves that choice; independent readers verify PSD, TIFF, PNG and JPEG outputs. Adobe-compatible output settings now accept the published iccProfile field, using the same native engine and isolated per-output resources. All60 integration tests,33 repair-focused optimized tests and2,364 full optimized tests pass. The record retains a test-representation mistake, a compiler repair and an independent inspector byte-order mistake alongside the passing results.

Color Settings, mismatch policies, full rich-layer handling, semantic Actions, exact Photoshop output and live/platform qualification remain open. The installed221 app and qualified/uploaded224 package are unchanged. [Detailed record](DEVLOG.md#dev-step-225), [profile evidence](COLOR_PROFILE_REFERENCES.json).

## 2026-10-28 — Step226: persistent working color settings

Color Settings now stores working RGB, CMYK and Gray profiles between launches. The native dialog uses the Photoshop menu position and Shift-Command-K shortcut, with installed-profile choices, ICC file loading, conversion intent and black point compensation. Cancel leaves settings unchanged; stale dialogs and API requests cannot overwrite newer settings. Files use bounded atomic writes, preserving prior bytes on a failed save.

New Document, color-mode changes and profile operations capture those settings when they begin. Changing only precision retains the document’s own profile. Native and shared-document API operations use the same defaults, with explicit overrides. Stateless Adobe and Photato resource jobs retain their own contract defaults. All28 initial focused and2,374 full optimized tests pass, including10 new settings tests and the mode/depth-picker regression. Source03 retains2,253 unchanged inputs; full workflow and live/platform qualification remain open.

Missing/mismatched-profile import and paste policies, working proof integration, Spot settings, CSF presets and advanced conversion options remain open. No claim is made of Adobe ACE output equivalence or live acceptance. Installed221 and uploaded224 remain unchanged. [Detailed record](DEVLOG.md#dev-step-226), [settings evidence](COLOR_SETTINGS_REFERENCES.json).


## 2026-10-28 — Step227: keeping color decisions consistent

Photato now follows separate RGB, CMYK and Gray policies when opening external documents and pasting between profiles. Optional missing-profile and mismatch review lets the user preserve a profile, convert colors, discard a tag or assign an interpretation before an image opens. Paste can preserve appearance or compatible component numbers. Cancel leaves the artwork untouched, and a changed clipboard or document prevents a stale decision from committing. Native and API paths share the same preparation and history transaction.

The API returns review choices without opening a desktop dialog. Older five-field Color Settings clients retain the newly added policy fields; version 2 persistence reads earlier settings with defaults. Working CMYK proofing now captures the selected working profile instead of always resolving to Generic CMYK. Stored proof presets keep that captured profile.

All 76 focused checks pass. A stronger test then caught a real presentation defect: the Color Settings window was 430 points high while its controls needed 641. Sizing the real window to its content fixes it, and 13 policy checks pass after the repair. Both failure and repair remain recorded. The offscreen captures omit native controls, so they do not establish visual acceptance. The first full run found one older PSB test comparing raw decoding with policy-aware opening. Native and API opens now produce identical bytes with no added profile tag. The first replacement assertion wrongly assumed all fixture layers were raster; it now compares all layer content, including groups, and checks that the source file remains untouched. All 2,387 full optimized tests also pass on 2,257 unchanged source inputs.

Custom ICC assignment during binary API import still requires a separate profile command or configured working profile. Drag/drop, additional rich/mode contexts, presets and exact/live/platform color qualification remain open. Installed build221 and private uploaded build224 are unchanged. The next major workflow is Timeline and animation, including editable frames, playback, export and video capabilities; smaller color fidelity refinements remain tracked. [Detailed record](DEVLOG.md#dev-step-227), [policy evidence](COLOR_POLICY_REFERENCES.json).


## 2026-10-28 — Step228: a diary you can take with you

The developer diary now bundles its HTML, CSS, JavaScript, logos, source provenance and downloadable narrative and license notice into one file. Copy `nusite/diary.html` anywhere and open it directly in a browser. Its entries, search, sorting and internal navigation need no server. The existing Forensic Intelligence design is retained, and the product page includes a download link for the standalone file.

The first dependency check caught a footer link that still depended on the product page. That link now returns to the diary overview, and validation passes. All 25 offline Chromium checks pass, including search, sorting, deep links, exact downloads, mobile navigation and widths from 320 to 1,440 pixels. All 228 entries are readable without JavaScript. Desktop and mobile screenshots retain the existing site appearance. External company and GitHub links still lead to their websites; the repository remains private until release. Each saved file is a dated snapshot, refreshed by the existing diary generator after source records change. The separate live dashboard is unchanged. This website update adds no native editing features or API operations; Timeline remains the next major application workflow. [Detailed record](DEVLOG.md#dev-step-228).


## 2026-10-28 — Step229: giving layers a timeline

Photato now has a native Timeline strip below the canvas. Create an animation, duplicate or reorder frames, change their delays and looping, and preview playback. Each frame stores layer visibility, position, opacity and style while sharing the editable pixels and text. Changes through the normal layer controls update the selected frame. Position/opacity tweening can insert intermediate frames between two compositions.

Frame edits use the existing Undo path. Selection and playback do not create content history entries, and playback leaves the committed document untouched. Native50 files and scratch history preserve every frame. Two new optional API commands share these operations and expose Timeline state. Preview ticks leave the API revision stable so clients can stop playback reliably; edits during playback ask the client to stop it first. Unsupported saves report the animation that would be lost.

All47 focused integration checks pass. The record retains a compiler insertion mistake, an incorrect test expectation about the view restored by Redo, and a legacy test that rejected newly supported archive50. Repairs keep their failed attempts alongside passing evidence. The first full run exposed three more legacy archive-version assertions. A separate regression then caught a real visibility-draft preview failure: temporary layer properties were being validated against the saved frame cache. Rendering a temporary still composition fixes it without changing saved frames; another guard prevents prepared replacements from silently dropping animation. All2,402 full optimized tests now pass on2,262 unchanged inputs, including15 new animation tests. Native menu/layout checks pass; no new live Photoshop or visual acceptance is claimed.

This is the first stage of Timeline support. Animated GIF/image-sequence interchange comes next, followed by video layers, timing, audio and keyframes. Multi-frame controls, effect tween, onion skins, all-frame geometry, semantic Actions, editable Photoshop animation files and exact/live/platform parity remain open. Installed221 and private uploaded224 are unchanged. [Detailed record](DEVLOG.md#dev-step-229), [animation evidence](ANIMATION_REFERENCES.json).

## 2026-10-28 — Step230: keeping every GIF frame

Opening an animated GIF now preserves its complete sequence as editable Timeline frames. Partial frame rectangles, transparent pixels, restore-previous/restore-background disposal, delays and loop settings survive import. The Timeline can export a rendered animated GIF, with the same implementation available through the optional API. Export preserves the editable document and history, supports cancellation and commits a file only after successful encoding.

An original four-frame fixture exposed a real platform edge case: ImageIO silently dropped the maximum finite loop count when writing. The first48-test run had one failure. We repaired the public loop metadata while keeping Apple's native pixel encoder. All48 focused tests and2410 full optimized tests now pass. An independent Pillow decoder checks the owned input and four exports against960 expected RGBA samples, timing and loop counts. The fixture generator and both failed and passing results are retained.

GIF's palette, binary transparency and centisecond timing impose visible output constraints; Photoshop's full Save for Web controls and exact output remain open. Image-sequence interchange comes next, followed by video, keyframes and audio. No live Photoshop comparison or new universal package is claimed. Installed221 and private uploaded224 remain unchanged. [Detailed record](DEVLOG.md#dev-step-230), [animation evidence](ANIMATION_REFERENCES.json).

## 2026-10-28 — Step231: image sequences become video layers

PNG sequences now import into one editable video layer. Reviewing Adobe's public workflow changed the implementation plan: separate still layers would not provide the video behavior we need. The native Timeline now offers seeking, playback, clip start and trim, independent source and Timeline frame rates, and painting on the current source frame. Undo restores edits, Rasterize Layer creates a still from the selected frame, and native archive51 preserves every source frame and its timing. The optional API provides the same construction, timing, view and cancellation paths while retaining the original source documents.

The first two builds found Swift range-type and actor-isolation errors. The first runtime run passed62 of63 checks; its remaining assertion compared two different internal raster representations rather than their pixels. We changed that assertion to compare every visible pixel and dimensions, while keeping exact Undo restoration of the original document. All63 focused tests and2420 full optimized tests now pass. Three independently encoded PNG fixtures and Pillow inspection verify144 output samples, including numeric file order, non-square coordinates and partial transparency. Every failed attempt remains in the record.

This is the video foundation, with bounded PNG sequences in memory. Sequence export, movie-file decoding, audio, keyframes, transitions, full Render Video, editable PSD/Actions and exact Photoshop behavior remain required. No new live comparison or universal package is claimed. The installed221 app and private uploaded224 package remain unchanged. [Detailed record](DEVLOG.md#dev-step-231), [video evidence](VIDEO_TIMELINE_REFERENCES.json).

## 2026-10-28 — Step232: exporting complete image sequences

Both Timeline modes can now export numbered PNG frames with a chosen range, prefix, starting number and padding. A companion manifest retains source frame numbers, timing, dimensions, color conversion and loop information. The native interface creates a new folder only after every file succeeds. Existing folders stay unchanged, and cancellation removes staging. The optional API runs the same renderer and returns a bounded ZIP with matching cancellation and permission/revision checks. Export preserves the editable source and its history.

The first54-test run had one assertion failure: Foundation decoded the JSON decimal0.07 with a tiny floating-point difference. Independent inspection confirmed the serialized timing was correct. We repaired the numerical assertion while retaining exact image/archive checks, and added permission revocation during export. All55 focused tests and2,428 full optimized tests now pass. Python's independent ZIP reader and Pillow verify both archives, all seven PNG frames/336 pixel-channel samples, checksums, filenames, order and timing. The failed attempt remains in the record.

The universal Apple Silicon/Intel macOS14+ development package is verified and uploaded to the private GitHub repository. Build metadata and source hashes accompany it; source was not pushed and the installed221 app was not replaced. PNG retains the current integer-profile pipeline, while32-bit HDR exports explicitly convert to SDR sRGB16. Native movie codecs, audio/keyframes, further export controls, full Render Video and Photoshop/live/platform parity remain open. [Detailed record](DEVLOG.md#dev-step-232), [export evidence](IMAGE_SEQUENCE_EXPORT_REFERENCES.json), [private build](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-7cde29c1ad993258aa5e).


## 2026-10-28 — Step233: real movie sources and video layers

File > Open now reads supported MOV/MP4 movies through AVFoundation, and Layer > Video Layers > New Video Layer from File adds an editable clip to an existing document. The importer retains exact rational presentation times, including variable frame durations, and keeps the original container and audio bytes. Native archive52 saves those sources alongside edited frame pixels. Placement converts all frames to the target profile/depth, starts at its playhead and supports Undo. The optional API shares movie upload, placement and cancellation; the Timeline explicitly indicates retained audio whose playback is not yet implemented.

Independent fixtures caught real problems. The first legacy QuickTime Animation fixture could not be decoded by this host; preserved probes established working uncompressed ARGB and ProRes decoding. A corrected rotation fixture then exposed opposite coordinate conventions in AVFoundation and Core Image. We fixed the transform instead of relaxing the pixel check. We also repaired a missed archive52 header guard and updated the unknown-version test. A normal128×96 H.264/AAC fixture now verifies movie decoding and presentation order; a tiny H.264 host rejection is preserved separately.

All 62 focused tests and 2,435 full optimized tests pass. Independent FFmpeg/Pillow comparison matches all 6,144 RGBA8 channel values across eight normal and rotated lossless frames. This establishes those owned fixture results, not Photoshop byte equality. The implementation still has explicit source/frame/memory limits and SDR conversion. Long disk-backed footage, HDR, audio playback/editing, keyframes, transitions, Render Video, editable PSD/Actions and full platform/live qualification remain required. The installed221 app and privately uploaded universal232 package are unchanged. [Detailed record](DEVLOG.md#dev-step-233), [movie evidence](MOVIE_IMPORT_REFERENCES.json).


## 2026-10-28 — Step234: animate layer properties in the video Timeline

Still and video documents now support editable Position, Opacity, Transform and Style keyframes. Expand a layer in the Timeline, enable a property with its stopwatch, move the playhead and edit the property normally. Enabled tracks capture the change automatically. Key controls provide previous/next navigation, add/delete, editable times and Linear or Hold interpolation. Position and Transform are alternative geometry tracks. Native53 saves the keys; Undo and the optional API use the same commands. Geometry animation retains source raster/video pixels instead of repeatedly resizing them. Image-sequence export renders the evaluated animation.

The first focused run exposed two integration issues. Our test incorrectly assumed playback would leave the API revision unchanged; view-state revisions deliberately change even though playback adds no history. An existing sequence-export test also exposed a revoked transfer continuing to render until cancellation surfaced late. The API now owns and cancels its export worker when permission or sharing is revoked, while desktop exports remain independent. Both failures and the passing repair are preserved. Timeline duration now survives rate/loop edits, and unsupported adjustment-layer tracks stay disabled.

All 65 focused tests and 2,450 full optimized tests pass. Five independently decoded PNG frames match 1,920 analytic RGBA8 channel values exactly. These are owned animation fixtures, not a Photoshop byte-equivalence claim. Advanced keyframe contexts, full visual Timeline interactions, clip groups/splitting, transitions, audio, Render Video, editable PSD/Actions and universal/live qualification remain open. The installed221 app and private universal232 package are unchanged. [Detailed record](DEVLOG.md#dev-step-234), [keyframe evidence](VIDEO_KEYFRAME_REFERENCES.json).


## 2026-10-28 — Step235: planning the next video workflows

We checked the public Photoshop Timeline documentation and planned video-group arrangement, exact playhead splitting and transitions. The design must preserve original video pixels, keyframe timing, Undo, saving and shared API behavior. Before implementation began, the maintainer redirected this work to the company homepage and a FOSS release policy. No clip-group, split or transition feature is claimed complete here. These remain the next native work, followed by audio and Render Video.

## 2026-10-28 — Step236: a home for all six projects

We downloaded the real Forensic Intelligence homepage and preserved its original HTML and response headers. The new master index keeps the company's existing visual style and five named projects, then adds Photato with accurate in-development status, its developer diary and repository policy. The existing Photato page remains the source for its own product content. A separate upload bundle connects the two; nothing has been published to the real domain.

A browser screenshot from the maintainer revealed oversized, stretched carousel artwork. We constrained the artwork and balanced the layout. An initial attempt to embed every image made index.html unnecessarily large; the maintainer caught that, and we corrected it. The final homepage is about87KB, with CSS and JavaScript inline and normal image files alongside it. The explicitly requested single-file developer diary remains self-contained. All79 homepage browser checks pass, covering file size, bounded artwork, six slides, keyboard controls, mobile navigation, no-JavaScript content, offline operation and responsive layouts. The existing live product/support destinations also respond successfully. The source download and reviewed desktop/mobile screenshots are preserved. A timing error in the first diary-link test was repaired, and the obsolete full-width Freefall card layout was adjusted for the six-project grid.

## 2026-10-28 — Step237: a pure FOSS release

The maintainer chose a free and open-source release without tipping or purchases. We removed the purchase window, Help/About entry points, StoreKit transaction adapter and listeners, product IDs, local purchase test host and obsolete tests. About now emphasizes licensing, source provenance and ways to contribute. The optional API loses the same purchase-related menu listing; its164 typed editing commands and Adobe-compatible routes are unchanged. The release plan and website now reflect the decision. The repository will still become public on the day the software is released.

All2,440 optimized tests pass. That is ten fewer tests than the prior checkpoint because the ten purchase-policy tests were withdrawn with their feature. The new binary has no direct StoreKit linkage or purchase implementation symbols. The production-purchases work package is explicitly withdrawn, leaving104 active packages; this is not a claim of additional Photoshop parity. The installed app and last private universal build remain unchanged. Historical diary entries and source/test evidence are retained, with the superseding policy stated at the top of this diary. Native video-group, split and transition work is still next.

## 2026-10-28 — Step238: arranging and splitting video

The Timeline can now split selected clips at the playhead without flattening their editable sources. Cuts retain precise source boundaries, including cuts between variable-rate movie timestamps. Painting one split portion leaves the other portion’s retained frames unchanged. Still images, type, shapes and ordinary groups can have clip durations, and Video Groups arrange those clips sequentially. Moving clips also moves their animation keys. The Timeline controls and optional API share the same commands, history and validation. Native54 saves the additional timing metadata; older download requests reject rather than lose it.

The first build caught an API null-handling type error. Review also found that an empty track could inherit the selected track as its parent, and moving an ordinary group could leave its nested clip times behind. Those cases were corrected and tested. All66 focused optimized tests pass, including12 new arrangement checks, and an independent PNG reader verifies576 analytic channel values across12 exported frames. A final review then caught grouped start-time controls accepting changes that sequential reflow immediately reversed; those controls now direct the user to group start/order, with an additional regression. The final source revision passes all 2,453 optimized tests and 13 final arrangement checks. All 2,298 frozen inputs remain unchanged; an independent reader again verifies all 576 channel values.

This extends a major workflow but does not close Photoshop parity. Transitions, audio, Render Video, graphical clip dragging, automatic movie grouping, richer clipping/nested timing contexts and PSD/Actions animation interchange remain unfinished. Exact Photoshop output, live interaction and broader platform qualification are separate open gates. The installed app and private universal232 build remain unchanged; user artwork is preserved.

## 2026-10-28 — Step239: graphical Timeline and editable transitions

The video Timeline now has native graphical tracks. Clips can be selected, moved, reordered, transferred between Video Groups and trimmed using their edges. A draggable playhead selects frames; transition handles change duration. The same commands drive the optional API, saving and Undo/Redo. Existing numeric clip and keyframe controls remain available. Fade, Cross Fade and fades through black, white or a chosen color are retained as editable objects in native55 documents.

Crossfades compose the outgoing and incoming branches over the same backdrop and mix their premultiplied colors. Masks, current blend modes and group styles remain part of that composition. Retained movie handles supply footage beyond trims; missing handles hold the source's edge frame. Split/reorder/trim/delete reconcile transition boundaries in the same transaction. Duplicating an entire track gives its transitions independent identities. None of this asserts byte-identical Photoshop behavior without comparison evidence.

The first build compiled but exposed incorrect test assumptions about stored alpha, an invalid active-layer fixture and rendering revisions after rejected operations. An offscreen test also crashed during window cleanup. These failures were preserved and repaired; the second candidate passes all82 focused tests. An independent PNG reader verifies384 analytic channel values across eight exported crossfade frames. The native offscreen capture shows contained tracks and controls; it is not live desktop acceptance. A final review adds selection cleanup when a transition or Timeline is removed and correct targeting in the transition editor. The final candidate passes all 2,474 optimized tests. All 2,306 frozen inputs remain unchanged, and the independent reader again verifies all384 channel values in newly exported frames.

Audio, Render Video, automatic movie grouping, direct transition-palette dragging, graphical keyframe rows and richer PSD/Actions animation remain unfinished. Exact Photoshop rendering, defaults, preferences and keyboard behavior, accessibility and supported-platform validation remain open. The installed app, user artwork and last private universal232 package are unchanged.

## 2026-10-28 — Step240: native Timeline audio

Soundtrack tracks and retained movie audio now have editable volume, mute and fades. Native import retains original files; graphical clips can move, trim and split, with Undo and native56 saving. The optional API exposes matching edits, binary imports and mixed-WAVE downloads. Preview frames follow the audio clock; automated playback uses a silent test player.

The first build chose a different build system and failed to link the test bundle. The native retry exposed an AVFoundation filename-suffix requirement: valid WAV data staged with a generic suffix had no detected tracks. A separate experiment confirmed the cause; staging now follows the actual container signature. Later tests found resampling truncated the end of a source and immediate playback cancellation left a worker registered; both were repaired before qualification. The failed build and both failing test runs remain recorded. Native soundtrack tracks, retained movie audio, volume/mute/fades, graphical move/trim/split, synchronized playback and native56/API/history integration pass 2,493 full optimized tests on 2,318 unchanged inputs. Independent WAVE inspection matches192,000 analytic Float32 channel values. Physical audio output, full Render Video, long streaming, richer Timeline/interchange and exact/live/platform parity remain open. Installed221 and private universal232 are unchanged. [Detailed record](DEVLOG.md#dev-step-240).

## 2026-10-28 — Step241: native Render Video

The Timeline can now render MP4 and QuickTime movies through native Swift and Apple media frameworks. The existing Render Video menu opens controls for codec, dimensions, frame rate, source range, audio and transparency. The API uses the same snapshot renderer, with cancellation and access-revocation checks. Completed output is staged before replacing the chosen file; the project and Undo history stay unchanged.

An initial test compilation error was repaired. The next run exposed a real brightness change in exported intermediate transition colours. Separate native probes traced it to the difference between a named graphics colour space and the space derived from video transfer metadata. The implementation now uses matching metadata-derived conversion, and the original colour assertions pass. Both failures and their repairs remain in the detailed record. Native Render Video now exports H.264/HEVC MP4 and ProRes422/4444/uncompressed QuickTime, with range/size/rate/audio/alpha controls, staged publication and shared API. 2,502 full optimized tests pass on 2,324 unchanged inputs. Independent inspection verifies12 movies, 55,296 exact uncompressed RGBA channels and48,000 exact Float32 audio values. DPX/HDR/work-area/aspect/presets and full Photoshop/live/platform fidelity remain open; SP01 is not closed. Installed221 and private universal232 stay unchanged. [Detailed record](DEVLOG.md#dev-step-241).

The full-suite screenshot also exposed a test-fixture appearance dependency: a white background hid dark-mode labels even though functionality tests passed. Both captures are retained. Explicitly matching the test window, controls and background repairs the capture; focused and full checks pass again. This is offscreen visual evidence, with live UI qualification still open.

## 2026-10-28 — Step242: Timeline work areas and onion-skin previews

The Timeline now has a draggable work-area bar and playhead-based range commands. Playback, audio and optional sequence/movie exports share that interval. Onion-skin settings show neighboring frames while editing, without baking them into image or movie exports. Settings survive project saving and Undo; the optional API uses the same operations and provides a separate onion-preview endpoint.

The first native display test found that the canvas had already stripped animation metadata before the new overlay could read it. Keeping the retained Timeline separately fixes both editing and playback previews. A missing output folder in the test harness was also repaired. More significantly, independent movie decoding exposed a row-stride interpretation disagreement at narrow widths that the earlier point-sample tests missed. Separate native writer probes reproduced the disagreement; the stored rowb metadata proves the original pixels are intact, while the installed FFmpeg6.1 decoder ignores that stride. A packed-row experiment breaks Apple decoding and is reverted. Full-frame comparisons now cover several non-aligned widths using both native reads and independent declared-row decoding. External raw-movie interoperability remains open, and failed evidence is retained. Timeline work areas and onion-skin previews now include graphical range handles, settings, ranged playback/audio/export, Undo, native57 and shared APIs. 2,516 full optimized tests pass on 2,331 unchanged inputs. Independent checks match2,192 preview/sequence/raw-movie RGBA channels and recheck12 existing movie fixtures. Raw-movie row metadata is independently verified; FFmpeg6.1 interoperability remains open. Exact defaults/blending, Timeline conversion/trim/interchange and live/platform fidelity remain open; SP01 is not closed. Installed221 and private universal232 stay unchanged. [Detailed record](DEVLOG.md#dev-step-242).

## 2026-10-28 — Step243: a universal Timeline preview

We packaged the completed Timeline work and pure FOSS policy as a new private development draft. Movie sources, keyframes, groups, transitions, soundtracks, Render Video, work areas and onion skins are now in the same universal preview. This checkpoint changes distribution and evidence, not editing algorithms or API contracts.

The native Timeline/FOSS batch is packaged as a universal macOS14+ private draft. The same2,331 inputs passed2,516 full and92 focused optimized tests at242. Both extracted distribution architectures pass the headless RGB16 archive/image-packing smoke operation; x86_64 uses Rosetta. Package signatures, weak AI linkage, licenses/model resources and removal of purchase code verify. All four uploaded assets match downloaded SHA-256 hashes. Installed221 and owned artwork remain unchanged. No full Photoshop, live UI or physical Intel/macOS14/macOS26 acceptance is claimed. An additional192 focused tests pass under Rosetta with independent pixel/movie/audio verification. Tests ran against the preserved test-enabled build of the same source; the separate distribution binaries also passed their own headless smoke operations. Rosetta execution does not replace testing on physical Intel hardware or earlier supported macOS releases. The package still has the documented raw-QuickTime reader interoperability limitation. The prior package and test evidence remain preserved; no user document or installed app was replaced.

The draft remains private, with licenses, checksums and source-input provenance. Remote main is not the matching source snapshot: this was a build-only upload, not a source publication. Next are Timeline mode conversion and cropping duration/content to the work area; full Photoshop equivalence stays open. [Detailed record](DEVLOG.md#dev-step-243).

## 2026-10-29 — Step244: trim the Timeline to its work area

The Timeline can now turn a selected work area into the document’s full duration. Surviving artwork stays editable, and Undo restores the original. The same operation is available through the optional API. Cropping through a dissolve or an audio fade keeps its original phase rather than starting the fade again. Native files retain the source and interpolation handles needed to do that. This is an independent implementation; Photoshop’s exact storage and editing semantics are still awaiting comparison.

The first tests caught a real clipping-dependency bug that retained unrelated earlier clips. We corrected it and kept the failed result. A later new test fixture failed to compile because it assigned a computed property; that failed attempt is preserved too. A movie-test expectation also incorrectly compared sRGB bytes with Rec.709 output. We replaced that expectation with exact pre-trim versus post-trim output comparisons, retaining independent analytic PNG/audio checks. Edge-dragging now measures from the cropped visible boundary, and newly inserted audio can extend a cropped Timeline.

Trim Document Duration To Work Area now crops/rebases the native Timeline while retaining editable surviving content and fade/interpolation handles. The desktop/API share Undo, native archive 58 persistence and signed pre-roll timing. 208 focused and 2,532 full optimized tests pass on 2,335 unchanged inputs; independent checks match 480 analytic PNG/sequence RGBA channels, 240 movie channels against the pre-trim export, and 48,000 analytic Float32 audio samples. Frame/video conversion, richer interchange, exact Photoshop retention/gesture semantics and live/platform fidelity remain open. Installed build 221 and private universal build 243 are unchanged. PNG/audio checks use owned analytic references; movie channels are compared independently against the original interval export rather than Photoshop-generated files, so their exact matches are not a claim of Adobe byte equivalence. Frame/video conversion is next; the full feature, keyboard, preference and platform requirements remain active. [Detailed record](DEVLOG.md#dev-step-244).

## 2026-10-29 — Step245: turn frame animation into an editable video Timeline

Frame animations can now become video Timelines without flattening their artwork. The conversion retains shared layer content and masks, and creates Hold keyframes for changing placement, opacity, style and visibility. Finite loop counts survive, including playback starting midway through a sequence. The native dialog accepts a frame rate, and the optional API performs the same undoable conversion. Saved native files and exported PNG sequence metadata retain the new state.

The implementation uses the existing frame playback timing, including its20ms minimum, and samples it at the chosen fixed video rate. The output duration rounds up to a complete frame; a low rate can skip very short source compositions. Native controls initially suggest30fps. These timing/default choices remain unqualified against Photoshop. Review caught and corrected whole-pass playback from a selected frame, converted-key interpolation inheritance and missing loop metadata in sequence exports. No proprietary Adobe implementation was used; public documentation describes the mode conversion behavior.

Frame animations now convert to an editable video Timeline with Hold Transform/Opacity/Style/Visibility keys, retained shared artwork/masks, finite loop counts, native59 and the shared API. 219 focused and 2543 full optimized tests pass on 2340 unchanged inputs. Independent PNG/sequence inspection matches 768 analytic RGBA values and eight frame timings. Reverse conversion, full animation interchange, exact Photoshop behavior and live/platform fidelity remain open. Installed221 and private universal243 are unchanged. Renderer comparisons cover RGB8/16/32, masks, groups, affine placement and styles. The independent pixel checks use owned analytic artwork; they do not establish Adobe byte equivalence. The Timeline screenshot is an offscreen fixture, not a live Photoshop interaction. Reverse conversion must handle retained video, audio and transitions before the full workflow can close. [Detailed record](DEVLOG.md#dev-step-245).

## 2026-10-29 — Step246: convert video to editable frames and keep the original

Video Timelines can now become frame animations while preserving each sampled appearance, including varying layer content, masks and transition progress. The resulting frames can be edited, rearranged and converted back to video with Hold keys. The original video layers and audio remain recoverable through a clearly named native menu action. Restoring the original replaces conversion edits, with Undo available. Frame playback is silent; converting an unchanged sequence back restores active audio. If frame order or timing changes, original audio remains retained rather than being silently resynchronized.

Both directions share cancellable native preparation and the optional API. Native60 files retain sampled content and source recovery, while ordinary API state exposes metadata without embedding media payloads. Positive video-derived delays preserve60fps timing in playback and movie export. Testing includes masks, editable gradient/pattern fills, vector masks, RGB8/16/32 crossfades, trimmed movie audio, per-frame painting, Undo, cancellation, stale requests and archive negotiation. A malformed-mask test initially assumed a valid1×1 mask was invalid; its repaired fixture checks the actual invariant. The uniform-fill budget fixture allocated no tiles despite its dimensions. Storage inspection corrected that assumption; the repaired nonuniform fixture checks actual allocated bytes before testing the limit. Repeated conversions retain the current sampled audio clock separately from the earliest recovery source. Full-suite qualification exposed worker-stack exhaustion in nested command dispatch during gradient preview. The five directly nested primitive operations now use the smaller composite dispatcher, preserving their existing behavior; the crash report and regression remain recorded. Compiler review also corrected retained-source memory accounting, and export review removed an unintended20ms clamp for high-rate samples. All failed attempts and repairs remain in the detailed record.

Video Timelines now convert to editable sampled frames and back, retaining content/masks/transitions and a recoverable original with source audio. Native menus, cancellable preparation, shared API, Undo and native60 persistence work together. 249 focused and 2560 full optimized tests pass on 2348 unchanged inputs. Independent output checks match 13056 analytic RGBA channels and 48000 Float32 audio samples. Full animation interchange, exact Photoshop behavior and live/platform fidelity remain open. Installed221 and private universal243 remain unchanged. The pixel/audio oracles use owned analytic inputs, and screenshots are offscreen native fixtures. These checks do not prove Photoshop byte equality or live platform acceptance. [Detailed record](DEVLOG.md#dev-step-246).

## 2026-10-29 — Step247: generate variations from one editable template

Photato can bind visibility, text and pixel replacements to layers, link the same input across layers, and save named data sets with embedded replacement images. The native Variables sheet supports placement options, row editing, local CSV/TSV import and an isolated preview. Cancel keeps the original document; Apply is one undoable transaction. Batch export starts every variation from the original template so Do Not Replace never inherits the preceding row’s image. Native files retain the template, while explicit rendered outputs omit unsupported variable metadata.

The optional API includes twelve matching commands, bounded typed schemas and metadata-only state. Draft PNG previews leave history/revision untouched; export supports cancellation and rejects delivery after transfer/share revocation or source changes. Profile assignment and conversion update embedded replacement assets in the same history transaction while preserving IDs and data-set references. Testing covers all four scaling methods, nine alignments, clipping, linked values, malformed UUIDs/data, cancellation, late failure, history and native persistence.

The first API compile exposed three Swift concurrency violations in static schema dictionaries; computed schemas repaired them. The first integrated run found a stale archive-version rejection test; the corrected test rejects future version62. The initial offscreen screenshot was too weak for visual assessment, so the settled capture uses a never-shown native window. Adobe’s public format table identifies variables resources7000/7001 but supplies no current XML schema, and none of240 existing PSD fixtures contains them. Editable PSD-template interchange stays unverified rather than being fabricated.

Native Variables/Data Sets now support linked visibility/text/pixel bindings, four placement methods, CSV/TSV and image import, draft preview, Apply/Undo, native61 persistence and staged batch output. Twelve shared API operations include nonmutating PNG preview and cancellable ZIP export. RGB profile assignment/conversion preserves embedded replacement assets. 80 focused and 2588 full optimized tests pass on 2363 unchanged inputs; independent outputs match192 analytic RGBA channels. PSD variable interchange, Actions, broader mode/lifecycle and exact/live/platform parity remain open. Installed221/private universal243 are unchanged. These owned analytic checks and offscreen captures do not establish Photoshop byte equality or live acceptance. Contact Sheet II is the next missing major automation workflow. [Detailed record](DEVLOG.md#dev-step-247).

## 2026-10-29 — Step248: build printable contact sheets

Photato now lays out selected files, folders or open documents onto named contact-sheet pages. The native window offers physical page units, resolution, color mode/depth/profile, row/column order, spacing, best-fit rotation, filename captions and optional flattening. Preview each page before creating the documents; cancellation and failed imports leave the original images unchanged. Editable outputs keep thumbnails and captions as individual layers.

Two optional API commands use the same engine to prepare and share every page together, or cancel creation. Stale source revisions, revoked access and insufficient sharing capacity reject the whole result. Existing API resource limits remain explicit. No proprietary Adobe implementation was inspected; the licensed Rust source and public workflow documentation supplied the starting point.

Compilation caught a test encoder dependency and two Swift access/concurrency issues. Subsequent tests found incorrect fixture sharing and a mistaken expected busy-response code. Each failure and repair is retained. An offscreen capture needed an explicit background for readable review; it is not a live app test.

Contact Sheet II now creates editable or flattened multi-page documents from files, folders or open images, with native layout/profile/caption controls, preview and shared API cancellation. 38 focused and 2599 full optimized tests pass on 2369 unchanged inputs; independent PNG checks match1024 analytic RGBA channels. Exact Photoshop defaults/resampling/typography, Bridge/Actions, broader limits and live/platform parity remain open. Installed221/private universal243 are unchanged. [Detailed record](DEVLOG.md#dev-step-248).

## 2026-10-29 — Step249: separate scanned photos

The existing Crop and Straighten Photos menu command now finds separate prints on a uniform scan background, straightens them and opens each as a new document. It reads the selected layer, honors a selection and uses Option to keep disconnected pieces together. Detection and extraction run in the background with the existing Cancel button and Escape handling. Every result is prepared before any document opens; cancellation, changed sources and revoked access leave no partial output. Source pixels, selections and history remain unchanged.

Three optional API commands use the same engine for detection previews, extraction and cancellation. Output retains document depth, profiles and resolution. Ordinary native-mode scans preserve their numerical component planes; complex non-RGB composites still use the existing RGB conversion path, a disclosed limitation. The detector was translated from licensed PhotoCraft source and compared with the unchanged Rust implementation on original mathematical fixtures. No proprietary Photoshop implementation was examined.

Compilation caught a read-only resolution property, Swift operator whitespace and a test Task returning main-actor document objects. Each failure and repair is retained. Review corrected fractional rectangle mapping before qualification. The automated tests exercise source isolation, selected areas, rotated gradients, color components, file persistence, API equivalence and cancellation. No live Photoshop equality is claimed.

Crop and Straighten Photos now detects and extracts selected-layer scans into separate native documents, with selection limits, Option single-photo mode, cancellation and three shared API operations. 19 focused and 2612 full optimized tests pass on 2377 unchanged inputs; independent PNG checks match36192 analytic RGBA channels. Native component/profile/depth retention and atomic publication are tested. Exact Photoshop detection/resampling, complex-mode composition, Actions and live/platform parity remain open. Installed221/private universal243 are unchanged. [Detailed record](DEVLOG.md#dev-step-249).

## 2026-10-29 — Step250: batch image conversion

Image Processor now opens from File > Scripts and processes open images, selected files or folders with optional subfolders. One run can produce JPEG, PSD and TIFF copies, each with its own resize-to-fit dimensions. Controls include JPEG quality and sRGB conversion, ICC embedding, TIFF LZW, copyright, a loaded Action and first-image profile reuse. Settings can be saved and loaded as JSON. The originals remain untouched; prepared files publish into format folders using unique names. Cancel, source changes and publication errors leave no partial output from the operation.

The optional API exports the same processed bytes as a ZIP and exposes operation state and cancellation. Transfers require explicit permission and current shared-source revisions. Adobe's pinned public API has no dedicated Image Processor endpoint, so no fictional route was added. Native Save/Load settings and API settings share the same model.

The first compile found a Darwin file-descriptor type mismatch. The first executing focused run found a metadata bug: ImageIO accepted a scalar assignment to an existing localized XMP copyright array but exported an empty array. Standalone probes established the behavior, and updating the default-language item repaired PSD copyright while retaining other translations. A folder regression also exposed Foundation enumeration skipping a real subfolder after a symlink, plus removal of multi-dot filename stems. Both were repaired and checked with actual folders and files. The same symlink-enumeration defect was corrected in Contact Sheet II with a regression test. Every failed attempt and repair remains recorded. Independent readers verify the test archive, dimensions, TIFF compression and analytic lossless pixels. Native tests also cover folders, cancellation, changed sources, existing files and API equivalence. The controls were reviewed through an offscreen AppKit capture; this is not live Photoshop qualification.

Image Processor now converts open images or file/folder batches to JPEG, PSD and TIFF, with per-format resizing, profiles, Actions, copyright, settings files and shared API ZIP export/cancel. 26 focused and 2623 full optimized tests pass on 2385 unchanged inputs. Independent lossless outputs match 32,000 analytic RGBA channels; the JPEG fixture has a maximum one-level channel error. Source preservation, unique output names and cancellation are tested. Exact Photoshop output/defaults, first-image Camera Raw, optional PSD composites, broader limits and live/platform parity remain open. Installed221/private universal243 are unchanged. [Detailed record](DEVLOG.md#dev-step-250).

## 2026-10-29 — Step251: turn movie frames into editable layers

File > Import > Video Frames to Layers now opens a native movie preview and range controls. Import the whole movie or a selected interval, keep every frame or sample at a chosen interval, and optionally create frame animation. Each result is a separate editable raster layer in one new unsaved document. Existing documents and original source files remain unchanged. The decoder filters before allocating image surfaces, so a small selection from a longer movie can fit where importing every frame would exceed the budget. Variable presentation intervals determine animation delays.

API clients use the existing binary movie-upload endpoint with a strictly described JSON options header, without needing an existing shared document. Capability discovery reports the active import and provides an explicit cancel route. Both interfaces share the native decoder and reject stale lifecycle state, cancellation or revoked permission before publishing a document. No Adobe endpoint was invented. Precise imported animation timing uses the existing native60 representation; the project archive version remains61.

The first integration compile found an Observation macro restriction on combined variable declarations. It was repaired and preserved with the failed log. Review also added guards for invalid preview seek values. Native tests verify preview-item readiness using an owned ordinary H.264 fixture, controls/menu wiring, source preservation, new-document editability, cancellation/close cleanup and API equality. An offscreen bitmap establishes the control layout; it does not establish live video playback. Independent FFmpeg and Pillow checks compare imported-frame PNGs to the original owned lossless/VFR movie. These tools are test utilities, not application dependencies.

Video Frames to Layers now imports complete or selected movie ranges into a new editable document, with every-N sampling, optional frame animation, native preview/cancellation and API upload options/state/cancel. 16 focused and 2632 full optimized tests pass on 2391 unchanged inputs. Independent FFmpeg/Pillow checks match 3,072 lossless RGBA channels. Exact Photoshop range/default/depth/codec behavior, HDR/larger media and live/platform parity remain open. Installed221/private universal243 are unchanged. [Detailed record](DEVLOG.md#dev-step-251).

## 2026-10-29 — Step252: open PDF pages as editable documents

File > Open now offers a native Import PDF window. Choose individual pages or a range, preview thumbnails, unlock password-protected PDFs, and set crop, dimensions, resolution, antialiasing, color mode and depth. Selected pages become separate editable unsaved documents after the entire selection renders successfully. Original files and existing documents remain unchanged; Save/Revert cannot silently replace the source PDF. The optional API provides the same inspection, page import and cancellation workflow with strict schemas and permission/capacity guards.

Original test PDFs contain known rectangles, five distinct page boxes, a rotated page and a blank page. The first renderer test found an extra vertical flip; removing it fixed the pixels without relaxing expectations. Integration tests then caught PDF-like image metadata and misleading filename detection. The full suite caught PDF registration preceding the native Photato format; restoring the native format first fixed both existing registration assertions. Failed attempts and their repaired candidates remain in the detailed record.

PDF pages now open through a native Import PDF chooser with thumbnails, multiselection, passwords, crop, size, resolution, color and depth controls. File > Open and the optional inspect/import/cancel API use the same renderer and atomically create editable unsaved documents. 29 focused and2648 full optimized tests pass on2400 unchanged inputs. Independent checks match201048 flattened RGB channels and62208 analytic RGBA channels. Embedded-image extraction, retained-vector Smart Objects, editable Photoshop PDF data and exact/live/platform parity remain open. Installed221/private universal243 are unchanged.

The independent Poppler and analytic comparisons cover our own fixtures, including transparency, crops and rotation; they do not prove Adobe rendering equivalence. Bounding crop currently follows rendered alpha within Trim Box. The native window was checked offscreen; live interaction and supported-platform acceptance are still pending. Embedded-image extraction is next, followed by retained-vector PDF Smart Objects and Photoshop PDF editing data. [Detailed record](DEVLOG.md#dev-step-252).

## 2026-10-29 — Step253: extract the images inside a PDF

The Import PDF window now offers Pages and Images. Images mode discovers artwork within pages and nested forms, including inline images and reused image objects. Selected images open in separate editable documents at their original pixel dimensions, with resolution, color and depth controls. The source PDF and existing documents remain unchanged. API clients receive matching discovery, thumbnails, selection/import and cancellation routes through the same native engine.

The extractor copies each selected image’s PDF object graph, including supported palettes, Decode arrays, profiles and mask streams, into a small in-memory image page. Native CoreGraphics then decodes it without cropping the original page or baking in its placement scale. Original fixtures test nested/reused RGB, inverted gray, Indexed palettes, soft masks, CMYK, RGB16, JPEG and inline color resources. Independent rendering caught and corrected an invalid fixture color-space declaration. The first module run also found an empty subtype on synthetic inline streams; classifying them from the EI callback fixes discovery without relaxing the expected samples. Integration checks then fixed the initial Shift-click anchor. Screenshot review exposed incorrect enlarged-image thumbnails; standalone probes showed CoreGraphics repeating source columns in Float32 PDF contexts. A16-bit intermediate repairs that geometry, with Float32 PDF/HDR precision retained as an explicit unresolved limitation.

Embedded PDF images now open through the native Images selector and matching inspection/import/cancel API. Page/Form discovery, reused and inline images, intrinsic dimensions, color/depth controls and atomic editable-document publication share the native engine. 40 focused and2660 full optimized tests pass on2406 unchanged inputs. Independent checks match60 original RGBA channels,8 grayscale endpoint channels and25600 enlarged-thumbnail channels; existing page/crop/rotation comparisons also pass. Exact image ordering/defaults/color/masks, pattern/annotation images, vector Smart Objects, Photoshop PDF editing data and live/platform parity remain open. Installed221/private universal243 are unchanged.

These tests establish the listed native workflows and owned samples, not complete Photoshop image semantics or byte equality. Discovery through patterns/annotation appearances, exhaustive codecs/profiles, exact defaults and live/platform acceptance remain open. Retained-vector PDF Smart Objects and Photoshop PDF editing data are the next major PDF gaps. [Detailed record](DEVLOG.md#dev-step-253).


## 2026-10-29 — Step254: publish the stable source snapshot

At the maintainer’s request, the complete current Swift source and development records are now on the private GitHub repository. The source includes the new PDF page/image workflows and all intervening implementation work since the19 October snapshot. It passed2,660 full optimized native tests; this is tested development progress, not full Photoshop parity.

**Source published (step254):** The complete qualified step253 source is committed and pushed to private GitHub main as [`4b3fdb6`](https://github.com/ForensicIntelligence/Photato/commit/4b3fdb6cd08c07a32d8f47f627c4687c838f10d3). All2374 published qualification inputs match the tested candidate;1057 original Rust files are unchanged. Native source, tests/fixtures, Xcode project, scripts, assets and development records are included. Generated model/cache files, builds, runtime logs and private working documents are excluded. GitHub confirms the commit and private visibility. The source passed2660 full optimized tests; no new app installation or binary upload accompanies this source delivery. [Receipt](SOURCE_PUBLICATION_254.json).

The update preserves existing repository history and the licensed Rust snapshot. A separate checkout prevents unrelated Desktop files from entering this repository. The bounded scan of3,880 tracked files found no tested credential patterns, excluded working files, oversized blobs, symbolic links or retired branding. Optional model weights can be reconstructed using the included instructions. The standalone diary remains usable without a server; source publication does not deploy the website. Retained-vector PDF Smart Objects remain next in the major-feature plan. [Detailed record](DEVLOG.md#dev-step-254).

## 2026-10-29 — Step255: retain PDF artwork through placement and transforms

Place Embedded now accepts PDF files through a native Place PDF window. Choose one page or embedded image, inspect thumbnails, select the page crop and then position, scale or rotate the artwork. Return commits one edit; Escape discards the preview without creating history or marking the document changed. Failed transform preparation preserves the draft for correction. Replace Contents and placement into frames also retain the original whole PDF. Unsupported PDF Edit Contents and Stack Mode stay disabled.

The engine keeps the selected page/image and fixed crop metadata in native archive62, and re-renders retained artwork through enlargement, ordinary Smart Filters and rasterization. The Photato API exposes matching selection, cancellation, state and an optional initial transform in one transaction. Adobe-compatible resource inputs use their existing contract; no unsupported page/image selector is invented.

PDF Page/Image placement now has a native single-selection chooser, crop/thumbnail controls, initial transform preview, atomic Return/Cancel, Replace Contents and frame placement. Original whole-PDF sources survive native62 saving, enlargement, ordinary Smart Filters and shared API operations. 65 focused and2682 full optimized tests pass on2415 unchanged inputs; independent vector/image checks match560016 RGBA values. The Place PDF controls are inspected offscreen. PDF source editing, linked files, Warp, editable PSD/PDF interchange and exact/live/platform parity remain open. Installed221, private universal243 and published source253 are unchanged.

Qualification caught missing archive allowlists, stale version assertions and a PNG whose PDF-like text metadata confused source detection. Later checks caught image0 validation and an offscreen capture appearance mismatch. Those repairs, the two test-compilation mistakes, the incorrect PNG-job expectation and every failed run remain in the technical record. Independent checks use original analytic artwork; they establish the stated native samples, not Photoshop byte equivalence.

Continue major L05/D01 PDF Smart Object source editing and editable PSD/PDF interchange, then linked-source workflows. Use independent public format/owned-file evidence before encoding unsupported descriptors; preserve original bytes and guard source/editor lifecycle. Keep encrypted-source credentials, image pattern/annotation contexts, Warp, large-file budgets, Float32 precision and exact/live/platform acceptance open. [Detailed record](DEVLOG.md#dev-step-255).

## 2026-10-29 — Step256: publish the PDF Smart Object source

The next complete source snapshot is committed and verified on private GitHub main from the qualified step255 candidate, including retained PDF page/image Smart Objects, initial transform previews, atomic commit/cancel, replacement, frames and matching API support. All2,415 qualification inputs and the built executable still match the candidate that passed65 focused and2,682 full optimized tests. The Xcode project, tests/fixtures, scripts, assets and development records accompany the source. The original Rust snapshot and existing Git history are preserved.

The repository remains private until release day. Generated optional models, build products, runtime evidence and private working documents stay out of source control; reconstruction instructions remain included. This source delivery does not replace the installed app or upload a new binary. Passing native tests does not establish complete Photoshop parity. Source commit: [`f2a9711`](https://github.com/ForensicIntelligence/Photato/commit/f2a9711d0f1e95c4e5bcf713bfa3181d31520057). [Verified receipt](SOURCE_PUBLICATION_256.json). [Detailed record](DEVLOG.md#dev-step-256).

## 2026-10-29 — Step257: place original artwork with a transform preview

Place Embedded now previews raster images, native documents, PSD/PSB files and supported camera RAW artwork before committing. Position, scale or rotate the pending layer, then use Return to accept or Escape to discard it without changing document history. RAW sources first open the existing native Camera Raw controls. The temporary RAW workspace preserves the working document until placement is accepted, and closing either workspace cancels preparation. Original source bytes remain embedded.

The optional API can now upload an original source directly, place or replace artwork, fill a frame and request cancellation. It also exposes placement state and accepts an initial transform on the existing shared-document command. These paths share native preparation/history rather than duplicate the image algorithms. Adobe-compatible file-input and bounds contracts remain unchanged.

The first focused run caught a test setup error: cancellation restored the actual empty selection, while the assertion expected a selected layer. Starting the fixture with an explicit selection repaired the test. Review also prevented an unintended reduction of existing RAW source limits. The failed candidate and passing repair are preserved. An original colored checker fixture verifies the rotation by an independent coordinate calculation; its768 exact RGBA values are not an Adobe pixel oracle. Native Camera Raw controls were inspected offscreen, not through live Photoshop interaction.

Raster/native/PSD/PSB and camera RAW Place Embedded now use an initial transform preview with atomic commit/cancel. RAW sources first open native Camera Raw controls; original bytes and settings survive placement and native62. Binary source upload, replacement/frame/cancel/state and optional shared-source transforms use the same engine. 70 focused and2690 full optimized tests pass on2419 unchanged inputs; the independent rotated fixture matches768 RGBA values. RAW controls are inspected offscreen. Linked sources, full PSD/RAW/PDF interchange, exact Photoshop/default/live/platform fidelity remain open. Installed221, private universal243 and published source255 remain unchanged.

Continue major L05/D01 with genuine PDF source editing and editable PSD/PDF interchange from independent public/owned-file evidence, then linked-source persistence/relink/update/package workflows. Preserve source bytes and stale/cancel/history/API behavior; keep unsupported formats, large-file/color/RAW/XMP limits and exact/live/platform gates open. [Detailed record](DEVLOG.md#dev-step-257).

## 2026-10-29 — Step258: publish the embedded placement source

A complete source snapshot is committed and verified on private GitHub main from the qualified step257 candidate. It includes transform previews for raster, native, PSD/PSB and camera RAW placement; Camera Raw settings before placement; original-source retention; atomic cancellation/history; and the matching API workflows. All 2,419 qualification inputs and the compiled executable match the candidate that passed 70 focused and 2,690 full optimized tests. Sources, tests/fixtures, the Xcode project, scripts, assets, notices and development records are included alongside the unchanged Rust snapshot.

The repository remains private until release day. Generated optional models, build products, runtime evidence and private working documents are excluded; model reconstruction instructions are included. This source delivery does not replace the installed app or upload a new binary. Passing native tests does not establish full Photoshop parity. Source commit: [`5115d64`](https://github.com/ForensicIntelligence/Photato/commit/5115d649088720c395b3f3f5793e6f0fc361ead3). [Verified receipt](SOURCE_PUBLICATION_258.json). [Detailed record](DEVLOG.md#dev-step-258).

## 2026-10-29 — Step259: edit retained PDF sources and restore dashboard updates

PDF Edit Contents now creates a durable associated-editor working copy. Atomic and in-place saves update shared PDF instances in one Undo transaction while retaining page/image selection and transforms. Busy edits wait; stale sources, cancellation, invalid PDFs and closed parents cannot commit. The Photato source upload/download/cancel/session APIs share the native engine, with an Adobe resource-job equivalence check. All 53 focused and 2,699 full optimized tests pass on 2,422 unchanged inputs; independent checks match 3,072 analytic RGBA channels. Live editor handoff, restart recovery UI, full PDF/PSD interchange, linked sources and exact/platform fidelity remain open. Installed221, private universal243 and published source257 remain unchanged.

The associated macOS editor receives a durable original PDF copy. Saving updates the parent only after active work finishes; Undo or another source edit creates a conflict that needs explicit Apply Saved PDF. Closing or stopping leaves the working file intact. Tests use an injected editor opener and real filesystem events; they do not establish live third-party editor acceptance. Two compiler failures were preserved and repaired before the focused and full suites passed.

The maintainer also found Completed Tasks stuck at checkpoint227. Its parser understood only older completion/test record shapes. The repaired companion recognizes both generations, restores qualified later checkpoints and test totals, and keeps unfinished work separate. Thirteen companion regression tests and desktop/mobile checks pass, including a repaired narrow-screen overflow. No broad parity package was closed by either change.

Continue major L05/D01 with editable PSD/PDF interchange from independent public/owned-file evidence, then linked-source persistence, relink/update and packaging. Qualify native PDF editor handoff without disturbing user documents; keep full vector/annotation rendering and exact/platform gates open. [Detailed record](DEVLOG.md#dev-step-259).

## 2026-10-29 — Step260: retain editable PDF pages across PSD and PSB

Retained PDF page Smart Objects now import/export through PSD and PSB with original source bytes, page/crop selection, dimensions/resolution and shared affine instances. Transformed unfeathered raster masks are projected only in the export copy. Native persistence, Photato binary transfers and Adobe resource jobs share the codec. All40 focused and2708 full optimized tests pass on2430 unchanged inputs. Independent checks validate24 source payloads and186624 RGBA values; Photoshop2026 opens native PSD/PSB and rerenders Media/page2 and Trim/page1 at200%. PDF image-index/antialias/Warp variants, transformed feathered masks, linked files, general PDF rendering and full exact/live/platform parity remain open. Installed221, private universal243 and published source257 remain unchanged.

PDF placements can travel through supported PSD/PSB files while preserving their original PDF bytes. Photoshop itself may extract a page into a new one-page PDF; the reader preserves that embedded source exactly. Normal UI observations and owned test files establish the supported records. The first focused run exposed a transformed-mask export rejection; the repaired export projects mask coverage without changing the native source. The independent checker also had one filename mismatch, preserved and repaired separately.

The independent comparisons include a Photoshop re-save and forced200% vector rerenders, not just native round trips. They qualify these small owned fixtures, not every PDF or Photoshop operation. The developer dashboard picks up qualified completion records automatically.

Continue major L05 with linked-source persistence, source availability/status, relink/update/embed and packaging through shared native/API transactions. Preserve the qualified PDF page interchange and defer fine rendering/default/platform parity gates without marking the broad workflow closed. [Detailed record](DEVLOG.md#dev-step-260).

## 2026-10-29 — Step261: linked-source work, preserved and parked

Work began on linked Smart Objects, source updates and packaging. Those edits were incomplete and had not been compiled or tested when the maintainer reported laggy painting. All thirteen modified and four new files were preserved with hashes, then the qualified step260 sources were restored. This is unfinished work, not a completed feature. [Detailed record](DEVLOG.md#dev-step-261).

## 2026-10-29 — Step262: make painting respond promptly

The maintainer reported laggy, jagged brush feedback and set a 60fps target. Profiling found that each preview replayed the entire stroke and processed the whole canvas. The new ordinary-brush path retains stroke coverage, accepts every delivered input sample and updates only changed pixels. Zoomed-out display pixels and transparency decoration are cached. Preview scheduling follows a 60Hz deadline, while document edits and Undo still use the same transactional commands. The optional API reports the target, published preview count, displayed sample count and latest render duration.

A first tiled-image approach changed fractional-zoom filtering and was rejected. Dense-image profiling then identified repeated validation and minification costs. The full suite also caught Clone Stamp cancellation leaving event coalescing disabled; explicit cancellation and lifetime cleanup repaired it. All attempts, failures and measured scopes are preserved.

Ordinary brush previews now retain stroke work and update only damaged pixels, with cached canvas display and 60Hz scheduling. All 64 focused and 2721 full optimized tests pass on 2440 frozen inputs. Continuous-input CPU benchmarks preserve all 240 samples and target 60 previews/second; they do not measure physical display presentation. Special tools, large-brush spikes and full platform/Photoshop parity remain open. Linked-source261 is parked.

On the final candidate, the 24-megapixel sequential preview falls from 156.1ms to 3.5ms at the95th percentile. With a dense image and two adjustment layers, sampled preview work is6.2ms and offscreen drawing4.0ms at that percentile. The benchmark measures CPU preparation and offscreen drawing, not photons reaching the screen. Large-brush spikes and the remaining special-tool paths still need qualification. No full Photoshop parity or universal 60fps guarantee is claimed. [Detailed record](DEVLOG.md#dev-step-262).

Live native checks confirm painting, erasing, undo/redo and zoomed workspace containment on an owned document. A separate Apple Silicon preview app is available locally; the existing installed app is unchanged. Cancellation and input cleanup are covered by automated lifecycle tests. Physical display timing and tablet acceptance remain open.

A final packaging check caught Finder metadata invalidating the Desktop app signature. The verified preview is therefore stored separately in Applications and supplied as a clean ZIP; extracting that ZIP also passes signature verification.


## 2026-10-29 — Step263: keep retouching visible while input continues

The painting performance work exposed the same problem in retouching: every new sample could cancel a preview already being calculated. On a dense24-megapixel image, Clone Stamp showed no new previews during two seconds of continuous input. It only displayed the result afterward.

Retouching now keeps all incoming samples while one paced preview finishes. Fixed-grid Clone Stamp and Spot Healing markers also retain coverage calculated earlier in the stroke. Healing, Dodge/Burn/Sponge and Blur/Sharpen/Smudge retain their existing algorithms with the improved scheduling. Final edits still create one Undo step. The optional API reports preview activity and counters; this does not claim that the currently missing general retouch-stroke API commands exist.

The same24MP experiment now publishes119 previews during1.99 seconds of input, followed by the final snapshot, with all240 samples preserved. Clone Stamp's small-image sequential p95 falls from4.89ms to3.12ms. We checked144 stored pre-change native pixel prefixes, three pixel depths, transformed sampling, masks, selection and transparency locks. All124 focused and2731 full optimized tests pass. Native Smudge/Blur/Spot Healing, Undo/Redo and150% canvas containment were exercised on disposable artwork, then discarded.

A separately signed Apple Silicon preview and ZIP preserve the existing installed app. This is a local test build, not a notarized universal release. CPU snapshot publication is not physical display presentation: first-frame work, longer/heavier strokes, large retouch documents, tablet input and all-platform60fps still need qualification. Smudge's measured final drain exceeded one frame interval in one case, and its algorithm/spacing remains a Photoshop fidelity gap. Linked-source work from261 stays preserved for resumption after the current feedback priority.

## 2026-10-29 — Step264: faster Dodge, Burn and Sponge on large images

The next measurements found that toning tools repeated all prior stroke work for every preview. Dodge, Burn and Sponge now keep their unquantized working pixels between updates and calculate only the new brush dabs. The final image, captured tool settings, cancellation and one-step Undo behavior remain the same. The API describes the improved preview capability; missing general retouch-stroke commands remain explicitly open.

On a 24-megapixel test image, each tool publishes119 previews during about1.99 seconds of input, compared with56–58 before. Preview calculation at the95th percentile falls from42–45ms to9–12ms. Every one of240 input samples is preserved. We checked432 pre-change native pixel prefixes across three bit depths, selections, masks and transformed targets. All137 focused and2737 full optimized tests pass on2454 frozen inputs.

Live native checks confirm lightening, darkening, desaturation and Undo/Redo on disposable gradient artwork. A file-dialog typing error and clipboard timeout were preserved as automation failures, then recovered through the visible path field. The edited fixture was discarded. Existing apps, packages and user artwork are unchanged; the normal local preview remains step263 while the remaining retouch work is checked together.

The first preview still takes about94ms. Blur, Sharpen and Smudge remain slower on large images and are next. The visible repeated-dab texture also remains a smoothness/fidelity issue. CPU preview publication does not measure the frames actually presented by the display, and preserving Photato’s earlier pixels does not establish Photoshop pixel equivalence. Physical60fps, tablet input and full platform/workflow parity remain open. [Detailed record](DEVLOG.md#dev-step-264).

## 2026-10-29 — Step265: keep Blur, Sharpen and Smudge work between previews

Blur and Sharpen repeatedly rebuilt their neighborhoods; Smudge also rebuilt its paint pickup state. These tools now retain that work during supported strokes. Complete edits and previews share the same calculations. Strokes at unsupported boundaries or requiring larger layer storage use the complete renderer, preserving existing results.

On the24-megapixel benchmark, Blur/Sharpen/Smudge publish119/119/119 previews during about two seconds, with95th-percentile preview work of9.33/7.71/10.34ms. Every case changes pixels, preserves all240 samples and matches the complete command. All648 saved native pixel prefixes match in both paths across three bit depths. All142 focused and2742 full optimized tests pass.

The first two focused attempts exposed weak history fixtures: a smooth gradient produced no Blur or Sharpen edit, and protected Sharpen also left a hard checker pattern unchanged. The engine correctly avoided creating Undo entries for these no-ops. We preserved the failed runs, checked the fixtures independently, then required actual changes using textured artwork and an explicit sharpening option. A diagnostic expression also needed splitting for the Swift compiler. Application pixel code did not need alteration after the first test run.

Native tools and Undo/Redo were checked on disposable artwork. A separate signed Apple Silicon preview and ZIP carry the verified changes, preserving the existing installation. The API describes the preview capabilities and keeps missing retouch submission commands explicit. Initial setup still takes substantially longer than one frame, and boundary/heavy cases, visible dab texture, tablet input and physical display timing remain open. CPU preview publication is not a universal60fps guarantee or proof of Photoshop pixel equivalence. [Detailed record](DEVLOG.md#dev-step-265).

## 2026-10-29 — Step266: reduce the pause before a stroke appears

Profiling found that startup repeatedly checked every pixel in already-validated images. Each24-megapixel scan took about11ms. Surface now retains proof that its privately owned tiles contain finite samples. Safe editing preserves that proof; decoding still checks untrusted data, and raw copies propagate it conservatively. Structural checks always run. Pixel values, file formats, undo semantics and equality are unchanged.

The same validation benchmark now takes about0.04ms. Blur, Sharpen and Smudge startup improves from113–125ms to59–71ms. All six measured large-image toning/Focus tools preserve240 samples and exact native output while publishing119 previews during1.99 seconds. Ordinary painting publishes121 previews over the two-second stream; its24-megapixel case has6.57ms95th-percentile render work.

All74 focused and2748 full optimized tests pass. Six new storage regressions cover malformed archives, non-finite padding, cached undo tiles, forged validation metadata, overflow, raw copies, repair and copy-on-write. Native painting and Undo/Redo are checked on disposable artwork. A separate signed Apple Silicon preview is available; previous installations remain intact. API capability metadata describes the optimization without claiming new retouch commands.

This improves responsiveness but does not finish the performance goal: large-image startup still exceeds one frame, and visible jagged/dab texture, heavy tools, tablet curves and physical display timing need further work. No universal60fps or Photoshop pixel-equivalence claim is made. [Detailed record](DEVLOG.md#dev-step-266).

## 2026-10-29 — Step267: prepare the canvas at the right zoom

The remaining startup delay had a specific cause: initial layout and early zoom changes could leave the pending canvas preview sized for an earlier viewport. The first stroke then rebuilt the entire minified image. Four regression cases reproduced incorrect dimensions for initial fit, explicit zoom, rapid zoom changes and Artboard fit. The app now refreshes presentation even before its first image is ready; Artboard fit uses the same path.

The24-megapixel moving-stroke comparison improves Dodge, Blur and Smudge startup from71–73ms to9–11ms. Initial canvas preparation remains about2.6 seconds, and a separate extra-warmup comparison confirms the normal path is already ready. All six large-image retouch tools preserve240 samples and complete-command pixels while publishing119 previews during1.99 seconds. Previous through266 startup reports remain preserved and are now explicitly identified as including cold rescaling after direct zoom assignment.

An early benchmark incorrectly required a stationary first dab to alter pixels. XCTest tried to describe both entire24-megapixel documents on failure; we stopped the owned worker, preserved its oversized diagnostic losslessly in a compressed archive, and changed the test to a moving two-point stroke with bounded failure output. The repaired baseline exposed eight dimension assertions across four cases. All54 focused and2753 full optimized tests pass after the app correction.

Native loading, zoom, painting and history were checked with disposable artwork; a separate signed Apple Silicon preview is packaged. No working pixels, brush kernels, file formats or API commands changed. Native input sampling and physical frame timing are next: these CPU results do not prove universal60fps or resolve every jagged stroke. [Detailed record](DEVLOG.md#dev-step-267).

## 2026-10-29 — Step268: redraw only changing feedback

The input audit corrected our previous next-step note: scoped uncoalesced mouse input was already implemented and tested in262. No duplicate input mechanism was added. The remaining source inspection found that every painting sample requested a full canvas redraw even before new pixels arrived, and moving a retouch cursor also invalidated the whole view. Painting now redraws with published previews, while pointer feedback redraws its old and new outlines and source marker. An unclipped Clone Source overlay still refreshes the whole image.

Two initial test attempts incorrectly relied on AppKit's layer-backed needsDisplay getter; the first also omitted the flipped event-coordinate conversion. Their failures are preserved. A subsequent optimized test found a clipped-edge nearest-neighbor mismatch at150% zoom. An independent Quartz reproduction isolated it; magnified damage now aligns to both source and backing pixels, with full redraw retained for fractional pan or noncommensurate zoom. The failed candidate and its pixel differences are preserved. Corrected tests verify all1001 curved Brush/Eraser samples, exact native output and Undo, and independently compare partial redraws with full canvas images across64 cases. Painting input no longer requests redraw of unchanged previews; all samples still feed the paced worker. Retouch cursor feedback invalidates old/new rings and same-document source markers; unclipped source overlays retain whole-image redraw. All64 partial/full canvas comparisons match byte for byte. In the bounded offscreen cases, median draw cost is0.36ms versus3.07ms for whole-canvas redraw, touching2.17% of the canvas. All32 focused and2756 full optimized tests pass on2464 frozen inputs; native editing/history and a separate signed preview are checked. Physical60fps, jagged curves and broad heavy-tool qualification remain open.

The Photoshop window was inspected read-only, but attempted tool selection failed through the UI connector; a follow-up screenshot confirmed unchanged Paint Bucket settings and artwork. This increment does not claim reference brush-default or kernel parity. Native input curves and physical display timing remain open. [Detailed record](DEVLOG.md#dev-step-268).

## 2026-10-29 — Step269: measure native editing feedback

Earlier checkpoints reduced preview preparation and redraw work, but did not measure when a live window draws each accepted preview. The optional local recorder now correlates input sample counts and receipt times, preparation, accepted revisions and AppKit drawing. View display-link callbacks add scheduling markers. These are CPU/scheduling observations, not physical frame or input-to-photon measurements. Normal editing creates neither recorder nor probe. No painting kernel, smoothing default or pacing change is claimed here.

Reports exclude artwork, coordinates and document names. Diagnostic buffers are bounded, overflow is explicit, stale stroke revisions are rejected and unique output is asynchronous. Apple documentation identified an incompatible pair of Foundation write flags while the first frozen candidate compiled; its test run confirmed the fatal precondition. The failed attempt and corrected atomic-write candidate are preserved. Tests cover correlation, bounds, stale previews, cancellation, API metadata, exact native painting pixels and Undo. Opt-in bounded timing now correlates brush/retouch input, preparation, accepted previews and AppKit draws, with display-link scheduling markers. Normal editing has no recorder or display probe. All35 focused optimized tests pass on2466 frozen inputs. The full run records2432 passing cases before interruption during prolonged native Save-panel waits in the locked session; it is not a full-suite pass. The isolated diagnostic app is signed and matches tested code. Live trace collection is pending because the Mac is locked; no physical60fps or new pacing improvement is claimed. Normal preview remains268.

Live inspection could not start because the Mac was locked and the UI connector could not unlock it. Manual unlock was requested while the automated suite ran. The separate diagnostic app is ready for owned-fixture painting, history verification and trace collection after unlock. The full suite then encountered prolonged native Save-panel initialization waits; a stack sample was saved, and the owned test process was stopped. Its completed cases have no assertion failures, but the suite is incomplete and must be rerun after unlock. The existing normal preview and user artwork are unchanged. The overall feature and60fps goals remain open. [Detailed record](DEVLOG.md#dev-step-269).

**Step269 availability follow-up:** The Mac remains locked across three consecutive goal turns. Native UI access and the remaining full-suite/painting trace are blocked until manual unlock; source02 and normal preview268 are unchanged. The interrupted full run and failed initial report writer remain preserved. This availability check is not a new implementation milestone; live frame pacing and the complete Photoshop goal remain unqualified.

**2026-10-30 — Step269 qualification after unlock.** Native access resumed and the full rerun passed. Owned Brush and Blur strokes, Undo/Redo and viewport containment were checked in the isolated app; the original test image was left unchanged and the diagnostic app quit. Short automation drags supplied only3–4 samples, so their traces could not establish continuous frame cadence. A new opt-in test therefore streams240 store-generated points over2 seconds into a real native window hosting the full workspace, recording actual AppKit draw callbacks without directly calling draw. It covers Brush, Blur, Dodge and Smudge and verifies all samples and exact complete-command pixels. These synthetic store gestures are distinct from physical tablet or mouse input.

Optional per-stroke timing now correlates input, preparation, accepted previews and native AppKit draws. The real-workspace benchmark retains all240 samples and exact native pixels for Brush, Blur, Dodge and Smudge, while recording104–111 distinct preview draws during each roughly2-second stroke and about two canvas draws per accepted preview. Median newest-input-to-draw delay is20.7–22.6ms. All36 focused and2760 full optimized tests pass on2467 frozen inputs. Owned native painting/Undo/Redo and a separate signed preview are verified. This is scheduling/CPU evidence, not physical60fps; no kernel or pacing change is claimed in269. The roughly doubled draw count provides a concrete next investigation: remove redundant prepublication workspace updates, then repeat the same measurement. Earlier failures, locked-session attempts and the incomplete full run remain preserved. [Detailed record](DEVLOG.md#dev-step-269).

<a id="diary-step-270"></a>

## 2026-10-30 — Step270: present accepted editing previews

Canvas and thumbnail updates now follow accepted preview publication, while live strokes avoid the per-preview busy indicator. The native-window Brush/Blur/Dodge/Smudge fixture retains all240 samples and exact native command pixels with 119–120 distinct preview draws over about2 seconds, each accepted preview drawn once instead of nearly twice. Median distinct-draw intervals are 16.57–16.80ms. All105 focused and2762 full optimized tests pass on2468 frozen inputs. Native painting/history checks and a separate signed preview are verified. Latency remains tool/run dependent; this is AppKit scheduling evidence, not physical60fps.

The previous native-window trace showed almost two canvas draws for every accepted preview. The workspace was reacting when rendering started, before the next pixels existed. A separate accepted-presentation counter now updates the canvas and thumbnails after publication; request revisions still protect APIs and reject stale renders. The busy indicator no longer invalidates the workspace for each live stroke. Painting algorithms and stored document pixels are unchanged.

The first focused run found a new test checking the wrong zoom buffer. That failed attempt and its measurements remain preserved; the corrected test checks both the reduced display preview and retained full-resolution image. Both performance attempts are retained because latency varies with timing phase, and one first-attempt Dodge latency was worse despite better cadence. Physical60fps, high-rate tablet curves, jaggedness and heavy-tool cases remain open. [Detailed record](DEVLOG.md#dev-step-270).

## 2026-10-30 — Step271: use the current preview and restore tool focus

Native zoom Return now releases keyboard focus for tool shortcuts, and external zoom/Fit changes supersede stale percentage drafts while unrelated updates preserve typing. The obsolete159 probe was retired after a byte-identical retained copy of its open document was verified; that document is now open in normal Preview271. All71 focused and2764 full optimized tests pass on2468 frozen inputs. Native zoom/shortcut/history checks and signed packaging pass. No new frame-rate or Photoshop pixel-equivalence claim is made; sustained60fps and stroke continuity remain open.

Process and native-window inspection revealed that the only running Photato was the old159 probe, which predates the painting improvements. A fresh save from that actual window matched the protected original byte for byte. Its retained copy opened in the current build with the correct title and canvas clipping, then the old probe was closed. The handoff also exposed a stale zoom field that retained keyboard focus after Return, swallowing tool shortcuts. That focus defect is now repaired and tested; unrelated typing and document cancellation guards are preserved.

Photoshop reference tool selection failed through the UI connector and did not alter the existing document. Adobe’s published smoothing description identifies pause catch-up as the next concrete brush behavior to reproduce; current native catch-up appears to require a new input point. This is a research finding, not a claim that that behavior has been fixed. Physical60fps, default/kernel equivalence and broad platform qualification remain open. [Detailed record](DEVLOG.md#dev-step-271).

## 2026-10-30 — Step272: layer opacity slider

The Layers panel now includes an arrow-triggered native opacity slider alongside numeric entry. Dragging previews the canvas; Return or outside dismissal commits one shared opacity command, and Escape preserves document/history/dirty state. Keyboard arrows use 1% steps and Shift uses 10%. All 69 focused and 2770 full optimized tests pass on 2470 frozen inputs; native slider/history checks and separate Preview272 packaging are verified.

The requested arrow beside the opacity value opens a compact slider. Temporary values affect the canvas preview without creating history entries; acceptance uses the same native command as numeric entry and the optional API. Cancellation preserves existing redo history. Draft ownership prevents a stale pop-up from editing a replacement document. Adobe’s published control guidance informed Return, Escape and keyboard increments; the installed reference screenshot established the arrow placement, while the failed reference click is retained in the detailed record.

Live inspection verifies native slider accessibility values, canvas preview, toggle acceptance, numeric entry and Undo/Redo. The connector cannot reliably target the separate popup for pointer drags or key delivery; the actual shown-window focus, Shift+Down and Escape paths are verified by AppKit regression tests. Physical popup interaction remains a qualification limit. The prior brush catch-up and sustained 60fps work remains active. [Detailed record](DEVLOG.md#dev-step-272).

## 2026-10-30 — Step273: held-pointer brush smoothing

Brush/Pencil/Mixer/Eraser smoothing now advances toward a paused pointer using a bounded native clock, while catch-up on release waits for commitment. Timed samples retain tablet attributes and share the final native/API history path. Both initial defects are reproduced; all 62 focused and 2777 full optimized tests pass on 2471 frozen inputs. Native painting/history checks and separate Preview273 packaging are verified. Physical60fps and exact Photoshop smoothing remain open.

Investigation found two related problems: stationary updates were generated only by airbrush build-up, and previews applied catch-up-on-release before the stroke was released. Two regression cases reproduced both defects before repair. The held-stroke clock now uses the same smoothing geometry as the painter, stops when its work is done, and preserves the samples used by final commands. Native tests cover the timer, disabled/pulled-string guards, tool/window/document cancellation, ordinary and fallback painting, masks, tablet attributes and API/history replay. The opacity slider from272 remains available. This is a bounded editing-feedback improvement; physical frame rate, tablet curves, exact Adobe kernels and broad workflow parity remain open. [Detailed record](DEVLOG.md#dev-step-273).

## 2026-10-30 — Step274: brush release responsiveness

Ordinary raster brush strokes now retain preview work through release, processing only unseen samples and the release tail. The owned 24 MP fixture improves release commitment from about 290 ms to 1.0–6.0 ms with exact native command pixels and one history entry. All 69 focused and 2783 full optimized tests pass on 2474 frozen inputs. Native painting/history and separate Preview 274 packaging are verified. Physical 60 fps, special-tool release work and full Photoshop/platform parity remain open.

The release path discarded completed brush work and replayed every dab. A retained native stroke owner now validates its target and input prefix, finishes the remaining samples and release-only smoothing, and uses the existing history transaction. Actions still record the original command rather than replacement pixels. Tests compare full-command results across depths, dynamics, transforms and selections, then verify replay, cancellation and stale-session rejection. The opacity slider remains available. The timed fixture and bounded native checks establish this improvement, while physical frame rate and Photoshop numerical equivalence remain open. [Detailed record](DEVLOG.md#dev-step-274).

## 2026-10-30 — Step275: retouch release responsiveness

Clone Stamp, Dodge/Burn/Sponge and Blur/Sharpen/Smudge now retain validated preview work through release, appending only unseen samples. On the owned 24 MP fixture, eligible release commitment improves from 12–40 ms to 0.8–1.0 ms with exact native command pixels and one history entry. All 50 focused and 2791 full optimized tests pass on 2478 frozen inputs. Native painting/history and separate Preview 275 packaging are verified. Healing final processing, retouch Actions/direct APIs, physical 60 fps and full Photoshop/platform parity remain open.

The retouch release path discarded completed preview work and rebuilt each full stroke. A shared native owner now keeps validated Clone Stamp, toning and focus buffers, completes unseen input and commits through the same history transaction. Existing renderer interfaces remain available. Healing markers never substitute for finished output; unsupported storage and boundary cases still use complete preparation. Tests cover pixels and masks across depths, transforms and selections, pending input, cancellation and replaced documents, plus API history and busy-state behavior. The audit also confirms an existing gap: semantic retouch Actions and general stroke APIs remain unsupported and are explicitly tracked. These changes improve responsiveness without claiming physical frame rate or Photoshop numerical equivalence. [Detailed record](DEVLOG.md#dev-step-275).

## 2026-10-30 — Step276: stable pause before a model switch

Paused at the maintainer’s request on stable Preview275. All2791 full tests previously passed;2478 compiler/test inputs and the delivered app/ZIP hashes are reverified unchanged. Retouch Actions/API investigation is saved, with no implementation started. No new application build or test run was needed for this documentation-only handoff.

The next investigation identified how Actions and an optional retouch stroke API can share the existing native tools. Sampling provenance and portable source references need explicit handling; the current code stores completed sample images without the recipe needed for portable replay. These findings and acceptance checks are saved for resumption. No new feature was added during this handoff. The broad Photoshop-equivalence goal remains unfinished and paused. [Detailed record](DEVLOG.md#dev-step-276).

## 2026-10-30 — Step277: retouch Actions and API

Nine native retouch tools now record semantic Actions21 and share retouch.stroke in the optional Photato API. Playback resamples portable layer/source recipes, with explicit external-source admission and atomic history. All 88 focused and 2801 full optimized tests pass on2484 frozen inputs; native Actions recording/playback and separate Preview277 delivery are verified. Full Photoshop/Adobe descriptors/ATN, physical60fps and platform qualification remain open.

Actions retain the original samples, settings and source recipe. Each playback samples its current document; external sources must be explicit and unambiguous. The API uses the same native commands and protects pending work against source changes, revocation and cancellation. Existing older Action formats remain supported. Tests prove native equivalence across depths, masks, transforms and selections; Photoshop numerical parity remains a separate open requirement. [Detailed record](DEVLOG.md#dev-step-277).


### 2026-10-30 — Large-document architecture (step278)

Native RGB canvases now accept 300,000 pixels per side (90 GP logical area), with sparse raster composition, bounded viewport display and native/API brush, history and file workflows. All 102 focused and 2,810 full optimized tests pass on 2,488 frozen inputs; native maximum-size create/paint/save/reopen and Preview 278 are verified. Dense disk-backed images, streamed large PSB/native files and full operation, mode and platform capacity parity remain open.

Adobe’s public specification supplies the geometry target. Native testing creates a300,000-square RGB8 document at0.27% fit, paints at100%, checks Undo/Redo, saves/reopens the owned33,936-byte sparse file and confirms the stroke. Python independently verifies its manifest dimensions/hash. Preserve the initial compile errors, interrupted main-thread Save scan, legacy boundary/zoom/fixture corrections and failed independent parser endian assumption beside their repaired evidence. The full density/large-file/operation/platform requirement remains open; this is the first capacity foundation. [Detailed record](DEVLOG.md#dev-step-278).


## 2026-10-30 — Step279: disk-backed dense raster input

Large RGB image import now converts bounded patches into immutable disk-backed tiles; painting promotes only edited tiles and history shares existing samples. An owned40MP PNG passes native Open/paint/Undo/Redo/save/reopen and authenticated API import/edit/history. All48 focused and2820 full optimized tests pass; separate Preview279 is verified. Full dense90GP/large PSB/native streaming and operation/platform capacity parity remain open.

The former36MP restriction also affected real image input. Large RGB images now convert in2048×64 patches into private anonymous scratch files; immutable mapped tiles survive history snapshots and promote only touched samples into writable memory. Owned tests preserve8/16/32-bit samples, HDR/signed zero, profiles, EXIF orientation, cancellation, capacity failure and concurrent COW isolation. API storage accounting distinguishes owned heap from mapped references and OS-managed pages. An owned8000×5000 PNG provides a real40MP native/API workflow. Preserve the initial syntax failure, its repair and the final local-directory validation change.

This is runtime paging, not complete dense Photoshop capacity: native reopening still restores owned arrays; large PSB/native streaming, hierarchical indexing, packed cold samples, all operations, disk stress and platform/display qualification remain open. [Detailed evidence](DEVLOG.md#dev-step-279).


## 2026-10-30 — Step280: paged native persistence and large file IO

Native file Open/Save now stream past the former512MiB file boundary, and checked chunked tile input stays mapped on reopen/API upload. Tests cover an owned >512MiB file, real40MP native editing and134MP/2GiB repeated tile references across all depths. All71 focused and2829 full optimized tests pass; separate Preview280 is verified. Hierarchical indexes, large PSB/all-operation/platform capacity parity remain open.

Native reopening now validates each unique tile and keeps its samples in immutable private scratch. Mapped snapshots preserve copy-on-write and history; file identity, checksums, finite samples and cancellation remain checked before publication. The API shares this reader and reports file, Data, metadata and owned-storage limits separately. An independent native container crosses512MiB while reads/writes stay in64KiB chunks; repacking/reopening preserves its hidden sample bits. A separate high-entropy HDR fixture writes585693075bytes and reopens with exact sample probes. All-depth134MP repeated-reference and real40MP native/API workflows are separate evidence, not a dense90GP proof.

Correct an earlier interpretation: the gray image thumbnail was present, with checkerboard in its aspect-fit margins. An opaque output test and read-only screenshot pixel inspection rule out the suspected missing-thumbnail defect; no speculative UI fix was applied. Preserve the initial UUID/dab fixture failures and their repair. Full hierarchical indexes, large PSB/all operations, recovery/dense stress and platform/display parity remain open. [Detailed record](DEVLOG.md#dev-step-280).


## 2026-10-30 — Step281: publish qualified native source280

Publish and independently verify the complete source from the stable candidate that passed71 focused and2829 full optimized tests. It includes the painting/retouch feedback work and API/Actions,300000-side sparse canvases, disk-backed dense RGB input and checked native paging with file IO beyond512MiB. Preserve all qualified input hashes, the original Rust snapshot, repository history and private visibility. Generated optional models/caches, builds, runtime evidence and working documents remain excluded; reconstruction instructions remain included. Source commit: [`e4e359b`](https://github.com/ForensicIntelligence/Photato/commit/e4e359b6d230d5c95984eefaa94325a56e53885e). [Verified receipt](SOURCE_PUBLICATION_281.json). This does not close Photoshop, capacity, chooser, platform or physical60fps gaps. [Detailed record](DEVLOG.md#dev-step-281).


## 2026-10-30 — Step282: indexed native archives

Native63 removes the flat archive-table barrier with a bounded authenticated hierarchy and compact1024-entry tile-reference pages. Native File Open, optional API63, exact sample/history behavior and atomic save fallback share the engine. An independent parser checks300000 index records, all-depth sample bits,65792 repeated tile references and a real585MB high-entropy output with six original HDR probes.

All63 focused and2840 full optimized tests pass. In the native app, a300000-square canvas and a real40MP image accept painting/Undo/Redo/SaveAs/OpenRecent with the stroke preserved. Preview282 is separately signed, packaged and running with the unchanged retained artwork at100% zoom. Preserve the initial test-fixture crash and serializer-wrapped save-cap defect and their repairs. The newly saved-file chooser can still disable Open while Open Recent succeeds; this known issue stays open. Runtime tile dictionaries, large PSB, dense maximum/all operations/recovery and platform/Photoshop parity remain open. [Evidence](NATIVE_INDEX_REFERENCES.json) · [Detailed record](DEVLOG.md#dev-step-282).


## 2026-10-30 — Step283: modifier-aware tool cursors

Modifier keys now refresh the icon for the existing tool operation without needing a mouse move. All52 current tools share the policy; selection/source/toning/geometry alternates and sheet workspaces show meaningful native glyphs. Stroke and polygon modes stay tied to the action captured when the gesture starts. Space/Hand feedback restores correctly after release, focus changes and detachment, without stealing text/control cursors. Every new tool/action must include this behavior and tests under the contributor rules.

All9 new cursor tests and2849 full optimized tests pass, including an832-case tool/modifier matrix and native Zoom/history/captured-mode checks. Separate Preview283 is signed, verified and running with the retained clean artwork. The development record preserves compiler/fixture repairs, a focused document-controller startup-order crash and the test-host inability to become foreground. Event admission is checked with controlled key-window state; physical held-key Photoshop comparison remains open. API discovery describes local presentation; editing/history contracts and Adobe routes remain unchanged. Missing Photoshop modifier actions, pointer preferences/exact hover and capacity/platform parity remain open. [Audit and evidence](TOOL_CURSOR_REFERENCES.json) · [Detailed record](DEVLOG.md#dev-step-283).


## 2026-10-30 — Step284: paged runtime index and universal qualification (remaining gates open)

Large mapped images now retain a private file-backed descriptor index and bounded copy-on-write edits. Ordinary images keep a bounded fast path; large imports construct ordered descriptors in one pass. Existing native63 saving is automatic for runtime-paged documents, and APIs distinguish index pages, sample pages and estimated heap use.

The arm64 source passes268 focused and2,863 full optimized tests. Independent checks verify all21,977,344 maximum-index records and all65,537 unique tiles (>4GiB raw samples) in the owned native file. Repeated samples in the maximum-index probe do not establish a dense90GP raster. Software brush preview p95 is2.67–3.56ms in the measured cases; physical60fps remains unproven. The record preserves and repairs coroutine/compiler failures, signed-zero/admission errors, performance regressions and a layer-merge worker-stack overflow.

The Xcode Release build succeeds for Apple Silicon and Intel, with macOS14.0 deployment metadata and verified signatures/resources/ZIP. An optional-model script dependency repair keeps script sandboxing enabled; valid/missing/corrupt model cases are checked. Only the project specification/generated project differ from the arm64-tested source. Newer Apple frameworks are weak-linked. These checks do not prove a physical macOS14 or Intel launch.

All277 focused Intel tests and independent descriptor/sample checks pass under Rosetta. The full Intel run executes2,863 tests but fails320 assertions:319 strict numeric comparisons and one hosted rename-focus check. Native scalar probes show some architecture math differences; promoting to Double would also alter existing arm64 output, so that shortcut was rejected. Expected hashes and tolerances remain strict. The hosted assertion repeats in isolated Intel execution while its arm64 counterpart passes; visible behavior still needs native access. These are unresolved fidelity gates, not a fully qualified Intel release.

The UI tool still reports the Mac locked. Native40MP paint/save/reopen and normal-preview handoff remain pending; Preview283 stays the qualified normal build. All candidate284 packages and frozen source inputs are preserved. No new source push or distribution release is claimed. The next major capacity defect is reproduced:269 unique tiles referenced807 times require excess scratch after cache eviction. Full metadata/pyramids, dense capacity, large PSB, general operations/recovery, chooser, supported-platform and Photoshop equivalence remain open. [Runtime evidence](RUNTIME_TILE_INDEX_REFERENCES.json) · [Universal evidence](UNIVERSAL_BUILD_284.json) · [Detailed record](DEVLOG.md#dev-step-284).

## 2026-10-30 — Step285: repeated native tile references (software qualified; UI pending)

The native63 loader previously forgot aliases outside its256-entry cache. An owned file with269 unique tiles referenced807 times therefore required excess scratch. A new decode-local cache keeps sparse8-byte descriptors in a private, immediately unlinked file and retains immutable samples. Readonly mappings plus checked writes preserve explicit I/O failure handling. Desktop Open and native HTTP uploads share the fix, with API discovery/documentation updated; owned decoding and portable bytes stay unchanged.

All48 focused and2,871 full optimized arm64 tests pass. The first focused attempt retained a test-fixture error:269 one-channel values collapse at8-bit quantization. Two quantized channels repair only the fixture; the strict one-byte-under-scratch assertion remains. Independent Python authenticates the original archive and compares all3,305,472 decoded pixels to both its tile payloads and procedural reference bits. Both arm64 and translated Intel Core now open that exact file at17,629,184 scratch bytes and match every bit. This is a concrete capacity repair, not full Photoshop or maximum-dense-document proof.

The isolated signed candidate ZIP and2518 exact source inputs are preserved. Native UI access still reports the Mac locked, so the candidate has not launched and normal Preview283/artwork remain unchanged. Candidate284 stays frozen separately with its319 numerical assertions and one hosted Intel focus failure still open. No new source publication, distribution release or complete parity claim is made. [Implementation and evidence](NATIVE_ORDINAL_REUSE_REFERENCES.json) · [Detailed record](DEVLOG.md#dev-step-285).

## 2026-10-30 — Step286: large Photoshop files (software qualified; UI pending)

Native PSD/PSB interchange now pages RGB8/16/32 layers, raster masks and flat composites into immutable scratch samples. Layered import reuses bounded raw rows; flat channel-major input stages raw planes on disk. Large merged previews render bounded regions. File admission, retained metadata, heap workspace, sample/staging scratch and API transport quotas remain separate. Final prepared-file copying now admits precisely the staged size, removing a second512MiB restriction affecting large native/Photoshop saves.

All2,878 optimized arm64 tests pass. The first83-test focus run passes82 cases; its new group fixture fails because I placed a marker before its child. Correcting only that fixture makes the exact regional/full-render comparison pass at all depths.36 independent Python vectors retain every raw sample and native PSB byte from actual prior285 output. A real640,003,428-byte40MP RGB16 PSB exports/reopens, while independent Python checks all640,000,000 layer/merged sample bytes. The full coordinated copy compares every byte; compressed40MP HTTP import/painting/stale-revision/Undo also passes. Intel Core/Imaging compile and translated36-vector/every40-million-pixel replay pass. These are format/native/translated checks, not Photoshop output or maximum dense90GP proof.

The signed isolated candidate and2561 exact source inputs are preserved. The Mac remains locked for native/Photoshop acceptance; candidate286 has not launched and normal283/artwork stay unchanged. The older Intel numerical/hosted-focus failures, full content/mode/recovery/rendering/dense capacity and physical supported-platform gates remain open. No source push, distribution release or complete parity claim is made. [Design and evidence](LARGE_PSB_WORKFLOW_REFERENCES.json) · [Detailed record](DEVLOG.md#dev-step-286).

## 2026-10-30 — Step287: large-document geometry (software qualified; native acceptance pending)

Image Size/rotation rejected large raster output, coloured canvas growth rejected large canvases, and saved channels allocated full results in memory. A retained prior286 probe also shows a32-bit linear identity transform changing one HDR component by one bit through an encoded colour round trip. Bounded resampling patches, exact raw grid permutations, preserved encoding and paged/shared rectangular borders replace those paths. Sparse support stays bounded.

All55 focused and2890 full optimized arm64 tests pass on2610 frozen Source03 inputs. Tests cover maximum sparse geometry, a real dense40MP resize/turn/history/native round trip, masks/channels, invalid/busy/stale/cancel behavior and API parity. All36 actual prior286 sRGB outputs match, independent raw32 maps preserve special sample bits, and translated Intel component replay passes. The strict renderer matrix compares80 depth/translation/mask/opacity/encoding combinations. These are native/independent/translated checks, not Photoshop kernel or maximum dense90GP proof.

The record preserves the typecheck typo, failed maximum masked API preview, its repair, a separately discovered linear-mask encoding mismatch and the final correction. Both passing full runs and failed evidence are retained. The signed isolated candidate is preserved; native/Photoshop acceptance awaits manual unlock and normal283/artwork stay unchanged. Dense selections, general composition, mode/operation limits, exact Photoshop variants and previous Intel/physical-platform gates remain open. No source push or distribution release is claimed. [Design and evidence](PAGED_GEOMETRY_REFERENCES.json) · [Detailed record](DEVLOG.md#dev-step-287).

## 2026-10-31 — Step288: paged selections and bounded channel views (software qualified)

Large selections use immutable paged coverage. Native64 retains coverage through saves, recovery and scratch-backed history. Shape/inverse/feather share prepared desktop and API commands; small legacy data stays compatible. Whole-array extraction is checked, point sampling does not allocate, and contours use bounded viewport sampling.

The continuation adds bounded saved-alpha/Quick Mask, RGB component, raw pixel-mask and Selection Brush previews. Cropped mask overlays keep their document position while panning. Numerical channel coverage ignores source alpha. The API's channel preview shares native rendering; two read-only per-layer mask resources return gray or RGBA overlay. They require authentication/shared documents and reject busy, absent, cancelled or revoked work without modifying history or stored pixels.

All 2,912 full optimized arm64 tests pass, with 37 focused workflow tests and 14 translated Intel component tests on corresponding production. Checks include complete 40 MP coverage/area input, 76 preserved prior-native selection vectors, maximum sparse/constant canvases, native64/history and matched native/API preview pixels. Native-size raw mask previews retain exact existing samples; reduced mask previews sample output-cell centers, and alpha overlays reduce composite/coverage before mixing. Full Photoshop preview-filter fidelity is unqualified.

The record preserves compiler migration failures, a reproduced worker-stack SIGBUS, stale capability expectations and the continuation's test-fixture actor-isolation error. Immutable selection storage restores stride64; the original crash path, footprint guard and complete suite pass. The fixture repair changes no production code; output oracles and tolerances were not weakened.

Separate signed candidates are preserved. Normal283/artwork remain unchanged; native/Photoshop acceptance awaits manual unlock. General large rich-stack/mode/proof/onion composition, explicit paged-coverage Actions, compact one-byte storage (current tiles use16-byte RGBA Float samples), Adobe descriptors/UXP, full dense capacity/frame rate and supported-platform qualification remain open. The master goal stays active; no source publication or distribution release is claimed. [Evidence](PAGED_SELECTION_REFERENCES.json) · [Native64](NATIVE_ARCHIVE_FORMAT_64.json) · [Detailed record](DEVLOG.md#dev-step-288).

## 2026-10-31 — Step289: save the qualified source to private GitHub

Published and independently verified the complete native source from Source13, which passed 2,912 full optimized arm64 tests, 37 focused workflows and 14 translated Intel component tests. Preserve the original Rust snapshot/history, licenses, Xcode project, tests and fixture provenance. Builds, generated models/caches, local runtime evidence and working documents stay excluded.

This delivers source only; the Mac remains locked for native acceptance. Normal283 and retained artwork stay unchanged. The repository remains private until release day, and full Photoshop/capacity/platform qualification stays open. Source commit: [`8556551`](https://github.com/ForensicIntelligence/Photato/commit/85565519fdff911a6a16fbda6739cd173d27970b). [Verified receipt](SOURCE_PUBLICATION_289.json).

## 2026-10-31 — Step290: large layered documents and continued cursor coverage

Large RGB8/16/32 groups, clipping, pointwise adjustments and supported raster/procedural/affine stacks now compose through bounded2048×64 patches and immutable sample/index pages. Sparse coordinate-independent stacks retain exact implicit backgrounds and actual global opacity facts. All2919 full optimized arm64 tests and46 focused tests pass on2,729 frozen inputs, including24 prior-native vectors, every40MP Float32/HDR/hidden sample and maximum native/API/history/persistence/error/cancel workflows. Intel builds and24 same-architecture renderer comparisons pass, but9 strict prior-arm64 comparisons fail and remain preserved; full Intel/Photoshop parity is open. A signed isolated candidate is preserved, with normal283/artwork unchanged. Native acceptance, large rich/mode limits, full dense capacity/performance and supported-platform gates remain open.

The implementation keeps the existing native compositor and evaluates actual document-coordinate patches. A shared per-document cache retains bounded mask preparation and global opacity facts. No reduced proxy replaces working pixels, and spatial/dithered sources keep full patch evaluation. Styles, vector/oversized feather masks, local raster planes, Smart Filter/Warp and non-RGB modes retain independent limits. The195 typed operations and existing Adobe-compatible resource jobs share the engine; discovery and usage documentation describe actual boundaries, without inventing Adobe routes.

The first build failed on Sequence.min name resolution; its source/log remain preserved before qualifying Swift.min. Strict Intel failures were retained without changing references or tolerances. Separate comparison proves24/24 paged outputs equal that architecture's existing regional renderer;15/24 match the prior arm64 reference. This is narrower evidence than universal or Photoshop equivalence.

All nine cursor regressions pass, including the52-tool/832-combination matrix, stationary zoom direction, gesture capture, settings/focus cleanup and alternate-action restoration. AGENTS/CONTRIBUTING now explicitly require all16 combinations of Control, Command, Option and Shift for future tools. Generated cursor artwork was inspected; physical held-key comparison remains pending. [Detailed record](DEVLOG.md#dev-step-290) · [Composition evidence](PAGED_COMPOSITION_REFERENCES.json) · [Cursor audit](TOOL_CURSOR_REFERENCES.json).

## 2026-10-31 — Step291: large vector masks and path selections

Large RGB documents now support unfeathered vector masks and paged path selections, with shared native/API coverage, opacity facts, regional rendering and sparse composition. All2923 full optimized arm64 tests pass on2767 final Source06 inputs;62 earlier focused Source05 tests also pass. All32 preserved native GRAY8 vectors match;3 translated Intel module tests pass on the same production source. Maximum300000-square mask/selection/preview/history/persistence and stale/busy/cancel cases pass. A private signed candidate is preserved; normal283/artwork remain unchanged. Large feather/effects/modes, cross-block/Photoshop AA and complete native/platform/dense-capacity/performance gates stay open.

The initial small CG patches changed antialias rounding; strict failures and rejected clipping/halo probes are preserved. An enormous CG context also lost owned far-edge pixels. The implementation now uses private unlinked GRAY8 scratch and16K coordinate blocks, then2048x64 output transfers. Empty/full rectangles remain implicit. A mapped guard row and explicit owner lifetime protect stride/pointer use. The90GB logical gray extent is separate from physical allocation, heap, native internal buffers and OS-managed residency; compact physical output and dense capacity remain open. Interrupted compiler attempts and their repairs remain in the detailed record, with unchanged reference bytes/tolerances. No native/Photoshop/universal release or source push is claimed. [Detailed record](DEVLOG.md#dev-step-291) · [Evidence](PAGED_VECTOR_REFERENCES.json).

## 2026-10-31 — Step292: filters for large photographs

The existing eight basic filters now support large direct RGB raster layers through checked readonly Float64 scratch and bounded output. Gaussian/Box/Motion Blur, Unsharp Mask, High Pass, Noise, Mosaic and Average retain native reduction order, selection/alpha/seed behavior, dialogs/history/persistence and shared APIs. All2930 full optimized arm64 tests and59 focused tests pass on2823 frozen inputs;5 translated Intel module tests pass.48 actual prior-native outputs and30 wide native band hashes match, including real9MP blur output. A signed isolated candidate is retained; normal283/artwork are unchanged. Smart Filters/other families/modes/channels, full Photoshop/native/platform/dense-capacity/performance gates stay open.

The previous common8MP cap rejected ordinary24–40MP photographs. Direct basic RGB filters now use checked unlinked readonly Float64 intermediates, bounded row/column buffers and immutable output patches. Running sums keep their full native order; Noise keeps its global sequence. Exact constant proofs support maximum implicit canvases. Per-plane4TiB admission is separate from simultaneous files, final raster scratch, physical disk, OS-managed mapped residency and RSS. Full dense throughput/capacity and Photoshop kernel equality remain unqualified.

The record retains a fixture field-type compile failure and private storage-accessor build failure, with their repaired reruns.48 vectors cover three depths and transformed fractional selections/alpha locks.30 prior-native6000-wide band hashes qualify the corresponding prefix of9MP Box/Gaussian output. A signed-zero regression preserves zero-seeded constant reductions. Channel/Smart Filter/other-family admission stays explicit rather than silently promising large support. [Detailed record](DEVLOG.md#dev-step-292) · [Evidence](PAGED_FILTER_REFERENCES.json).

The final native check remains blocked by the locked Mac; the candidate is preserved without replacing normal Preview283. The factory menu/dialog and API paths are qualified by software tests. An unbound legacy blur helper still uses the common size limit and is recorded for consistency cleanup.

## 2026-10-31 — Step293: editable filters on large images

The eight basic RGB Smart Filters now retain editable sources over large placed canvases with paged placement, blending and selection/pixel masks. Native RGB source conversion/reopen and depth conversion avoid whole-canvas enumeration for sparse inputs. Native dialogs, filter editing, history, persistence and APIs share the engine. All2942 full optimized arm64 tests and90 focused tests pass on2878 frozen inputs;6 translated Intel module tests and48 exact prior-native outputs pass. A signed isolated candidate is retained; normal283/artwork remain unchanged. Full Photoshop/native/platform/dense-capacity, other-family/mode/Warp/large-feather and rich PSB/job/output gates stay open.

Smart Filters now use bounded affine placement and immutable output pages, with exact defaults for proven pointwise blends and aligned masks. Selections reuse existing GRAY8 storage. Original embedded source bytes and samples stay editable. A native workflow test exposed the compositor-to-RGB8 depth conversion walking every pixel of a maximum canvas; the disposable test was interrupted, its runtime sample preserved, and that conversion was changed to paged allocated-tile traversal. Six maximum sparse cross-depth comparisons retain legacy quantization and signed-zero comparisons. Two test compile repairs and an encoded-Float32 mask review remain in the record.

The48 regression references come from the actual previous native renderer, not Photoshop. Adobe basic-filter mappings use the shared engine, while large PSD/PSB caches/masks, source-byte limits and resource-job outputs still have separate limits. No complete Photoshop, dense90GP, frame-rate, physical Intel or macOS14/26 runtime claim is made. [Detailed record](DEVLOG.md#dev-step-293) · [Evidence](PAGED_SMART_FILTER_REFERENCES.json).

The initial unfiltered Smart Object snapshot exposed a second full-canvas traversal. Ordinary raster caches now use the existing sparse compositor; strict cached-object comparisons retain bounded-renderer pixels at all depths. The legacy blur helper and editable-filter entry now use kind-specific availability. Native access is still locked, so the candidate remains unlaunched and normal Preview283 is preserved.

## 2026-10-31 — Step294: save the qualified source to private GitHub (in progress)

Prepare the complete source of checkpoint293, which passes2,942 full optimized arm64 tests,90 focused workflows and6 translated Intel Core module checks. The portable manifest identifies2,846 included inputs and32 excluded generated model/provenance/cache files. Existing Rust provenance and licenses stay intact. This source-only backup changes no native function, menu, shortcut, API or installed package. The repository remains private until release day. Native acceptance, full Photoshop parity, dense capacity, performance, rich large PSB/jobs and supported-platform qualification remain open. The verified publication receipt follows after push.
