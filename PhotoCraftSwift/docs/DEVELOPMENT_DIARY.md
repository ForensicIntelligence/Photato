## Source update — 9 November 2026 UTC, build 514

Auto-Blend now keeps visible editable source layers when seamless blending is enabled and transparent-area fill is off. Photomerge also retains the photograph names. Fill adds a merged layer; translucent sources still use the documented isolation fallback.

Debug and optimized ARM pass 37/37 focused tests, including all nine new methods. Intel passes 36/37 and eight of nine new methods; its exact linear-RGB comparison remains failed. Native commit, Undo/Redo and saved PSD reopening were checked. The Intel difference is isolated to the same color-transfer behavior in the retained build 513; the stored component comparison is unchanged. The original assertion remains required. Full blending fidelity, large-photo capacity, all prior failures and Photoshop parity remain open.

[514 — Development record](DEVLOG.md#dev-step-514) · [Workflow/API](EDITABLE_PHOTO_BLEND.md) · [Qualification](SOURCE_PUBLICATION_514.md).

## Source update — 9 November 2026 UTC, build 513

Legacy Macintosh RGB proofing is now available in the native app and API. Shared Apple RGB profiles also work for document creation and output. Native controls, cancellation, Command-Y and saved/reopened PSD components were checked.

All seven new tests pass in Debug and both optimized architectures. Broader runs pass 54/55 on Apple Silicon and 52/55 on translated Intel. The remaining Gray-profile and frozen-proof failures reproduce on the actual retained build 512 binary; they remain open. The universal package passes static checks and is unlaunched. Full color-proofing and Photoshop parity are unfinished.

[513 — Development record](DEVLOG.md#dev-step-513) · [Workflow/API](APPLE_RGB_PROOF.md) · [Qualification](SOURCE_PUBLICATION_513.md).

## Source update — 9 November 2026 UTC, build 512

Merge Channels now works through the native Channels panel and the optional API. Assign grayscale images to RGB, CMYK, Lab or Multichannel output. The result opens as a new document; only the chosen sources close.

All 15 new tests pass in Debug and both optimized architectures. The broader run passes 68/69, with the same legacy Multichannel failure reproduced on public build 511. Actual RGB16 and Multichannel16 saves reopen correctly and match all 960 Photoshop reference component values. Full parity and the recorded cleanup work remain open.

[512 — Merge Channels](DEVLOG.md#dev-step-512) · [Usage/API](MERGE_CHANNELS.md) · [Validation](SOURCE_PUBLICATION_512.md).

## Source update — 8 November 2026, build 511

Photoshop rejected our Gray32 PSD exports even though Photato could reopen them. The writer omitted HDR toning metadata for grayscale. That is fixed in the shared native and API export path.

All 32 selected tests pass in Debug and both optimized architectures. Photoshop opens all eight tested PSD/PSB compression variants. A separate Float32 merged-preview difference remains. Merge Channels reference work is recorded, but that command is still in progress.

[511 — Gray32 Photoshop file export](DEVLOG.md#dev-step-511) · [Validation and remaining work](SOURCE_PUBLICATION_511.md).

## Source update — 8 November 2026, build 510

The diary now includes reviewed adjustment values, language/plugin audits and editable gradient profile conversion. The current workflow passes all14new tests in Debug and both optimized architectures, plus a native save/reopen check. The broader run has a known Intel failure, independently reproduced on public506; it remains required.

- [507 — Reviewed adjustment values](DEVLOG.md#dev-step-507)
- [508 — AI, language and plugin acceptance](DEVLOG.md#dev-step-508)
- [509 — Plugin host requirements](DEVLOG.md#dev-step-509)
- [510 — Editable gradient profiles](DEVLOG.md#dev-step-510)

[Validation and remaining gaps](SOURCE_PUBLICATION_510.md).

## Source update — 8 November 2026, build 506

Photato now has a local learned upscaling workflow. Image > Generative Upscale creates a separate 2× or 4× document using an optional BSD-licensed Real-ESRGAN model. The original stays unchanged. Native progress, cancellation and API create/cancel share the same preparation.

All 46 selected methods pass in Debug, optimized Apple Silicon and translated Intel; 19 archive-tool checks pass. The diary includes the failed compiles, Intel half-precision repair and inherited archive path-guard correction. This remains an unfinished development alpha.

- [506 — Local learned upscaling](DEVLOG.md#dev-step-506)
- [Workflow and API](LOCAL_SUPER_RESOLUTION.md)
- [Validation and remaining gaps](SOURCE_PUBLICATION_506.md)

## Source update — 8 November 2026, build 505

Generated backgrounds now prepare bounded references from larger masked subjects. The image workspace also offers an explicit request to edit a reference image on eligible Apple Silicon Macs running macOS 27 or later. Ordinary editing still targets macOS 14+.

All 81 focused methods pass in Debug, optimized Apple Silicon and translated Intel, including 20 new methods from 504–505. The records include failed attempts, the unresolved native AI-sheet connection failure and the limits of the model checks.

- [504 — Background generation on large documents](DEVLOG.md#dev-step-504)
- [505 — Edit a reference image](DEVLOG.md#dev-step-505)

[Source delivery and remaining gaps](SOURCE_PUBLICATION_505.md). Standalone website promotion remains pending.

## Source update — 8 November 2026, build 503

People selection now works beyond the former small-image admission limit. Apple text-service readiness explains missing device, system, model or signed-capability requirements. The Remove tool can mark background people for review before an explicit apply.

The current source passes 114 focused methods in Debug and each optimized architecture, including all 31 new 501–503 methods. The diary records the failed attempts and the portrait-classification correction. Full Photoshop functionality and output parity remain unfinished.

- [501 — Select People on large documents](DEVLOG.md#dev-step-501)
- [502 — Report Apple text-service availability](DEVLOG.md#dev-step-502)
- [503 — Review people before removal](DEVLOG.md#dev-step-503)

[Source delivery, validation and remaining gaps](SOURCE_PUBLICATION_503.md). The standalone website and canonical historical-evidence pipeline remain separately pending.

## Source update — 8 November2026

Build500 passes its42 focused Debug tests and the same42 optimized tests on Apple Silicon and translated Intel. Actual sandboxed export, Cancel/history and normal Quit checks pass. This source snapshot includes the work through500; it does not establish full Photoshop parity or a full-suite pass.

- [487 — Share the person-selection model](DEVLOG.md#dev-step-487)
- [488 — Image styles and canvas size](DEVLOG.md#dev-step-488)
- [489 — Native Remove tool](DEVLOG.md#dev-step-489)
- [490 — Generated backgrounds](DEVLOG.md#dev-step-490)
- [491 — Reference images for generation](DEVLOG.md#dev-step-491)
- [492 — Reviewed edit plans](DEVLOG.md#dev-step-492)
- [493 — Profile changes on large documents](DEVLOG.md#dev-step-493)
- [494 — Directory durability](DEVLOG.md#dev-step-494)
- [495 — Paged Warp](DEVLOG.md#dev-step-495)
- [496 — PSD vector path semantics](DEVLOG.md#dev-step-496)
- [497 — Untagged files and sandboxed copies](DEVLOG.md#dev-step-497)
- [498 — Large colour-mode files](DEVLOG.md#dev-step-498)
- [499 — Paths to Illustrator](DEVLOG.md#dev-step-499)
- [500 — Repair native asset export](DEVLOG.md#dev-step-500)

The detailed private attempt records remain retained. The canonical history-index and website refresh are still pending; [delivery details](SOURCE_PUBLICATION_500.md).

# Photato development diary

<!-- process-note:start -->
## Source code and compatibility testing

Photato is a native Swift image editor targeting Photoshop 2026 functionality. The open-source PhotoCraft Rust project provides inspiration and licensed implementation material. Photoshop 2026 defines the behavior we need to reproduce. Ported code keeps its MIT/Apache licensing and credits. We record the source and license of dependencies and test fixtures.

For Photoshop compatibility, we use public Adobe documentation and Photoshop’s normal interface with our own test artwork. We record controls, defaults, shortcuts and results, and examine saved files. Some compatibility facts come from installed metadata and script definitions; Adobe’s script code is not incorporated into Photato.

We port licensed PhotoCraft code where suitable and write independent Swift code for the editor, macOS interface and APIs. We have not decompiled or disassembled Photoshop executables, extracted proprietary algorithm code, or copied Adobe’s proprietary implementation into Photato.

Tests compare results with the original Rust implementation, public file specifications and Photoshop-generated test files. They cover editing, previews, cancellation, undo/redo, saving and APIs. Byte-identical results are claimed only for tested cases. Mismatches and untested behavior remain in the record, along with source/build hashes, commands, failed attempts and repairs.

This is independent implementation with black-box compatibility research. Research and implementation happen within the same project, so this is not a claim of formal clean-room separation. Observing behavior and examining saved files are part of the process; the diary does not claim that no reverse engineering of any kind occurred. The restriction on decompiling, disassembling or copying Photoshop’s proprietary implementation remains explicit.

<!-- process-note:end -->

**Release policy — updated 6 November 2026:** Photato will be a free and open-source release under MIT OR Apache-2.0, without tips, donations, in-app purchases, subscriptions or paid feature unlocks. The repository is now public at the maintainer’s request; application releases remain manually approved. Earlier entries describe the former purchase experiment as history; step237 records its removal.

<!-- current-status:start -->
<!-- current-status-step:486 -->
**Latest record: 486. Application build: 486, validation candidate.** Classic RGB16 Gradient Map now matches the fresh checked Photoshop references across native files, PSD/PSB and native/API edits. All 61 selected Debug tests pass. Optimized Apple Silicon passes 61/61 and translated Intel 60/61, with all three new methods passing both. The remaining Intel failure reproduces on build485. Native edit/Undo/Redo/cleanup and universal package checks pass. Full A06 and earlier gaps remain open. Build480 remains the latest fully qualified selected universal. Next: AI01, then AI02. [Latest record](#dev-step-486) · [Evidence](CLASSIC_RGB16_BOUNDARIES_486.json).
<!-- current-status:end -->

## The brief and the decisions that shaped the project

The original brief was to inspect PhotoCraft, plan the port, implement it module by module, and test each module. The target became Photoshop 2026 functionality in a fully native Swift application for macOS 14 and later, with a universal application for Apple Silicon and Intel. Optional Apple AI belongs behind platform and availability checks. The maintainer clarified at step335 that Rust is a source of inspiration, not a required first parity milestone. Missing Photoshop workflows determine the work, regardless of whether Rust implements them.

The maintainer then made several decisions that continue to govern development:

- Use Photoshop's interface, menu structure and factory shortcuts by default. A visible menu item does not establish that its function is implemented.
- Allow Apple's Private Cloud Compute as well as eligible on-device features, and describe which service is actually used.
- Release the work as an open-source fork with clear PhotoCraft attribution. Name the application **Photato**, and use the supplied icon.
- The earlier optional App Store tip experiment was removed at step237. The current release is free and open source, with no purchases or paid feature unlocks.
- Include a native Xcode project alongside the package-based build and test workflow.
- Maintain both the Photato API and an interface compatible with the published Adobe Photoshop API wherever that contract defines the operation. Desktop and API operations share the native engine.
- Record every development change, including failures and removals, from the beginning.
- Follow the current seven-pass order: **major quick wins, major still needed, minor quick wins, minor still needed, major cleanup, minor cleanup, final settings/checks**. UI, menus, shortcuts, APIs and focused tests stay with each delivered function. Full original acceptance still governs package closure.

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

## 2026-10-20 — Step152: protection reaches editing and both APIs

The previous isolated protection model now governs actual native edits and file persistence. Painting preserves the existing alpha stencil; Photoshop’s explicit selected Clear removes pixels. Image and position locks block their respective operations, while full-lock Rename and grouping follow the observed reference. The native dialog, layer buttons, shortcut and both API paths share those transactions. Version12 prevents older readers from silently losing partial protection; compatible existing files retain their prior version.

The first two compilations exposed test inference and initialization errors. Full01 later found94 failed assertions, mostly90 repetitions of the old TIFF partial-to-full collapse. An independent byte inventory proved all30 TIFF fixtures contain transparency-only protection. Focused06 also exposed a known unsupported little-endian opaque metadata block; the test now distinguishes that limitation from protection-only output. Later review also corrected API-only flag transitions and a reproduced protected-Fill integer quantization defect; both interrupted validations and the failing regression are preserved. Live testing then exposed initial checkbox enablement overridden during SwiftUI installation; a hosted-control regression reproduced five failures before the environment-state fix. Final59 focused,1,442 Debug,1,442 Release and20 Rosetta tests pass, with universal packaging and an owned native UI probe. This is bounded integration, not complete Photoshop parity; all major gates remain open.

[Runtime development record](DEVLOG.md#dev-step-152), [checkpoint152](ACTIVE_CHECKPOINT_152.json)

Step153 completes the first editable original-project migration subset. Source-generated RGB 8/16/32 fixtures retain raster/group/mask/path/selection/protection data through native Open, API editing and Photato persistence. Empty-selection and file-registration regressions were reproduced and repaired; all 1,455 Debug/Release tests,13 Rosetta cases,universal packaging and an owned live workflow pass. Rich source features and all major gates remain open. See [the detailed step153 record](DEVLOG.md#dev-step-153).

Step154 adds independent source/Photoshop rendering comparisons and repairs off-canvas raster-mask edge handling. The first broad cropped-mask hypothesis was disproved by controls; the final change follows the measured layer-boundary distinction. All 1,460 Debug/Release tests, 14 Rosetta cases and native/UI/API/package checks pass. Gaussian/vector/full byte parity remains open. See [step154](DEVLOG.md#dev-step-154).

## 26 October 2026

Step155 resumes the feather experiment begun on20October. Controlled identical-byte tests identify a filesystem visibility defect behind misleading Photoshop import errors. The first core repair passes while end-to-end tests expose AppKit staging as a second boundary; the final change carries destination visibility through both. All1,471 Debug/Release,33 focused and22 Rosetta tests pass, and direct Photoshop Open accepts native UI and generated outputs without byte changes. The atlas independently records16 radii, with exploratory exact fits at4/5/10; general feather parity remains unfinished. Historical pauses, failed tests/harnesses and both current-source builds are preserved. See [step155](DEVLOG.md#dev-step-155).

### 26 October: major features before numerical refinement

Step156 captures 48 independent transparent feather controls, but fractional radii invalidate the first simple kernel hypothesis. The maintainer asks to prioritize missing major functionality. Research and reference files are preserved; no feather algorithm is changed. [Deferred research](DEVLOG.md#dev-step-156)

Step157 adds a shared Swift raster-filter workflow: Gaussian/Box/Motion Blur, Unsharp Mask, High Pass, Add Noise, Mosaic and Average. Native preview sheets, Cancel/OK, selection and locks, one undoable edit, existing file persistence, the Photato command and both resource-job interfaces are integrated together. All59 focused Debug and1,483 full Release tests pass, along with24 functional cases on arm64 and x86_64 under Rosetta. The universal macOS 14+ candidate and live UI checks verify; installed117 remains unchanged. Failed fixture/old synchronous-test assumptions and outdated API-count assertions are retained with their repairs. Exact Photoshop filter pixels and Smart Filters remain open. [Filter workflow](DEVLOG.md#dev-step-157)

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
| 2026-10-28 | 221 | [Native Indexed Color and Bitmap — in progress](DEVLOG.md#dev-step-221) |
| 2026-10-28 | 222 | [Duotone and Multichannel — in progress](DEVLOG.md#dev-step-222) |
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
| 2026-10-31 | 295 | [Streamed Smart Filter cache interchange](DEVLOG.md#dev-step-295) |
| 2026-10-31 | 296 | [Large isolated resource jobs](DEVLOG.md#dev-step-296) |
| 2026-10-31 | 297 | [Modern adjustment layers](DEVLOG.md#dev-step-297) |
| 2026-10-31 | 298 | [Apply Image and Calculations (software qualified)](DEVLOG.md#dev-step-298) |
| 2026-10-31 | 299 | [Linked Smart Objects (in progress)](DEVLOG.md#dev-step-299) |
| 2026-10-31 | 300 | [Rich PhotoCraft migration (in progress)](DEVLOG.md#dev-step-300) |
| 2026-10-31 | 301 | [Diary refreshed against current evidence](DEVLOG.md#dev-step-301) |
| 2026-10-31 | 302 | [Exposure workflow prerequisite (in progress)](DEVLOG.md#dev-step-302) |
| 2026-10-31 | 303 | [Editable source vector shapes (unbuilt, in progress)](DEVLOG.md#dev-step-303) |
| 2026-10-31 | 304 | [Diary synchronized with actual source and test evidence](DEVLOG.md#dev-step-304) |
| 2026-10-31 | 305 | [Editable source shapes: native/API workflows tested, strict gates open](DEVLOG.md#dev-step-305) |
| 2026-10-31 | 306 | [Rich source text migration (unbuilt, in progress)](DEVLOG.md#dev-step-306) |
| 2026-10-31 | 307 | [Diary synchronized with current work and verified evidence](DEVLOG.md#dev-step-307) |
| 2026-10-31 | 308 | [Rich source text native/API workflows tested; exact gates open](DEVLOG.md#dev-step-308) |
| 2026-10-31 | 309 | [Source Smart Object prerequisites; workflow crash remains open](DEVLOG.md#dev-step-309) |
| 2026-10-31 | 310 | [Diary synchronized with current work, tests and failures](DEVLOG.md#dev-step-310) |
| 2026-10-31 | 311 | [Command-worker crash repaired; full inventory and strict gates recorded](DEVLOG.md#dev-step-311) |
| 2026-10-31 | 312 | [Editable source Smart import: cached workflows tested; nesting failure open](DEVLOG.md#dev-step-312) |
| 2026-10-31 | 313 | [Diary synchronized with current import and retained failures](DEVLOG.md#dev-step-313) |
| 2026-10-31 | 314 | [Nested source worker repaired; native/API workflows pass, strict gates open](DEVLOG.md#dev-step-314) |
| 2026-11-01 | 315 | [Editable source filter mappings expand to107; functional tests pass, strict gates open](DEVLOG.md#dev-step-315) |
| 2026-11-01 | 316 | [Native Relight engine and integration draft; testing pending](DEVLOG.md#dev-step-316) |
| 2026-11-01 | 317 | [Diary synchronized with working316 and tested315](DEVLOG.md#dev-step-317) |
| 2026-11-01 | 318 | [Native Relight workflows and exact original-engine reference subset qualified](DEVLOG.md#dev-step-318) |
| 2026-11-01 | 319 | [Multi-light Lighting Effects; partial tests and failed repair](DEVLOG.md#dev-step-319) |
| 2026-11-01 | 320 | [Diary synchronized with current319 evidence](DEVLOG.md#dev-step-320) |
| 2026-11-01 | 321 | [Lighting Effects functional qualification and complete test inventory](DEVLOG.md#dev-step-321) |
| 2026-11-01 | 322 | [Source Displace functional qualification and diary synchronization](DEVLOG.md#dev-step-322) |
| 2026-11-01 | 323 | [Original adjustment-layer functional breadth and source composition](DEVLOG.md#dev-step-323) |
| 2026-11-01 | 324 | [Original layer effects: staged native controls and rendering helpers, unfinished](DEVLOG.md#dev-step-324) |
| 2026-11-01 | 325 | [Diary synchronized with tested323 and unfinished324](DEVLOG.md#dev-step-325) |
| 2026-11-01 | 326 | [Original layer-effects functional qualification and shared Global Light menu](DEVLOG.md#dev-step-326) |
| 2026-11-01 | 327 | [Diary reconciled with tested source, installed preview and remaining major work](DEVLOG.md#dev-step-327) |
| 2026-11-01 | 328 | [Original channels and auxiliary spot workflows functionally qualified](DEVLOG.md#dev-step-328) |
| 2026-11-01 | 329 | [PSD/PSB auxiliary channel interchange functionally qualified](DEVLOG.md#dev-step-329) |
| 2026-11-01 | 330 | [Document guides and source layout import](DEVLOG.md#dev-step-330) |
| 2026-11-01 | 331 | [Xcode archive and alpha store preparation; validation and media pending](DEVLOG.md#dev-step-331) |
| 2026-11-01 | 332 | [Window lifecycle, recovery and updated Xcode archive](DEVLOG.md#dev-step-332) |
| 2026-11-01 | 333 | [App Store validation after Xcode sign-in](DEVLOG.md#dev-step-333) |
| 2026-11-01 | 334 | [Native File Info and source document metadata](DEVLOG.md#dev-step-334) |
| 2026-11-01 | 335 | [Photoshop 2026 as the reference](DEVLOG.md#dev-step-335) |
| 2026-11-01 | 336 | [Layer Comps and production export](DEVLOG.md#dev-step-336) |
| 2026-11-01 | 337 | [Smart Object comp selection](DEVLOG.md#dev-step-337) |
| 2026-11-01 | 338 | [Parent Layer Comp Smart Object choices](DEVLOG.md#dev-step-338) |
| 2026-11-01 | 339 | [Editable PSD/PSB Layer Comps](DEVLOG.md#dev-step-339) |
| 2026-11-02 | 340 | [Editable PSD/PSB Global Light](DEVLOG.md#dev-step-340) |
| 2026-11-02 | 341 | [Production Export As workflow](DEVLOG.md#dev-step-341) |
| 2026-11-02 | 342 | [Layers to Files](DEVLOG.md#dev-step-342) |
| 2026-11-02 | 343 | [Color Range selection](DEVLOG.md#dev-step-343) |
| 2026-11-02 | 344 | [Magnetic Lasso tool](DEVLOG.md#dev-step-344) |
| 2026-11-02 | 345 | [Selection Modify and Reselect](DEVLOG.md#dev-step-345) |
| 2026-11-02 | 346 | [Transform Selection](DEVLOG.md#dev-step-346) |
| 2026-11-02 | 347 | [Selected-pixel Free Transform](DEVLOG.md#dev-step-347) |
| 2026-11-02 | 348 | [Background layer semantics](DEVLOG.md#dev-step-348) |
| 2026-11-02 | 349 | [Background selected-pixel Free Transform](DEVLOG.md#dev-step-349) |
| 2026-11-02 | 350 | [Move and copy selected pixels](DEVLOG.md#dev-step-350) |
| 2026-11-02 | 351 | [Pixel-mask Free Transform](DEVLOG.md#dev-step-351) |
| 2026-11-02 | 352 | [Auxiliary-channel Free Transform](DEVLOG.md#dev-step-352) |
| 2026-11-02 | 353 | [Multi-layer and group transforms](DEVLOG.md#dev-step-353) |
| 2026-11-02 | 354 | [Projective layer transforms](DEVLOG.md#dev-step-354) |
| 2026-11-02 | 355 | [Layer links and whole-layer Move](DEVLOG.md#dev-step-355) |
| 2026-11-02 | 356 | [Color Fill and Stroke](DEVLOG.md#dev-step-356) |
| 2026-11-02 | 357 | [Pattern Fill](DEVLOG.md#dev-step-357) |
| 2026-11-02 | 358 | [Large-document Crop](DEVLOG.md#dev-step-358) |
| 2026-11-02 | 359 | [Layer capacity](DEVLOG.md#dev-step-359) |
| 2026-11-02 | 360 | [Flatten Image](DEVLOG.md#dev-step-360) |
| 2026-11-02 | 361 | [Duplicate Image](DEVLOG.md#dev-step-361) |
| 2026-11-02 | 362 | [Trim and Reveal All](DEVLOG.md#dev-step-362) |
| 2026-11-02 | 363 | [Private full-source backup](DEVLOG.md#dev-step-363) |
| 2026-11-02 | 364 | [Rich layer merging](DEVLOG.md#dev-step-364) |
| 2026-11-02 | 365 | [Linked preview sampling](DEVLOG.md#dev-step-365) |
| 2026-11-02 | 366 | [Quick Mask and saved selections](DEVLOG.md#dev-step-366) |
| 2026-11-02 | 367 | [Saved-selection documents; next major function selected](DEVLOG.md#dev-step-367) |
| 2026-11-02 | 368 | [Quick Mask workflow checks; C01 next](DEVLOG.md#dev-step-368) |
| 2026-11-03 | 369 | [Quick Mask visibility and hidden brush target](DEVLOG.md#dev-step-369) |
| 2026-11-03 | 370 | [Private source backup and next major function](DEVLOG.md#dev-step-370) |
| 2026-11-03 | 371 | [Hidden Quick Mask commands and pixel Invert](DEVLOG.md#dev-step-371) |
| 2026-11-03 | 372 | [Quick Mask target transitions; C01 queued](DEVLOG.md#dev-step-372) |
| 2026-11-03 | 373 | [Mask paint colors and S05 audit](DEVLOG.md#dev-step-373) |
| 2026-11-03 | 374 | [Large saved-selection files](DEVLOG.md#dev-step-374) |
| 2026-11-03 | 375 | [PSB file compatibility](DEVLOG.md#dev-step-375) |
| 2026-11-03 | 376 | [Shared paint colours](DEVLOG.md#dev-step-376) |
| 2026-11-03 | 377 | [App Store listing and media](DEVLOG.md#dev-step-377) |
| 2026-11-04 | 378 | [App Store familiarity wording](DEVLOG.md#dev-step-378) |
| 2026-11-04 | 379 | [Multichannel Quick Mask files](DEVLOG.md#dev-step-379) |
| 2026-11-04 | 380 | [Mask paint-colour contexts](DEVLOG.md#dev-step-380) |
| 2026-11-04 | 381 | [Mask target lifecycle](DEVLOG.md#dev-step-381) |
| 2026-11-04 | 382 | [Current full test inventory](DEVLOG.md#dev-step-382) |
| 2026-11-04 | 383 | [Document lifecycle regression repairs](DEVLOG.md#dev-step-383) |
| 2026-11-04 | 384 | [Animated layer-style transactions](DEVLOG.md#dev-step-384) |
| 2026-11-04 | 385 | [Fit Image and reusable batch constraints](DEVLOG.md#dev-step-385) |
| 2026-11-04 | 386 | [Find and Replace Text](DEVLOG.md#dev-step-386) |
| 2026-11-04 | 387 | [Numeric component-plane storage](DEVLOG.md#dev-step-387) |
| 2026-11-04 | 388 | [Native component blocks](DEVLOG.md#dev-step-388) |
| 2026-11-04 | 389 | [Private source backup](DEVLOG.md#dev-step-389) |
| 2026-11-04 | 390 | [Component archive streaming](DEVLOG.md#dev-step-390) |
| 2026-11-04 | 391 | [Large native component documents](DEVLOG.md#dev-step-391) |
| 2026-11-04 | 392 | [Large component geometry](DEVLOG.md#dev-step-392) |
| 2026-11-04 | 393 | [Large component tools](DEVLOG.md#dev-step-393) |
| 2026-11-04 | 394 | [RGB8 component routing](DEVLOG.md#dev-step-394) |
| 2026-11-04 | 395 | [Private source backup and listing wording](DEVLOG.md#dev-step-395) |
| 2026-11-04 | 396 | [Large native channel arithmetic](DEVLOG.md#dev-step-396) |
| 2026-11-04 | 397 | [Independent channel eyes](DEVLOG.md#dev-step-397) |
| 2026-11-04 | 398 | [Temporary mask channels](DEVLOG.md#dev-step-398) |
| 2026-11-04 | 399 | [Consolidated S05 validation](DEVLOG.md#dev-step-399) |
| 2026-11-04 | 400 | [Quick Mask options and gestures](DEVLOG.md#dev-step-400) |
| 2026-11-04 | 401 | [Quick Mask reference matrix; repair parked](DEVLOG.md#dev-step-401) |
| 2026-11-04 | 402 | [Seven-pass work order](DEVLOG.md#dev-step-402) |
| 2026-11-04 | 403 | [Delete All Empty Layers native baseline](DEVLOG.md#dev-step-403) |
| 2026-11-04 | 404 | [Single-pixel marquee and quick-win audits](DEVLOG.md#dev-step-404) |
| 2026-11-04 | 405 | [Color Lookup export and quick-win audits](DEVLOG.md#dev-step-405) |
| 2026-11-04 | 406 | [RGB8 component selection](DEVLOG.md#dev-step-406) |
| 2026-11-04 | 407 | [Duplicate saved actions](DEVLOG.md#dev-step-407) |
| 2026-11-04 | 408 | [Shape stroke presets](DEVLOG.md#dev-step-408) |
| 2026-11-04 | 409 | [Quick-win source audit](DEVLOG.md#dev-step-409) |
| 2026-11-05 | 410 | [Gradient Fill API and Actions](DEVLOG.md#dev-step-410) |
| 2026-11-05 | 411 | [Last Filter and Pattern Fill audit](DEVLOG.md#dev-step-411) |
| 2026-11-05 | 412 | [Filter Gallery dragging](DEVLOG.md#dev-step-412) |
| 2026-11-05 | 413 | [Brush Settings sidebar controls](DEVLOG.md#dev-step-413) |
| 2026-11-05 | 414 | [Smart Filter dragging](DEVLOG.md#dev-step-414) |
| 2026-11-05 | 415 | [Select Subject options](DEVLOG.md#dev-step-415) |
| 2026-11-05 | 416 | [Selected-mask removal and API](DEVLOG.md#dev-step-416) |
| 2026-11-05 | 417 | [Statistical image stacks](DEVLOG.md#dev-step-417) |
| 2026-11-05 | 418 | [Frame Timeline dragging](DEVLOG.md#dev-step-418) |
| 2026-11-05 | 419 | [Rename sky presets](DEVLOG.md#dev-step-419) |
| 2026-11-05 | 420 | [Rasterization responsiveness](DEVLOG.md#dev-step-420) |
| 2026-11-05 | 421 | [Channel thumbnail options and major quick-win sweep](DEVLOG.md#dev-step-421) |
| 2026-11-05 | 422 | [Arrange selected layers](DEVLOG.md#dev-step-422) |
| 2026-11-05 | 423 | [Layer filtering and isolation](DEVLOG.md#dev-step-423) |
| 2026-11-05 | 424 | [Asynchronous layer content filters](DEVLOG.md#dev-step-424) |
| 2026-11-05 | 425 | [Layer selection and deselection](DEVLOG.md#dev-step-425) |
| 2026-11-05 | 426 | [Customize Save Dialog File Formats](DEVLOG.md#dev-step-426) |
| 2026-11-05 | 427 | [Adjacent artboard controls](DEVLOG.md#dev-step-427) |
| 2026-11-05 | 428 | [Animated selection borders](DEVLOG.md#dev-step-428) |
| 2026-11-05 | 429 | [Transform reference point](DEVLOG.md#dev-step-429) |
| 2026-11-05 | 430 | [Large-document Equalize](DEVLOG.md#dev-step-430) |
| 2026-11-05 | 431 | [Color Lookup output formats](DEVLOG.md#dev-step-431) |
| 2026-11-05 | 432 | [Pattern Patch](DEVLOG.md#dev-step-432) |
| 2026-11-05 | 433 | [Channels footer Save/Load](DEVLOG.md#dev-step-433) |
| 2026-11-05 | 434 | [Batch file naming](DEVLOG.md#dev-step-434) |
| 2026-11-05 | 435 | [Precise shape creation](DEVLOG.md#dev-step-435) |
| 2026-11-05 | 436 | [Extended Fill Path](DEVLOG.md#dev-step-436) |
| 2026-11-06 | 437 | [Character and Paragraph panels — development](DEVLOG.md#dev-step-437) |
| 2026-11-06 | 438 | [Point-text layout and native editing](DEVLOG.md#dev-step-438) |
| 2026-11-06 | 439 | [Direct native path typing](DEVLOG.md#dev-step-439) |
| 2026-11-06 | 440 | [Paged Curves and Levels histograms](DEVLOG.md#dev-step-440) |
| 2026-11-06 | 441 | [Light painting and retouch previews](DEVLOG.md#dev-step-441) |
| 2026-11-06 | 442 | [Gradient creation and portable Actions](DEVLOG.md#dev-step-442) |
| 2026-11-06 | 443 | [Pattern groups and PAT hierarchy](DEVLOG.md#dev-step-443) |
| 2026-11-06 | 444 | [Public repository and Shape Blur development](DEVLOG.md#dev-step-444) |
| 2026-11-06 | 445 | [Public Git history credential audit](DEVLOG.md#dev-step-445) |
| 2026-11-06 | 446 | [Custom Shape Blur numerical investigation](DEVLOG.md#dev-step-446) |
| 2026-11-06 | 447 | [Custom Kernel ACF preset interchange](DEVLOG.md#dev-step-447) |
| 2026-11-06 | 448 | [Blur Gallery mask output](DEVLOG.md#dev-step-448) |
| 2026-11-06 | 449 | [Public source and unpublished build backup](DEVLOG.md#dev-step-449) |
| 2026-11-06 | 450 | [Liquify last mesh reuse](DEVLOG.md#dev-step-450) |
| 2026-11-06 | 451 | [Local build cleanup; lens-default audit](DEVLOG.md#dev-step-451) |
| 2026-11-06 | 452 | [Camera and lens defaults](DEVLOG.md#dev-step-452) |
| 2026-11-06 | 453 | [Custom Filter Gallery textures](DEVLOG.md#dev-step-453) |
| 2026-11-06 | 454 | [Brush pattern textures](DEVLOG.md#dev-step-454) |
| 2026-11-06 | 455 | [Eraser mode reference](DEVLOG.md#dev-step-455) |
| 2026-11-06 | 456 | [Eraser modes](DEVLOG.md#dev-step-456) |
| 2026-11-06 | 457 | [Blur, Sharpen and Smudge blend modes](DEVLOG.md#dev-step-457) |
| 2026-11-06 | 458 | [Content-Aware Fill without leaving the workspace](DEVLOG.md#dev-step-458) |
| 2026-11-06 | 459 | [Eyedropper averaging and source controls](DEVLOG.md#dev-step-459) |
| 2026-11-06 | 460 | [Mask and channel clipboard](DEVLOG.md#dev-step-460) |
| 2026-11-06 | 461 | [Advanced blending channel controls](DEVLOG.md#dev-step-461) |
| 2026-11-06 | 462 | [Saved layer style presets](DEVLOG.md#dev-step-462) |
| 2026-11-06 | 463 | [Smart Object Convert to Layers](DEVLOG.md#dev-step-463) |
| 2026-11-06 | 464 | [Smart Filter stack and mask transfer](DEVLOG.md#dev-step-464) |
| 2026-11-06 | 465 | [Magic Wand averaged sampling](DEVLOG.md#dev-step-465) |
| 2026-11-07 | 466 | [Selection source policy and Magic Wand Subject](DEVLOG.md#dev-step-466) |
| 2026-11-07 | 467 | [Select and Mask source workflow](DEVLOG.md#dev-step-467) |
| 2026-11-07 | 468 | [Layer and Smart Filter mask filtering](DEVLOG.md#dev-step-468) |
| 2026-11-07 | 469 | [Large auxiliary-channel filtering](DEVLOG.md#dev-step-469) |
| 2026-11-07 | 470 | [Split Channels](DEVLOG.md#dev-step-470) |
| 2026-11-07 | 471 | [Large-document soft proofing](DEVLOG.md#dev-step-471) |
| 2026-11-07 | 472 | [Large image stacks](DEVLOG.md#dev-step-472) |
| 2026-11-07 | 473 | [Embedded originals in source projects](DEVLOG.md#dev-step-473) |
| 2026-11-07 | 474 | [OpenEXR HDR files](#dev-step-474) |
| 2026-11-07 | 475 | [Generated image jobs and originals](#dev-step-475) |
| 2026-11-07 | 476 | [Blank video drawing layers](#dev-step-476) |
| 2026-11-07 | 477 | [Sky preset groups and batch import](#dev-step-477) |
| 2026-11-07 | 478 | [Local Color Lookup painting](#dev-step-478) |
| 2026-11-07 | 479 | [Color Lookup property responsiveness](#dev-step-479) |
| 2026-11-07 | 480 | [Independent Color Lookup references](#dev-step-480) |
| 2026-11-07 | 481 | [Repeatable archive validation](#dev-step-481) |
| 2026-11-07 | 482 | [Menu inventory reconciliation](#dev-step-482) |
| 2026-11-07 | 483 | [Script Events Manager](#dev-step-483) |
| 2026-11-07 | 484 | [Quick Mask selection semantics](#dev-step-484) |
| 2026-11-07 | 485 | [Sampled Hue/Saturation ranges](#dev-step-485) |
| 2026-11-07 | 486 | [Classic RGB16 gradient boundaries](#dev-step-486) |
| 2026-11-08 | 487 | [Share the person-selection model](DEVLOG.md#dev-step-487) |
| 2026-11-08 | 488 | [Image styles and canvas size](DEVLOG.md#dev-step-488) |
| 2026-11-08 | 489 | [Native Remove tool](DEVLOG.md#dev-step-489) |
| 2026-11-08 | 490 | [Generated backgrounds](DEVLOG.md#dev-step-490) |
| 2026-11-08 | 491 | [Reference images for generation](DEVLOG.md#dev-step-491) |
| 2026-11-08 | 492 | [Reviewed edit plans](DEVLOG.md#dev-step-492) |
| 2026-11-08 | 493 | [Profile changes on large documents](DEVLOG.md#dev-step-493) |
| 2026-11-08 | 494 | [Directory durability](DEVLOG.md#dev-step-494) |
| 2026-11-08 | 495 | [Paged Warp](DEVLOG.md#dev-step-495) |
| 2026-11-08 | 496 | [PSD vector path semantics](DEVLOG.md#dev-step-496) |
| 2026-11-08 | 497 | [Untagged files and sandboxed copies](DEVLOG.md#dev-step-497) |
| 2026-11-08 | 498 | [Large colour-mode files](DEVLOG.md#dev-step-498) |
| 2026-11-08 | 499 | [Paths to Illustrator](DEVLOG.md#dev-step-499) |
| 2026-11-08 | 500 | [Repair native asset export](DEVLOG.md#dev-step-500) |
| 2026-11-08 | 501 | [Select People on large documents](DEVLOG.md#dev-step-501) |
| 2026-11-08 | 502 | [Report Apple text-service availability](DEVLOG.md#dev-step-502) |
| 2026-11-08 | 503 | [Review people before removal](DEVLOG.md#dev-step-503) |
| 2026-11-08 | 504 | [Background generation on large documents](DEVLOG.md#dev-step-504) |
| 2026-11-08 | 505 | [Edit a reference image](DEVLOG.md#dev-step-505) |
| 2026-11-08 | 506 | [Local learned upscaling](DEVLOG.md#dev-step-506) |
| 2026-11-08 | 507 | [Reviewed adjustment values](DEVLOG.md#dev-step-507) |
| 2026-11-08 | 508 | [AI, language and plugin acceptance](DEVLOG.md#dev-step-508) |
| 2026-11-08 | 509 | [Plugin host requirements](DEVLOG.md#dev-step-509) |
| 2026-11-08 | 510 | [Editable gradient profiles](DEVLOG.md#dev-step-510) |
| 2026-11-08 | 511 | [Gray32 Photoshop file export](DEVLOG.md#dev-step-511) |
| 2026-11-09 UTC | 512 | [Merge Channels](DEVLOG.md#dev-step-512) |
| 2026-11-09 UTC | 513 | [Legacy Macintosh proof](DEVLOG.md#dev-step-513) |


## 2026-10-26 — Step158: editable layer effects

Major-feature breadth continues with ten native effect kinds, a style editor, copy/paste/clear, native persistence and both APIs. Six effect kinds have bounded PSD interchange. Live numeric editing exposed an exclusivity crash that model-only tests missed; the setter was repaired and a regression added. A command-matrix writing error was recovered from preserved evidence; eight filter evidence sentences are explicitly reconstructed. All55 focused Debug and1,498 full Release tests pass, plus30 cases each on arm64/Rosetta and universal package verification. The repaired native workflow passes. Fine contour matching, advanced variants and full Photoshop parity remain open. See [the complete record](DEVLOG.md#dev-step-158).

## 2026-10-26 — Step159: automatic subjects and backgrounds

The next broad workflow uses Apple's local Vision model to select foreground subjects or create an editable layer mask. Original pixels stay editable; native history and both API interfaces use the same engine.56 focused checks pass, including cancellation and revoked sharing. The real model removes the icon background and native Select Subject/Undo works. A mask-focus callback guard found by testing was repaired. The Mac locked before the remaining live mask check; all1,510 full Release tests and the universal macOS 14+ package verify. Final parser/default repair passes26 focused tests, with platform model results preserved separately. Intricate edges and the rest of object/sky/people selection remain open. See [the development record](DEVLOG.md#dev-step-159).

## 2026-10-26 — Step160: embedded Smart Objects

The next major workflow preserves the original source behind a rendered layer. Resize/rotate retains source samples; ordinary copies share content, while New Smart Object via Copy stays independent. Native Edit Contents opens a child document and Save updates its parent through Undo. Placement, replacement, source export, native14 persistence and an affine PSD/PSB subset share the Photato/Adobe API engine.57 integration tests and14 final focused tests pass. All1,524 full Release tests,36 checks per architecture and the universal macOS 14+ package verify. The Mac remains locked for live checks; no independent Photoshop Smart Object fidelity claim is made. Linked sources, warp, richer source formats and Smart Filters remain open. [Complete record](DEVLOG.md#dev-step-160).

## 2026-10-26 — Step161: editable Smart Filters

Eight native filters now remain editable over original Smart Object sources. Layers expose filter settings, per-filter blending/visibility/order and a shared paintable mask; ordinary layers retain baked filters. Native15, history, Photato automation and published Adobe execute-actions share the same engine. Seven filter types have bounded PSD/PSB descriptor/cache mappings; unsupported exports fail explicitly.67 integration checks pass. All1,536 final Release tests,87 checks per architecture and the universal macOS 14+ package verify. The first Release run exposed one outdated archive-version test; its two expectations were corrected before the passing full rerun. All failed compile attempts remain recorded; no independent Photoshop or live UI claim while the Mac is locked. The next major workflow is native text editing; numerical refinements remain deferred. [Complete record](DEVLOG.md#dev-step-161).

## 2026-10-26 — Step162: native text editing

The basic text stamp is now a native point/paragraph editor with caret selection, mixed character formatting, paragraph controls, local typing Undo and a single committed document edit. Native16, two Photato commands and a published Adobe create-composite subset preserve editable content. A bounded Swift port of upstream TySh/EngineData supports native-generated PSD/PSB round trips. Compilation and runtime failures are preserved, including a missing NSTextView text system initially mistaken for a Redo failure; an explicitly owned TextKit stack repaired it. All54 integration tests pass. All1,548 final Release tests and48 checks per architecture pass, and the universal macOS 14+ package verifies. The first full Release run exposed one obsolete PSD type-rejection test, corrected before the passing rerun. Independent Photoshop/live UI and advanced typography remain open; major-feature breadth continues with classic adjustments. [Complete record](DEVLOG.md#dev-step-162).

## 2026-10-26 — Step163: Classic adjustment workflows

Five missing classic adjustments now share native Properties/dialog controls, selection masks, history, native17 saving and three typed Photato commands. The source approximations were translated from Rust with explicit validation. Nine factory menu commands are newly bound; the newer Color and vibrance layer remains open because its white-balance controls are additional functionality. PSD/PSB carries editable supported records; Adobe action jobs and the published /v2/edit color subset use the same Swift engine. Test failures exposed an omitted archive-header version discriminator and stale catalogue/fixture expectations; each attempt is retained. All46 integration tests pass. All1,559 final Release tests and90 checks per architecture pass; universal macOS 14+ packaging verifies. The first full run found11 stale catalogue/version expectations. Those were corrected, and a review also added a missing prepared API creation-limit check with an atomicity test;36 final focused checks pass. Exact Photoshop output, richer Photo Filter transport and live UI remain open. [Complete record](DEVLOG.md#dev-step-163).

## 2026-10-26 — Step164: Color Lookup workflow

Color Lookup now has a usable native grading workflow: import Cube/3DL/LOOK, choose generated Photato looks, preview or create editable layers, and retain masks/settings/history in native18. Source-domain and nonuniform shaper information survive import and save. Photato APIs upload bounded LUTs, create/set/apply adjustments and download original LUT files; Adobe execute-actions uses the shared native engine for a bounded inline descriptor subset. PSD/PSB supports loaded Trilinear LUTs. No Adobe preset files are redistributed. Two compile failures and an incorrect Adobe test-request envelope were repaired with their logs retained. All34 focused tests pass; 1,569 full Release tests passed, followed by a PSD name/format metadata correction,35 final focused Release checks and27 cases per architecture. The final universal macOS 14+ package verifies. Both source snapshots and packages are retained. Live UI, exact Photoshop grading, ICC/CSP and richer interchange remain open. [Complete record](DEVLOG.md#dev-step-164).

## 2026-10-26 — Step165: Native Liquify workspace

The major-feature queue moves to Liquify. PhotoCraft’s inverse displacement grid now has native Swift brushes, freeze masks, reconstruction and mesh-program persistence, alongside a dedicated macOS workspace. Local Vision landmarks feed independent face controls. Pixel-layer editing and editable Smart Filters use shared history, native19 saving and the typed API; face detection is a read-only API command. Compilation/test fixture failures and their repairs are preserved in DEVLOG. All53 Debug focused,1,583 full Release tests before identity repair,71 final Release checks and29 public checks per architecture pass; the universal macOS 14+ package verifies. Real local Vision requests on a nonface image complete on both architectures; portrait quality remains unqualified. Photoshop mesh files/PSD descriptors, Adobe Liquify actions, exact numerical behavior and live checks stay open. [Liquify development record](DEVLOG.md#dev-step-165)

## 2026-10-26 — Step170: Crop and content-aware edges

The Crop tool now has an expandable boundary, rotation/straighten line, common aspect ratios, retained/deleted raster pixels and transparent/background/content-aware extension. Preview, cancellation, one-step undo and API use the same native implementation. Generated edge pixels remain on an editable layer; interior transparency is retained. A redundant mask-coordinate calculation and a synthetic event-coordinate test were repaired; all 47 focused tests pass. The first full run exposed two outdated API counts; these and the shared Image > Crop integration are covered by the final 1,637 passing Release tests. The universal macOS 14+ package verifies. Exact Photoshop rendering, advanced presets/settings and live/platform checks remain open. Patch, Content-Aware Move and Red Eye are next. [Complete development record](DEVLOG.md#dev-step-170).

## 2026-10-26 — Step169: Content-Aware Scale

Native seam carving now shrinks or enlarges a raster layer or selected pixels while retaining protected content. The existing canvas transform controls add reference-point, Amount, saved alpha-channel and skin-tone options; preview, cancellation and one-step undo share the engine with the API. The factory shortcut is connected. A compile-time error-property assignment was repaired, and all 25 focused engine, desktop/API, menu and transform tests pass. A procedural output comparison was inspected. The universal macOS 14+ package verifies. Photoshop numerical equality, nonlinear mask deformation and live/platform qualification remain open. Content-aware crop fill is next. [Complete development record](DEVLOG.md#dev-step-169).

## 2026-10-26 — Step168: Content-Aware Fill workspace

The next major workflow now has native sampling and selection brushes, a preview, color/rotation/scale/mirror adaptation, current/new/duplicate-layer outputs, cancellation and undo. The desktop and `contentAware.fill` API share the Swift implementation derived from the licensed Rust source. A compile error and an AppKit test-controller initialization crash were repaired; all 30 final focused tests pass. A procedural before/after image was inspected. The universal macOS 14+ package verifies. Exact Photoshop output, live interaction, cross-document sampling and finer workspace controls remain open. Content-Aware Scale and crop fill are next. [Complete development record](DEVLOG.md#dev-step-168).

## 2026-10-26 — Step167: Alpha channels and Quick Mask

The maintainer reinforced breadth over fine fidelity. Persistent grayscale channels, saved selections, painting/filtering, Quick Mask, native20 saving and history now work through the native UI and two typed API operations. Three Select commands and Q are connected. Three compile failures and repairs are retained;47 initial and73 final focused tests pass. The final universal macOS 14+ package and28 refresh-repair tests pass. PSD/spot channels, cross-document operations and independent/live fidelity remain open. Full-suite and platform qualification are batched. Content-Aware Fill is next. [Complete development record](DEVLOG.md#dev-step-167).

## 2026-10-26 — Step166: Native Select and Mask workspace

A major selection workflow now has a native Swift matting engine and workspace: guided edge detection, global refinements, decontamination, brushes/lasso, subject selection, local history and six output choices. The factory menu/shortcut and existing selection/mask controls open it. The Photato API shares the engine and prepared document history; new-document outputs require transfer permission and leave the source untouched. Compilation repairs, the missing decontamination-preview correction and their passing focused tests are preserved. Offscreen captures have unreliable native-control compositing and are not accepted visual qualification; live work awaits unlock. All47 initial/12 repaired focused checks and1597 final full Release tests and54 checks per architecture pass; the universal macOS 14+ package verifies. Adobe proprietary hair/Object Aware algorithms, action descriptors, exact output and broader contexts remain open. Next major workflow: channels, saved selections and Quick Mask. [Complete development record](DEVLOG.md#dev-step-166).


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

Validation found and fixed a missing shared const-schema rule, outdated command-count assertions and an out-of-canvas test fixture. Final API review corrected an assumed mask endpoint by adding density/feather operations and updated action-library version descriptions. Failed attempts remain saved. All 156 focused Debug and156 focused optimized checks pass. Full regression and universal packaging are batched with the next major selection increment; the last verified package190 does not contain191. All1444 frozen inputs,754 original Rust files and four protected files verify. Photato.xcodeproj remains present/unchanged. The desktop remains locked; no live UI comparison or physical platform qualification is claimed. Full presets, newer adjustment types, exact pixels/models and richer Adobe compatibility remain open. Major feature work continues with Object Selection, Quick Selection and Selection Brush; fine numeric/cosmetic work waits.

[Development details](DEVLOG.md#dev-step-191), [checkpoint191](ACTIVE_CHECKPOINT_191.json), [Adjustment Brush evidence](ADJUSTMENT_BRUSH_REFERENCES.json).

## 2026-10-27 — Step192: three major selection tools

Object Selection now supports rectangle/lasso initialization through native graph cut and clicked-object targeting through Apple's local Vision adapter. Quick Selection follows image boundaries from painted seeds. Selection Brush paints editable soft coverage with a colored overlay. The graph, mixture model, geodesic costs and boundary refinement were translated from the preserved MIT/Apache PhotoCraft sources into Swift, with attribution and native cancellation/work limits. Source images remain unchanged; existing masks, history and Select and Mask workflows consume the result.

Four typed API commands expose configuration and all three tools through the same native transaction, with discoverable state/result schemas and request lifecycle guards. Actions version4 retains explicit coverage on its original canvas; replay does not silently redetect objects. Native archives remain32. Tests include independent exhaustive small-graph cuts, textured segmentation fixtures, reduced-resolution recut, offscreen/synthetic interaction, soft coverage at 8/16/32-bit, current/composite sampling, cancellation and native/HTTP equality. No test attempt failed; one stale-context patch made no changes and was reapplied correctly. Validation also corrected stale overlays on tool changes and the API's omitted Object Selection mode fallback.

All155 broad focused Debug checks,7 final dedicated workflow checks and1876 full optimized tests pass. The universal macOS 14+ package verifies and includes191 Adjustment Brush. All1455 frozen inputs, four protected files and754 original Rust hashes verify. The Xcode project remains present and unchanged. Source deltas, build/signature evidence and prior attempts are retained. No live desktop qualification was possible because the last authoritative desktop state remains locked. Photoshop byte/model equivalence, broader finder/People workflows and platform qualification remain open. Continue major workflow breadth with Sky Selection and Sky Replacement.

[Development details](DEVLOG.md#dev-step-192), [checkpoint192](ACTIVE_CHECKPOINT_192.json), [selection references](SELECTION_TOOL_REFERENCES.json).

## 2026-10-27 — Step193: Sky Selection and Sky Replacement

Select > Sky now runs the source-derived detector in Swift. Edit > Sky Replacement opens a native preview with imported skies or a raster layer source, sky placement, manual Add/Subtract mask brushing, edge refinement, sky brightness/temperature and foreground color/light controls. Output preserves the original layers and either adds editable masks/transforms/adjustments or a merged duplicate. The user sky library persists atomically and reports invalid files instead of overwriting them. The classical detector is not represented as Adobe AI, and no proprietary sky assets were copied.

Three Photato commands expose selection, replacement and sky-library management with strict discovery schemas, observable state, document/library revisions and the same prepared history path as the desktop. Select Sky records explicit coverage in Actions4; replacement recording remains visibly unsupported. The Adobe contract has no dedicated sky route. Native archive32 and the Xcode project remain unchanged.

The development record preserves failed compilation, test assumptions and a metadata-validation defect that blocked output. The attempted arbitrary sourceTags metadata was removed; existing native layers retain editability. Follow-up tests verify no-sky/manual fallback, all depths, canvas gestures, preview/local/document Undo, read/close cancellation, native/API equality, valid source-layer strokes, selection combinations, library corruption and stale/busy/revoked requests. The only retained numerical discrepancy is Float32 duplicate recomposition at up to2.98e-8 in the synthetic fixture; integer-depth samples match. The functional tolerance is1e-7, with exact bytes explicitly deferred under the maintainer's major-first priority. The renderer was not changed to chase that detail.

A documentation helper used the wrong CSV column and partially wrote the command matrix. The partial file was preserved; reconstruction from earlier backups/update blocks exactly matched final192's recorded hash before applying the one intended change atomically. All645 prior rows remain. The first recovery attempt stopped before writing because an obsolete626-row assertion failed; both helpers remain evidence.

All113 focused Debug and113 optimized tests pass. The universal macOS 14+ package verifies. Last full regression is1876 passing tests at192; the next major batch will broaden again. All1464 frozen inputs, four protected files and754 original Rust hashes verify. Fresh package extraction confirms both architectures, macOS 14 minimum, ad-hoc signature, licenses and icon. The offscreen synthetic preview is readable; no live desktop test was performed because the latest authoritative desktop state remains locked. Exact/model/preset/Actions/full-context/platform requirements remain open. Next is Focus Area, followed by Mask All Objects; numerical and cosmetic work stays deferred.

[Development details](DEVLOG.md#dev-step-193), [checkpoint193](ACTIVE_CHECKPOINT_193.json), [sky references](SKY_REFERENCES.json).

## 2026-10-27 — Step194: Focus Area

Focus Area now selects sharp regions using a native Swift translation of PhotoCraft's local Laplacian-energy detector, normalization, guided cleanup and upsampling. The source's range direction contradicted Adobe's documented interface, so the native controls deliberately increase strictness as range rises; manual zero selects the entire image. Auto range/noise estimates are transparent native heuristics, with exact Adobe algorithms/defaults still unqualified. Attribution preserves the original MIT/Apache provenance.

The existing refinement workspace supplies the preview, Add/Subtract brushes, view modes, local history and six selection/mask/layer/document outputs. Focus controls add Auto/manual range/noise and Soften Edge. Turning Auto off preserves the displayed estimate. Preview can show the unmodified image. Select and Mask handoff keeps corrected coverage in the draft without changing the source until OK. Native document reload/close cancels pending analysis and cannot commit late results.

Select > Focus Area is bound in the captured menu position. The new selection.focus API uses strict settings/stroke schemas, requested/effective workspace state, shared native preparation/history and existing new-document permission/revision/lifecycle guards. Selection output records coverage in Actions4; nonselection output remains explicitly unsupported for recording. Native archive32 and the Xcode project are unchanged. No dedicated Adobe endpoint or focus actionJSON conformance is claimed.

The first core and integration runs passed. Expanded controls exposed a Swift exclusivity compile error; the failed attempt is preserved and the settings copy repaired. Code review also found hard-mask output could resurrect discarded tiny components at the soft-field threshold; hard output now uses cleaned binary labels, with a focused regression. Six core and seven new workflow tests cover sharp/blur/noise/flat/depth/cancellation, six native/API outputs, source and archive preservation, transforms/locks, sampling independent of prior selection, controls/brush/handoff, new-document/read/close lifecycle and invalid/stale/busy/revoked requests. The offscreen synthetic preview is readable; it is not live desktop evidence.

All83 final focused Debug and1903 full optimized tests pass. The universal macOS 14+ package verifies and includes193 Sky workflows. All1470 frozen inputs, four protected files and754 original Rust hashes verify. Fresh extraction checks both architectures, macOS 14 minimum, signature, version, licenses and icon. No installed/root app replacement, publication, commit or user settings change occurred. The original full Photoshop objective remains active. Next: Mask All Objects with separate editable per-object mask groups, followed by broader object-selection workflows; numerical/cosmetic refinements remain deferred.

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

All70 final focused Debug and1920 full optimized tests pass. The universal macOS 14+ package verifies and includes195 Mask All Objects. Real local Vision detect/hit/select/save/Undo succeeds. All1480 frozen inputs,754 Rust source hashes and four protected files verify. Five code/test files were added,13 inputs modified and none removed. Universal extraction verifies arm64/x86_64, macOS 14 minimum, signature, version, licenses and icon. The Xcode project, root/installed app, user settings and version remain unchanged. Source and package identities are recorded in checkpoint196;195 evidence is annotated with this subsequent full qualification while its original checkpoint stays immutable.

The next major workflow is Select People. Adobe’s February23 workflow describes a thumbnail picker and whole-person/feature selection; the public Apple SDK supports person-instance masks on macOS 14. It does not itself provide semantic hair/beard/skin parts. The saved plan requires capability/model verification and honest unavailable parts rather than generic shapes presented as precise selection. No live desktop re-probe occurred while the desktop remains locked.

[Development details](DEVLOG.md#dev-step-196), [checkpoint](ACTIVE_CHECKPOINT_196.json), [references](OBJECT_FINDER_REFERENCES.json).

## 2026-10-27 — Step197: Select People

The native Object Selection options now open a person picker backed by Apple's macOS 14 person-instance request. It detects people separately from ordinary foreground objects, creates bounded thumbnails and previews actual masks on the canvas. Choose one or several people, apply New/Add/Subtract/Intersect with optional Hard Edge, or hand the resulting selection to Select and Mask for manual refinement. Hover, detection and picker state do not dirty the document; applying the union uses one Undo and Actions4 explicit coverage. Native32 remains unchanged.

Three matching APIs expose detection, hover and selection, with optional full-canvas UInt8 mask export and96px PNG thumbnails. Strict cache IDs, source/sample/layer/tool invalidation and cancellation/read/close/revocation guards keep results tied to the current image. Empty detections return an empty ready list; model failures remain visible. Hair/skin/facial features are explicitly unavailable because the Apple request does not provide those semantic labels. No new Adobe route or model equality is claimed.

The first compile found a SwiftUI binding through an immutable workspace reference. A mistakenly gated repair command did not apply before the second attempt; both failed logs remain. Explicit get/set binding repaired it. Seven new imaging/workflow tests plus shared selection/API regression coverage pass. Offscreen overlays are readable, but some unshown native controls remain blank, so full live/control rendering is not qualified. The desktop remains locked and was not re-probed.

All46 focused Debug and46 optimized tests pass;9 optimized menu checks also pass. Real local Vision finds1 person in a portrait and2 in an overlapping two-person photo; selection, source retention, native save and Undo/Redo succeed. Latest full1920-test/universal baseline196 excludes197. Timings in the model report include selection/archive/overlay work, not just inference. NASA images stay in local evidence with attribution/use provenance; they are not bundled or published. All1485 frozen inputs,754 original Rust hashes and four protected files verify. Five files added, nine modified inputs, none removed. Xcode project/version/root and installed apps/settings remain unchanged. Broad/full/universal qualification stays batched. Next: evaluate and verify a suitably licensed semantic model through native Core ML before exposing hair/skin/clothes classes; fine cosmetic/numerical details stay deferred.

[Development details](DEVLOG.md#dev-step-197), [checkpoint](ACTIVE_CHECKPOINT_197.json), [references](PEOPLE_SELECTION_REFERENCES.json).

## 2026-10-27 — Step198: people feature segmentation

The native person picker now selects hair, face skin, body skin, clothes and accessories, independently or together, for selected people. Feature probability maps intersect Vision person instances; the existing selection modes, Hard Edge, refinement, Undo/Redo, Actions4 and native32 archive paths remain shared with the API. Missing or failing optional model resources leave whole-person selection available and disclose feature availability/errors. Fine facial labels remain unavailable.

Google's official Apache2.0 MediaPipe multiclass256 model was pinned by source SHA, with embedded class, normalization and SOFTMAX metadata verified. An independent bounded graph converter produces a macOS 14 Core ML MLProgram; the deployed app uses only Swift and Apple frameworks. Offline Python/TensorFlow tools regenerate the ignored resource and record provenance. Twelve comparisons, including photographs on CPU/all compute, match original-runtime classifications within declared numerical tolerances. The first converter failed on a scalar reduction axis; the first Swift build failed actor isolation. Both failures and passing repairs are preserved. Actual Swift inference matches original photo probabilities within0.000006974, and one/two-person selection/save/Undo checks pass. Native overlays were inspected; no pixel-perfect Adobe or live-desktop claim is made.

All61 focused Debug and1933 full optimized tests pass. The universal macOS 14+ package includes197 Select People and the native feature model; fresh extraction verifies both architectures, signature and model provenance. Xcode Debug build also passes. All1502 frozen inputs match the workspace/isolation. Seventeen newly covered inputs include existing NOTICE/.gitignore, generated native resources and new tooling; ten previously covered inputs changed and none were removed. NOTICE/.gitignore were modified, not newly created. The Xcode project deliberately gains a verified optional model resource phase; original bytes are retained. Root app/ZIP, user settings and754 original Rust hashes remain unchanged. No version change, publication or installation occurred. Independent platform, exact/model/default/persistence and live UI qualification remain open.

Next is G03 live shape drawing/editing, with native UI, history, persistence and API as one workflow. Existing rectangle/ellipse/path foundations and original Rust live-shape code can be reused; proprietary shape-library assets will not be copied. Fine semantic-mask and numerical/cosmetic refinement remains deferred under the major-first scheduling instruction.

[Development details](DEVLOG.md#dev-step-198), [checkpoint](ACTIVE_CHECKPOINT_198.json), [references](PEOPLE_FEATURE_REFERENCES.json).

## 2026-10-27 — Step199: native live shapes

The legacy rectangle/ellipse fill-only mouse-up path now uses native live geometry shared by seven tools: rectangle, ellipse, triangle, polygon, star, line/arrows and custom shapes. Retained components support boolean drawing, individual corners and parameter editing; fills and strokes support none, solid, gradient and embedded pattern paints, with alignment/dash/cap/join controls. Native properties preview and cancellation, shape/path/pixel output, custom preset definition/import/export, U-group integration, native33 saving and Actions5 shape recording accompany three API commands. Rasterize Shape uses the existing native raster/API engine. Rust geometry provenance remains explicit; no Adobe artwork/presets are redistributed.

Initial compiler/fixture failures were preserved and repaired. A background stack overflow revealed that nested Frame commands allocated the large primitive command dispatcher twice; indirect shape enum storage helped but did not resolve it. Separating modular dispatch from the primitive switch fixed the underlying nesting problem without dropping protection validation. A reused dictionary-only API decoder also raised an Objective-C exception for mode strings; the shape decoder now explicitly supports typed JSON fragments. All failed runs and diagnostic stacks remain in the199 evidence directory.

All80 focused Debug and1944 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1511 frozen inputs match the workspace and isolation;9 files added,26 changed and0 removed. Root app/ZIP, Xcode project, workspace preferences and754 original Rust source hashes remain unchanged. Native events and offscreen snapshots demonstrate functional integration; locked-session native chrome/text does not fully render in those snapshots, so no live visual qualification is claimed. Full editable PSD/.csh/gradient cross-profile transfers and precise Adobe output/default parity remain open. No version bump, installation, publication or commit occurred.

Next is the missing major Pen/Paths workflow. Fine shape rasterization/default/cosmetic refinements remain deferred under the maintainer's major-first instruction.

[Development details](DEVLOG.md#dev-step-199), [checkpoint](ACTIVE_CHECKPOINT_199.json), [references](SHAPE_REFERENCES.json).

## 2026-10-27 — Step200: native Pen and Paths

Freeform and Curvature Pen now join the P tool group. Freeform previews sampled geometry, fits editable cubic handles on release, extends endpoints and cancels without history. Curvature clicks interpolate smooth anchors, double-click toggles corners, clicking the first point closes a contour and anchors remain draggable. The Paths panel exposes selection tracing with tolerance, foreground fill and current-brush stroke with optional pressure simulation. All share existing saved/work paths, vector masks, native persistence and Undo. Five typed API commands expose the same engines, geometry, settings and state. Rust marching squares/fitting provenance is recorded.

Two compile attempts caught a shadowed error assignment and a test whitespace error. The first runtime suite exposed a shared API guard that rejected selected paths; a narrowly scoped path-context option repaired that without removing channel/mask/busy/revocation protection. Preserved failed attempts remain under the200 run directory.

All100 focused Debug and1951 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1518 frozen inputs match workspace/isolation;7 additions,12 modifications and0 removals are enumerated in changes01.json. Protected root app/ZIP, Xcode project, workspace preferences and754 original Rust hashes remain unchanged. Synthetic native events are functional evidence; the locked desktop was not re-probed. Full G04, exact Photoshop curve/pressure kernels, magnetic pen, multiple-anchor editing, advanced Fill/Stroke options, clipping exports and semantic Actions remain open. Next major breadth is multilingual/OpenType typography. No installation/publication/commit or version bump occurred.

[Development details](DEVLOG.md#dev-step-200), [checkpoint](ACTIVE_CHECKPOINT_200.json), [references](PATH_WORKFLOW_REFERENCES.json).

## 2026-10-27 — Step201: native advanced typography

Vertical Type joins the T tool group with native editable point/paragraph text. Properties exposes OpenType features, variable axes and a language tag; the Glyphs panel pages installed fonts and inserts retained glyph identities at the text cursor. Font discovery and glyph insertion have typed APIs, while text creation/editing exposes the same options. The published Adobe text adapter accepts vertical orientation and small capitals through existing contract fields. Native34 and Actions6 retain advanced metadata; the bounded PSD subset retains orientation and represented flags and rejects metadata it cannot preserve.

The first two compile attempts caught CoreText option-set syntax and API range-type conversions. Focused runtime tests caught missing version34 reader allowlists. An initial ligature expectation used a font that did not provide that substitution on this host; an independent six-font probe established HelveticaNeue as the valid regression font. A new downgrade test needed property-list parsing. Final review repaired paragraph formatting loss on glyph insertion through shared desktop/API construction. Failed attempts and repairs remain individually saved.

All 70 focused Debug and 1959 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1524 source inputs match workspace/isolation;6 additions/23 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Tests prove host native rendering, metadata/Undo/API behavior and source-derived codec round trips; no live desktop, independent Photoshop output or physical platform certification is claimed. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. T04 path/warp text is next; minor utilities and exact/cosmetic refinements remain deferred.

[Development details](DEVLOG.md#dev-step-201), [checkpoint](ACTIVE_CHECKPOINT_201.json), [references](ADVANCED_TYPOGRAPHY_REFERENCES.json).

## 2026-10-27 — Step202: editable shaped text

Text can follow a saved path, fit inside a closed shape, use fifteen preset warps, or dynamically fit Block, Circle, Arch and Bow layouts. A native workspace retains rich text beside the curved preview, layout controls, local Undo, canvas preview and one document transaction. Logical-origin compensation prevents normalized glyph bounds from moving the text anchor or its mask. The native API exposes the same layout engine through text.layout and complete text descriptions. Native35 and Actions7 retain geometry; unsupported editable PSD output fails explicitly.

The first five compile attempts caught Core Foundation casting, a test initializer, Observation declarations/initialization, a mutable detached-task capture and API helper mismatches. Runtime checks then found two inconsistent HTTP input error codes and an older test still rejecting newly supported archive35. Each attempt and repair is retained. Offscreen diagnostics show all seven layouts; the hidden-window native sheet is synthetic evidence, not a live desktop check.

All 89 focused Debug and 1966 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1530 frozen inputs match workspace/isolation;6 additions/27 modifications/0 removals are enumerated in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and the Xcode project remain unchanged; no installation, publication or commit. Full T04/Photoshop equality remains open. Filter Gallery is the next major family; minor typography utilities and numerical/cosmetic refinements remain deferred.

[Development details](DEVLOG.md#dev-step-202), [checkpoint](ACTIVE_CHECKPOINT_202.json), [references](SHAPED_TEXT_REFERENCES.json).

## 2026-10-27 — Step203: native Filter Gallery

The47 original artistic effects are now Swift kernels with a native gallery workspace: category thumbnails rendered from the actual layer, parameter and color controls, effect ordering/visibility, before-after preview/zoom, local Undo and one document commit. Smart Objects retain source pixels and editable effects. Existing native filter APIs and Actions/Batch share the same command; native36 and Actions8 prevent older formats from silently discarding Gallery metadata. Exact Adobe ActionJSON and editable PSD mappings remain explicitly unsupported.

The first compile found a duplicate decoder variable. New engine/workspace/API tests then passed; broader regression checks found older assumptions that every filter used native15 or supported Adobe/PSD descriptors. Those qualification lists were corrected. An independent adapter executed the original unmodified Rust kernels and helper bodies, producing47 synthetic default fixtures: the Swift results match every RGBA8 byte. This is source-port evidence, not Photoshop equality. A hidden-window image verifies readable controls and layout; it is not a live desktop check.

All42 focused Debug and1973 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1589 frozen inputs match workspace/isolation;59 additions/20 modifications/0 removals are listed in changes01.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged; no installation, publication or commit. The next major family is Smart Sharpen/Reduce Noise; minor variants and exact numerical/cosmetic polishing stay deferred.

[Development details](DEVLOG.md#dev-step-203), [checkpoint](ACTIVE_CHECKPOINT_203.json), [references](FILTER_GALLERY_REFERENCES.json).

## 2026-10-27 — Step204: paused with a current dashboard

The maintainer paused development after the verified Filter Gallery checkpoint and asked to see remaining work. The master goal is paused. Preserved exact package/source identity and the next Smart Sharpen/Reduce Noise plan. A current expandable dashboard distinguishes81 major,21 minor and3 final broad packages from285 partial/360 pending command statuses and282 wired/443 unavailable menu commands. Existing functions still need qualification inside those broad packages, so these are not percentage-complete estimates. The October9 snapshot remains unchanged. No application source or package changed.

[Pause checkpoint](PAUSE_CHECKPOINT_204.json), [development record](DEVLOG.md#dev-step-204).

## 2026-10-27 — Step205: investigation paused, live dashboard reopened

A brief resumed Smart Sharpen/Reduce Noise source investigation produced no application changes or new builds. The maintainer requested pause again; the goal is paused and checkpoint203 remains the last verified implementation. Saved the exact next-major work and opened the existing live dashboard against the current project. Its105 open broad packages include implemented capabilities still awaiting strict parity qualification. Source and package hashes remain unchanged.

[Pause checkpoint](PAUSE_CHECKPOINT_205.json), [development record](DEVLOG.md#dev-step-205).

## 2026-10-27 — Step206: native photo detail workflows

The maintainer explicitly resumed development. Smart Sharpen and Reduce Noise now have native controls, preview at Fit/100%, Cancel/local Undo, one document commit and editable Smart Filters. Gaussian sharpening and guided denoising follow the original Rust approach; Lens/Motion use actual native disk/line deconvolution. Tonal fades, JPEG-grid softening and additional RGB channel denoising are available. Native37/Actions9 and the shared Photato API retain the new settings. Exact Adobe descriptors and editable PSD remain unqualified and reject explicitly.

The first compile exposed grouped Observation properties; splitting them repaired it. Integration tests initially referenced two wrong API names; these were corrected with failures retained. All45 focused checks pass, including noise/edge behavior, blur direction, depth/alpha, desktop/API equivalence, history, persistence, cancellation and rejection guards. Both offscreen panels were inspected. An API review also caught unnecessary internal fields in the preview-state payload. The first full build was stopped and retained, then the payload and a public round-trip check were repaired before restarting. All45 final focused Debug and1980 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1595 frozen inputs match the tested source;6 additions/19 modifications/0 removals are listed in changes02.json. Four protected files and754 original Rust hashes remain unchanged. Application0.2.0build2 and Xcode project unchanged. The next major workflow plan covers Lens Blur depth maps and iris controls.

[Development record](DEVLOG.md#dev-step-206), [scope and evidence](PHOTO_DETAIL_REFERENCES.json).

[Verified checkpoint206](ACTIVE_CHECKPOINT_206.json).

## 2026-10-27 — Step207: native Lens Blur

Implemented iris/depth/highlight/noise controls with native preview, focus picking, local history, one commit and API support. Live mask/channel references remain editable; invalid sources or source deletion reject. Native38 and Actions10 preserve settings. Adobe excludes Lens Blur from Smart Filters, so Photato's editable version is explicitly a native extension.

All53 focused and1990 full optimized tests pass. Early failures, including a real background stack overflow in nested Smart Filter mask dispatch, were preserved and repaired. Offscreen layout was inspected. Production packaging was batched with the user's208 title/overflow fixes; the combined208 universal package now verifies. Full Photoshop parity remains open. [Evidence](LENS_BLUR_REFERENCES.json).

## 2026-10-27 — Step208: title and viewport corrections

The user requested `Photato - <current doc name>` and supplied a screenshot of canvas content covering window controls. Read-only live inspection and a failing pixel-boundary regression confirmed the overflow. Added view/layer clipping and a saved CGContext clip around the full draw pass. Window titles now update with active tabs and document names; native API state exposes the same title. The first resized fixture misinterpreted bitmap Y coordinates; its repaired rerun proves no pixels escape the viewport. Failure evidence is preserved.

All 59 focused Debug and 1,991 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction, including both architectures, signature, icon/licenses and optional model provenance. All1,601 frozen inputs match workspace/isolation; one test file added, six files modified, none removed. Four protected files and754 original Rust hashes remain unchanged. Separate current Debug live checks cover title,200% zoom, horizontal/vertical scrolling and actual native window resizing. No user document input/edit/save; validation app exited. Application0.2.0build2 and Xcode project unchanged. The current Lens Blur work is included in this package. [Evidence](WINDOW_PRESENTATION_REFERENCES.json), [checkpoint208](ACTIVE_CHECKPOINT_208.json).

## 2026-10-27 — Step209: Photato identity cleanup

At the maintainer’s request, removed the retired family identity from About, demo names, project documentation, the diary and archived text copies. Photato retains its own name, supplied icon and original PhotoCraft attribution. Renamed owned TIFF fixture group metadata without changing image samples. All50 focused checks pass, including TIFF decoding/pixels, gradient presets, support links and window/viewport regressions. The refreshed universal macOS 14+ app verifies after extraction; its contents have no retired branding. Earlier208 full1991-test results remain historical. Archived signed binaries and screenshots are retained as historical evidence. The repository stays private until the software’s release day, when it will become public.

## 2026-10-27 — Step210: the developer diary on the website

The maintainer requested an elegant way to read the developer diary from the Photato website. The website now presents210 dated, expandable entries with local search, chronological sorting, keyboard access, stable per-entry links and a downloadable narrative diary. The existing Forensic Intelligence visual style is retained. Desktop and320/390px mobile views were inspected; search, empty state, sorting, permalinks and mobile navigation pass with no browser warnings/errors. The GitHub repository already exists; it remains private during development and will become public on the same day the software is released. The website is saved locally for the maintainer to publish.

## 2026-10-27 — Step211: private GitHub development build

At the maintainer's request, the verified universal macOS 14+ development build is now attached to a private GitHub draft release. It includes Lens Blur, the document window title and canvas containment fixes, and the current branding cleanup. The repository remains private until software release day.

A fresh extraction verifies the signature, executable hash and both architectures. All four uploaded assets were downloaded again and their hashes match. The package is ad-hoc signed, not notarized or App Store signed. The 50 focused tests apply to this snapshot; the preceding 1,991-test full run is historical. Full Photoshop parity and the physical platform matrix remain open. The release notes explicitly state that local build sources are newer than GitHub main; this build-only upload does not push source changes. [Private draft release](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-04479448d8da0ffe8270). [Development record](DEVLOG.md#dev-step-211).

## 2026-10-27 — Step212: distortion workflows and window-build handoff

Displace, Shear, Wave, Pinch, Spherize, Twirl, Ripple, Polar Coordinates and ZigZag now have native Swift settings, previews, Cancel/Undo and editable Smart Filters. Displacement maps stay embedded with the document; Shear curves can be edited directly. The Photato API shares the same operations. Native39 and Actions11 preserve the new settings. The first integration attempts exposed a Swift getter, a test comparison and missing archive negotiation paths; each failed attempt was preserved and repaired. The full run also found two outdated version expectations, corrected before the final run.

All45 focused checks and2,003 final full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Adobe's observed dialogs informed controls and parameter ranges; exact Photoshop pixels, action descriptors, editable PSD interchange, live native filters and the physical platform matrix remain unqualified. Other major F02 filter families remain open.

The maintainer's recurring workspace-overlap screenshot was traced to an older test app still running before the clipping fix. Its document was saved separately, and the verified corrected build was installed alongside it. The title appears correctly, but the Mac locked before the same-document zoom/scroll check and handoff could finish. That live check remains pending; automated containment checks pass.

The diary overview was checked at desktop and phone widths, with five readable numbered steps and no horizontal page overflow. At the maintainer’s request, it explains the actual engineering process, licensed PhotoCraft provenance, public specifications, black-box comparisons and saved-file analysis. It explicitly excludes decompiling/disassembling Photoshop or copying proprietary Adobe implementation code. It does not assert a formal clean-room separation or the unsupported broader statement that no reverse engineering of any kind occurred. [Development record](DEVLOG.md#dev-step-212).

## 2026-10-27 — Step213: native Pixelate workflows

Color Halftone, Crystallize, Facet, Fragment, Mezzotint and Pointillize now run in native Swift. Facet and Fragment apply immediately; the other four have settings, previews and local Undo. Smart Filters keep their source and editable parameters. Native40 and Actions12 save those settings, and the Photato API uses the same commands as the desktop. Pointillize captures the current background color; seeded patterns make repeatable renders possible.

Eighteen synthetic reference images produced by the original, unmodified Rust filter source match byte-for-byte. The first focused run exposed unnecessary sparse-tile allocation on an unchanged white image; that was repaired without changing expected pixel output. All68 final focused checks and2,015 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Hosted workspace images were inspected; they are not live interaction evidence.

Adobe's published API lists these filter families but requires recorded action descriptors. Those mappings and editable PSD interchange remain incomplete. Exact Photoshop pixels/defaults/depth availability, live interactions and the physical platform matrix also remain open. Other major F02 workflows are still outstanding; the next family is Stylize.

The recurring workspace-overlap report remains a delivery handoff in progress. The older test app is still running; the corrected installed build and saved copy of its document retain their verified hashes. Automated canvas-containment checks pass. The Mac remains locked, so reopening that document, checking zoom/scroll/resize and safely closing the obsolete test window still await unlock. No new live pass is claimed. [Development record](DEVLOG.md#dev-step-213).

## 2026-10-27 — Step214: native Stylize workflows

Diffuse, Emboss, Extrude, Find Edges, Oil Paint, Solarize, Tiles, Trace Contour and Wind now run in native Swift. Find Edges and Solarize apply immediately; the other seven offer native settings, preview and local Undo. The same commands power the desktop and Photato API. Editable Smart Filters retain the original pixels, parameters and masks through native41 and Actions13 saving. Emboss also has PSD descriptor round-trip coverage using the licensed PhotoCraft mapping.

Twenty-seven synthetic reference images generated with the original Rust source match byte-for-byte. The first run exposed three test setup issues: tiny Tiles settings legitimately produced no change, an HDR fixture used encoded instead of linear storage, and a wide Oil Paint reference used whole-image processing instead of the original application's default256-pixel tiles. A separate original-Rust experiment reproduced the tile-dependent difference. The corrected fixtures retain exact assertions and preserve the failed evidence; no editing algorithm was changed to make these tests pass.

All 80 final focused checks and 2,027 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Oil Paint, Extrude and Tiles workspace renderings were inspected for layout; they are offscreen evidence. Adobe actionJSON support, wider editable PSD interoperability, exact Photoshop output/defaults/depth behavior, live interaction and physical platform qualification remain open. F02 is still in progress; Render workflows are next.

For the recurring window-overlap report, the corrected installed app and saved document still match their verified checksums. The older test app remains running. Current canvas-containment tests pass, but the locked Mac prevents the same-document zoom, scroll and resize handoff. The obsolete window will remain open until that handoff can safely finish. [Development record](DEVLOG.md#dev-step-214).

## 2026-10-27 — Step215: native procedural Render filters

Clouds, Difference Clouds, Fibers and Lens Flare now run in native Swift. Clouds and Difference Clouds use immediate menu commands; Fibers and Lens Flare offer native previews and local Undo. Lens Flare can be positioned directly in the preview. Generated textures fill the selected canvas region even on empty or cropped pixel layers while retaining transforms, masks and transparency locks. Editable Smart Filters preserve the source and captured settings through native42 and Actions14 saving. The Photato API uses the same commands, history and validation.

Twelve synthetic images produced using the licensed original Rust functions match byte-for-byte. The first attempt stopped at a test typing error. The second exposed a real Lens Flare porting mistake: the original helper handles reversed smoothstep edges with a hard step, while the initial translation used a smooth ramp. The implementation was corrected without changing the expected reference images. Two further assertions differed only because separately created Smart Filters received different identifiers; those comparisons now normalize that identifier while checking the complete document. Both failed attempts and their repairs remain preserved.

All 94 final focused checks and 2,041 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. Fibers and Lens Flare workspace images were inspected for layout; they are offscreen evidence. Adobe actionJSON and editable PSD mappings, exact Photoshop output/defaults/depth contexts, live interaction and physical platform qualification remain open. F02 remains in progress. Flame, Tree and Picture Frame are the next major Render workflows. Lighting Effects exists in the licensed source but is absent from the captured current Photoshop menu; its reference context needs separate review.

The recurring window-overlap report still requires a live handoff. The older test app remains running; the corrected installed app and saved document retain their verified hashes. Current canvas-containment tests pass. The Mac remains locked, so the same-document zoom, scroll and resize check and safe closure of the old window remain pending. The private GitHub development build remains209; this215 package is local. [Development record](DEVLOG.md#dev-step-215).

## 2026-10-27 — Step216: native Flame, Tree and Picture Frame

Three more Render workflows now run in Swift. Flame follows a chosen document path and exposes the six source modes, shape, style and flame controls. Tree offers34 source designs, leaf/branch/light controls and a draggable base. Picture Frame offers16 source designs, line/spacing/color and fade settings. Each has a native preview, local Undo, Cancel, one document Undo on commit and optional new-layer output. Selection, transparency locks, cropped storage and mask placement are retained. The three Photato API commands use those same transactions. Actions15 records settings, portable target layers and actual Flame paths; generated raster pixels use existing native and PSD persistence.

The first core run stopped at incorrect persistence helper names in a new test. After that repair,70 original-Rust reference comparisons exposed89 channel samples differing by one eight-bit level across36 cases. Diagnostic paint-buffer comparisons traced this to the floating-point PI constant: Swift's Float.pi rounds down, whereas the source Rust constant rounds to nearest. Using the explicit source bit pattern fixes every reference without changing expected images or weakening assertions. The first app-integration compile then caught grouped declarations unsupported by Swift Observation and an error-variable shadowing mistake; those were repaired. Failed attempts remain available in the development record.

All109 focused tests and2,055 full optimized tests pass. The universal macOS 14+ package verifies after fresh extraction. All70 original-Rust RGB8 cases match byte-for-byte in both focused and optimized tests. The three hosted dialog images were inspected for containment and layout; that is offscreen evidence. These results do not prove Photoshop pixel equivalence. Exact Photoshop settings, output/depth contexts, Adobe raster ActionJSON/ATN compatibility, live interaction and physical platform qualification remain open. The original-source fallback arc is not substituted when Flame lacks a real path. F02 stays open; remaining Other/Video workflows are next, with Lighting Effects' current availability still requiring a separate audit.

The workspace-overlap handoff remains unfinished. The old test app is still running alongside the corrected installed209 app. All23 dedicated window/containment checks pass, as do the window cases in the full suite. The installed executable and saved document match their verified copies, but native app access reports the Mac locked. Same-document zoom, scrolling, resizing and safe closure of the obsolete window remain pending. The private downloadable build remains209; this216 package is local. The inherited Actions import-description version hint also remains a small metadata follow-up, while the actual decoder/discovery state correctly supports Actions15. [Development record](DEVLOG.md#dev-step-216).

## 2026-10-27 — Step217: native Other and Video filter workflows

Seven more Photoshop menu operations now have working native Swift implementations: Custom, HSB/HSL, Maximum, Minimum, Offset, De-Interlace and NTSC Colors. Custom offers a 5×5 matrix with scale and offset plus portable JSON presets. Maximum and Minimum support square and round neighborhoods. Offset handles wrapping, repeated edges and transparency in the selected region or canvas. De-Interlace offers field order and duplication/interpolation choices. Settings, previews, Cancel and local/document Undo share the same transactions as the Photato API. Editable Smart Filters retain their sources through native43 and Actions16 saving; ordinary raster results also survive PSD saving.

The reference generator initially needed a Copy annotation on its Rust adapter and a fresh output directory. Three early Swift builds caught spacing, missing error propagation and a test fixture using a read-only store property. The next run exposed eight old generic interchange expectations that incorrectly included filters whose Adobe descriptors are explicitly unsupported, plus a busy-request test that had not selected its newly created layer. Those tests now distinguish qualified operations and check that a preview really opened. The full suite then caught two older archive expectations: discovery still ended at42 and the invalid-version list contained the now-supported43. Those now use readable1–43 and unsupported44. Every failed attempt remains preserved. No expected reference pixels were changed.

All 124 focused tests and 2,068 full optimized tests pass. All 44 synthetic original-Rust RGB8 outputs match byte-for-byte. Fresh extraction verifies the universal macOS 14+ package. Hosted dialog images were inspected for layout; these are offscreen checks. Photoshop output/defaults, Adobe ACF presets, ActionJSON/ATN and editable PSD descriptors, fractional Roundness behavior and live/platform qualification remain open. Full F02 is still in progress. The next major breadth work is the remaining Blur, Noise and Sharpen operations.

The older window from the overlap screenshot is still running. Selecting the corrected installed app again reports the Mac locked, so the same-document zoom, scrolling, resizing and safe closure of the old window remain pending. The private downloadable build remains209; this217 package is local. The stale Actions import-help version hint noted in216 is now corrected to1–16, matching the actual decoder and discovery state. The diary overview was also brought forward from its stale211 summary to this verified checkpoint. [Development record](DEVLOG.md#dev-step-217).

## 2026-10-27 — Step218: native Blur, Noise and Sharpen workflows

Twelve more factory menu operations now work in native Swift: Blur, Blur More, Radial Blur, Shape Blur, Smart Blur, Surface Blur, Despeckle, Dust & Scratches, Median, Sharpen, Sharpen Edges and Sharpen More. Six apply immediately; the other six open settings and previews with Cancel and local Undo. Radial Blur has Spin/Zoom, quality and a draggable center. Shape Blur offers nine built-in kernels. Smart Blur has quality and three output modes. The family shares document Undo, selection/transparency handling, cropped pixel and mask placement, editable Smart Filters, native44/Actions17 saving and the Photato API. Known Adobe bit-depth restrictions are enforced in desktop and API execution.

The Rust reference harness initially failed because unused large-Gaussian helpers referenced Rayon. A sequential iterator adapter repaired the harness while preserving the selected original algorithm bodies. All 44 resulting RGB8 test images match byte-for-byte. The first native focused run passed all 149 tests; the only later production change clarified the aggregate API description of unsupported editable PSD interchange. The complete optimized suite then passed all 2,082 tests. Fresh extraction verifies the universal macOS 14+ package. Hosted settings-dialog images were inspected for control placement; these are offscreen checks, not live user interactions.

This is F01 functional breadth; the initial working note classified it as F02, which is corrected in the current ledger. Both packages remain open. Exact Photoshop output/defaults, imported or custom Shape presets beyond the nine source kernels, Adobe ActionJSON/ATN/editable PSD descriptors, large-document processing budgets and live/platform qualification remain outstanding. Radial Draft/Good use native sample budgets derived from the source Best path; no Adobe quality-kernel equivalence is claimed. Next major breadth work is the remaining classic adjustment family.

The overlap screenshot still corresponds to the old159 app. The corrected209 app and retained document keep their verified hashes and signature. A new native app selection returned no window, and the follow-up inventory explicitly reported the Mac locked. No input was sent and no same-document live handoff is claimed. Canvas pixel-containment and document-window regressions pass in the full suite; opening the saved artwork, zooming, scrolling, resizing and safely closing the old window remain pending manual unlock. The private downloadable build remains209; this218 package stays local. [Development record](DEVLOG.md#dev-step-218).

## 2026-10-27 — Step219: classic tone and color adjustments

Five previously unavailable Image > Adjustments workflows now run in native Swift. Shadows/Highlights includes tonal widths, radii, clipping and color/midtone controls, and can remain editable on Smart Objects. HDR Toning offers four methods, a curve and a flattened result with one Undo restoring the source layers. Match Color can read an open source document or layer with selection-weighted Lab statistics. Replace Color supports additive/subtractive samples, localized clusters and selection-mask preview. Equalize supports selected-area mapping or whole-target mapping based on the selected sample. Native previews, local history, cancellation and document Undo share the same engine with two new API commands.

The implementation translates the licensed PhotoCraft tone, Gaussian, Lab, HSL and Equalize behavior. Twelve independently generated original-Rust RGB8 references match byte-for-byte. They are not Photoshop output. The first compile found a missing API-schema bracket; the next regression found outdated generic command/version/interchange expectations. Both failures and repairs remain in the evidence record. A final API review corrected the statistics depth schema to match its actual string payload. All161 focused tests and2,094 full optimized tests pass, followed by fresh-extraction universal package verification. Four hosted dialog renders were inspected for contained previews and readable controls, with longer HDR controls in a scrollable panel. These are offscreen checks, not live interaction acceptance.

There are112 typed Photato commands. Statistics are read only through a shared source document route and are portable values for a separate target request. Editable Shadows/Highlights uses native45; ordinary tone Actions use18. Semantic HDR Actions, Adobe STA/presets/ActionJSON/ATN and editable PSD descriptors remain unsupported. Exact Photoshop output/defaults/depth behavior and ICC-specific processing remain unqualified, as do physical Intel/macOS 14/macOS26 and live workflows. Full A03 is still open. The next major breadth work is native document color modes and separations.

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

**Tested development build:** The integrated Indexed Color and Bitmap workflows now pass all2,259 optimized tests and package as a universal macOS 14+ app. A painting regression exposed previews whose stored color samples were stale. The shared preparation step now reconciles those samples before preview or commit, preserving untouched colors and duplicate palette indices. Six new workflow tests cover12 mode/depth contexts and84 tool/context combinations, native cancellation/history, automatic layers/masks, HTTP painting and reopening; all39 final focused checks pass. The failed reproduction and one API test-fixture correction remain documented. API capabilities and the diary reflect the fix. Build221 is saved locally;220 remains the uploaded private build. Same-artwork window acceptance still needs an unlocked desktop. Exact Photoshop output, full tool contexts and other parity gaps remain open; Duotone/Multichannel are the next major workflow.

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

Tests caught an AppKit dirty-state effect from assigning NSDocument.printInfo, an invalid test controller startup order and a printerless-preview regression; each failed attempt and repair is retained. All 65 focused tests now pass. The real AppKit print path also wrote four distinct separation pages to an owned PDF without contacting a printer. An independent PDF reader confirms16-bit CMYK/gray image data and embedded profiles. All2,351 full optimized tests also pass on the same unchanged source. Universal macOS 14+ build224 is verified and uploaded as a private draft; all four downloaded assets match their SHA256 hashes.

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

The universal Apple Silicon/Intel macOS 14+ development package is verified and uploaded to the private GitHub repository. Build metadata and source hashes accompany it; source was not pushed and the installed221 app was not replaced. PNG retains the current integer-profile pipeline, while32-bit HDR exports explicitly convert to SDR sRGB16. Native movie codecs, audio/keyframes, further export controls, full Render Video and Photoshop/live/platform parity remain open. [Detailed record](DEVLOG.md#dev-step-232), [export evidence](IMAGE_SEQUENCE_EXPORT_REFERENCES.json), [private build](https://github.com/ForensicIntelligence/Photato/releases/tag/untagged-7cde29c1ad993258aa5e).


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

The native Timeline/FOSS batch is packaged as a universal macOS 14+ private draft. The same2,331 inputs passed2,516 full and92 focused optimized tests at242. Both extracted distribution architectures pass the headless RGB16 archive/image-packing smoke operation; x86_64 uses Rosetta. Package signatures, weak AI linkage, licenses/model resources and removal of purchase code verify. All four uploaded assets match downloaded SHA-256 hashes. Installed221 and owned artwork remain unchanged. No full Photoshop, live UI or physical Intel/macOS 14/macOS26 acceptance is claimed. An additional192 focused tests pass under Rosetta with independent pixel/movie/audio verification. Tests ran against the preserved test-enabled build of the same source; the separate distribution binaries also passed their own headless smoke operations. Rosetta execution does not replace testing on physical Intel hardware or earlier supported macOS releases. The package still has the documented raw-QuickTime reader interoperability limitation. The prior package and test evidence remain preserved; no user document or installed app was replaced.

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

Live inspection could not start because the Mac was locked and the UI connector could not unlock it. Manual unlock was requested while the automated suite ran. The separate diagnostic app is ready for owned-fixture painting, history verification and trace collection after unlock. The full suite then encountered prolonged native Save-panel initialization waits; a stack sample was saved, and the owned test process was stopped. Its completed cases have no assertion failures, but the suite is incomplete and must be rerun after unlock. The existing normal preview and user artwork are unchanged. The overall feature and 60 fps goals remain open. [Detailed record](DEVLOG.md#dev-step-269).

**Step269 availability follow-up:** The Mac remains locked across three consecutive goal turns. Native UI access and the remaining full-suite/painting trace are blocked until manual unlock; source02 and normal preview268 are unchanged. The interrupted full run and failed initial report writer remain preserved. This availability check is not a new implementation milestone; live frame pacing and the complete Photoshop goal remain unqualified.

**2026-10-30 — Step269 qualification after unlock.** Native access resumed and the full rerun passed. Owned Brush and Blur strokes, Undo/Redo and viewport containment were checked in the isolated app; the original test image was left unchanged and the diagnostic app quit. Short automation drags supplied only3–4 samples, so their traces could not establish continuous frame cadence. A new opt-in test therefore streams240 store-generated points over2 seconds into a real native window hosting the full workspace, recording actual AppKit draw callbacks without directly calling draw. It covers Brush, Blur, Dodge and Smudge and verifies all samples and exact complete-command pixels. These synthetic store gestures are distinct from physical tablet or mouse input.

Optional per-stroke timing now correlates input, preparation, accepted previews and native AppKit draws. The real-workspace benchmark retains all240 samples and exact native pixels for Brush, Blur, Dodge and Smudge, while recording104–111 distinct preview draws during each roughly2-second stroke and about two canvas draws per accepted preview. Median newest-input-to-draw delay is20.7–22.6ms. All36 focused and2760 full optimized tests pass on2467 frozen inputs. Owned native painting/Undo/Redo and a separate signed preview are verified. This is scheduling/CPU evidence, not physical60fps; no kernel or pacing change is claimed in269. The roughly doubled draw count provides a concrete next investigation: remove redundant prepublication workspace updates, then repeat the same measurement. Earlier failures, locked-session attempts and the incomplete full run remain preserved. [Detailed record](DEVLOG.md#dev-step-269).

<a id="diary-step-270"></a>

## 2026-10-30 — Step270: present accepted editing previews

Canvas and thumbnail updates now follow accepted preview publication, while live strokes avoid the per-preview busy indicator. The native-window Brush/Blur/Dodge/Smudge fixture retains all240 samples and exact native command pixels with 119–120 distinct preview draws over about2 seconds, each accepted preview drawn once instead of nearly twice. Median distinct-draw intervals are 16.57–16.80ms. All105 focused and2762 full optimized tests pass on2468 frozen inputs. Native painting/history checks and a separate signed preview are verified. Latency remains tool/run dependent; this is AppKit scheduling evidence, not physical60fps.

The previous native-window trace showed almost two canvas draws for every accepted preview. The workspace was reacting when rendering started, before the next pixels existed. A separate accepted-presentation counter now updates the canvas and thumbnails after publication; request revisions still protect APIs and reject stale renders. The busy indicator no longer invalidates the workspace for each live stroke. Painting algorithms and stored document pixels are unchanged.

The first focused run found a new test checking the wrong zoom buffer. That failed attempt and its measurements remain preserved; the corrected test checks both the reduced display preview and retained full-resolution image. Both performance attempts are retained because latency varies with timing phase, and one first-attempt Dodge latency was worse despite better cadence. Physical60fps, high-rate tablet curves, jaggedness and heavy-tool cases remain open. [Detailed record](DEVLOG.md#dev-step-270).

## 2026-10-30 — Step271: use the current preview and restore tool focus

Native zoom Return now releases keyboard focus for tool shortcuts, and external zoom/Fit changes supersede stale percentage drafts while unrelated updates preserve typing. The obsolete159 probe was retired after a byte-identical retained copy of its open document was verified; that document is now open in normal Preview271. All71 focused and2764 full optimized tests pass on2468 frozen inputs. Native zoom/shortcut/history checks and signed packaging pass. No new frame-rate or Photoshop pixel-equivalence claim is made; sustained 60 fps and stroke continuity remain open.

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


## 2026-10-30 — Step278: large-document architecture

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

The Xcode Release build succeeds for Apple Silicon and Intel, with macOS 14.0 deployment metadata and verified signatures/resources/ZIP. An optional-model script dependency repair keeps script sandboxing enabled; valid/missing/corrupt model cases are checked. Only the project specification/generated project differ from the arm64-tested source. Newer Apple frameworks are weak-linked. These checks do not prove a physical macOS 14 or Intel launch.

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

The48 regression references come from the actual previous native renderer, not Photoshop. Adobe basic-filter mappings use the shared engine, while large PSD/PSB caches/masks, source-byte limits and resource-job outputs still have separate limits. No complete Photoshop, dense90GP, frame-rate, physical Intel or macOS 14/26 runtime claim is made. [Detailed record](DEVLOG.md#dev-step-293) · [Evidence](PAGED_SMART_FILTER_REFERENCES.json).

The initial unfiltered Smart Object snapshot exposed a second full-canvas traversal. Ordinary raster caches now use the existing sparse compositor; strict cached-object comparisons retain bounded-renderer pixels at all depths. The legacy blur helper and editable-filter entry now use kind-specific availability. Native access is still locked, so the candidate remains unlaunched and normal Preview283 is preserved.

## 2026-10-31 — Step294: save the qualified source to private GitHub

Publish and independently verify the complete source of checkpoint293, which passes2,942 full optimized arm64 tests,90 focused workflows and6 translated Intel Core module checks. The portable manifest identifies2,846 included inputs and32 excluded generated model/provenance/cache files. Existing Rust provenance and licenses stay intact. This source-only backup changes no native function, menu, shortcut, API or installed package. The repository remains private until release day. Native acceptance, full Photoshop parity, dense capacity, performance, rich large PSB/jobs and supported-platform qualification remain open. Source commit: [`fbb9eda`](https://github.com/ForensicIntelligence/Photato/commit/fbb9edaf9841930a443568d33a4fcec14de752b4). [Verified receipt](SOURCE_PUBLICATION_294.json).

The first documentation-receipt commit failed before creating a commit because its message-file path was relative to a different checkout. Its passing staged scan and failure log are preserved; the runner now resolves the path absolutely and retries in a new output directory. Native source and the verified source commit remain unchanged.

## 2026-10-31 — Step295: large editable Photoshop files

Supported editable RGB PSD/PSB Smart Filter caches now stream rows and decode masks into paged storage, including native/file/API source composition. Large global derived cache tags use reader views instead of full metadata copies. All 2950 full optimized arm64 tests and 61 focused tests pass on 2893 frozen inputs;5 translated Intel Imaging/Core checks pass. Six exact prior cache wires/three mask vectors, 9MP editable native/HTTP workflows and an actual 640MB cache tag pass. A prior constant-filter storage-depth/blend-domain bug found by round-trip tests is repaired without changing reference bytes or tolerances. A signed isolated candidate is retained; normal preview 283/artwork remain unchanged. Full native/Photoshop/platform/dense-capacity/performance, descriptor/mode/mask-option and independent resource/job/source-byte gates stay open.

The old cache writer built complete colour/mask byte arrays, and filter masks still rejected above8MP. Checked row compression, section views and paged numeric masks now serve native PSD/PSB files and the existing APIs. A640MB authored global cache proves the file path can bypass the512MiB Data/metadata allowance without copying unused source planes; nine-million-pixel mask values and editable file/HTTP round trips are verified. Embedded RGB source composition also retains pages to respect existing heap admission.

Strict round-trip tests caught an earlier constant-filter shortcut changing byte layers to Float32 and applying the wrong gamma in blending. The original depth/encoding and base working domain now remain intact, with exact regressions. Failures and repairs remain documented, including a test concurrency capture, a diagnostic property typo, an invalid synthetic alpha-channel header, and long HTTP encoding cancelled by the old connection timer (client timeout changes alone did not repair it). Prior reference bytes come from the actual native renderer, not Photoshop; independent Photoshop/native/platform/dense-capacity and broader descriptor/resource-job limits remain open. [Detailed record](DEVLOG.md#dev-step-295) · [Evidence](STREAMED_FILTER_CACHE_REFERENCES.json).

## 2026-10-31 — Step296: large documents through both job APIs

Supported RGB PSD/PSB resource jobs now use the native paged reader instead of the nonpaged Data reader and a generic4MP rejection. Both Photato action jobs and Adobe execute-actions/composite paths share logical300000-side admission, separate64-layer/128MiB resident data limits and unchanged64MiB resources/128MiB aggregate output. RGB blank creation retains its published32000-side schema and implicit samples. PSD output enforces64MiB during row writing while preserving default bytes, and reuses immutable prepared sources/global opacity facts across output patches. All 2954 optimized arm64 tests pass on frozen Source02, including every40M authored Float32/HDR/alpha sample, compressed native output equality, real5.4MP High Pass through both HTTP jobs, untouched desktop history, independent existing Photoshop references and invalid/cancel/budget regressions. Final metadata-only Source03 passes3 focused capability/HTTP checks; all2892 remaining inputs, including Core/Imaging, match Source02. The signed candidate binds to2894 frozen Source03 inputs and is isolated; normal preview283/artwork remain unchanged. Full Photoshop/native/platform/Intel/dense capacity/performance, larger transport and remaining format/mode/analysis/action gates stay open.

The same source that could open natively still failed resource jobs at four megapixels. The job adapter now uses the paged Photoshop reader and checks geometry separately from stored/resident data. RGB blank documents keep implicit background samples; accepted jobs continue using the shared native command engine. Nonpaged formats, analysis and artboard flattening retain separate current limits. A bounded PSD serializer stops oversized output during writing instead of first constructing a much larger buffer.

The regression suite verifies all 40 million layer samples from an authored RGB32 input, lossless native/job output bytes and a real5.4MP High Pass through both authenticated routes with untouched desktop history. These are native functional checks, not proof of Adobe algorithm or hosted-service equality. The current Adobe guide documents5GB resources; local transport still requires further work. Major modern Light/Color and vibrance/Clarity and dehaze/Grain layers remain outstanding after the official feature audit. [Detailed record](DEVLOG.md#dev-step-296) · [Evidence](LARGE_RESOURCE_JOB_REFERENCES.json).

## 2026-10-31 — Step297: modern editable adjustment layers

**Modern adjustment layers software qualified; native acceptance pending (step297):** Color and vibrance, Light, Clarity/Dehaze and Grain now have distinct editable native adjustment layers, Properties controls, masks, opacity/blends, history, native65, Actions22 and shared Photato adjustment commands. All2965 inventoried optimized arm64 tests in bounded module processes pass on2901 frozen inputs. Earlier Source05 also passed23 focused checks; the current complete inventory includes those same cases. Existing published Adobe /v2/edit controls share native transfers; no modern live-layer descriptors or routes are invented. A signed isolated candidate is preserved; normal283/artwork remain unchanged. The long-lived monolithic AppKit test hang, modern PSD/PSB descriptors, legacy Light versions, larger spatial processing, independent Photoshop/menu/default/ICC/numerical, native and supported-platform qualification remain open. [Evidence](MODERN_ADJUSTMENT_REFERENCES.json).

Color and vibrance, Light, Clarity/Dehaze and Grain are distinct live masked layers. Properties edits preserve source pixels, support history and native65, and record semantic Actions22. Spatial effects use complete input before projecting a region; grain uses stored document coordinates and seed across patches and reopening. Existing Photato adjustment commands and the published Adobe edit fields share the native implementation where their contracts overlap. Modern PSD descriptors and legacy Light versions still require independent qualification.

The record retains the failed menu/version assertions, worker-stack crashes, test-bootstrap correction and interrupted single-process AppKit run. Pixel/filter entry points now use isolated stack frames with the original adjustment loop unchanged. Every one of2965 inventoried cases passes on the same final Source07 in16 bounded processes, with no missing cases. This does not qualify native long-session behavior or Photoshop numerical equality. Normal283/artwork are preserved; native visual acceptance remains pending while the Mac is locked. [Detailed record](DEVLOG.md#dev-step-297) · [Evidence](MODERN_ADJUSTMENT_REFERENCES.json).

Complete software-qualified source297 is backed up privately as [d4d6e04](https://github.com/ForensicIntelligence/Photato/commit/d4d6e04e1c5ad2a79477d7e423c8f9d00cfea782). All2869 included qualification inputs and1057 original Rust files verify; build products, model/cache outputs, runtime evidence and working documents stay excluded. This source delivery uploads no new binary and does not change repository visibility. [Publication receipt](SOURCE_PUBLICATION_297.json).

## 2026-10-31 — Step298: Apply Image and Calculations

Apply Image and Calculations now have native sheets, retained document/layer/channel sources, independent masks,21 channel blends/Add/Subtract controls, pixel/component/mask/alpha/ink targets and all three Calculations outputs. The desktop and197 typed Photato commands share native preparation/history; external API sources require explicit sharing/current revisions. All2980 inventoried optimized arm64 cases pass in17 bounded processes on2911 frozen inputs. Preserve the failed attempts, repaired orphan-document test bootstrap and signed isolated candidate. Normal283/artwork remain unchanged. Native visual acceptance, Photoshop exact kernels/ICC/modes, semantic Actions recording, published Adobe actionJSON descriptors, larger native-mode storage and supported-platform/Intel/long-session gates remain open.

Both commands use retained source snapshots and atomic history. Apply Image supports the active pixel/channel/mask target; Calculations creates a channel, selection or grayscale document. Tests preserve strict numerical assertions and cover sparse300000-side RGB/coverage data, source revocation, stale previews, undo and native persistence. The record retains two one-bit Float32 failures and their production arithmetic repair, plus an isolated save-test bootstrap crash and fixture correction. Earlier source/packages and failed evidence are preserved. C03 stays open and retains its phase2 classification; work returns to missing major workflows after this in-flight batch. [Detailed record](DEVLOG.md#dev-step-298) · [Evidence](CHANNEL_ARITHMETIC_REFERENCES.json).

Complete software-qualified source298 is backed up privately as [e91e5ef](https://github.com/ForensicIntelligence/Photato/commit/e91e5ef92c6fa973dee38488640d5023be199150). All2879 included qualification inputs and1057 original Rust files verify; build products, generated models/caches, runtime evidence and user documents stay excluded. No new binary was uploaded or installed, and the repository remains private until release day. [Publication receipt](SOURCE_PUBLICATION_298.json).

## 2026-10-31 — Step299: linked Smart Objects and packaging, in progress

Photato now has Place Linked, Relink, Update selected/all, Embed, Embed All, Convert to Linked and Package controls, private source approval and modified/missing monitoring. Seven linked operations bring the optional API to204 commands. Native66 retains references/previews while omitting original linked bytes; decoding never opens an unapproved path.

Source20 closes a native/API placement gap: approved API artwork can select PDF pages/images/crop/resolution/antialias, RAW development, initial transforms and frame contents through the same Swift preparation as native choosers. Original files stay retained. Native automatic and API RAW refresh now preserve the user's development settings and decoder across shared instances. All seven new cases pass, including exact native/API pixels, original bytes, schema validation, cancellation/revocation/stale guards, unchanged output for unchanged Bayer data and atomic Undo/Redo.

Package streams a native/PSD/PSB document, original Links files and an inventory. Explicit Update Existing Folder/API replace updates in place, reuses identical originals, preserves unrelated entries and rolls back unchanged outputs; intervening user edits retain recovery staging. The earlier eight merge, four type, six new-folder and three bulk cases stay covered. At Source17,165 targeted cases had164 passes. Source20 broadens the unique union to183 cases with182 passes; the same masked PSD/PSB preview case retains two exact failures. Sixteen affected isolated groups pass107 cases. The nine cursor tests/832 combinations pass again, with no new tool or modifier action.

The diary retains the failed builds, private-type-tag export repair, Source18 schema-test mistake and safe-but-incorrect422 stale-target response. Source19 repairs the schema path and shared409 conflict guard; Source20 repairs RAW refresh instead of resetting its settings. No strict pixel assertion is weakened. Source20 freezes 2,933 compiler/test inputs. Nested/media/XMP dependencies, new-file API output and complete linked editing, full Adobe/Photoshop behavior, large-original/all-operation capacity, full-suite/long-session and native/platform/physical60fps gates remain open. Normal283, candidate298, original artwork and private source298 are preserved. [Detailed record](DEVLOG.md#dev-step-299) · [Checkpoint](WORKING_CHECKPOINT_299.json).

Source21 adds an explicitly separate linked-original download/save API and native per-file write switches, disabled by default. A save requires the current document revision and the original file’s strong fingerprint; it validates the replacement and parent edit before publishing the file. Concurrent saves of the same approved original are rejected. Cancellation, stale state, permission changes and path replacement are covered by new tests. If the file is already saved when a later check fails, the response reports that fact instead of claiming rollback. Parent Undo restores the document, not the external file. The source monitor acknowledges successful saves so Undo is not immediately undone by automatic refresh.

This implementation adds safe response headers and bounded binary admission, a strict no-follow option to the shared atomic writer, source-format/RAW/PDF preservation checks and native permission controls. Thirteen new cases are authored for these paths, including a sparse 300,000×300,000 native original. The 2,937-input Source21 build failed before tests: the new test helper exposes a private type at too broad a visibility, and concurrent test tasks return non-Sendable response dictionaries. The compiler reports 13 diagnostics; zero tests execute. The failed source and log were preserved without repair during the diary-only pass. Subsequent Source22 fixes the test helper visibility and returns Sendable raw responses from concurrent tasks before decoding JSON on the main actor. All 11 original-editing App cases pass. Two strict-writer fixtures then fail because Foundation resolves their temporary directory through the /var symlink. A physical-path probe confirms the difference; Source23 uses Darwin realpath in the fixture, as production authorization already does. Both strict tests pass without changing the writer or weakening its path checks. Live native acceptance remains pending; Source20’s passing subset is retained as historical evidence. There are still 204 typed command names; the new binary routes are separate Photato capabilities, with no invented Adobe endpoint.

**Diary synchronization requested by the maintainer.** Refresh this overview and narrative, the technical record, status/plan and dashboard workflow text, and both single-file HTML/Markdown/provenance copies. Preserve the existing299 milestones, source/test history, private repository link and public-on-release policy. This documentation pass changes no editing implementation or installed preview.

Source23’s focused run passes 101 of 102 cases, retaining only the existing two strict PSD/PSB assertions. Sixteen affected isolated groups pass 107 cases; their deduplicated union is 199 cases with 198 passing. All 2,937 frozen inputs remain unchanged; no new app is installed or source published. The native permission PNG is blank on inspection, so its construction/reset test is not evidence that controls are visible. A fresh native check still reports the Mac locked; the earlier unlock request remains pending. Continue missing major workflows while keeping complete Photoshop/source/platform and visual acceptance gates open.



## 2026-10-31 — Step300: rich original PhotoCraft migration, in progress

After qualifying linked-original saving as a functional subset, work returns to missing major breadth. Actual source inspection finds that original PhotoCraft `.pcraft` import still rejects all non-raster/group layer content. The migration plan covers every source content kind and its metadata; the first batch connects editable solid, gradient and pattern fills, document patterns and fill opacity to the existing native engine.

Owned fixtures are generated by unmodified original Rust crates, then loaded again there. Their independent content pixels and Float32 gradient-ramp words will check the Swift mapping at all three sample depths. The initial offline generator fails on a missing cache package; its log is preserved, and a separate registry-backed generator succeeds. Rust is a test-only reference, never an application dependency.

Native Open and the existing Photato upload/resource paths share the expanded importer. Source projects retain their original files; Save As creates a native Photato document. Unsupported editing data still rejects the entire import. Dual-alpha gradients, linked pattern-mask anchors, nondefault pattern samples outside the declared frame and remaining rich layer types/metadata are explicit open mappings. Existing dedicated gradient/pattern-control API gaps also remain visible; source import is not a claim that every editing API is complete. No Adobe `.pcraft` route or input support is invented.

Eleven new cases exercise retained controls, source references, pattern hidden pixels, fill opacity, native editing/history/save, API equivalence and failed imports/budgets/cancellation. Source01 builds successfully and passes 164 of 168 cases. Independent comparisons reveal endpoint differences, and the new stale-request test uses the wrong request field. Its resource test also requests a PSD representation that the existing translucent-solid writer explicitly rejects. All failures are preserved.

Source02 fixes the request field and keeps the PSD error check. Its attempted PNG output then correctly encounters the existing unconverted RGB32 precision guard. Source03 checks both explicit output failures and successful float TIFF using the same F32 project. All three native/API workflow cases now pass, and TIFF bytes equal native output. Native Photato saves keep editable layers and patterns; the tested TIFF is raster output.

The current focused result is 166 passes from 168 cases, with only the two exact source-gradient cases still failing across 18 assertions. A frozen-object probe isolates the source's last-segment interpolation versus the native ramp's exact stored endpoint. The independent controls and oracles stay unchanged pending a source/Photoshop endpoint decision. Four Source02 oracle/archive/color-policy groups pass another 21 cases; all production and those test sources are identical to Source03, with explicit provenance instead of a claim that every case ran again. All 2,949 frozen inputs and 1,057 original Rust files verify unchanged.

Next comes the remaining source type/shape/adjustment/Smart Object and document-metadata breadth. Dual alpha curves, linked pattern-mask anchors, off-frame pattern data, output/API/color/capacity/fidelity and physical/native/platform gates stay open. The earlier locked-Mac acceptance gate is retained; it was not rechecked during these compiler/test runs. Installed283, candidate298, private source298 and protected artwork are preserved. [Detailed record](DEVLOG.md#dev-step-300) · [Checkpoint](WORKING_CHECKPOINT_300.json).

## 2026-10-31 — Step301: the diary brought up to date

At the maintainer's request, the development record was checked against the actual current source, checkpoint manifests, preserved test attempts and live dashboard. Entries already reached 300; this update makes the different checkpoints easier to understand at a glance and records the intervening investigation.

The overview now separates the current 300 Source03 work, earlier 299 linked-object work, the last complete test inventory 298, installed preview 283 and private source backup 298. Passing workflow tests do not erase the two current gradient failures, the earlier PSD/PSB failure or missing native, platform and Photoshop qualification. No new app functionality, build or source upload is claimed by this diary refresh.

The next rich-source adjustment review identified an Exposure prerequisite: the source retains offset and gamma as well as exposure, while the native legacy operation stores gain only. The complete native/API workflow is planned, not implemented. The major-feature order and all open migration requirements remain in force.

Both website copies were regenerated as self-contained HTML with the same Markdown and provenance. The overview includes the refresh time and explains that a saved file is a snapshot. Validation found two older index rows, 221 and 222, with their date and milestone columns reversed; those rows are corrected without changing their historical account. The private GitHub link, release-day public policy, FOSS terms and independent-implementation process remain visible. Documentation checks cover 301 entries, offline resources/local links, source provenance, mirrors and dashboard freshness; application input and protected-asset hashes are checked without inventing a new test run. [Detailed record](DEVLOG.md#dev-step-301).

## 2026-10-31 — Step302: Exposure gains the missing controls

Rich-source migration uncovered a prerequisite: PhotoCraft retains offset and gamma as well as exposure, while the native legacy operation stores gain only. A typed full-control operation now preserves all three settings. Existing gain-only documents and requests keep their original operation.

Native sliders, preview/Cancel/OK, editable layers, Properties, factory menu entries, selection masks and history use the shared engine. Photato commands expose the controls; published Adobe create-composite add/edit uses its documented exposureValue, offset and gammaCorrection fields and five placement types. Native67, Actions23 and PSD/PSB expA retain the values, and original .pcraft Exposure migrates through native/API import. Native new brushes use full controls; old API new/retyped requests retain gain unless a new field explicitly selects full controls.

Owned U8/U16/F32 source projects and transfer arrays come from unchanged original Rust crates. The first generator stops on declared toolchain metadata; the preserved metadata-only retry builds successfully. Three pinned Photoshop-authored RGB references and original licenses provide independent output checks. No Rust runtime or proprietary algorithm code is added to the app.

The first optimized build succeeds but catches missing expA entries in shared PSD admission lists, an outdated unknown-version probe and a regional-preview test expecting cropped coordinates. The same run exposes a brush format-version expectation that initially looks like an API regression. Source02 repairs the production/API details and verifies old/new HTTP behavior, all-depth source outputs and native/PSD workflows. Its broader 389-case run passes 383 cases and retains six failures, including two test expectations. Inspection confirms that the brush test uses the new native full-control factory, which correctly requires Actions23; the other stale probe still expects native66 to be unsupported from before299.

Source03 changes only those two test bodies: it verifies full Actions23, preserved legacy Actions3 replay and downgrade rejection, plus supported native66/67 and invalid68. Its 45-case run passes 44, with zero unexpected errors. All 11 new workflow/model/interchange cases pass. The one remaining new strict case matches all 27,648 independent RGB8 merged bytes, but retains 6,660 differing RGB16 bytes and 40,102 RGB32 bytes. These comparisons remain exact; they are not relabeled as a full Photoshop match.

The latest wider targeted union has 385 passes/four failed cases/22 assertions across 389 distinct cases. Only 45 execute on Source03; the others are explicitly attributed to Source02 with identical production and unchanged relevant test/fixture inputs. The earlier source-gradient and linked PSD/PSB failures remain. Full-inventory qualification still belongs to298.

After tests finish, the native inventory lists Photoshop and installed283 running, but direct access reports the Mac locked. No visual acceptance or screenshot is claimed. Current 2,968 inputs, all 1,057 original Rust files, 40 protected assets, installed283/candidate298/private source298 and artwork are preserved. Continue major source richness while keeping the remaining Exposure/Photoshop/native/platform/performance and capacity gates open. Both standalone diary copies and the dashboard are refreshed. [Detailed record](DEVLOG.md#dev-step-302) · [Checkpoint](WORKING_CHECKPOINT_302.json).


## 2026-10-31 — Step303: editable vector-shape migration, in progress

The next rich-project feature is editable PhotoCraft vector shapes. The source stores exact paths and optional live primitives, open contours, independent stroke opacity, dash lengths relative to stroke width, original cached appearance and vector records. The native model needs to retain those details instead of flattening them or silently discarding controls.

Draft Swift changes now cover those fields, bounded inversion and paint frames, source shape import, pristine cache reuse, native Properties/path editing, shared Photato API operations/state and native68/Actions24 admission. The implementation inventory identifies 28 modified source/test inputs and three new Swift files; no paths in those compared groups were removed. Six existing test files adjust version expectations, but no successful 303 build or test run has been recorded. This paragraph reconstructs the current file state on 31 October 2026; it does not imply that the earlier brief design note documented every edit when it occurred.

Next is integration/typechecking, owned fixtures produced with unchanged original Rust, focused model/render/import/native/API/history/archive tests and a frozen source qualification. Source 302's passing Exposure workflows do not qualify this newer working tree. Cache invalidation, live/path editing, all-depth precision, compound/inverted/open contours, full source/Photoshop formats and native/platform/capacity acceptance remain open. No 303 app has been installed or published. [Detailed in-progress record](DEVLOG.md#dev-step-303).

## 2026-10-31 — Step304: the diary brought into line with the working tree

At the maintainer's request, this refresh reconciles the saved diary with actual source, checkpoint manifests, preserved test results and the live dashboard. The previous standalone edition ended at302 while303 implementation was underway. Both303's missing source-state account and this documentation-only update are now indexed and readable.

The overview distinguishes unbuilt303, tested302, the last complete inventory/private source backup298 and installed preview283. Exact Exposure/source-gradient/linked-file failures and open parity gates remain visible. The dashboard journal follows the saved record; an in-progress WORKING checkpoint is not converted into a completed application task. No native source, API behavior, application build, installation or GitHub publication changes in this refresh.

The single-file HTML, downloadable narrative and provenance are regenerated in both local website copies. Offline resources, anchors, index coverage, mirror/provenance hashes and dashboard freshness are checked; application inputs and protected assets are compared without rerunning unrelated app tests. The independent-implementation process, licenses, FOSS terms and private-until-release repository link stay intact. [Detailed reconciliation](DEVLOG.md#dev-step-304).

The first regenerated edition passes all 18 content and integrity checks, including 304 entries, offline reading and matching website copies. All 2,970 application inputs, 40 protected assets and 1,057 original Rust files remain unchanged. The final edition and history inventory are checked separately after recording these results; neither check runs application tests or qualifies the unfinished shape implementation.


## 2026-10-31 — Step305: source shapes become editable native workflows

The unfinished303 shape draft is now integrated and tested. PhotoCraft shapes retain their exact paths and live controls, open contours, independent stroke opacity, width-relative dashes, paint/inversion frames, cached original appearance and vector records. Properties and path-anchor editing share native history and the Photato API. An actual edit invalidates obsolete cached appearance; Undo restores it. Accepting unchanged Properties preserves the source pixels and creates no extra history entry.

An owned Rust-only fixture generator uses the unchanged licensed source to create 13 small variants at each of three bit depths. Its first compilation fails on an incorrect helper name and missing import; a preserved second attempt succeeds. All 33 original caches retain exactly 811,008 sample words in native Swift, and uncached integer rectangles match another 73,728 words. The curved-stroke comparison remains strict and fails by 107/167/357 words across depths. No proprietary Photoshop implementation is incorporated.

The first Swift build stops on a type-checking limit in a compound bounds expression. Simplifying that expression allows the optimized build to complete. Tests then reveal an API guard rejecting the new shape-path target, plus a memory fixture that used an allocation-free uniform surface. Both are repaired. The final production also preserves caches on unchanged configuration. Native open/edit/Cancel/Undo/Save As, API state/guards/download, PNG/TIFF resource equality, schema/version compatibility and actual Actions24 encode/decode/replay pass. Unsupported editable PSD/Adobe output boundaries remain explicit.

The final Source04 selection runs all 166 cases on that frozen source: 162 pass and four strict cases retain 23 assertions. All 13 new functional cases pass. The other strict cases are the earlier Exposure and gradient comparisons, whose expectations remain unchanged. Source04 changes only one Actions replay test body from Source03; all 856 production Swift files and the app binary are identical. A separate catalog lists 3,077 tests; that list is not a full test run. Source298 remains the last complete qualified inventory and private source backup.

The current binary targets macOS 14 and was tested on arm64/macOS27.0.1. A fresh native inspection first finds no usable window, then confirms the Mac is locked. Physical UI, held-key, 60fps, Intel/macOS 14 and full Photoshop acceptance remain open. The existing shape rasterization limit, complete source metadata/types and editable PSD/PSB/CSH workflows are also open. The next work continues missing major source workflows; numerical refinements remain scheduled after breadth under the maintainer's priority. Normal preview283 and private source298 remain preserved. API/status/plan/command/phase references and both standalone diary copies are refreshed; final integrity and history receipts retain the verification outcome. [Detailed record](DEVLOG.md#dev-step-305).

The documentation checks also identify an existing duplicate Keyboard Shortcuts row in the command ledger: 649 rows represent 648 distinct IDs. This is recorded as an open bookkeeping issue; the shape update changes three evidence cells and no command statuses or scope. The first validator’s contrary uniqueness assumption is corrected against the preserved before-state, with both attempts retained.


## 2026-10-31 — Step306: rich source text migration, in progress

The next source migration feature is editable rich text. PhotoCraft stores character and paragraph runs as UTF-8 byte lengths; native text editing uses UTF-16 ranges. The draft conversion follows the original run normalization, including Unicode boundaries, empty runs and independent character/paragraph spans. Source font identity, traits, OpenType features and variation axes, language, caps, kerning, paragraph justification/leading/negative indents, fractional point/box frames, orientation, antialiasing, warp, original cache pixels and raw type records need to survive migration.

Draft Core fields and a first-edit transaction retain the original source appearance until a real edit changes the text. Native layout/font/paragraph/optical-kerning code, Properties controls, editor placement, source import and shared text API/schema paths are being connected. Native69 and Actions25 are proposed for extended data, with backward-compatible legacy defaults. Unsupported editable PSD output, named source style libraries and source-cache type-to-frame conversion retain explicit boundaries rather than silently dropping data.

Owned fixtures use the unchanged original Rust text engine and its licensed Inter fonts. An offline dependency attempt fails; a registry-enabled second attempt builds dependencies but exposes a harness macro error. Both failures are preserved. The corrected third attempt generates12 variants at each of three depths, including rich fractional boxes, caps, optical kerning, justification, vertical/warped text and empty text. Expected sample arrays cover the declared180×150 document window; they are not Photoshop equality results.

Twelve Swift tests are authored for model/archive/source samples/native editing/API/history/output behavior. Three syntax-only checks pass, most recently parsing1,420 Swift files. No native306 build, link or test run has occurred. A file-state reconciliation at307 inventories26 modified and24 added inputs (11 Swift files and13 fixture/provenance files), with no deletions. This is a retrospective account of the applied file state, not recovered timestamps for each edit.

Next is typechecking and integration repair, fractional-frame UI and API discovery review, then focused native/API/source/cache tests bound to frozen inputs. Live caps/optical/caret/affine behavior, fallback fonts, named styles, complete formats, exact Photoshop behavior, capacity and platform acceptance remain open. Tests from305 or298 do not qualify this newer working tree. No new app is installed or source published. [Detailed in-progress record](DEVLOG.md#dev-step-306).

## 2026-10-31 — Step307: developer diary synchronized with current work

At the maintainer's request, the diary now includes the ongoing306 rich-text work and this documentation-only refresh. Its overview distinguishes unbuilt306, tested305 Source04, the last complete inventory/private source backup298 and installed preview283. Failed oracle attempts, strict output differences and the remaining major workflow/acceptance gates stay visible.

The readable diary, oldest-first index, engineering record, status, plan and phase/working metadata are reconciled. Both single-file HTML copies, narrative downloads and provenance are regenerated. Completed Tasks is not advanced with unfinished work or documentation-only milestones. The independent-implementation process, licensed sources, FOSS terms and private repository/public-on-release-day policy remain explicit.

Verification covers offline resources, anchors/indexes, provenance, matching website copies, dashboard freshness and preservation of application inputs, protected assets and original Rust. It does not run native application tests or establish native visual acceptance. No application code or API behavior changes in this refresh. [Detailed reconciliation](DEVLOG.md#dev-step-307).

The first verification passes all24 checks:307 indexed entries, valid offline resources and anchors, matching source provenance and website copies, and a fresh dashboard journal. All3,007 application inputs,40 protected assets and1,057 original Rust files remain unchanged. The final edition and history index are checked after recording this result. These are documentation checks, not newly passed application tests.


## 2026-10-31 — Step308: rich source text becomes a tested native workflow

The unbuilt306 draft, recorded as such at307, is now integrated and compiled. Original PhotoCraft text retains Unicode run boundaries, source font identity and traits, paragraph fields, fractional frames and baseline placement, orientation/antialias/warp settings, original cache pixels and type records. A real edit leaves the cached appearance through the retained logical transform; accepting unchanged text preserves the cache and avoids an undo item. Undo restores the original. Missing imported fonts use a native editing fallback where supported while keeping their identity.

Native Character/Paragraph and fractional-frame controls share the same Swift transactions as the text API. Native69 and Actions25 preserve extended type and semantic edit replay. Open/edit/Cancel/Undo/Save As/source preservation, authenticated import/state/guards/download, exact native/API transaction equality and real PNG8/TIFF32 resource jobs pass. Adobe's existing text_layer adapter now maps published synthetic faces, all caps, retained AA modes and last-line justification; a real composite PNG job matches native output. Integer Adobe coordinates and explicit unsupported boundaries remain intact.

The build history preserves an initial AppKit color-space compile failure, an intentionally cancelled harness typo attempt and passing repairs. Tests expose a fractional-frame harness that compared the wrong selected baseline and never created its canvas text view; those setup errors are repaired using the real editor and unchanged model equality checks. A PNG job initially uses its helper's default PSD header expectation; the final test explicitly expects PNG and retains exact bytes/header assertions. No original expected samples or tolerances are changed.

Source06 runs all144 focused cases:139 pass, five strict cases retain26 assertions, and no unexpected failure occurs. All16 new functional cases pass. The seventeenth new case compares uncached source text strictly and differs by5,937/4,243/5,773 words across the three depths. All3,564,000 cached original words match; the source arrays cover a declared180×150 document window. Source05 and06 share all864 production Swift files and the same binary; only one test helper argument changes. This is not a complete current test inventory or a Photoshop equality claim.

Earlier Exposure, gradient, curved-stroke and linked PSD/PSB differences remain visible. Named source styles, complete live editing/composer/AA/font behavior, remaining rich source types, editable formats/ICC, capacity and supported-platform/performance acceptance stay open. After all workers end, native inspection still reports the Mac locked. Preview283 and complete private source298 remain preserved. The next work continues missing major source workflows, with numerical refinements deferred under the maintainer's priority. Both offline diary copies and the technical records are refreshed and checked. [Detailed record](DEVLOG.md#dev-step-308).

All30 initial documentation checks pass, including308 entries, portable offline resources and matching provenance/mirrors. All3,007 tested inputs,40 protected assets,1,057 original Rust files and the owned fixtures/fonts remain unchanged. The current arm64 binary targets macOS 14.0/SDK27.0 and ran on macOS27.0.1; physical Intel/macOS 14 and native acceptance remain open. Final records and history are checked after recording this result.


## 2026-10-31 — Step309: source Smart Objects, in progress

PhotoCraft Smart Objects can contain original layered .pcraft sources. Their saved caches are already placed, warped and filtered in document space. Migration must preserve those original bytes and per-instance appearance without applying placement twice or flattening editable content. The new native prerequisites add projective geometry, retained original appearance, offset warp frames, nested source admission, source fingerprints, memory accounting and native70 persistence/negotiation. Sparse affine sources keep their existing bounded path; non-affine preparation retains explicit limits. These are prerequisites; the outer source Smart layer importer remains disabled.

The first optimized build succeeds but an existing published Adobe text job crashes. Its retained diagnostic explicitly identifies cooperative-worker stack exhaustion. Large newly added inline payloads are moved into immutable reference values, without increasing thread stack limits. A second attempt stops at an incorrect test enum name; the corrected third source builds and all five existing NativeTypeWorkflowTests pass, including that Adobe job.

Source03 then crashes later in the Smart Object convert/copy/reset/rasterize/API workflow. Running that case alone also crashes with signal10. The copied report named for this attempt is actually an earlier report; it must not be used to assert the current cause. No completed affected-selection or stable-build claim is made. On the same Source03 binary, a separate isolated run passes all10 new model cases with zero failures. Those cover homogeneous math and bounds, exact integer translations across depths, warp-frame offsets, cached appearance/mask placement/invalidation, native70/temporal persistence, a cooperative-worker command, maximum sparse affine geometry and fingerprint changes. Small model passes do not qualify the crashing workflow.

A reconciliation at310 appends these retained terminal outcomes to DEVLOG and inventories the actual source changes against308. Next is a current crash trace and command/workflow repair, followed by affected tests and complete source/filter/stack/link/UI/API/fixture integration before import activation. Source03 has3,011 frozen inputs; the isolated model pass is not a full current inventory. Strict earlier output differences remain open, as do native/Photoshop/format/capacity/platform/60fps gates. No app is installed or source published. [Detailed record](DEVLOG.md#dev-step-309) · [Working checkpoint](WORKING_CHECKPOINT_309.json).

## 2026-10-31 — Step310: diary brought up to the current engineering record

At the maintainer's request, the overview, oldest-first index and readable diary now include unfinished309 and this documentation-only refresh. Both standalone HTML editions, narrative downloads and provenance are regenerated. The live dashboard's journal remains current without promoting working records into completed features.

The record distinguishes309's passing10-case model subset and crashing workflow,308's last completed focused selection,298's full inventory/private source backup and installed283. Failed attempts, the incomplete current crash diagnosis and all remaining parity gates are retained. No source code, API behavior, command/package status, installed app or repository visibility changes in this refresh. Documentation checks verify offline resources, provenance, mirror equality, dashboard freshness and preservation of source inputs, protected assets and original Rust. These checks are not new application tests or native visual acceptance. [Detailed reconciliation](DEVLOG.md#dev-step-310).

The first documentation verification passes all31 checks:310 entries and links, offline resources and JavaScript syntax, matching provenance and website copies, current dashboard records, and unchanged3,011 application inputs,40 protected assets and1,057 original Rust files. The current Source03 binary also remains unchanged. These are documentation integrity results; the application crash and parity gates remain open.


## 2026-10-31 — Step311: command-worker crashes repaired and the full inventory exercised

The source Smart Object work reveals a crash in an existing native/API workflow. A fresh debugger trace confirms cooperative-worker stack exhaustion when independent copying invokes another validated command through the broad primitive switch. Preserve both debugger attempts; a debugger exit code is not a passing test result. Move the original command bodies into eight smaller handlers that the optimizer must keep separate. A mechanical audit confirms all90 moved case bodies are unchanged, and the outer validation/transaction order remains intact. Add a real worker-thread PreparedEdit/Smart Object copy regression at all three pixel depths, preserving original source bytes, pixels, cache and document identity.

Source01 compiles and completes all137 affected cases:136 pass and the existing uncached-type comparison retains three strict assertions. Both previously crashing API paths now pass. The broader inventory contains3,105 unique tests, all executed in18 fresh bounded processes. It records3,098 passing cases and seven failed cases/30 assertions, with no missing case or crash. Six failed cases/28 assertions are existing strict Exposure, linked PSD/PSB, source fill/gradient, curved-stroke and uncached-type differences. The seventh has two stale version expectations, inherited from an older archive contract. This is a failing full run, not a new fully qualified build.

The evidence scripts encounter a SwiftPM warning spliced into a test identifier and then into the original inventory. Keep both failed parsing attempts and raw logs. A separate-stream inventory corrects exactly one identifier and proves the same class partitions/filters; distinct group16/18 replays preserve terminal results. No native failure is hidden or test omitted.

After all workers stop, Source02 changes only the stale archive-version test: assert complete1…70 reader discovery, roundtrip downloads64…70 and reject the actual unknown71. All24 final cases pass: that HTTP/import/history test, five native type cases, seven Smart Object workflow cases and11 model cases. All868 production Swift files, every other compiler input and the app binary match Source01. The earlier complete execution and later focused repair remain separately attributed; no complete Source02 rerun is claimed. No expected image sample, tolerance or production behavior is changed by the test repair.

The same shared Swift command engine serves native editing and both API interfaces; no route/schema/menu/shortcut/tool/cursor/format contract is added by this repair. Read-only native inspection first reports a missing reference window, then explicitly reports the Mac locked. No screenshot or visual acceptance is claimed. Source Smart layer import remains disabled while its full embedded/link/filter/stack/cache/UI/API mapping and owned fixtures are completed. Native70 is still a prerequisite, not full source parity. Exact output, full current green tests, formats/capacity/native/platform/60fps and all major package gates remain open. Installed283, last recorded full/private source298, artwork and original Rust are preserved. [Detailed record](DEVLOG.md#dev-step-311) · [Checkpoint](WORKING_CHECKPOINT_311.json) · [Evidence](COMMAND_DISPATCH_REFERENCES.json).

The checkpoint integrity verification passes all33 checks:311 indexed entries, valid offline resources and JavaScript, matching provenance/mirrors, fresh dashboard, correct source/result attribution and unchanged3,012 final inputs,40 protected assets and1,057 original Rust files. The final offline edition and history index are checked after recording this result. These documentation checks do not close the remaining native or parity gates.


## 2026-10-31 — Step312: editable original Smart Objects, in progress

The native migration draft now reads embedded original Smart Object files, including layered PhotoCraft projects. It preserves shared source identity, original placed caches/raw records, affine and projective placement, Warp source frames, filter masks, nine mapped filter commands and all eleven source stack modes. Native70 retains the representation. Unsupported linked-source extents, unknown stages and unmapped adjustment/filter programs reject explicitly rather than disappear. The full source manifest remains preserved as provenance. The original Rust app is used only to generate owned reference fixtures; it is not a runtime dependency.

Rasterize, Reset Transform and Replace Contents now account for retained source appearance and source-relative geometry. Native source picking, Photato resource/state/capability schemas, Warp sourceBounds and original-source upload/download are reflected in the draft. Adobe-compatible resources continue to reject original PhotoCraft files, including a disguised filename, because that additional format is a Photato capability. No menu, shortcut or modifier action changes. Recorded Smart Object creation remains explicitly unsupported rather than inventing an Actions26 contract.

The initial offline Rust harness fails because a dependency is absent; a separate registry-enabled attempt builds and produces75 owned variants across all three depths. A machine-specific Cargo fixture manifest is withdrawn from bundled tests and retained in local evidence. The original fixture data and expectations are preserved. A further generator supplies the admitted/rejected nested-depth boundary files.

Source01 builds on3,170 frozen inputs and completes148 selected cases:142 pass, six fail with38 assertions, no crashes or unexpected failures. All57 supported cached variants match1,167,360 original sample words exactly. Native Edit Contents/child commit/Save As/Undo/source preservation, source controls/native70, Warp-frame API and PNG8/TIFF32 jobs pass. Uncached affine translations match; nine projective/Warp/filter assertions remain strict differences. Earlier fill/gradient/curve/type failures remain, and one HTTP case exposes an empty-stack no-op/cache/history defect.

Source02 repairs that no-op and factors projective placement around the original affine controls. It also corrects native visible bounds and Auto-Select, adding independent hit-testing and nested-depth tests. Both targets compile/link on3,174 frozen inputs. The selected test process then crashes with signal10 in the admitted-depth nested-source HTTP case; no completed selection is claimed. A separate current debugger reproduction stops on EXC_BAD_ACCESS in the repeated SmartObjectIO/PcraftImport/PcraftLayerMapper/PcraftSmartObjects chain. Its zero debugger exit is not a test pass. All3,174 inputs remain unchanged after the attempt.

The recursive decoder frames need repair before rerunning the admitted eighth/rejected ninth decode, native/API no-op/hit-testing workflows and affected selection. The draft code branch is connected, but activation is not qualified and312 remains unfinished. Strict numerical differences are retained while major feature breadth remains the scheduling priority. No app is installed or source pushed; all native/Photoshop/full-current/platform/capacity/60fps gates remain open. [Detailed record](DEVLOG.md#dev-step-312) · [Working checkpoint](WORKING_CHECKPOINT_312.json) · [Source-import evidence](SOURCE_SMART_IMPORT_REFERENCES.json).

## 2026-10-31 — Step313: developer diary brought up to the current work

The maintainer requested a diary refresh. The overview, oldest-first index and readable narratives now include312's actual implementation and both native attempts, including the new unresolved nested-source crash. Both single-file HTML editions, narrative downloads and provenance are regenerated. The live dashboard retains its distinction between working records and completed features.

This is documentation synchronization only. It does not repair the crash, rerun native tests, alter API implementation, close a parity package, install an app, publish source or change repository visibility. Source01's completed142/148 focused result, Source02's interrupted selection,311's older failing full execution,298's entirely passing full inventory/private backup and installed283 are identified separately. Offline resources, mirror/provenance equality, current dashboard and preserved input/artifact identities are checked before completion. These are documentation checks rather than Photoshop equivalence or live visual acceptance. [Refresh record](DIARY_REFRESH_313.json) · [Detailed entry](DEVLOG.md#dev-step-313).

The first documentation verification passes all33 checks:313 unique entries/indexes, valid offline dependencies and JavaScript, matching provenance/mirrors and current dashboard. All3,174 application inputs,40 protected assets,1,057 original Rust files and the tested binary remain unchanged. The final edition is regenerated after this note, checked again and included in the refreshed history inventory. These results do not qualify the unfinished application workflows.


## 2026-10-31 — Step314: nested-source crash repaired, major migration continues

The admitted nested-source HTTP fixture exposed a cooperative-worker crash in312. The original trace remains preserved. The repair changes three Imaging files: the layer mapper owns its import context on the heap, document preparation/finalization execute outside recursive decoding, and original-source decoding is separated from larger layer/filter/cache assembly. Validation, budgets, appearance calculations and the eight-level nesting contract remain unchanged. Mechanical checks confirm unchanged layer/appearance bodies and the original nesting file.

The optimized app and test targets build on3,174 frozen inputs in352.01 seconds. The original real HTTP regression now passes:the eighth decode opens; the ninth rejects atomically. On the same source/binary, all150 affected cases execute in25.153 seconds without crashes or unexpected failures.145 pass; five strict cases retain33 assertions. All seven source Smart workflows and four functional Imaging cases pass, including the earlier no-op/cache/history, original projective controls and visible-bounds/Auto-Select fixes, child editing/commit/Undo/Save As, Warp frames, resource jobs and native/API/Adobe-format guards. All57 cached variants still match1,167,360 original words.

The five failed cases compare exact original fill/gradient, curved-stroke, uncached Smart and uncached-text output. No sample or tolerance changes. Earlier Exposure and linked PSD/PSB differences remain open. The62-declaration source-filter audit identifies53 additional mappings beyond the current nine; these and linked-source/adjustment/metadata breadth are the next major work, with numerical refinement deferred under the maintainer's scheduling rule. Native70/Actions25, APIs, menus, shortcuts and cursor contracts are unchanged by this repair. No full-current test pass, live visual acceptance, universal qualification, installation or source publication is claimed. Normal283 and full/private source298 remain preserved. [Detailed record](DEVLOG.md#dev-step-314) · [Working checkpoint](WORKING_CHECKPOINT_314.json) · [Source-import evidence](SOURCE_SMART_IMPORT_REFERENCES.json).

All34 checkpoint integrity checks pass, including source/binary binding, real HTTP boundary evidence, cached words, unchanged strict captures, offline resources/provenance/mirrors and current dashboard. All3,174 tested inputs,40 protected assets and1,057 original Rust files remain unchanged. The final edition is regenerated after this note and checked again before the history inventory is refreshed and verified. These checks do not constitute new native visual or full Photoshop qualification.


## 2026-11-01 — Step315: broad editable source-filter migration

The nine original mappings expand to107 of110 inventoried source commands. This includes59 direct filter commands,47 individual Gallery effects and the Gallery stack. New parameter adapters translate original flat settings to existing native models, preserving source Float32 defaults/clamps, seed bits, aliases, colors, ordered effects, hidden Gallery entries, masks, pins and paths. Relight, Lighting Effects and unresolved Displace source maps remain explicit gaps; parameter/context/depth limits are disclosed through API capabilities. Original source bytes and manifest provenance are retained. Native70/Actions25, menus, factory shortcuts, cursor policy and Adobe's supported input formats do not change.

A standalone structural production probe passes. Three optional standalone test probes cannot load the XCTest Swift overlay correctly; that shortcut is withdrawn and its failures retained. The normal production builds compile the tests successfully. The first owned Rust harness also fails on four string-replacement argument types; a separate corrected attempt builds and generates378 rows across8/16/32 bits, each cached and uncached.357 rows represent supported parameter variants;21 exercise explicit rejection. The independent catalogue combines62 original base declarations and48 delegated Gallery commands. Procedural pixels, generator, raw words, source hashes and license provenance are bundled; Rust is not a production dependency.

Source01 builds on4,319 frozen inputs and executes220 cases:212 pass, eight fail with220 assertions, including two unexpected Lens Blur storage-depth errors. Both App workflow cases pass, but cached/archival loops stop at RGB32 Lens Blur. The strict uncached matrix completes with172 exact vectors,178 numerical differences and seven unsupported depths. No cached all-vector claim is made from that interrupted first loop.

The repair separates stored settings/reference validation from render eligibility. A valid original RGB32 Lens cache survives native persistence and no-op edits; disabling the stage and Undo preserve its appearance. Rendering without that valid cache still obeys the native depth guard, and the RGB32 editor remains unavailable. Missing mask/channel references continue to reject. Explicit HTTP and rasterization regressions cover those transitions.

Source02 builds in454.05 seconds on the same4,319 input count/876 production Swift files. All221 selected cases finish in47.594 seconds:215 pass, six fail with218 strict assertions, zero unexpected errors or crashes. All seven new functional cases pass. All357 saved appearances match274,176 original words exactly; native70/history/source preservation and all119 RGB8 editor/Cancel/API-no-op variants pass. Thirteen richer programs pass native/HTTP editing with identical native pixels/history plus busy/stale guards, and the new RGB32 storage regression passes. The earlier source Smart/nesting workflows remain passing.

The uncached test stays strict:172 vectors match,178 differ numerically and seven reject unsupported depths. Five earlier strict cases contribute33 more assertions. Those and the older Exposure/linked-PSD failures remain open. Three unmapped commands/context, source-mask/transparent-edge/range/depth support, linked originals, adjustment/metadata breadth and all full-current/native/Photoshop/platform/capacity/60fps gates remain unfinished. This is a qualified functional subset, not a stable release or full source parity. No app is installed or source pushed; installed283 and full/private source298 are preserved. [Detailed record](DEVLOG.md#dev-step-315) · [Working checkpoint](WORKING_CHECKPOINT_315.json) · [Source-filter evidence](SOURCE_FILTER_IMPORT_REFERENCES.json).

All37 checkpoint integrity checks pass, including current source/binary binding, original cached words, unchanged strict capture scope, independent fixture/catalogue provenance, offline resources/mirrors and dashboard. All4,319 inputs,40 protected assets and1,057 original Rust files remain unchanged. Work spans31 October–1 November 2026; the completed documentation snapshot uses its finalization date and preserves the original build/test timestamps. The final edition is regenerated and checked again before the history inventory is refreshed and verified.

## 2026-11-01 — Step316: native photographic Relight, in progress

A new deterministic local Relight filter is staged in native Swift, translated from the licensed PhotoCraft renderer. Its six controls change direction, elevation, intensity, ambient light, warmth and softness. The draft includes cancellable tile processing, alpha/hidden-pixel/HDR handling, a bounded192-pixel preview, gesture-aware local Undo/Redo and Smart Filter blend/opacity controls. It connects to the shared document/history and optional API paths, stages source command108 and native71/Actions26 storage, and adds a clearly scoped Filter > Photato > Relight entry. It is not Adobe Harmonize or a generative AI model. No Photoshop factory command or shortcut is substituted.

The first Core typecheck fails on private-helper access. The helper visibility is repaired in source, but that repair has not been rechecked. The first owned Rust fixture generator also fails; its separate repair succeeds and produces19 reference vectors/117 files across8/16/32 bits, including transparency, HDR, identity and a tile-boundary image. Original source and generator hashes and redistribution terms are retained. Successful Rust reference generation is not a native Swift test pass.

Four Core and three Imaging cases now cover the intended kernel/source/history/storage behavior, but none has run. App preview/API/Actions/archive/menu regression coverage is still to be finished, then the actual production source must build and its focused workflows must be tested. The108th source mapping, native71/Actions26 and all new UI/API behavior remain unqualified drafts. Prior315 has215/221 focused passes and six strict failed cases/218 assertions; those results cannot be carried forward as316 qualification. No app is installed or source pushed. [Detailed ongoing record](DEVLOG.md#dev-step-316) · [Working checkpoint](WORKING_CHECKPOINT_316.json).

## 2026-11-01 — Step317: developer diary brought up to the working source

The maintainer requested this refresh. The overview, oldest-first index and readable entries now cover the actual Relight draft, the preserved Core/generator failures and exactly which tests have not run. Both standalone HTML editions, embedded narrative downloads and source provenance are regenerated together. The live dashboard's journal and current-work description are synchronized while completed-package and delivered-preview records retain their existing scope.

This changes documentation only. Application/configuration/fixture inputs and the previously built binary are preserved; no new build, native test, screenshot, installation, GitHub push or repository visibility change occurs. The latest completed focused tests remain315, the last full execution311, the last entirely passing full inventory/private backup298 and the normal installed preview283. Offline resources, links, JavaScript, mirrors/provenance and original/protected input identities are checked separately from application correctness. Relight316 remains in progress and the full Photoshop-parity goal stays active. [Refresh record](DIARY_REFRESH_317.json) · [Detailed record](DEVLOG.md#dev-step-317).

## 2026-11-01 — Step318: photographic Relight becomes a tested native workflow

The316 draft now builds and works through native editing, preview/local history/Cancel/full-resolution commit, editable Smart Filter opacity/blending, shared Photato API/history, native71 and Actions26. Source command108 of110 maps to the actual Swift renderer. Six-control photographic Relight stays in its clearly named Photato submenu, without a new default shortcut. Generative Harmonize/Firefly and multi-light Lighting Effects remain separate requirements.

All13 new cases pass on Source06:four Core, three Imaging and six App workflows. Seven direct Float32 vectors match143,100 original words, and19 source rerenders match164,076 original words exactly. The19 cached-source cases pass saved appearance, native storage, rasterization and Undo. Native/API pixel equality, invalid/busy/stale rejection, preview restart, source retention, Actions replay/version guards and PNG8/TIFF32 resource jobs are covered. The full affected selection finishes258 cases:252 pass, six earlier strict cases retain218 assertions, with zero unexpected errors or crashes. Earlier357 cached filter vectors remain exact;178 uncached numerical differences and seven unsupported-depth results remain open.

Failed attempts are retained. Source01 catches the PSD export enum; Source02 catches Observation/BlendMode declarations; Source03 is deliberately cancelled for a statically identified bad HTTP fixture/unsafe unwrap; Source04 links the app but finds a private test helper; Source05 runs252 cases and identifies stale version expectations and a Core fixture color-encoding error. Source06 changes nine test files, preserving all879 production Swift files and the same app binary. Fixture input storage is made explicitly linear, every expected word remains unchanged, and supported71/invalid72/explicit PSD boundaries are tested. The summary identifier separator mismatch is repaired only in postprocessing. No failure or image tolerance is hidden.

The binary is arm64 with minimum macOS 14. The806-entry menu regression,102 primary/eight alternate shortcuts and nine menu/nine shared-cursor cases pass; this new filter adds no tool/modifier action. Exact Photoshop equivalence, complete source/context/depth/capacity/performance/native/universal/platform acceptance and a passing current full suite remain unqualified. No app is installed or source pushed; normal283/full-private298 are preserved. Continue major Lighting Effects/Displace/source-context work. [Detailed record](DEVLOG.md#dev-step-318) · [Checkpoint](WORKING_CHECKPOINT_318.json) · [Relight guide](RELIGHT.md) · [Evidence](RELIGHT_REFERENCES.json).

## 2026-11-01 — Step319: multi-light Lighting Effects, still in progress

The next major workflow adds native point, spot and infinite lights, signed intensity/linear color, material and surface controls, six source texture channels and document alpha references. The sheet offers a bounded preview, draggable light/target/direction handles, light selection/add/duplicate/delete/toggle, local history/Reset/Cancel, four local styles and strict JSON preset Load/Save. Smart blending, shared Photato API/state/schema, native72, Actions27 and source command109 are staged. Displace remains unmapped. The clearly named Photato menu extension preserves captured Photoshop factory rows and shortcuts. Global Colorize, full Adobe styles/interchange and cross-document alpha identity remapping remain open.

An owned Rust harness generates64 procedural original-engine reference vectors/387 licensed, hashed files across8/16/32 bits. Direct application and source Smart rendering use separate expected words. Source01 fails on a missing exhaustive PSD-read branch; Source02 fails on an unavailable AppKit color-space member. Their separate repairs reach Source03:the optimized build takes325.09 seconds, and all273 selected cases execute in85.936 seconds.256 pass;17 fail with309 assertions/84 unexpected errors, zero crashes. Eight of15 new cases pass. All22 direct Float32 vectors match169,320 original words; all64 cached appearance vectors match242,736 words before failing archive checks. Uncached source output matches59/64 vectors. All16 actual preview modifier combinations/captured modes/focus/capacity tests pass, but do not establish live visual or physical performance acceptance.

Failures identify missing native72 indexed-header recognition, incorrect alpha-fixture depths, a stale source-count expectation and source empty-list fallback semantics. Source04 stages repairs while preserving all expected pixel words and tolerances. It then fails compilation on optional PcraftNode diagnostic access; no tests run, and the binary remains Source03. The proposed first-difference capture is unexecuted. Two translated16/32-bit vectors each retain24 differing words in the last actual run. All four archives/logs/results and the failed tests remain visible. No functional completion, Photoshop equivalence, full test pass, installation or source publication is claimed. Normal283 and last entirely passing full/private source298 remain preserved. [Detailed record](DEVLOG.md#dev-step-319) · [Working checkpoint](WORKING_CHECKPOINT_319.json) · [Lighting guide](LIGHTING_EFFECTS.md).

## 2026-11-01 — Step320: developer diary brought up to the actual build evidence

At the maintainer's request, the overview, chronological index and319/320 entries now describe the current Lighting Effects work, all four attempts, the last273-case result and the failed current-source compile. Both standalone HTML editions, embedded narrative downloads and source provenance are regenerated together. The dashboard's journal/current-work text is synchronized while delivered-preview and package-completion scope stays unchanged. The stale Source01-running Lighting reference is corrected to the terminal result.

This is documentation-only work. All4,837 current application inputs/884 production Swift files, the retained Source03 binary,40 protected identities and1,057 original Rust files are checked unchanged. No new app build/test, native capture, installation, GitHub push, API/schema modification or visibility change occurs. Documentation checks cover index continuity, offline resources, JavaScript, downloads, links, mirrors/provenance and dashboard freshness; the development evidence inventory is refreshed/checked separately. Current319 remains incomplete, earlier Relight318 retains its scoped qualification, last full execution311/last green private source298/installed283 remain distinct, and the overall goal stays active. [Refresh record](DIARY_REFRESH_320.json) · [Detailed record](DEVLOG.md#dev-step-320).

All44 initial documentation/preservation checks pass, including320 continuous milestones, both indices, standalone resources/downloads/JavaScript, matching provenance/mirrors, current dashboard and all frozen/protected/original identities. This result is recorded before a final regeneration/recheck and evidence-index audit. No application test result is changed.

## 2026-11-01 — Step321: Lighting Effects becomes a tested native workflow

The optional-node compiler repair lets the actual app/test targets build and verifies319's staged fixes. Source01 builds in366.42 seconds and executes273 focused cases:266 pass, seven strict cases fail with220 assertions, zero unexpected errors/crashes. All14 new functional cases pass:four Core, two Imaging and eight App workflows. Native/API editing, presets, named alpha references, Smart blending/re-edit, preview/local history/Cancel/commit, native72/Actions27 persistence, source retention, jobs and16 actual modifier gesture combinations are tested.22 direct Float32 vectors match169,320 words;64 cached vectors match242,736 words and archive/history checks. Uncached source output matches62/64 vectors; two translated16/32-bit cases each retain24 boundary RGB differences. Original words and tolerances remain unchanged.

The complete current inventory contains3,153 cases. Eighteen bounded processes finish all of them:3,142 pass,11 fail with227 assertions/two unexpected descriptor errors, no crashes,702.672 seconds of XCTest time. A warning-corrupted initial inventory/collector and singular-summary aggregation defect are preserved and corrected only in collection. Each reused group's exact case set and source is independently matched. A sample of the long-running group shows actual paged box-filter scratch writes/fsync, not a hung PDF test inferred from buffered output.

Two broad-run failures come from stale tests:804 menu entries instead of807, and generic Adobe descriptor coverage incorrectly including native Relight/Lighting. Source02 changes just those two test files, retains all884 production Swift files and the same binary, builds in107.19 seconds and passes all30 affected API/menu/Core checks in1.020 seconds. The3,153-name inventory is identical. Earlier full Source01 is not retroactively green, and no current full rerun is claimed; nine strict cases/224 assertions remain open, including older Exposure and linked PSD/PSB comparisons.

Source mapping reaches109/110 commands, with native72/Actions27 and shared API metadata. Lighting remains a partial Photoshop command:global Colorize, full Adobe styles/preset interchange, cross-document alpha remapping, native visual/menu/output/platform/capacity/performance acceptance and other broader parity requirements remain open. Fresh CUA inspection reports the Mac locked. No app is installed or source pushed; normal283 and last entirely passing full/private source298 remain preserved. The diary, command/reference/API/status/phase records and both offline editions are refreshed and checked. Continue major Displace/source-context and broader migration work. [Detailed record](DEVLOG.md#dev-step-321) · [Checkpoint](WORKING_CHECKPOINT_321.json) · [Lighting guide](LIGHTING_EFFECTS.md) · [Evidence](LIGHTING_EFFECTS_REFERENCES.json).

All49 initial checkpoint integrity checks pass, including exact full-inventory case-set/log binding, current source/binary, original/protected identities and synchronized offline/dashboard records. The final edition is regenerated and checked again before refreshing/checking the evidence index. These checks do not change the nine strict output failures or native/Photoshop/platform acceptance.

## 2026-11-01 — Step322: Original Displace maps become editable native workflows

The remaining original Displace command now maps to typed source references and optional embedded one/two-channel Float32 maps. Original file/session hints are retained without granting access or inventing the old document identity. Explicit file selection or API samples bind a map without8-bit quantization. Missing-map warnings, original unresolved identity behavior, fractional controls, transparent edges and source-reference placement work through native preview, local history, Cancel/commit/re-edit, Smart Filters and document Undo. Native73 and Actions28 persist the settings; earlier native8-bit behavior keeps its existing contracts. Shared HTTP/state/schema/capabilities and Photato-only native resource input accompany the feature. Adobe input restrictions/proprietary descriptor rejections remain explicit.

Five frozen attempts document the implementation. The first two stop during compilation (helper defaults, then warning-row tooltip placement). Source03 builds and executes322 cases with311 passes, revealing bound sampling and workflow/test setup gaps. Source04 repairs source-reference edge sampling/Float32 reduction and Photato native resource admission, and all43 cached/unresolved/bound references become exact; it passes314/322 with one missing transfer opt-in causing the remaining new failure. Source05 changes one test setup line, builds in107.53 seconds and executes322 cases in114.382 seconds:315 pass, seven prior strict cases fail with220 assertions, zero unexpected errors/crashes. All13 new cases pass. All885 production Swift files and the app binary are identical across Source04/05;5,188 frozen inputs bind the evidence.

All43 owned reference cases match206,028 original words per cached, unresolved and bound comparison set, across8/16/32 bits. Those sets overlap. Original Rust is used only as a licensed procedural fixture oracle; production remains native Swift. All reference words/tolerances and original source files remain preserved. Existing Lighting/Relight/cached-source checks retain their documented results. All110 source filter command IDs now map, but parameter/context/depth/source-project and Photoshop parity remain incomplete. No649-command status or104-package closure is inferred from the mappings.

No complete inventory runs at322. The latest complete321 Source01 result is still3,142/3,153 with11 failed cases; two later test-contract repairs pass30 checks on unchanged production, leaving nine known strict cases overall. This focused322 selection reruns seven, with older Exposure and linked PSD/PSB failures still open. Native lookup does not establish a visible app, and no fresh screenshot/live UI acceptance occurs. Binary inspection is arm64/minimum macOS 14, not universal or supported-host runtime qualification. No app is installed or source pushed; installed283 and last entirely passing full/private source298 remain preserved.

The maintainer requests the diary be brought current. Refresh its overview, continuous index and this narrative, related API/status/reference/phase records and both self-contained HTML editions, preserving the process note and release-day repository policy. Verify source/binary/fixture/protected identities, historical records, offline resources/embedded Markdown/provenance/JavaScript, dashboard freshness and the history inventory. Next major breadth is source adjustment-layer migration, currently limited to Exposure, followed by source contexts/metadata. Full strict/native/Photoshop/platform/capacity/performance requirements remain open. [Detailed record](DEVLOG.md#dev-step-322) · [Checkpoint](WORKING_CHECKPOINT_322.json) · [Displace guide](SOURCE_DISPLACEMENT.md) · [Evidence](SOURCE_DISPLACEMENT_REFERENCES.json).

The diary synchronization passes45 integrity checks, including all322 entries, offline downloads/provenance/mirrors, unchanged tested source/binary, protected/original files and current dashboard records. A verifier syntax error is preserved before its repair; it does not change application code. The history inventory is refreshed and checked separately; these documentation checks do not establish additional Photoshop functionality.

## 2026-11-01 — Step323: Original adjustment layers become editable native workflows

Original migration previously admits Exposure alone. Add typed original Float32 controls and a native renderer for all16 executable adjustment kinds plus opaque Unsupported records; retain the earlier Exposure classic import representation. Brightness/Contrast legacy/modern, Levels, Curves, hue/ranges, color/weights/matrices, lookup cubes, steps and gradients preserve original values without integer UI rounding. Native Properties, explicit cube selection, shared API create/set/apply/state/schema, selection masks, history, native74/Actions29 and retained source originals accompany the model. Unknown records/profile-only lookups remain visibly inactive. CMYK/Lab tone evaluation and broader source contexts remain open.

Five frozen attempts record the work. Source01 compiles Core then catches a missing throwing-call marker; Source02 compiles Core/Imaging then catches the chooser's reader type; Source03 builds the app then catches a test Action step label. Source04 changes only those test labels and executes355 cases with349 passes/six failures/191 assertions, zero unexpected errors/crashes. All129 direct source-reference vectors match107,844 words. Ten new cases pass, but the HTTP test calls nonexistent Undo/Redo command names, and full-document comparison exposes source composition context. All attempts, source hashes and errors remain retained.

Source05 corrects those test calls and implements original adjustment blending and post-layer whole-level RGBA grids separately from existing native adjustments. Linear samples avoid unnecessary32-bit conversion; hidden colors retain exact bits. The whole-document test distinguishes original unrounded buffers and native stored-depth output using separate unchanged oracles. Build465.74 seconds;355 cases finish68.843 seconds:350 pass,five strict cases fail with111 assertions, zero unexpected errors/crashes. Eleven of12 new cases pass (Core4, Imaging3 functional, App4). All129 direct vectors stay exact. Stored composites improve5→86/129 (RGB8 43/43, RGB16 40/43, RGB32 3/43); unrounded working composites match83/129. Existing Exposure and Float32 context differences remain strict failures. No expected word or tolerance is relaxed.

The owned fixture oracle has43 programs/129 depth rows/778 files, with unchanged licensed Rust used only for procedural reference generation. Production stays native Swift.5,976 frozen inputs/892 production Swift files bind the tested binary. Source-only controls preserve original semantics; complete Photoshop output/UI/default equivalence is not inferred. No complete inventory executes at323. Nine prior strict cases plus this new whole-document case are known; the latest complete inventory remains321 Source01 and its separately passing two-test repair. At least ten known strict cases do not exclude other untested current regressions.

After compiler/test workers terminate, fresh CUA lookup returns no accessible Photoshop window; no screenshot/live visual acceptance occurs. Offscreen Properties layouts and software/API tests are not physical UI or60fps qualification. Native deployment inspection is arm64/minimum macOS 14, not universal/Intel/macOS 14 runtime acceptance. No application is installed or source pushed; installed283 and last entirely passing full/private source298 remain preserved. Refresh guides/reference/API/status/plan/phase/command evidence, human overview/index/narrative and both offline editions, preserving earlier records and process/release policy. Next major breadth is source layer-effects translation, followed by channels/guides/global-light/metadata and remaining source contexts. [Detailed record](DEVLOG.md#dev-step-323) · [Checkpoint](WORKING_CHECKPOINT_323.json) · [Guide](SOURCE_ADJUSTMENTS.md) · [Evidence](SOURCE_ADJUSTMENT_REFERENCES.json).

All46 checkpoint integrity checks pass, including the323-entry diary, frozen source/binary, preserved originals/protected assets, strict reference counts, retained attempts, offline resources/provenance/embedded downloads/mirrors and dashboard freshness. The history inventory is refreshed and checked separately; these record checks do not qualify additional functionality or resolve remaining source/Photoshop differences.

## 2026-11-01 — Step324: original layer-effects work is underway

The next major migration gap is original layer effects. Ten effect kinds already have native counterparts, but the earlier model cannot retain many source options. This unfinished increment adds typed contours, glow/bevel/texture variants, gradient and pattern paint, reference positions and opaque PSD data. It also stages shared document global light, atomic multi-layer style transactions, closed JSON validation and prospective native75 handling. Legacy wire compatibility is intended, not yet proven by tests.

Imaging helpers now cover source distance/chamfer maps, dilation, tent blur, contour/range lookups, shadows/glows/satin, prepared gradients/patterns and bevel height/light maps. They are not yet connected into a tested full effect compositor. Source-project translation, usable native editing/preview/Cancel, API/schema/capabilities/patch commands, Actions30 persistence and independent original-engine references remain unfinished. The original Rust renderer ignores some fields it retains; keeping those values does not implement their Photoshop behavior.

An earlier Core structural typecheck exits0 in73.928 seconds with warnings. Two Core files change after that check. No preserved terminal receipt establishes the latest parse-only result, and no optimized324 app build or XCTest has run. The current workbench contains5,982 inputs/898 production Swift files: six production files added, ten modified, none deleted compared with the preserved323 baseline. The binary remains tested323 Source05. Diary325 retrospectively records these intervening edits with explicit provenance rather than inventing original timestamps or results. No installation, push or visual acceptance occurs. [Detailed record](DEVLOG.md#dev-step-324) · [Working checkpoint](WORKING_CHECKPOINT_324.json).

## 2026-11-01 — Step325: the diary catches up with the workbench

The requested refresh brings the overview, chronological index, latest narratives, dashboard and both standalone diaries up to date. It separates unfinished324 source work from tested323 adjustments, the latest complete321 inventory, the earlier entirely passing/private298 source and installed283 preview. The product page's diary teasers also now point to tested323/322/321 workflows. Older entries, failed attempts, the engineering-process note and the FOSS/private-until-release policy remain intact.

This is documentation-only work. Preservation checks cover all5,982 application inputs/898 production Swift files, the retained323 binary,40 protected identities and1,057 original Rust files. The offline diaries retain embedded CSS/JavaScript, provenance and Markdown downloads. Documentation validation checks continuity, resources, JavaScript syntax, mirror equality and dashboard freshness; evidence-index validation is separate from application testing. No new app tests, source changes, API behavior, installation or GitHub publication are claimed, and no package status or delivered build is promoted. [Refresh evidence](DIARY_REFRESH_325.json) · [Detailed record](DEVLOG.md#dev-step-325).

## 2026-11-01 — Step326: original layer effects become editable native workflows

The324 draft reaches a tested functional checkpoint:all ten source effect kinds retain advanced records and editable controls,with native preview/Cancel/history,source import,shared global light,API access and native75/Actions30 saving. Pattern hints never open files or substitute artwork; retained original PSD data remains inert. The captured Global Light menu path now opens a dedicated dialog that changes document light without adding or replacing a layer style. Existing factory menus/default shortcuts and the shared tool-cursor policy remain intact.

Independent original Rust APIs generate138 direct effect vectors and138 source projects/full working-output references using owned artwork. The first two harness attempts fail compilation and are preserved before repairs. A standalone Swift module-emission probe crashes inside the compiler; the normal optimized build succeeds. Source01 passes23/24 cases; Source02 integrates the usable workflows and passes62/66. Source03 repairs an incorrectly read test schema and adds whole-project comparisons on identical production/binary. Those comparisons reveal gradients using tile allocation instead of original content bounds. Source04 fixes the actual frame, reducing project differences7,086→575 without changing an expected pixel. Source05 adds the native Global Light menu/dialog and its regression. Source06 removes an inactive generic row from the advanced-bevel UI and explains appearance changes. Source07 corrects stale source-import capability text and verifies typed effect/adjustment/archive discovery.

The final frozen source has6,685 inputs/902 production Swift files. Build307.77s;67 focused cases finish11.004s:64 pass,three strict cases fail136 assertions,zero unexpected errors/crashes. All16 new functional cases pass;the17th remains strict. Direct output matches83/138 vectors (393,576 words compared;622 differ). Imported-project working output matches75/138 (393,576 words;575 differ);each scope matches45/46 RGB32 vectors. These sets overlap. Two older fill/gradient strict cases remain too. Every failure,repair,source/binary identity and oracle stays recorded.

Noise/jitter/anti-alias and several other source-retained switches remain inactive. Expanded controls can change legacy appearance. Vector/text/off-canvas/transform/ICC/PSD/Adobe descriptor contexts,exact Photoshop output,full-current tests,native/platform/Intel/capacity/physical60fps remain open. Fresh native Photoshop access returns cgWindowNotFound,so there is no live visual acceptance. No app is installed or source pushed;normal283 and entirely passing/private298 remain preserved. The diary,website mirrors,dashboard and evidence records are synchronized,while I03 and the full goal remain open. Next comes original channels/guides/metadata breadth. [Checkpoint](WORKING_CHECKPOINT_326.json) · [Detailed record](DEVLOG.md#dev-step-326) · [Source-effect guide](SOURCE_LAYER_EFFECTS.md).


## 2026-11-01 — Step327: diary reconciled with tested source and remaining major work

At the maintainer's request, reconcile the diary against engineering326 and the actual324 Source07 test receipts. The previous edition already included326, but its dense overview did not make recent major workflows and build delivery easy to distinguish. Replace the current overview with readable tables for source filters, Relight, Lighting Effects, Displace, adjustment layers and layer effects. Keep each workflow's tested scope and open comparisons alongside its progress. Add the327 index entry and this account; preserve every prior narrative and the engineering-process note.

The latest application evidence is unchanged: 6,685 frozen inputs, 902 production Swift files, native75/Actions30 and206 typed commands. The latest affected run passes64/67 cases, including all16 new functional cases, with three strict failed cases/136 assertions and no unexpected errors or crashes. The latest complete inventory remains321, the last entirely passing full inventory/private complete source remains298, and the installed preview remains283. No passing current full suite, complete source/Photoshop parity or new delivered build is inferred from the documentation update.

Record the intervening channels/prepress investigation as investigation only. Existing native alpha and Multichannel ink workflows do not yet provide original-project auxiliary/spot-channel migration; the source importer still requires empty channels/guides, no Quick Mask and default metadata. This is next major work, with remaining modes/ranges/linked contexts also open. No channel model, renderer, UI, API or persistence code changes in this refresh.

Regenerate both standalone HTML diaries and their Markdown/provenance companions from the same sources. Verify chronological continuity, preserved earlier entries, current source hashes, embedded resources/downloads/JavaScript, mirror equality and dashboard journal freshness. Check the unchanged application inputs and binary, protected release/reference identities and original Rust; refresh and check the history inventory separately. No application tests are rerun for this documentation-only change. Package/command acceptance, APIs, installed283, private source298, artwork and release policy remain unchanged. [Refresh evidence](DIARY_REFRESH_327.json) · [Engineering record](DEVLOG.md#dev-step-327).


## 2026-11-01 — Step328: original channels and auxiliary spot workflows become editable

Extend existing alpha/Quick Mask and separate Multichannel ink support with ordinary-document auxiliary SpotInk color/Solidity. Black adds ink, white removes it, and changes to Solidity leave every separation sample untouched. Native creation/options/name/color/conversion, selection initialization, Cancel/stale protection, gray/overlay viewing, painting, history, native76 and API createSpot/configure/state/schema/download negotiation share the native engine. Original RGB8/16/32 projects import alpha/spot/Quick Mask with exact numeric coverage and retained names/options. Unknown fields, invalid spot Quick Mask, excess count, depth mismatch and nondefault off-canvas samples reject atomically.

The owned Rust fixture harness first fails coordinate typing, then succeeds after explicit u32-to-i32 conversions without changing original sources. Three projects, twelve planes and three ordered two-ink previews have per-file provenance. The native Source01 build reaches App then fails a shared non-Sendable static schema and unsupported AutomationValue equality. Source02 fixes those API compilation issues, builds328.39 seconds and passes101/102 cases in12.466 seconds. All12 new cases pass;12 planes match2,244 Float words and three overprints match2,244 RGBA words. An older archive test still expects supported75 to reject. Source03 corrects that contract to reject77 and positively round-trip73–76, builds39.41 seconds and passes all102 cases in11.229 seconds, zero failures/unexpected errors/crashes. Its904-file production and app binary are identical to Source02; no expected oracle or tolerance changes.

This qualifies a functional subset. PSD/PSB separations, simultaneous auxiliary visibility, Merge Spot, color libraries, printing/export policy, semantic channel Actions and exact Photoshop/native visual behavior remain open. Fresh Photoshop lookup returns cgWindowNotFound; no live screenshot/acceptance occurs. The current102-case selection does not execute at least eleven retained older strict failures or establish a current full-green inventory. Installed283 and the last entirely passing full/private298 source stay unchanged, with no installation or push.

Update the source-channel guide/reference, API/version metadata, native archive recognition, command evidence and phase328 progress, human overview/index, both standalone diary editions and menu/cursor references. C02 moves open to in_progress, I03 remains in_progress, and no package is closed. Existing factory menu/shortcut inventory and all16-combination cursor policy remain; nine menu and nine cursor regressions pass. Continue remaining prepress and guides/metadata major breadth. [Checkpoint](WORKING_CHECKPOINT_328.json) · [Guide](SOURCE_CHANNELS.md) · [Evidence](SOURCE_CHANNEL_REFERENCES.json) · [Engineering record](DEVLOG.md#dev-step-328).


## 2026-11-01 — Step329: PSD/PSB channels share the native file workflow

Ordinary RGB/Gray/CMYK/Lab PSD/PSB files now retain alpha, spot and Quick Mask planes with supported display records, names, IDs and Quick Mask index/flags. All four codecs use shared bounded row/scratch infrastructure. Imported Float32 spots retain original editing-gray words until a sample changes; depth changes clear only incompatible retained gray. Native77 preserves this metadata through history and desktop/API transfers. The56-plane boundary requires proven opacity before dropping a redundant transparency plane; transparent overflow rejects. Desktop Save permits the existing streamed backend for large canvases, with300,000-square policy admission covered separately from unqualified physical maximum-size editing/export. TIFF auxiliary mapping and private color-book records reject explicitly.

Independent generation uses pinned psd-tools1.26.0 and public format structures:80 owned cases plus one licensed corpus input,118 attributed fixture files and1,226,640 auxiliary sample words. A separate reader verifies all81 captured native outputs against those expected raw planes and metadata. Input/output scopes overlap and are not Photoshop-generated rendering references. The original Rust writer's modern display-record stride differs from the independently documented layout; it is not treated as an oracle. The second corpus input's private color-book/large native-mode context remains unqualified. CUA lists Photoshop running but reports a locked Mac after normal activation; manual unlock is requested without bypassing it.

Source01 reaches test compilation and fails a missing try. Source02 builds and passes118/119 cases; Source03 corrects an old native-version expectation and passes119/119. Inspection then discovers a retained Float32 gray lifecycle bug during bit-depth conversion; repair the actual Core/ordinary/ink conversion paths and add a fifth Core case. Source04 passes171/173, Source05 passes176/177; remaining failures are older supported-version expectations. Source06 updates the final indexed archive contract and passes177/177 including all14 new Core/Imaging/App cases, zero failed assertions/unexpected errors/crashes. Source04–06 production/binary and all expected sample oracles are identical. All six frozen attempts, failed patch/reference inspections, independent results and source hashes are retained.

Update engineering/human diaries, API/version/state, status/plan, command evidence, phase329, menu/cursor evidence and both standalone HTML/Markdown/provenance editions. Existing factory inventory and modifier policy remain unchanged; nine menu/nine cursor regressions pass. C03 moves open to in_progress; C02/I03 remain in progress and all 104 scopes/acceptance criteria remain. No whole package closes, no full-current or Photoshop/platform/60fps/capacity acceptance is inferred, and no install/push occurs. Continue major functional breadth with earlier strict numerical differences retained. [Checkpoint](WORKING_CHECKPOINT_329.json) · [Guide](PSD_AUXILIARY_CHANNELS.md) · [Evidence](PSD_AUXILIARY_CHANNEL_REFERENCES.json) · [Engineering record](DEVLOG.md#dev-step-329).


Diary presentation updated at step329: replace the introductory slogans and promotional copy with plain headings and descriptions. Historical entries, test results, attribution, process disclosures and release policy are retained. This changes documentation only; neither application API is affected.


## 2026-11-01 — Step330: document guides and source layout import

Original projects with guides can now open as editable documents. Guide positions retain the original Float32 words. The native app provides New Guide, Edit Selected Guides, New Guide Layout, preview/Cancel, ruler dragging, selection, lock/show/clear and guides from layer bounds. Rows, columns, margins and gutters produce a guide layout; Move snapping uses the current integer layer-position precision. Option changes guide orientation during dragging; Shift snaps to pixel ruler ticks, and Shift+Option-click selects multiple guides. Cursor feedback follows the dispatched action, including add/subtract selection and focus cleanup. Command temporarily suppresses layer snapping on macOS.

Guides save through native78/history and PSD/PSB resource1032, including supported ordinary, restricted and Multichannel paths. Unchanged file records retain bytes/order and grid header words; edited coordinates quantize to1/32 pixel. Older native opaque guides become editable at shared desktop/API admission before a new guide can overwrite them. Empty guide/grid headers keep their earlier native compatibility. Guide colors persist natively; PSD/PSB explicitly rejects custom colors until modern color records are implemented. Both API commands, schemas, state, availability and invalid/busy/stale behavior use the native engine. Semantic guide Actions and Adobe guide descriptors remain unsupported.

The owned reference harness uses unchanged original Rust crates. Its first attempt stops on the crates’ compiler-version declaration; the second uses the same explicit development override as earlier reference work and succeeds. Three projects provide30 source guide words and source-formula1032 records; two separately assembled public-format inputs check framing. Source01–03 expose and repair Core/App integration and test-isolation compilation errors. Source04 runs292 cases:287 pass, all17 new cases pass, five older cases fail. The failures identify three old command-count expectations and an empty-guide-header admission bug; the latter is repaired in production. Source06 passes296 cases after the shared count repair. Source07 adds an explicit PSD/PSB rejection for custom guide colors so they cannot be silently discarded. All attempts are retained separately. Source07 passes all297 affected cases in34.021 seconds, including all18 new cases, with no failed assertions, unexpected errors or crashes. The independent reader verifies8 exported files/80 guide records exactly. Native/source sample references and tolerances are unchanged.

Update the command matrix with the two previously untracked selected-guide factory commands, enable partial progress for ten existing guide/snap rows and record208 typed API commands. U05 is in progress as a dependency of major I03; no package closes. Existing factory menu order/shortcuts and other tool policies remain; nine menu/nine cursor regressions pass. Modern color records, broader ruler/grid/guide/snap/Actions/preferences and full-current/Photoshop/native/platform/capacity/60fps acceptance stay open. The Mac is locked, so no live Photoshop visual result is claimed. Installed283 and private complete298 remain unchanged, with no installation or push. [Checkpoint](WORKING_CHECKPOINT_330.json) · [Guide](DOCUMENT_GUIDES.md) · [References](DOCUMENT_GUIDE_REFERENCES.json) · [Engineering record](DEVLOG.md#dev-step-330).


A source review also records a remaining pointer issue when Space is held during an active guide drag: the guide remains captured, while the cursor can fall through to Hand/the selected tool. This is outside the tested four-modifier matrix. It remains in the guide/gesture backlog; no live Photoshop comparison is claimed.


## 2026-11-01 — Step331: Xcode archive and alpha store preparation

The maintainer requested an archive and validation under ca.forensicintelligence.photato, followed by a free App Store page with images and video. The copy must identify the alpha limitations and AI-aided development. All releases require manual approval. The diary has passed checkpoint 300; the wider project-migration work started there remains unfinished.

The project now has an AppStore configuration derived from Release. Its shared archive action enables sandboxing, selected-file read/write, persistent bookmarks, printing and the network access needed by optional features. The app identifier is updated, while native document and clipboard identifiers are retained. A privacy manifest records local file metadata and app timing uses. Debug and Release keep the local ad-hoc signing workflow. No editing implementation or API contract changes.

Xcode archives Photato 0.3.0 (331) for Apple Silicon and Intel. The archive carries the FI team’s Apple Development signature; App Store distribution export uses the distribution identity. Twenty local checks pass, including code signing, architectures, minimum OS, entitlements, notices, icon and symbols. An initial diagnostic incorrectly required a profile in the development archive; that failed check is preserved and corrected. The first Xcode validation attempt exposes an export-option error. After repair, validation reaches the account gate: App Store Connect access for the FI team is required. Neither attempt establishes Apple validation.

The local store draft includes a name, subtitle, promotion, description, keywords, categories, verified live URLs, review notes and the original supplied icon. It describes working feature categories without claiming professional parity. A four-image and 25-second preview plan calls for real application captures with owned artwork. App Store Connect still needs sign-in; the locked Mac blocks capture. No app record, media upload, free-price setting or manual-release setting has been saved remotely. Apple’s beta-testing policy directs this alpha toward TestFlight qualification. No review submission, tester distribution or release occurred.

A full Release attempt records 2,119 completed cases (9 failed) before an AppKit recovery-autosave wait blocks the main thread. Sampling first confirms active large-file decoding; that Smart Filter/API case passes. A later sample shows the user-interaction wait with no progress. Only the verified disposable test process is terminated. The underlying cause, and whether the locked host contributes, are unresolved. Preserve this as an incomplete inventory, with strict comparisons intact. The previous focused guide qualification remains 297 passing cases; the last entirely passing full source checkpoint remains 298.

Thirteen preservation/static checks pass, including the original Rust source, supplied artwork and previous build/source identities. REL01 is now in progress; no major package is closed. Both offline diary editions are regenerated. Account access, genuine media capture, autosave investigation, current full qualification, supported-platform checks and release readiness remain outstanding. [Preparation record](APP_STORE_PREPARATION.md) · [Detailed record](DEVLOG.md#dev-step-331).


## 2026-11-01 — Step332: Window lifecycle, recovery and updated archive

Investigation of the interrupted331 run found background workers blocked in window animation. The initial spinner hypothesis did not hold: stopping or replacing the progress control did not prevent exhaustion. A controlled 200-window probe reproduced the problem without any progress control. Disabling transitions on app-owned windows kept background work available. The repair uses public AppKit window and panel subclasses; system alerts and file panels keep their normal behavior. A regression test repeats the lifecycle and verifies exact document recovery afterward. This measures the failure mechanism, not screen refresh rate.

The first focused run exposed layered TIFF recovery failing because its metadata carrier was treated as though it also contained a PSD merged-transparency plane. The decoder now respects the external TIFF composite. Twelve depth, byte-order and opacity combinations round-trip exact layer samples. Broader tests then exposed custom document-controller initialization happening after AppKit had created a base singleton. Startup and the viewport fixture now install the custom controller first. Panorama cancellation tests use a gated worker so cancellation is measured while work is active. Stale archive, auxiliary-channel and large-canvas format assertions were corrected without relaxing numerical comparisons.

All370 affected tests and13 fresh viewport cases pass. The complete inventory runs 3,242 unique cases with 12 failed cases retained. Earlier incomplete reports survive: compiler warnings had interrupted test names in combined output, and a diagnostic parser missed the singular “1 failure” summary. Separate stdout/stderr capture and exact case-set checks repair the reporting. One obsolete archive75 rejection is then repaired and checked separately; other numerical failures remain open. No full-green or monolithic long-session result is claimed.

Xcode creates Photato0.3.0(332), a universal sandboxed archive for ca.forensicintelligence.photato, with all 20 local package checks passing. Apple validation still needs FI account access. App Store Connect sign-in and the locked Mac prevent saving the requested listing settings or capturing genuine screenshots/video. The free/manual-release/alpha drafts and supplied icon remain prepared locally. No upload, submission, distribution or release occurred. Installed283, private complete source298, original Rust sources and artwork remain preserved. Both offline diary editions are refreshed. Full parity, supported-platform runtime, physical60fps, maximum capacity and distribution readiness remain open. [Details](DEVLOG.md#dev-step-332).


## 2026-11-01 — Step333: Validation after Xcode sign-in

The maintainer signed in to local Xcode. We checked the existing332 archive’s binary identity and retried Apple validation. It still stops at the FI team’s App Store Connect access requirement, without changing the archive. Native automation reports the Mac locked; the browser remains at Apple Account sign-in. The remaining request is to keep this Mac unlocked, confirm FI Forensic Intelligence team membership in Xcode Accounts and sign in to App Store Connect. The precise account or permission problem is not established.

The retry and limited diagnostic classifications are saved separately from earlier failures. No credentials are copied into the project or diary. No source, API, application tests, archive, media or remote listing settings changed. Free alpha/AI-aided-development copy and manual-release requirements remain prepared locally. Nothing was uploaded, submitted or released. Both offline diary editions are refreshed. [Record](DEVLOG.md#dev-step-333).


## 2026-11-01 — Step334: Native File Info and source metadata

With App Store access pending, work returned to major editing functions. File Info had a factory menu entry and shortcut but no native action. Original PhotoCraft projects with nondefault document metadata also rejected. The licensed source implements eight descriptive XMP fields; the native editor now supports those fields through Description and Raw Data pages, the existing factory shortcut, document history and a shared file.info API. It leaves pixel/channel targets and protected layers alone. Cancel, unchanged values and stale/busy requests preserve the committed document.

Apple ImageIO handles XMP, keeping unedited properties and localized alternatives. Descriptive IPTC/TIFF values are carried where supported. Source XMP, raw EXIF, named image resources and global-block payloads are retained with the manifest. Opaque globals remain source provenance; they do not become trusted rendering programs. Full metadata interpretation and export fidelity remain unfinished. No native archive or Actions version change is needed; the API now has209 typed commands.

The owned Rust harness first failed a declared toolchain minimum, then an Arc-copy mistake. Both attempts survive; the corrected harness generates three source-depth projects and24 expected values without editing the original crates. The first two Swift builds expose test-fixture type/selection errors. A third run passes158/160 cases and exposes two issues: comparing fresh random fixture identities, and byte differences between native/API metadata. A Foundation probe reproduces nondeterministic binary property-list ordering. The new writer uses XML properties; strict document equality remains enforced, with a new30-edit native-file byte comparison.

Source04 passes all161 affected cases and14 new cases, with no failed assertions, unexpected errors or crashes. An independent Python parser verifies six PSD/PSB outputs,48 field values and exact named-resource bytes. The source/binary hashes bind the result. Full Photoshop File Info panels/templates, exact serializers, further IPTC/EXIF/global interpretation and export, semantic Actions, live UI/platform and full-current qualification remain open. No major package closes. Store archive332, installed283 and private complete source298 remain unchanged; no new archive, installation, publication or release occurs. Both offline diary editions are refreshed. [Record](DEVLOG.md#dev-step-334).

### Photoshop 2026 as the reference — step335

The maintainer clarified that PhotoCraft Rust is a source of inspiration and Photoshop 2026 is the gold standard. The project instructions and current plan now say this explicitly. Work is chosen from missing Photoshop workflows, in the existing major, minor and final-detail order. Finishing the Rust migration is not a prerequisite for adding a Photoshop feature. Rust comparison results remain useful regression evidence, but they do not prove Photoshop compatibility. Existing source attribution and earlier test records are retained.

This checkpoint changes documentation only. The tested334 source and binary, store archive332 and command/package inventories are preserved. No new function or parity closure is claimed. Both offline diary editions are regenerated; application tests are not rerun for this guidance change. [Record](DEVLOG.md#dev-step-335).

### Layer Comps and production export — step336

Production export needed saved layer variations, while the native Layer Comps menu entries had no implementation. The new Swift model records visibility, position and appearance without copying pixels. A floating panel handles named comps, comments, property choices, apply/update, duplicate/delete/reorder, previous/next and the state before application. Missing layers remain warnings. Native79 retains the records, and three API commands share native history, state and validation.

Comps export to PSD, PSB, PNG, JPEG, TIFF and Photato files or a multipage PDF. Each variation begins from the same source. File exports stage a complete new folder and preserve an existing destination; the API returns ZIP or PDF without filesystem access. Cancelling or revoking access returns no archive. Editable Photoshop comp metadata remains unsupported; ordinary PSD/PSB saves reject it rather than silently discard it.

The first build stops at an overlapping-access error in a new test. The second compiles the application but rejects an incorrect test-helper call. The third runs260 cases with257 passes: old tests still reserve native79 as invalid, and a new API test expects400 where semantic errors correctly return422. Those test expectations are repaired without changing production code or weakening pixel checks. Source04 passes all260 affected cases and17 new cases. Independent CoreGraphics page rendering checks red/blue PDF samples, order and dimensions.

An initial ledger draft duplicated the existing L08 package after an audit looked only at phase1. The draft is preserved and corrected:104 scopes remain; saved comps are a dependency of I05 production export, while optional local libraries stay in phase2. The existing PDF export menu was missing from the CSV and is now recorded. A final inventory check also finds two identical Keyboard Shortcuts rows; the redundant row is removed with the draft preserved. The ledger had the same duplicate and omitted the existing Embed All Linked command; both are corrected. The matrix and phase ledger now each contain651 distinct commands. This corrects the inventory, not the feature count. No package closes.

Photoshop’s published guide is the reference; the Mac is locked, so no live UI or Photoshop-generated comp fixture was acquired. Smart Object comp selection, editable PSD resources, complete warnings, geometry/timeline behavior, docking/defaults, Actions and full/platform/performance qualification remain open. Store332, installed283 and private full-source298 are unchanged. Both offline diaries are refreshed. [Record](DEVLOG.md#dev-step-336).

### Smart Object comp selection — step337

The Smart Object Properties panel now offers the source document's named Layer Comps. Each placed instance can use a different comp while sharing the original source. Choosing one updates its cache through a native history transaction; original bytes, placement, masks, styles and filters remain. Source replacements rebuild the choices independently. A deleted selected comp stops the replacement atomically, and linked originals require existing authorization and matching fingerprints. Native80 keeps the choices; one new API command shares the native preparation, history, state and errors.

The first expanded run passes362/364 cases. A new test looks for compID at the schema envelope instead of inside parameters; correcting the assertion gives all13 new cases passing. The other failure is the linked PSD/PSB cached-pixel mismatch already recorded at332. Both diagnostic vectors match that earlier run exactly, and the strict comparisons remain enabled.

A review also finds selected revisions rehashing the full source during state reads. They now use the cached base revision. The added64MiB Core regression first exposes an overlapping-access error in its fixture; that failed compile is preserved and the fixture is repaired. Source04 passes all14 new cases and364 of365 affected cases, with no unexpected errors or crashes. One thousand revision reads take25.894ms. This does not establish physical60fps or Photoshop pixel parity.

The Mac remains locked, so no live Photoshop or Photato controls are verified. Parent comp recording of Smart Object choices, Photoshop resource descriptors, full warning/nested/source-change behavior, Actions, complete suite and platform/performance gates stay open. All 104 packages remain open. Store332, installed283 and private full-source298 are preserved. The diary's335/336 index cells are aligned with their existing date/milestone columns; dates and records are retained. Both offline copies are regenerated. [Record](DEVLOG.md#dev-step-337).


### Parent Layer Comp Smart Object choices — step338

Adobe's Photoshop guide lists a fourth property when creating a parent comp: the Layer Comp selection of each Smart Object. The native panel and API now record those source/choice IDs without storing extra pixels. Applying a saved parent variation or exporting it prepares current child artwork first, then commits the whole change in one Undo transaction. Last Document State retains choices from before preparation. Shared sources are decoded once per parent application, with independent selections and cached distinct renders. Embedded selections propagate under the existing nesting budget; nested linked originals still need an explicit resolver.

Linked reads use existing grants and file fingerprints. Native bookmark access alone does not authorize API file reads. Source identity changes, missing child choices, stale source bytes and permission changes reject atomically. Native 81 keeps the parent records; ordinary comps/per-instance choices retain their older feature versions where applicable. The command catalogue stays213. CONTRIBUTING's stale statement that Rust defines behavior is corrected: Photoshop 2026 is the acceptance standard.

All 13 new cases pass. The expanded optimized selection passes 377 of 378 cases, retaining one existing strict linked PSD/PSB cached-pixel case with two failed assertions, zero unexpected errors and no crashes. Its diagnostic vectors match checkpoint 332. Source02 freezes 6898 inputs and 926 production Swift files. No full-current-suite or Photoshop equivalence is claimed.

The first run passes374 of378 cases. It exposes a real API routing regression: ordinary comp capture is incorrectly sent through the linked-artwork commit guard. The repair uses that permission only for changed child-cache preparation. A cancellation fixture also rotates its file authorization after registering the API grant, so it is reordered; strict live-worker assertions remain. The nested expected state is strengthened by manually selecting its child. Failed and repaired inputs/logs are kept separately.

The Mac remains locked, so this is functional native/API/PDF-reader evidence and not a live Photoshop comparison. PSD comp resources/descriptors, full warnings/geometry/timeline/defaults, Actions, platform/capacity/performance and complete current-green gates remain open. All 104 scopes stay open. Store332, installed283 and private full-source298 remain unchanged. Both offline diary copies are regenerated. [Record](DEVLOG.md#dev-step-338).


### Editable PSD/PSB Layer Comps — step339

The saved-variation workflow now reaches Photoshop files. Public Adobe envelopes, MIT ag-psd field definitions and one independent saved file guide the mapping. Two fixture paths have identical bytes. The file contains a no-property comp and inherited visibility values; a primary report also describes how Photoshop2026 handles omitted visibility. Those findings replace earlier arbitrary restrictions. No Photoshop script implementation is copied, and the locked Mac prevents a new owned reference capture.

Supported catalogues, comments, integer IDs, visibility/position and prior state become native editable comps. Embedded shared sources retain separate selected child comps. Appearance changes, parent child-comp records and other unqualified fields retain explicit loss guards. Source01 passes all11 new cases and406/407 affected cases, retaining the old linked-cache mismatch. The separate reader initially verifies only8-bit layers; support for alternative16/32-bit sections repairs four reader failures. Original effect-reference fields are also preserved and tested in Source02, whose11 new cases pass.

Review finds that a nil typed library in an older native file can still hold opaque Photoshop comps. Saving must preserve those records. Explicit Clear now records native82 intent, with state/schema, history and recapture handling. Two further regressions cover the legacy and clear cases, plus real HTTP clear/download assertions. The exact older resource and per-layer records survive an unmodified legacy save. The legacy library is retained rather than automatically migrated.

All 13 new cases pass. Source03 passes 408 of 409 affected optimized cases; one existing linked PSD/PSB cache case retains two strict failed assertions. Both diagnostic vectors match332. There are no unexpected errors or crashes. The separate reader verifies six output files across8/16/32-bit PSD/PSB metadata. These are native/independent-format checks, not Photoshop2026 execution or full-current-suite acceptance.

The six Source01/02/final output sets overlap; they are not independent new fixtures. Native/API/Adobe output checks and the separate metadata reader do not prove Photoshop rendering or universal platform acceptance. Rich interchange, full legacy migration and all other parity gates remain open. All 104 scopes stay open. Store332, installed283 and private full-source298 are unchanged. Both offline diaries are refreshed. [Record](DEVLOG.md#dev-step-339).


### Editable PSD/PSB Global Light — step340

Native shared-light controls existed, but Photoshop-file saving rejected explicit document light and changed participating shadows to local values. The shared encoder now carries both resources, global/local flags and inactive local angles. Both effect renderers use a consistent shared direction; local bevel altitude no longer follows document light. Conservative native migration preserves conflicting fallback behavior. PSD precision and unsupported rich effects keep explicit save guards.

The first optimized run builds and completes484 cases:478 pass,6 fail,136 assertions and4 unexpected decode/lifecycle errors. Ten new cases pass. The new public-fixture assertion is wrong: that file contains light resources but no modern styles. A separately extracted MIT public descriptor records shared angle132° with inactive local120°; its exact628 bytes and license become a test fixture. The full original effect file is not claimed as supported. Two existing transfer tests need native75 negotiation after light promotion. Another retained strict test catches resource order changing on unmodified saves. The repair preserves order, names and padding, with a positive edit assertion. The original failures and pre-repair files remain preserved.

All 11 new cases pass. Source02 passes 482 of 484 affected optimized cases, retaining two existing strict comparison failures (120 assertions): linked PSD/PSB cached pixels and source-effect words. Their diagnostic vectors match332. There are no unexpected errors or crashes. A separate reader verifies resources and style flags in six 8/16/32-bit PSD/PSB outputs. Native round trips and independent metadata checks do not establish Photoshop2026 pixel/UI equivalence or full-current-suite acceptance.

The11 new cases cover dialog/API/history/Cancel, native adoption, Adobe output, malformed resources, all depths, independent format metadata and failure atomicity. The private source-effect and linked-cache diagnostics match332; their strict checks remain. There is no live Photoshop acceptance while the Mac is locked. All 104 scopes remain open; no release or installation occurs. Both offline diary copies are refreshed. [Record](DEVLOG.md#dev-step-340).


### Production Export As workflow — step341

The former Export As binding opened a basic save panel. This increment adds an asset workspace and Quick Export/preferences. Current Adobe documentation supplies the workflow and published per-output layer contract. Photoshop itself remains inaccessible while this Mac is locked, so no new live UI/default comparison is claimed.

Native workers prepare independent document/layer/group/artboard assets, scales, canvas sizes, profiles and limited metadata. Cancel/history/source behavior and HTTP output share the engine. Quick preferences and last Export As settings stay separate, and persistent API preference writes use the existing permission gate. Adobe create-composite gets layer references/crop modes and selection-aware output caching; editable single-group PSD uses the existing serializer. No new Adobe route or drawing tool is invented.

Source01 stops at a wrong geometry type reference; Source02 stops at a misplaced API schema-validation block. Both fail before runtime tests, with their inputs/diagnostics and repairs preserved. Source03 builds and runs316 cases:311 pass,5 fail, with one unexpected fixture error. Fifteen new cases pass. A noncontiguous group fixture, wrong imported-profile assumption, malformed UUID error class and two stale command-count assertions are repaired. The separate reader catches generated metadata under None; the encoder now strips descriptive PNG/JPEG metadata without changing samples or selected ICC tags. Every failed run and pre-repair file remains preserved. Source04 passes all316 affected cases. A final review then removes an unintended second resampling when changing export coordinates. Original pixels, masks and affine transforms now remain intact, with a nineteenth regression checking retained data and RGB8 appearance. Preview updates coalesce and wait for canceled encoders to finish before starting replacements. The test set includes deterministic cancellation/revocation, preference and existing-file preservation, privacy filtering, menu shortcuts and asynchronous Adobe output. The independent PNG reader checks owned analytical pixels rather than Photoshop images.

All 19 new cases and 317 affected optimized cases pass, with no failed assertions, unexpected errors or crashes. A separate reader verifies five owned PNG outputs and 412 analytical RGBA channels. This is native/format evidence; full-current-suite and Photoshop2026 output/UI/platform acceptance remain open.

Full production export, exact Photoshop encoders/options/UI, maximum dense processing, supported platforms and physical performance remain open. No entire package is closed. Installed283/private full298/store332 are unchanged. Both offline diary editions are refreshed. [Record](DEVLOG.md#dev-step-341).


### Layers to Files — step342

This missing production command now exports individual layers through a native folder/options workflow. Adobe's current guide defines the visible controls. The implementation uses existing Swift codecs and private staging, with source checks before publication. Eye visibility is kept separate from opacity; groups supply retained ancestor context. The same selection implementation now serves published Adobe output layers, and canvas fills no longer inherit an unrelated alignment restriction.

Native PSD/PSB/Photato streams files independently of the API aggregate budget. Other formats use their existing encoders, including native indexed PNG. The folder transaction refuses existing names and rolls back only matching newly linked files after failure. Shared API settings/state/progress/cancel preserve source/history. The first compile fails on an encoder initializer's argument order and is repaired without withdrawing formats or assertions; every attempt remains in the detailed record. The first runtime run passes329 of331 cases. BMP/Targa need their own native destination path, and two numeric schema bounds need Double values for the existing validator. After those repairs all331 pass. A final comparison aligns Export As with batch/Adobe ancestor context; the final source repeats all331 passes.

All 14 new and 331 affected optimized cases pass, with zero failures, unexpected errors or crashes. The independent reader verifies four PNGs and384 analytical RGBA channels. A260-file native batch totals137216120bytes and publishes successfully while the128MiB API ZIP correctly rejects it. These owned/native checks do not establish full Photoshop2026/default/UI/codec/platform/capacity or current-full-suite acceptance.

The260-file boundary uses tiny owned images and metadata, not maximum-size real artwork. Complete Photoshop/UI/default/codec/platform/current-suite acceptance remains open. All 104 packages stay open, and installed283/private full298/store332 remain unchanged. Both offline diary editions are refreshed. [Record](DEVLOG.md#dev-step-342).


### Color Range selection — step343

The factory command now opens native sampled-color and tonal controls, with localized clusters, pipettes and mask/image/matte previews. Existing selections constrain the result. Save/Load use portable Photato JSON presets. One shared native transaction supports desktop/API Undo and explicit-coverage Actions; preview, cancellation, stale-source checks and sharing revocation preserve the source. The independently written analytical kernel is documented. Skin Tones/Detect Faces, Out of Gamut, Adobe preset compatibility and exact Photoshop masks remain open.

All 14 new and 127 affected optimized cases pass, with zero failures, unexpected errors or crashes. The separate checker verifies10 analytical mask bytes. Sparse300000×300000 classification is tested; physical maximum-capacity editing,60fps, complete current suite and Photoshop numerical/UI/default/platform acceptance remain open.

All 14 new cases cover native math, profiles/depths, previews/history, API equality/errors/revocation and 16 modifier combinations for every sampler. The source/test changes, setup repair and every build attempt are preserved in the detailed record. Both standalone diary copies are regenerated. No new installation, archive, source push or release; all 104 scopes stay open. [Record](DEVLOG.md#dev-step-343).


### Magnetic Lasso — step344

The toolbar's existing Magnetic Lasso entry now uses an independent Swift tracer. Width, Contrast, Frequency, tablet pressure, Feather and anti-aliasing accompany fastening points, Delete, closure and temporary freehand/straight segments. The source snapshot, captured selection mode, incremental previews, modifier cursors, lifecycle cancellation and one Undo transaction share the API replay model. Photoshop's exact tracing algorithm and defaults remain unqualified;32-bit availability follows Adobe's published restriction.

All 14 new and 235 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate checker verifies all 768 analytical mask bytes. Sparse 300000×300000 output is tested; physical maximum dense capacity,60fps, the complete current suite and exact Photoshop paths/pixels/defaults/UI/platform behavior remain unqualified.

All 14 new cases pass. The independent mask is owned analytical artwork; sparse maximum dimensions do not prove dense capacity. The diary retains every failed attempt and repair. Both standalone copies are refreshed. No new installation, archive, push or release; all 104 scopes remain open. [Record](DEVLOG.md#dev-step-344).


### Selection Modify and Reselect — step345

Border, Smooth, Expand and Contract now have native controls, cancellation, validation and one Undo transaction. Their independent disc extrema/median and centered borders operate on tiled grayscale coverage. Reselect retains the previous deselected rectangle or soft mask in this open document; identity/size/read/close changes clear recall. A strict shared preparation path permits document selection edits in component/mask contexts without admitting pixel changes. Two API commands expose the same operations and state. No new native or Actions format is required.

All 14 new and 323 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 1,920 analytical mask bytes across four odd/even borders. Sparse 300,000 × 300,000/constant-plane admission is tested. Exact Photoshop kernels/gray coverage/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 14 new cases pass, with source/target preservation, HTTP/native equality, recall/history, admission/error/revocation, factory menu and lifecycle checks. Both standalone diary copies are refreshed. Complete S01 and all 104 scopes stay open. No new install, archive, push or release. [Record](DEVLOG.md#dev-step-345).


### Transform Selection — step346

The selection boundary now has scale, rotation, move, skew, distort, perspective and flip controls, including numerical values, reference positions, contextual menus and captured modifier cursors. Preview work transforms a bounded contour off the main actor; final coverage is resampled once from the original mask. Pixels, layers, masks, channels, profile, depth and editing targets are preserved. One new API command shares the same history and cancellation path; native 82/Actions 30 stay unchanged.

All 14 new and 356 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 320 analytical GRAY8 bytes across four transforms. Sparse 300,000 × 300,000 projective admission is tested. Exact Photoshop sampling/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 14 new cases pass, covering native/API equality, lifecycle/source/target preservation, history/Actions, invalid/busy/stale/revoked/canceled work and all 16 modifiers. Both standalone diary copies are refreshed. Full S01/G01 and all 104 scopes remain open. No new install, archive, push or release. [Record](DEVLOG.md#dev-step-346).


### Selected-pixel Free Transform — step347

Command-T now handles ordinary RGB raster selections, using the same scale/rotate/skew/distort/perspective/reference controls as boundary transforms. Pixels are lifted from the immutable source and composited onto the cut remainder; newly transformed off-canvas content stays in layer storage. Native previews use a bounded image proxy without changing the document. The desktop, API, Undo/Redo and semantic Actions share the same engine. Old Action versions remain readable; selected-pixel steps require31. Native82 remains unchanged.

All 16 new and 424 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 3,072 analytical RGBA channels across four selected-pixel transforms. Sparse 300,000 × 300,000 admission is tested. Exact Photoshop sampling/soft overlap/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

All 16 new cases pass, covering native/API equality, preview/lifecycle/source/target preservation, raw identity, off-canvas masks/storage, history/Actions, invalid/busy/stale/revoked/canceled work and all 16 modifiers. Both standalone diary copies are refreshed. Full G01/S01 and all 104 scopes remain open. No new install, archive, push or release. [Record](DEVLOG.md#dev-step-347).


### Background layer semantics — step348

Background is now a layer identity rather than a name. Opaque RGB File/New documents create it; old documents retain their prior meaning. Layer/New conversion, the native options sheet, lock/name behavior, Clear/Cut/Eraser, canvas geometry and file/API persistence follow this model. Conversion and edits have shared history and portable Actions32. Published create-composite accepts Background add/edit/delete and explicit conversion; the existing JSON output describes its role.

All 20 new cases pass. Of 603 affected optimized cases, 602 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python parser verifies six owned8/16/32-bit PSD/PSB Background records. Sparse300,000 ×300,000 opaque planes are tested. These checks do not establish Photoshop output/UI/default equivalence, full-current-suite acceptance, supported-platform coverage, maximum dense capacity or physical60fps.

Both standalone diary copies are refreshed. Full L01 and all 104 scopes remain open, including richer conversion/selected-pixel contexts. No new installation, archive, push or release. [Record](DEVLOG.md#dev-step-348).


### Background selected-pixel Free Transform — step349

Background selections now use the existing Free Transform modes, numeric controls and previews. Vacated pixels use the background swatch captured at the start. The layer remains opaque and canvas-sized; ordinary layer behavior is retained. Apply/Undo/Redo, semantic Actions33 and the shared API use the same captured value. Native83 and227 commands remain.

All14 new cases pass. Of617 affected optimized cases,616 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels across four Background transforms. Sparse300,000 ×300,000 editing and clipped virtual support are tested. Exact Photoshop pixels/soft overlap/interpolation/defaults/UI, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

The14 new cases include captured palette/preview/commit, native planes/HDR/three depths, all16 modifiers, API/profile/PSD/history equality, cancellation/stale/revoked work, lifecycle and bounded previews/storage. Both standalone diary copies are refreshed. All 104 scopes remain unclosed. No new installation, archive, push or release. [Record](DEVLOG.md#dev-step-349).


### Move and copy selected pixels — step350

Move/V now handles selected image content before Auto-Select. A captured source and bounded coalesced proxy supply previews; release commits one Move transaction. Shift constrains, arrows nudge1/10pixels and Option copies on the same layer. Native/API/Actions34 share the selected-pixel compositor and target/lifecycle/history guards. Background holes remain opaque. The API now has228 commands; native83 stays unchanged.

All16 new cases pass. Of633 affected optimized cases,632 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels for ordinary/Background move/copy. Sparse300,000 ×300,000 copies are tested. Exact Photoshop pixels/soft overlap/defaults/gestures/cursor art/live UI, key-repeat scheduling, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

Both standalone diaries are refreshed. All 104 scopes remain unclosed. No new install/archive/push/release. [Record](DEVLOG.md#dev-step-350).


## 2026-11-02 — Step 351: Pixel-mask Free Transform

Whole unlinked pixel masks now use the shared Free Transform controls, six modes, reference positions and numeric fields. The engine changes raw mask coverage and placement while retaining the layer and mask properties. Coalesced previews include gray/overlay views. Native/API history, target guards, cancellation and Actions35 accompany229commands; native83 stays unchanged.

All 16 new cases pass. Of 711 affected optimized cases, 710 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 186 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 masks are tested. Exact Photoshop samples, mask bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](DEVLOG.md#dev-step-351).


## 2026-11-02 — Step 352: Auxiliary-channel Free Transform

Whole and selected auxiliary channels now use the shared Free Transform controls, six modes, reference positions and numeric fields. Whole projection shares the mask sampler; selected coverage shares the immutable-source compositor. Other channels/layers, display metadata and retained spot gray survive. Coalesced previews honor channel gray/overlay modes. Native/API history, target guards, cancellation and Actions36 accompany230commands; native83 stays unchanged.

All 16 new cases pass. Of 744 affected optimized cases, 743 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 768 analytical grayscale samples across four transforms. Sparse 300,000 × 300,000 channel planes are tested. Exact Photoshop samples, channel bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](DEVLOG.md#dev-step-352).


## 2026-11-02 — Step 353: Multi-layer and group transforms

Multiple layers and groups now share affine scale, rotation, skew and fixed transforms around common bounds/reference controls. Parent/child targets normalize to root subtrees. Editable content, hierarchy, masks and Smart Object sources survive. Coalesced previews leave the original document/history intact; projective collection modes remain unavailable. Native/API history, target guards, cancellation and Actions37 accompany231commands; native83 stays unchanged.

All 16 new cases pass. Of 851 affected optimized cases, 850 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 5120 analytical RGBA channels across four transforms. Sparse 300,000 × 300,000 layers are tested. Exact Photoshop samples, collection bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](DEVLOG.md#dev-step-353).


## 2026-11-02 — Step 354: Projective layer transforms

Distort and Perspective now work on supported whole RGB pixel layers, resolved Smart Objects and their groups. Inverse projection uses bounded paged patches without a dense UV map. Linked masks share the edit; unlinked masks keep world placement. Smart sources remain editable. Six-mode native controls, captured modifier feedback, coalesced previews and API state/history are integrated. Projective Actions38 preserve old affine37;231commands/native83 are unchanged. Unsupported editable target types are explicit and remain unflattened.

All 16 new cases pass. Of 963 affected optimized cases, 960 pass; 3 cases retain 12 failed assertions. There are zero unexpected errors and no crashes. An independent Python checker verifies 10240 analytical RGBA channels across eight ordinary/Smart-mask outputs. Sparse 300,000 × 300,000 projective layers are tested. Exact Photoshop samples, bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

All 104scopes remain unclosed. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](DEVLOG.md#dev-step-354).


## 2026-11-02 — Step 355: Layer links and whole-layer Move

Persistent links now connect regular layers and groups without flattening them. Individual links can be temporarily disabled; Select Linked Layers includes those partners without changing document history. Enabled partners and descendants join Move and whole-layer Free Transform once. Move/V without a pixel selection now previews whole-layer translation or Option-copy, preserving pixel storage and Smart sources. Copies use independent link groups. Native panel/menu controls,16modifier cursor modes, history, API graph/state/schemas and PSD/PSB resources1026/1072 are integrated. Native84 and Actions39/40 retain older feature minima.

All 22 new cases pass: 9 model, 5 imaging and 8 application cases. Of 1128 affected optimized cases, 1125 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent readers verify 10240 RGBA channels across eight owned Move/copy outputs and link records in six PSD/PSB files. Sparse 300,000 × 300,000 Move/copy storage is tested. Exact Photoshop behavior/output, live UI, the full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

Transform Again, full linking contexts and all 104 scopes remain open. No install/archive/push/release. Both standalone diary editions are refreshed. [Record](DEVLOG.md#dev-step-355).


## 2026-11-02 — Step356: Color Fill and Stroke

The missing raster Stroke workflow now has native width/color/Inside-Center-Outside/mode/opacity/transparency controls. Solid-color Fill can blend at partial opacity, reaches the selected canvas beyond a small layer's storage, and retains palette choices/Content-Aware handoff. Raster/mask/auxiliary planes share one cancellable transaction; channel display inversion is applied once, masks and off-canvas source pixels retain placement, and live content is not rasterized implicitly. Portable Actions41 and235API commands preserve prior format minima. Width250, the edge kernel, initial settings and full preferences remain unqualified against Photoshop.

All 17 new cases pass: 7 model, 8 application and 2 imaging cases. Of 1178 affected optimized cases, 1175 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. An independent reader verifies 1080 alpha bytes across nine owned Stroke outputs. Sparse 300,000 × 300,000 Stroke and implicit full-canvas Fill are tested. Exact Photoshop edges/blends/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical 60fps remain unqualified.

All 104 scopes remain open. No installation, push, archive or release. Both standalone diary editions refreshed. [Record](DEVLOG.md#dev-step-356).


## 2026-11-02 — Step357: Pattern Fill

Pattern is now a Fill source with a native Custom Pattern choice. Document assets take precedence over library IDs, and each request captures its asset. The shared engine applies selection/canvas coverage, blend/opacity, raster transparency and scalar display rules, preserving untouched words and mask positions. Portable Actions42 carry the asset rather than depend on a later library lookup. Existing pixels.fill/state/schemas expose pattern selection and explicit native placement while keeping235commands/native84 and old solid41minimum. Full phase/sampling/profile/default/picker/range behavior remains unqualified.

All 13 new cases pass: 6 model, 5 application and 2 imaging cases. Of 1204 affected optimized cases, 1201 pass; 3 retain 12 failed assertions. Zero unexpected errors or crashes. Independent modulo/pixel and PNG readers verify 4320 RGBA bytes across eight owned raw outputs and one PNG. Sparse 300,000 × 300,000 localized and implicit-uniform pattern fills are tested. Exact Photoshop phase/kernel/profile/defaults, live UI, full current suite, supported platforms, dense maximum capacity and physical60fps remain unqualified.

All 104complete scopes remain open. No installation, source push, archive or release. Both standalone diary editions refreshed. [Record](DEVLOG.md#dev-step-357).


## 2026-11-02 — Step358: Large-document Crop

Remove the16MP canvas and64MP aggregate RGB delete guards. Exact copies and rotated delete samples use bounded pages; Background expansion avoids a full-canvas Boolean array. Native width/height fields, preview and API share the range. Source/export resolution remains full size. History, cancellation and immutable prepared-source validation stay shared.

18 of 19 new cases pass: all 8 model and 7 application cases, and 3 of 4 imaging cases. One strict encoded-sRGB Float32 PSB sample comparison remains open. Of 1268 affected optimized cases, 1264 pass; 4 retain 13 failed assertions. No unexpected errors or crashes. Independent readers verify 432 RGBA bytes in eight owned integer crop vectors and one PNG. Maximum 300,000 × 300,000 sparse delete/retain/rotation, implicit saved channels,40.5MP Background output and80000wide PSB are tested. Dense maximum capacity, exact Photoshop interpolation/defaults/UI, full current suite, supported platforms and physical60fps remain unqualified.

All 104complete scopes remain open. No installation, source push, archive or release. Both standalone diary editions refreshed. [Record](DEVLOG.md#dev-step-358).

## 2026-11-02 — Step359: layer capacity

Remove the inconsistent512native/64API layer ceilings. Common document admission, native panel filtering, bulk hierarchy operations, native persistence and supported PSD/PSB/API workflows now use the declared8,000-layer development target. The exact Photoshop2026 ceiling remains unverified; Rust is a supporting reference only. Preserve separate algorithm/frame/file/memory limits and Adobe's100-reference output bound.

All 19 new capacity cases pass. Of 648 affected optimized cases, 640 pass; 8 retain 149 failed assertions. There are 1 unexpected errors and 0 crashes. Independent readers verify four owned PSD/PSB files: 32,000 layer names, 8,000 raster records or 16,000 group/divider records per file, and 128,000 raw channel bytes.

The exact Photoshop 2026 layer ceiling remains unverified. Dense stacks, sustained interaction speed, live UI, complete Photoshop output, supported Macs, the full current suite and physical 60fps are not qualified. All 104 complete package scopes remain open. No installation, source push, archive, upload or release. [Record](DEVLOG.md#dev-step-359).

## 2026-11-02 — Step360: Flatten Image

Add the missing Layer > Flatten Image workflow, native hidden-layer confirmation, shared composition/history, Photato operation/state/schema, semantic Actions43 and Adobe flattenImage/FltI descriptor support through both resource-job interfaces. Preserve saved document state and numerical native planes in the supported single-layer case; specialized compositors remain required.

All 19 new cases pass. Of 312 affected optimized cases, 312 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent checks verify 48 RGBA bytes across three analytical vectors and three PNGs, plus six PSD/PSB headers.

This is a working Flatten Image increment. Layered/transparent native components, palette/ink and temporal flattening still need their numerical/plate/frame compositors. Full Photoshop output/defaults/live UI, complete L02 merge/rasterization, supported platforms, dense capacity and physical60fps remain open. All 104complete scopes are preserved. No installation, source push, archive, upload or release. [Record](DEVLOG.md#dev-step-360).

## 2026-11-02 — Step361: Duplicate Image

Add Image > Duplicate with an editable name, merged-layer option and cancellation. Whole-document copying retains editable and numerical state; the copy has independent native history and no saved file association. Shared preparation powers the new document.duplicate API (201). Merged static RGB output retains transparency; unsupported specialized composition remains visible.

All 15 new cases pass. Of 233 affected optimized cases, 233 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify 48 RGBA bytes across three document depths.

Merged native component, palette/ink and temporal composition, multi-document Actions, exact Photoshop output/defaults/live UI, supported Macs, full current suite, dense maximum capacity and physical 60fps remain open. All 104 complete package scopes remain open. Rust comparisons do not determine Photoshop acceptance. [Record](DEVLOG.md#dev-step-361).

The final lifecycle review caught a focus bug: a copy could be registered while its source was still busy or its sheet was closing, leaving the original tab active. The source now clears its busy state before presentation, and a pending presentation waits for the native sheet to detach. Closing the queued copy removes the request. The passing 15-case feature set includes this repair. Earlier attempts and the initial passing run that missed the bug remain in the detailed record.

## 2026-11-02 — Step362: Trim and Reveal All

Add Trim controls, retained-content Reveal All, exact sparse/paged canvas framing and numerical component byte copies. The UI, typed API and semantic Actions share preparation/history. Bounds, stored origins, masks, saved channels/guides/paths and comp positions are handled together. Preserve failed attempts and distinguish owned/native checks from live Photoshop qualification.

All 24 new cases pass. Of 304 affected optimized cases, 302 pass; 2 fail with 2 assertions and 1 unexpected errors. There are 0 crashes. Independent analytical/PNG readers verify336RGBAbytes; 12 PSD/PSB headers are checked separately.

Temporal and ink-mode canvas rebasing, layered native component Trim, advanced mask/effect bounds, authoritative Adobe actionJSON descriptors, exact Photoshop defaults/output/live UI, supported Macs, full current suite, dense maximum capacity and physical60fps remain open. All 104complete package scopes remain open. [Record](DEVLOG.md#dev-step-362).

## 2026-11-02 — Step363: Private full-source backup

Deliver the complete current native source to the existing private repository, preserving the Rust snapshot and history. Retain actual qualification limits and known failures. Check every included qualified input against362Source03. Exclude generated/private runtime material and the external Layer Comp PSD identified by the upstream image-asset exception; retain source/hash/acquisition instructions. Verify the no-network helper, package/project structure, staged blob contents and destination privacy before committing. The source commit is [4514839](https://github.com/ForensicIntelligence/Photato/commit/45148392a5a3977ed731c4624730e8cbfcb9e29f); GitHub commit/tree and private visibility are verified. [Record](DEVLOG.md#dev-step-363).

Private source commit [4514839](https://github.com/ForensicIntelligence/Photato/commit/45148392a5a3977ed731c4624730e8cbfcb9e29f) includes the complete current native app/test code and the documented source exclusions. GitHub main/tree and private visibility are verified. The app was not installed, uploaded as a binary, submitted to Apple or released.

## 2026-11-02 — Step364: Rich layer merging

Extend the native merge commands beyond plain pixel layers. Add shared compositor preparation, hierarchy validation, rich/paged output, source-bound history and both API paths while retaining measured plain-pixel behavior. Preserve unavailable specialized/retention cases and failed attempts explicitly.

All 18 new cases pass. Of 298 affected optimized cases, 297 pass and 1 fail; 2 failed assertions, 0 unexpected errors and 0 crashes. Independent readers verify 288 RGBA bytes and 672 raw merged PSD/PSB component bytes across three PNGs and six Photoshop files.

Complete L02 merge/rasterization, numerical/palette/ink/temporal composition, cross-parent selections, clipped artwork without its selected base, hidden descendants inside visible merged groups, stamp/merge-clipping variants and exact Photoshop backdrop/effects/geometry/defaults/live UI remain open. Supported-platform, full-current-suite, dense maximum capacity and physical60fps qualification remain open. All 104 work packages remain open against their full acceptance criteria. [Record](DEVLOG.md#dev-step-364).

## 2026-11-02 — Step365: Linked preview sampling

Correct the export-only source-edge policy and project linked masks as numerical coverage. Preserve the native document and general geometry defaults, and test desktop/API serializers and missing-source reexport. Keep integer rounding and Photoshop reference gaps explicit.

All 12 new cases pass. Of 359 affected optimized cases, 358 pass and 1 fail, with 2 failed assertions, 0 unexpected errors and 0 crashes. Independent math checks cover 5184 raw RGBA bytes; a standalone PSD/PSB parser checks 12432 bytes across all owned layer, alpha, mask and merged-image planes.

Integer preview/mask quantization still needs independent Photoshop qualification: the retained strict RGB8 round-trip comparison is not waived. Other current affected failures are recorded by case below. Full L05/I01 functionality, general Photoshop interpolation/ICC/filters/projective/effect/mask defaults, complete live UI, full current suite, supported Macs, dense capacity and physical 60 fps remain open. All 104 work packages retain their full acceptance criteria. [Record](DEVLOG.md#dev-step-365).

## 2026-11-02 — Step366: Quick Mask and saved selections

The maintainer asked for one major workflow to be completed and tested. S05 was selected, with C01 queued next. Photoshop reference files exposed incorrect gray selection combinations; the shared engine now matches the controlled8/16/32-bit channel samples. The native dialogs, Quick Mask defaults/gestures and API gained the missing workflow pieces. The first run found own-sheet admission and test-fixture issues; those failures and their repairs are retained.

All 15 new cases and all 266 affected optimized tests pass, with 0 failed assertions, 0 unexpected errors and 0 crashes. The 491.43-second optimized build and 34.724-second affected run used 7,065 unchanged frozen inputs and 1,003 production Swift files.

S05 is still in progress: finish the remaining Save/Load source/destination cases and live UI qualification before closure. C01 is preselected next. The full current suite, all-input Photoshop output, supported physical Macs and 60 fps qualification remain open. Installed preview283, private source backup363 and store archive332 are unchanged; no installation, source push, archive, binary upload or release. [Record](DEVLOG.md#dev-step-366).

## 2026-11-02 — Step367: Saved-selection documents; C01 queued

Photoshop Save Selection > New produces a document containing mask channels, with no image layers or printing plates. Photato now represents that directly, with native85 storage and8/16-bit PSD/PSB interchange. Load Selection gained the remaining component, layer transparency and mask source choices. New-document transfers require explicit API permission and preserve the source document and its Undo history. A failing first run found an incorrect sample-depth tag, unhandled Photoshop document metadata and a stale test expectation; the logs and repairs are retained.

All17 new cases and all388 affected optimized tests pass, with0 failed assertions,0 unexpected errors and0 crashes. The run used7,074 unchanged frozen inputs and1,007 production Swift files.

The next full major function is C01: separate channel viewing and editing targets, grayscale/color display, temporary mask rows, actual paint/filter targets, eye gestures and Photoshop shortcuts. It starts after S05 completes and is tested.

S05 remains in progress pending native live UI and remaining qualification; C01 is preselected and starts after S05 completes and is tested. The full current suite, all-input Photoshop output, full supported-platform coverage, dense maximum capacity and 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. No installation, source push, archive, binary upload or release. [Record](DEVLOG.md#dev-step-367).

## 2026-11-02 — Step368: Quick Mask workflow checks; C01 next

We checked Quick Mask painting, Undo/Redo, saved selections, standalone selection documents, cross-document loading, channel shortcuts and reopening files in the native app. The checks found two display bugs: saved documents appeared under their internal names in the source picker, and layerless Multichannel documents were labelled RGB in Properties. Both were repaired.

A coloured Photoshop reference exposed a larger difference: loading the composite as a selection used fixed RGB weights instead of the working Gray profile. The standard RGB8 transform now uses numerical calibration captured from our own test image, with every possible RGB8 colour represented. Embedded-profile and untagged Photoshop references agree. Other profiles retain their separate fidelity checks. No Photoshop source code, executable internals or proprietary runtime is used.

All 432 affected optimized tests pass on Apple Silicon and translated Intel, including all 11 new cases on each architecture. There are no failed assertions, unexpected errors or crashes. The runs used 7,084 unchanged frozen inputs and 1,010 production Swift files.

The first ARM test run caught an incorrect test expectation. Intel test discovery also chose the wrong architecture; running the unchanged test bundle directly under Rosetta resolved the launcher problem. Failed attempts remain in the record. The universal package includes its required selection resource, and the Xcode Release resource path was checked separately. The final current-source live check could not run because the Mac was locked; the earlier native checks used367Source03.

C01 is next because the Channels panel needs complete, independent viewing and editing targets. The plan includes component and mask rows, eye controls, real brush/filter targets, factory shortcuts and matching API behaviour.

S05 remains in progress; its current-source live recheck awaits an unlocked Mac. C01 is queued after completion. General profile/CMM fidelity, the full current suite, physical supported-platform coverage, dense maximum capacity and sustained 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. [Record](DEVLOG.md#dev-step-368).

## 2026-11-03 — Step369: Quick Mask visibility and hidden brush target

The previously blocked Mac checks could be completed. Saved-document names and the Multichannel Properties label were correct. The packaged composite-selection command also matched64 coloured Photoshop reference samples saved through the native UI. An ordinary Photoshop-saved PSD opened normally; the minimal test PSD's disabled Open-panel state remains unqualified.

The channel audit found that the Quick Mask eye was wired to exit the mode. We separated its display visibility from the editing target, mask data and Undo history. A direct Photoshop check added an important rule: painting a hidden Quick Mask raises a hidden-target warning. An early candidate allowed that painting; it was withdrawn and replaced with matching native/API rejection. Showing the overlay restores painting, and Undo removes only the new stroke.

All 454 affected optimized tests pass on Apple Silicon and translated Intel, including all five new Quick Mask visibility cases on each architecture. There are0 failed assertions,0 unexpected errors and0 crashes. All7,085 frozen inputs and1,010 production Swift files remained unchanged.

The first test attempt read the schema at the wrong level. The first Intel build also omitted testability support. Both failures and repairs remain in the record. One unqualified raw executable was overwritten before it was copied; its source snapshot, hash and failed logs survive. The qualified Source02 executables, resources and universal app are preserved separately. The current native eye, warning, show, paint and Undo checks pass.

S05 remains in progress against its full acceptance criteria; C01 stays queued. Other hidden-target Fill/filter/tool contexts, general profile/CMM fidelity, full current suite, physical supported-platform coverage, dense maximum capacity and sustained 60 fps remain open. Installed preview283, private source backup363 and store archive332 are unchanged. [Record](DEVLOG.md#dev-step-369).

## 2026-11-03 — Step370: Private source backup and next major function

The tested369 source is now backed up in the existing private repository. Every7051 included qualified input matches its frozen SHA256;34 model/cache/external-image inputs are excluded with reasons. All original1057Rust files remain unchanged. The source includes the app, tests and redistributable fixtures, Xcode project, scripts, assets, licenses and developer records. This was a source delivery; it did not upload or install a new app.

The maintainer asked again which major feature follows S05. We confirmed C01: Component visibility and edit targeting. The plan covers independent viewing and editing, channel/mask rows, real painting/filter targets, factory shortcuts, history and API support. C01 starts after S05 is complete and tested; neither package is marked closed by this decision.

The source retains checkpoint369's454 affected passing tests per architecture and its native Quick Mask check. No native tests were rerun for documentation and source-copy changes. The full current suite, complete Photoshop behaviour and supported-platform/performance gates remain open. GitHub's main ref and source tree were verified, and repository visibility remains private. [Record](DEVLOG.md#dev-step-370).

## 2026-11-03 — Step371: Hidden Quick Mask commands and pixel Invert

Photoshop treats hidden Quick Mask commands differently. Fill opens its dialog but rejects the commit; Invert is disabled. Gaussian Blur can still run on the hidden mask. We reproduced those rules in direct and prepared native/API commands, including the separate modern painting path. The factory Image Adjustments Invert command now changes supported pixels rather than adding a layer; RGB clients can use the existing adjustment.apply operation.

The first run caught a bad test request: it sent saved-filter JSON instead of the public API’s kind/radius fields. We corrected the request without relaxing the decoder. Another test still expected the retired64-layer limit; it now checks the current8000-layer boundary and atomic admission. Strict source comparisons remain unchanged and open, including three additional Intel assertions.

All eight new cases pass on both architectures. The affected totals are583/584 on Apple Silicon and582/584 through Rosetta, with no unexpected errors or crashes. Both source attempts and their raw executables survive. The first case-list inspector overlooked Intel stderr; reading both preserved streams proved that the same584 case IDs ran on each architecture.

An owned Photoshop Invert output supplies the numeric reference. Independent parsing confirms192 RGB bytes and64 unchanged alpha bytes in each native PSD export. The current universal app also passes the native shortcut, hidden Fill warning, Gaussian preview/cancel/commit/Undo/Redo and reveal checks, then closes the disposable document and quits. The input file remains unchanged.

S05 remains in progress; C01 stays next. Broader channel/filter contexts, exact profiles/kernels/defaults, the full current suite and physical platform/performance checks remain open. No binary was installed or uploaded and no software release was made. [Record](DEVLOG.md#dev-step-371).

## 2026-11-03 — Step372: Quick Mask targets; next major feature

C01, Component visibility and edit targeting, remains next after S05. Its scope includes independent channel eyes and editing targets, grayscale/color views, temporary mask rows, painting and filters, gestures and factory shortcuts. Native/API behavior, history and workflow tests are part of completion.

An owned Photoshop document exposed a shared dependency. Command2 selects RGB while leaving Quick Mask present and visible; component and saved-alpha shortcuts choose their own editing targets. The temporary mask has the next numbered shortcut. Q exits the mode even when RGB is selected. Photato had inferred the target solely from the mask's presence, so it could send an intended RGB edit to the mask.

The native target override is now scoped to the document and temporary mask. RGB and numerical components can receive edits without changing Quick Mask; alpha and temporary-row shortcuts share that state. API visibility changes only the eye, while API state reports the actual target. Native reopen and a new mask reset the session override. Full independent component/auxiliary visibility remains C01.

All six new channel-transition cases and all 293 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. The exact same ordered case IDs run on both architectures. All7089 frozen inputs and1010 production Swift files remain unchanged. Current universal native checks are recorded separately. The371 broader strict source comparisons remain open; these focused runs do not replace them or prove full Photoshop output equality. No app was installed, source pushed or software released. [Record](DEVLOG.md#dev-step-372).

## 2026-11-03 — Step373: Mask paint colors and remaining S05 work

The image foreground color was carrying into Quick Mask. Photoshop keeps separate image and mask colors: mask painting starts black/white, X swaps that pair, and RGB restores the image colors. An owned Photoshop document confirmed that the mask pair survives Q exit and re-entry. Its original foreground was restored and the file closed without saving.

Photato now remembers the image and auxiliary pairs when targets change. The API exposed another mismatch: changing a brush background did not change the native palette background. Both now agree, and included-color presets update it too. API state reports the active context and both pairs; no new command or Adobe route is added.

The first builds failed before tests because old brush presets can omit a background. The repair keeps the current background when it is absent. The failed attempt and its source survive; its retained executables are correctly identified as the older372 binaries, since373 had not linked. All eight new paint-color workflow cases and all 347 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. Both architectures run the same ordered case IDs. All7091 frozen inputs and1011 production Swift files remain unchanged.

The full S05 audit also identifies the next file-workflow gap: standalone Multichannel selections still pass through dense ink-plane storage and cannot reopen above8.4 megapixels. Auxiliary planes need the paged row decoder. That remains open along with application-global palette and full output/platform requirements. C01 stays queued. No app was installed, source pushed, uploaded or released. [Record](DEVLOG.md#dev-step-373).

## 2026-11-03 — Step374: Large saved-selection files

Standalone selections were still going through dense printing-plate storage when opening Multichannel PSD/PSB files. That imposed an8.4-megapixel limit even though native selections already supported paged storage. Auxiliary channels now use the bounded row decoder and paged tiles. Printing-plate capacity stays separate and remains open.

Independent Python fixtures cover8/16-bit PSD/PSB, raw/RLE/ZIP/prediction encodings,40.5 megapixels, maximum PSB side and every16-bit word. Photoshop opened the owned RLE input and saved both PSD and PSB copies. An independent reader verified every numeric sample. It rejected both ZIP PSB probes, so those are not qualified for Photoshop interoperability. Channel Unicode terminators and identifiers also needed repairs to survive saving and reopening.

The first native run passed269 of273 cases per architecture. The second passed272 of273, including every new case; its remaining version85 assertion compared against version11 bytes. The final test-only repair checks version85 bytes and decodes the response back to the model. All exported values were correct, but the new path allocated tiles for implicit black samples. The repair keeps those regions implicit without changing the pixel assertions. An older HTTP test also rejected native85 even though the format was already supported; it now positively checks85 and rejects86. All 11 new large-selection file cases and all 273 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,118 frozen inputs and 1,011 production Swift files remain unchanged.

The live large-file check remains unqualified after unreliable chooser navigation; both test executables and resources are preserved. S05 stays open against its full requirements. C01 remains the next complete major function, covering independent channel visibility and real editing targets. No installation, source push, archive, upload or release. [Record](DEVLOG.md#dev-step-374).

## 2026-11-03 — Step375: PSB file compatibility

The large selection opened and painted correctly in Photato. Undo removed the stroke, and the saved file retained every original sample. Photoshop rejected that output. The problem was in the file structure: wide tagged blocks had8-byte lengths preceded by the ordinary8BIM signature. Photoshop used8B64 for those blocks. An owned probe changing only the two signatures opened successfully.

The shared writer now pairs each supported block signature with its length width. The audit also found the same issue in16/32-bit layer-depth records, saved paths, mask-display records, embedded Smart Objects and Smart Filter caches. PSD and ordinary PSB block framing remain as before. Existing native/API saves use the same repair; no new route or format option is added.

The first build failed before tests because a new test passed a URL to the Data reader. That attempt is preserved; its retained executables were still the previous374 build. The test now uses the file reader. All nine new cases and all 356 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,120 frozen inputs and 1,011 production Swift files remain unchanged. Independent output checks and the current native/Photoshop workflow are recorded separately.

Shared image/mask paint palettes and other S05 requirements remain open. C01 stays next with its full scope. No installation, upload or release. [Record](DEVLOG.md#dev-step-375).

## 2026-11-03 — Step376: Shared paint colours

Photoshop carries foreground/background colours from one document to another. Its image and Quick Mask pairs are separate: a swap in Quick Mask survives a document change without replacing the image colours. Two owned RGB8 files confirmed that behaviour, including the exact d24a7e image foreground in the second picker. The probe files were closed without saving, and the entered original colours restored.

Photato now keeps both pairs in the document controller. Editors select the appropriate pair while retaining their own brush settings. Old copies cannot overwrite the live palette when targets change. Closed editors detach a snapshot. Palette changes update API revisions in other documents, and in-progress native strokes retain the colour captured at their start. Normal application startup uses a bounded preference record; snapshots and test controllers stay isolated.

The first candidate was cancelled after a test review found an impossible comparison of UUID-bearing layers from different documents. The corrected tests compare each document with its own original. The next diagnostic passed every new palette case but found an obsolete test expecting large Background clearing to be unsupported. That test now checks the working white clear and two-step Undo/Redo. The startup audit also found a second launch path needing explicit palette injection. All 11 new shared-palette cases and all 485 affected optimized cases pass on Apple Silicon and translated Intel, with 0 failed assertions, 0 unexpected errors and 0 crashes. Both architectures run the same ordered case IDs. All 7,121 frozen inputs and 1,011 production Swift files remain unchanged.

The current native workflow and preference restart are checked, with independent HTTP-state comparisons kept separate from pixel/CMM claims. S05 stays open against its full scope. C01 remains next. [Record](DEVLOG.md#dev-step-376).

## 2026-11-03 — Step377: App Store listing and media

The existing App Store Connect record was an empty1.0 draft. It now uses0.3.0, with copy describing the current editor, its alpha limitations, optional Apple AI and AI-aided development. The source-release policy and upstream attribution are included. Free pricing is saved across175storefronts, and automatic release has been changed to manual.

Four screenshots show a real layered composition, the opacity slider, brush work and Quick Mask. The original CoastalLight artwork was made for these captures. Its lettering is raster artwork, so the screenshots do not claim editable type. A27.478-second preview shows actual layer, painting and selection actions. The capture service limits source cadence; the video makes no physical frame-rate claim.

The first artwork candidate used the wrong layer order and was retained. Preview preparation also caught a timing overrun, an unavailable text filter and a full-range video-format mismatch. The passing export preserves real frame timings and uses separate caption cards. All824 output frames decode correctly. Four screenshots and one preview are uploaded; Apple is still processing the preview.

The privacy label is saved as a draft. Apple’s agreement, the content-rights declaration and private review-contact details remain pending. There was no binary upload, review submission or software release. Native source376 is unchanged. [Record](DEVLOG.md#dev-step-377).

## 2026-11-04 — Step378: App Store familiarity wording

The App Store description and promotional text now say: “If you know your way around a professional image editor, Photato will feel familiar.” The early-alpha disclosure remains clear. Generic reviewer-note wording is prepared locally, but the portal still has its prior private notes because the required reviewer contact is missing.

Apple’s keyword documentation explicitly excludes competing app and company names. The saved keywords therefore describe layers, masks, painting, retouching, colour, selections, PSD/PSB, brushes and open source. An initial same-tab reload appeared to show all four changes. The Save error then exposed missing contact fields; an untouched fresh tab confirmed only the three public changes persisted. The older private notes remain saved. Manual release remains selected; no build was submitted or released. [Record](DEVLOG.md#dev-step-378).


## 2026-11-04 — Step379: Multichannel Quick Mask files

Photoshop saves selection-only documents with Quick Mask active. Photato rejected them and required leaving the mode before saving. The shared Swift reader/writer now retains the temporary mask separately from saved selections and printing channels, including display options, identifiers and the initially-empty flag. Native SaveAs permits it, and standalone opening selects Quick Mask for editing.

All nine new cases and all494 affected optimized cases pass on Apple Silicon and translated Intel, with0 failed assertions,0 unexpected errors and0 crashes. Both architectures execute the same ordered case IDs. All7125 frozen inputs and1011 production Swift files are unchanged. Independent readers verify78 files/4480 samples. Real native brush/Undo/Redo/SaveAs passes; Photoshop opens that8-bit output and a16-bit RLE output with Quick Mask active. The initial failed new test compared internal tile storage outside document bounds; the corrected test checks every document pixel exactly. Production binary hashes did not change. Both attempts remain recorded.

The reused aggregate-report name and diary-format assumption were caught and corrected. Their initial helpers and failures remain. S05 remains in progress against its full scope; C01 follows after completion and testing. Cross-profile/custom-gray/layer-mask/component palette semantics, Photoshop restart defaults, full interoperability, current full suite, exact all-input output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain unqualified. Prior371 broader strict comparison failures remain open. Native Float32 standalone selection storage remains supported;32-bit mode7 output remains unavailable after the observed Photoshop save failure. Printing plates retain their separate dense capacity limit. Prior ZIP PSB rejection is not cleared by native/independent decoder passes. No installation, source push, archive, upload or release. [Record](DEVLOG.md#dev-step-379).


## 2026-11-04 — Step380: Mask paint-colour contexts

Photoshop remembers a mask colour pair separately from its image and Quick Mask pairs. A layer-mask colour also appears when selecting a Smart Filter mask. D uses white/black for these masks. Q returns to image editing when its own target is selected; if another mask is selected while Q remains, removing Q keeps that mask target. These observations came from owned test artwork and normal Photoshop controls. Original palette values were restored and the artwork closed without saving.

Photato now has the third shared palette, migration of the old preferences, target-aware D/X and the same native/API mask selection and painting path. Invalid or deleted mask targets fall back safely. The API retains the selected mask after supported brush/channel operations.

All 545 affected optimized tests pass on Apple Silicon and translated Intel, including eight new mask-palette workflow cases. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. The run uses 7,126 unchanged frozen inputs and 1,011 production Swift files. Independent checks cover128 colour components and256 mask samples. The first candidate was cancelled for new test-helper defects. The next test build caught a private-setter misuse; the following run correctly rejected a malformed RGBA-array fixture. Those attempts remain. The corrected test sends the existing object format and checks actual black mask pixels. Production binaries were unchanged by the test-only repairs.

The Mac locked before the current app could be inspected. Live acceptance remains pending; no successful screenshot is claimed. S05 remains in progress against its full scope; C01 follows after S05 is complete and tested. Current-build live UI is pending an unlocked Mac. General profile/custom-gray conversion, component colour contexts, Photoshop restart defaults, complete channel visibility/temporary rows/filter targets, full interoperability, the current full suite, exact all-input Photoshop output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain open. Earlier strict comparison failures and ZIP PSB rejection are retained. Native Float32 standalone storage remains supported; 32-bit Multichannel output and full printing capacity remain unqualified or unavailable. [Record](DEVLOG.md#dev-step-380).


## 2026-11-04 — Step381: Mask target lifecycle

Returning from a Smart Filter mask had cleared its owner but left an editing flag set. Merge and Calculations still treated the document as a mask target, even after selecting RGB, previewing the composite or selecting all layers. Six new workflow cases reproduce five failures and21 assertions per architecture against unchanged build380. The document-read case passes as a control.

The repair clears filter-mask editing whenever its owner is cleared. It preserves viewing state so supported prepared mask edits can restore their captured target. Native and HTTP Merge now produce a single layer and one Undo, and busy rejection keeps the original valid mask. API availability/state/capabilities describe the same behavior; existing contracts and command counts remain.

All 698 affected optimized tests pass on Apple Silicon and translated Intel, including six new mask-target lifecycle cases. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. All 7,127 frozen inputs and 1,011 production Swift files remain unchanged. Independent analytical red8x8 comparisons verify1,024RGBAbytes across native/API and both architectures. The initial repaired attempt was stopped before tests after finding an invalid argument in the new HTTP capture helper; frozen source, partial logs, process cleanup and stale380 executables are retained. The corrected test uses the helper’s existing GET behavior.

S05 remains in progress against its full scope; C01 follows after S05 is complete and tested. Current native live UI awaits an unlocked Mac. General profile/custom-gray conversion, component colour contexts, Photoshop restart defaults, complete channel visibility/temporary rows/filter targets, full interoperability, the current full suite, exact all-input Photoshop output/settings/shortcuts, supported physical Macs, dense maximum capacity and sustained 60 fps remain open. Earlier strict comparison failures and ZIP PSB rejection are retained. Native Float32 standalone storage remains supported; 32-bit Multichannel output and full printing capacity remain unqualified or unavailable. [Record](DEVLOG.md#dev-step-381).


## 2026-11-04 — Step382: Current full test inventory

The last complete test run was at checkpoint 332. This pass discovers 3,845 unique cases in both current compiled bundles and runs every case in 21 fresh processes per architecture. The app and test source stay frozen at build 381. No existing result is reused.

All 3,845 discovered tests execute on each architecture in 21 fresh bounded groups. Apple Silicon: 3779 pass, 66 fail, 0 skip, 37 unexpected errors and 0 crashes. Translated Intel: 3771 pass, 74 fail, 0 skip, 37 unexpected errors and 0 crashes. This is a complete execution with failures, not a passing full suite. Raw logs retain every failed assertion, unexpected error and test identity. These test counts are not a measure of Photoshop functionality.

The installed Xcode discovery helper is ARM-only, so it could not list the Intel bundle. A small test-only helper using public XCTest APIs lists the same 3,845 test IDs from both bundles. Its dependency/name-format repairs and failed discovery attempts are recorded. A generated environment diagnostic was sanitized immediately; raw environment values were not retained.

The failures include old fixture assumptions and checks that still need functional diagnosis. The next repair pass starts with lifecycle/API failures and preserves the current Photoshop Background and mask-colour behavior. Strict Rust comparisons remain supporting diagnostics; Photoshop remains the reference. S05/C01 and the full original goal remain open. [Record](DEVLOG.md#dev-step-382).


## 2026-11-04 — Step383: Document lifecycle regression repairs

The complete baseline exposed generic fixtures that made invalid edits to protected Background layers. Those tests could not reach the recovery or closing behavior they were meant to check. They now use regular layers with the same factory pixels, dimensions, depth, profile and IDs. All original history, cancellation, permission and saved-byte checks remain. Production guards are unchanged.

A new test uses actual indexed recovery for opaque Background layers at all three depths. It checks the restored model and snapshot identity, supported painting, rejected rename, one Undo/Redo and unchanged backup bytes. The first repaired run passed 715 of 718 cases on each architecture; its remaining failures were stale native-version expectations.

The follow-up pins the existing native85/Actions44 inventories, extends positive indexed round-trips through85, and rejects86. It preserves minimum feature versions and corrupt-input/resource tests. The 40-million-pixel HDR/alpha fixture now uses a regular layer, and the layer-limit test checks 8,000 accepted/8,001 rejected instead of treating 65 as invalid.

All 740 affected optimized tests pass on Apple Silicon and translated Intel, including the new all-depth indexed Background recovery case. There are no failed assertions, unexpected errors or crashes. Both architectures run the same ordered cases. In this focused run, 43 previously failing full-baseline cases pass per architecture. The full current inventory has not been rerun. Production executables are byte-identical to381. This does not erase the full382 baseline or prove complete Photoshop parity. S05/C01, current live UI and all original global gates remain open. [Record](DEVLOG.md#dev-step-383).


## 2026-11-04 — Step384: Animated layer-style transactions

A style edit changed a private candidate, then validated it against the old keyframe or animation-frame state. Validation rejected the edit before the outer engine could record the new value. An existing regression and new native/API checks reproduced this on both architectures. The unchanged-code run passed one of six cases; the other five failed. All failed runs and source snapshots remain in the record.

The first repaired run passed 467 of 468 cases per architecture. The new 32-bit midpoint assertion had read an encoded display value; the renderer blends those pixels in linear RGB. The corrected test checks linear working values and independently checks encoded PNG output. The production blending path is unchanged.

The style transaction checks its source composition, then records the changed temporal composition before final validation and assignment. It retains the existing key identity and interpolation when replacing a key, changes only the selected animation frame, preserves movie/source pixels, and keeps invalid edits atomic. The API uses this same path for replacement, patch and clear. No new endpoint or file-format version is required.

All 476 affected optimized tests pass on Apple Silicon and translated Intel, including 6 new temporal-style regression cases. Both architectures run the same ordered cases with no failed assertions, unexpected errors or crashes. Independent checks cover 36 PNGs and 3,456 RGBA8 channel values. The full current test inventory has not been rerun. The independent samples check a red square with a blue overlay at authored times. They are regression evidence, not a claim of matching Photoshop pixels. Current live UI and full S05/C01 acceptance remain open. The store copy already followed the requested generic wording; no portal field was changed in this increment. [Record](DEVLOG.md#dev-step-384).


## 2026-11-04 — Step385: Fit Image and reusable batch constraints

The Automate menu listed Fit Image but had no implementation. Recording an absolute Image Size also failed to express a useful constraint for a batch with different aspect ratios. Fit Image now records the bounding box and enlargement policy, calculates each input’s dimensions independently and uses the existing native geometry engine. A fit that leaves a small image unchanged remains recordable without adding an Undo entry.

The native dialog, API and Actions share the operation. Image Processor now uses it for its existing per-format resize settings. The checks cover portrait and landscape sources, small images, all three component depths, source preservation, target identities, error guards, persistence and history. All 220 affected optimized tests pass on Apple Silicon and translated Intel, including 10 new Fit Image cases. Both architectures execute the same cases with no failed assertions, unexpected errors or crashes. Independent checks cover 30 PNGs and 2,032 exact RGBA8 channel values. The current full inventory has not been rerun. Independent files check authored white pixels and dimensions; photographic interpolation and Photoshop output are still unqualified. The initial Photato bounds and resampling policy are documented working defaults, not verified Photoshop defaults. S05 remains open, with C01 next after completion and testing. [Record](DEVLOG.md#dev-step-385).


## 2026-11-04 — Step386: Find and Replace Text

The Edit menu listed Find and Replace Text without an implementation. It now opens a native dialog with search scope, caret direction, case and word options. Find Next highlights the matching context. Change, Change/Find and Change All use the same rich-text replacement and shaping path as the API, with one Undo per edit. Search itself leaves the document and history unchanged. On-canvas Photoshop-style selection remains unqualified.

Replacements preserve untouched character/paragraph runs and use the first replaced character’s style for inserted text. Hidden or image-locked type layers, including inherited visibility/protection, are skipped. Native Actions46 retains the search policy, so Batch recalculates matches in each input rather than repeating previously baked text. Long Unicode layer names use the existing native capacity.

The first compilers rejected combined observable-property declarations before any test ran; that failed source and logs remain. Separate declarations repaired the compiler error. Review also corrected a narrow target-name guard and the new caret test’s baseline after the existing TextKit draft commit. All 16 new Find/Replace cases pass on Apple Silicon and translated Intel. Of 211 affected cases per architecture, 210 pass and one retained imported-text comparison fails with three assertions; there are no unexpected errors or crashes. A previous385run of the195existing cases reproduces that one failure with identical word counts. Independent checks cover 10 owned text/state outputs with 31 exact literal checks. The affected run fails; the current full suite has not been rerun. Independent owned output checks compare literal text/counts/ranges; they do not establish Photoshop glyph/pixel or default equivalence. A fresh native attempt still found the Mac locked. S05 remains open and C01 stays next after completion and testing. [Record](DEVLOG.md#dev-step-386).


## 2026-11-04 — Step387: Numeric component-plane storage

The component/printing modes still have an 8 megapixel limit. Lifting it safely needs storage that can retain exact numeric values and history without allocating a complete plane per edit. We added raw blocks of 4,096 samples, implicit uniform fills, bounded row transfers and private immutable mapped snapshots. InkPlane now uses shared blocks; legacy file bytes and capacity guards remain. Rendering/export loops use exact sample reads to avoid repeatedly exporting whole planes. API metadata describes the backing and unchanged limit.

All nine new numeric storage cases pass on Apple Silicon and translated Intel. Of 139 affected cases per architecture, 138 pass and one retained master-palette case reports an unexpected CancellationError; there are no crashes. Preserved build 386 test bundles reproduce that same cancellation. Two other retained test failures are repaired by updating obsolete command-count expectations. Independent Python packing verifies 40,136 raw bytes from eight owned outputs. The affected run fails; current full execution has not been rerun. Tests also cover cancellation, invalid ranges, admission/I/O failures, negative zero, snapshot ownership and concurrent history branches. The maximum-size sparse tests are sparse storage checks, not full-document rendering/save/performance qualification. All 104 package scopes and 651 menu identities stay intact. S05 remains open; C01 stays next. No installation, source push, archive, upload or release. [Record](DEVLOG.md#dev-step-387).


During the final evidence check, three old temporary candidate binaries from builds 284–286 were missing. Their source, logs and recorded hashes survive, but the original binary bytes were not retained in those run folders. The remaining 37 protected files match. Build 387 source and complete test/binary evidence are retained; this does not recover the missing historical binaries. The final verification reports that preservation gap separately from current build checks.


## 2026-11-04 — Step388: Native component blocks

Native component storage now uses shared raw blocks. Uniform conversion and display/channel preparation no longer fill a dense plane. Local edits retain untouched sample words; geometry and TIFF access preserve raw order. Native85/Actions46and242API commands keep their existing contracts, with backing/limit metadata added.

All 14 new native-component and Surface-equality cases pass on Apple Silicon and translated Intel. The broadened run executes 1184 identical ordered cases per architecture; Apple Silicon passes 1182, translated Intel passes 1175. Six regressions from the earlier storage attempt now pass without changing their assertions. Independent Python packing checks 40,248 raw bytes from 14 owned outputs. Retained failures are listed in the evidence; this is not a passing full suite. The first compiler failure and earlier six document/cache regressions remain in the evidence. Their existing assertions were not weakened; Surface equality now checks logical sample bits across implicit, owned and mapped storage. Broad qualification includes all Core cases because equality is shared. Application limits remain8MPuntil component file streaming and operation integration are complete. S05, full Photoshop/platform/performance requirements and historical binary gaps remain open. [Record](DEVLOG.md#dev-step-388).


## 2026-11-04 — Step389: Private source backup

We backed up native build 388 before changing component file storage. Every included tested input matches the frozen source. Generated models, caches, machine/signing/runtime files and an externally restricted PSD remain excluded. The original Rust source and existing Git history are preserved.

The commit includes current native source, tests, Xcode project, assets, scripts and records. Its notes retain the actual test results: all 14 new cases pass; the broader run has two remaining ARM failures and nine Intel failures, all reproduced by the prior baseline. No new native test run is needed for this delivery because the tested code and configuration are unchanged. The repository remains private and no application binary is uploaded or released. Component streaming remains next; S05/C01 and full parity gates stay open. [Receipt](SOURCE_PUBLICATION_389.json).


## 2026-11-04 — Step390: Component archive streaming

Native86 and history now use a bounded raw-component tree, with4096sample blocks,1024-entry leaves and256-reference branches. The decoder validates exact words, geometry, alpha, padding, tree order/counts, budgets and failures before publication. Existing APIs advertise/accept86; older requested versions retain their previous layouts. No tools or shortcuts change.

All18 new component archive/history/API cases pass on Apple Silicon and translated Intel. The broadened run executes1217identical ordered cases per architecture, passing1215ARM and1208translatedIntel; remaining failures reproduce on preserved388. Independent Python verifies57,351logical sample bytes and86,016raw block bytes per architecture. This is a focused affected run, not a passing current full suite. The first compiler failure and its repair remain recorded. Application admission remains8MP; complete operation/metadata/codec integration and original Photoshop/platform/performance gates stay open. The Desktop package later failed signature checking after Finder metadata appeared. A copy outside Desktop and a ZIP extraction preserve every file byte and pass signature checks; the original failed candidate is retained. No installed preview, repository push, Xcode archive, App Store change, upload or release. [Record](DEVLOG.md#dev-step-390).


## 2026-11-04 — Step391: Large native component documents

Logical native component geometry is now separate from dense-operation limits. Owned/mapped accounting reaches document, history/recovery and API admission; implicit fills and local blocks let sparse300,000²documents pass creation, conversion, channel/brush edits, native86save/reopen, viewport rendering and Undo/Redo tests. Dense exports/tools still report their unfinished limits. Public Swift planes access now throws instead of allocating a large logical plane. Existing byte assertions add try without being weakened.

All 13 new cases pass on Apple Silicon and translated Intel. The broadened run executes 1,481 identical ordered cases per architecture, passing 1,478 on Apple Silicon and 1,470 on translated Intel. Remaining failed IDs and assertion counts reproduce on preserved build 390. This is an affected run, not full-suite success. A viewport failure exposed native buffers in a scalar render comparison; they are stripped only after exact equality. An independent maximum-file reader validates stored words but its cross-architecture Gray32default comparison fails by one ULP. That remains a colour-fidelity gate. All original Photoshop/S05/platform/dense/60fps requirements stay open. No installation, source push, Xcode archive, App Store action, upload or release. [Record](DEVLOG.md#dev-step-391).


## 2026-11-04 — Step392: Large component geometry

Component resampling, expanded canvas framing and Trim now work through bounded native storage. Shared checked scratch, direct numerical sampling and bounded derived caches keep the source intact on cancellation, I/O or admission failure. Existing native/API history transactions use the same implementation.

All 19 new cases pass on Apple Silicon and translated Intel. The affected run executes 1,547 identical ordered cases per architecture, passing 1,543 on Apple Silicon and 1,535 on translated Intel. Every remaining failed ID and assertion count reproduces on preserved build391. This affected run retains failures; the full current suite has not been rerun. The failed compile typo and downscale cutoff are preserved with their repaired reruns. Independent owned kernel checks pass; Photoshop, physical dense/platform/60fps and the prior Gray32comparison remain open. S05 is not closed. No install, push, Xcode archive or App Store release action. [Record](DEVLOG.md#dev-step-392).


## 2026-11-04 — Step393: Large component tools

Individual colour-channel Fill, Invert, Brush/Eraser and eight basic filters now use bounded storage beyond the former eight-megapixel guard. The small implementation remains unchanged for regression comparisons. Forward selection samples, native untargeted planes and alpha, history and API availability are checked.

All 12 new cases pass on Apple Silicon and translated Intel. The affected run executes 195 identical ordered cases per architecture, passing 194 on Apple Silicon and 194 on translated Intel. Remaining failed IDs and assertion counts reproduce on preserved build392. The full current suite has not been rerun. The stopped maximum Motion Blur attempt, exact binary shortcut, fixture compilation error and repaired run remain documented. Independent owned sample checks pass. Full Photoshop, dense capacity, current live/platform/60fps, prior Gray32comparison and full S05 requirements remain open. No install, push, Xcode archive or App Store release action. [Record](DEVLOG.md#dev-step-393).


## 2026-11-04 — Step394: RGB8 component routing

Ordinary RGB8 selected-channel tools now share the native component engine. The legacy target/view/API state and neutral Fill label remain. Held brush previews, captured release, filters, Undo, cancellation, maximum RGB8 edits and temporary Quick Mask/image transitions are covered.

All 13 new cases pass on Apple Silicon and translated Intel. The affected run executes 335 identical ordered cases per architecture, passing 335 on Apple Silicon and 335 on translated Intel. Three stale command-count assertions reproduce on preserved393 and are corrected to the unchanged242-command catalog. The full current suite has not been rerun. The maximum guard-order bug, nonneutral API/UI mismatch and stale count assertions remain recorded with the repaired rerun. No test identity or source is removed. Full Photoshop/S05/C01/platform/dense/60fps requirements and prior strict/Gray32failures stay open. No install, push, Xcode archive, upload or release. [Record](DEVLOG.md#dev-step-394).


## 2026-11-04 — Step395: Private source backup and listing wording

We backed up native build 394 after its 335 affected tests passed on each architecture. All 13 new RGB8 component tests pass. Every included tested input matches the frozen source; generated models, caches, machine/signing/runtime files and an externally restricted PSD remain excluded. The original Rust source and existing Git history are preserved.

The commit includes native source, tests, the Xcode project, assets, scripts and developer records. We verified the staged file bytes, source commit/tree on GitHub and continued private visibility. No new native test run was needed because tested application code and configuration are unchanged. Current full-suite, live UI, physical supported platforms, dense capacity, 60 fps and exact Photoshop qualification remain open. Full S05 stays open and full C01 follows it.

The maintainer asked that App Store blurbs avoid named Photoshop comparisons. The current files and step378saved record already use familiarity with a professional image editor. Rechecking Apple's search guidance confirms it excludes competing app names from keywords, so functional and file-format terms remain. The browser is at sign-in; no new App Store write or fresh field verification is claimed. The private review-note edit remains pending contact details. Free pricing and manual release stay unchanged. [Delivery receipt](SOURCE_PUBLICATION_395.json).


## 2026-11-04 — Step 396: Large native channel arithmetic

Apply Image and Calculations New Document had separate 8 MP guards in native component storage. We replaced those large-document paths with bounded numeric projections and immutable component output, while keeping the small-document arithmetic and initializer. Existing native sheets and APIs use the same preparation and transaction.

The first run passed 101 of 102 affected cases on both architectures. A new HDR assertion expected 5 but omitted the existing partial-transparency step; the scalar result is 4. We corrected the expectation and added a dense comparison. A maximum expansion also took 88 seconds. Sampling traced it to scanning the entire output during identity resampling; large integer expansion now uses exact raw reframing. The failed run, sample, correction and tested source/binaries remain saved.

The second run passes all 103 affected cases on both architectures, including 13 new cases. The expansion case takes 0.013/0.019 seconds in those runs. Independent Python checks verify literal 8/16/32-bit gray and opacity words at three positions. Native/API preview/cancel/commit, Undo, transfer policy, invalid/busy/stale handling and native86 reopen pass. A universal package and its extracted copy pass signature/hash checks. The reporting script initially read Intel stdout instead of stderr; that failed postprocessing attempt and its repair are recorded separately from application test outcomes.

Full 3,989-case execution, Photoshop output/ICC/defaults, current live UI, physical supported systems/dense capacity and sustained 60 fps remain open. The Mac is locked. Full S05 and C01 scopes are unchanged; no software release is made. [Evidence](LARGE_CHANNEL_ARITHMETIC_396.json).


## 2026-11-04 — Step 397: Independent channel eyes

Saved alpha/spot eyes formerly selected the channel and the renderer displayed one auxiliary plane. The new session view separates eyes from the editing target, combines saved masks in document order and shares bounded presentation with the canvas and API. Native eye buttons support click, drag, accessible state and cancellation. Reopening clears the view; Undo can restore a deleted channel’s prior visibility.

The first run passed 306 of 312 affected cases per architecture. A fresh run of the retained build reproduced five of the six failed cases. We restored the isolated layer-mask viewing guard for the new regression, repaired three obsolete command-count assertions and made a palette test’s starting image/ink explicit. We also added missing partial-alpha neutral component Fill support rather than weakening its workflow expectation. A repair script stopped midway on whitespace; that partial state and failure were preserved before completing the repair.

The second run passed all 316 cases per architecture, including 26 new cases. The extra Fill/component run stopped at its first async test after two document lifecycle tests; its caller did not retain the native exit code. Starting with the existing HTTP initialization test let all 39 extra cases pass. The runner then incorrectly rejected XCTest’s grouped case order. The actual ordered lists matched between architectures and contained every requested case; that reporting correction is recorded separately. The initial unsuccessful attempt remains in the evidence.

Native UI access became available. In disposable documents, we checked two saved masks, independent eyes, a native process-eye sweep, image painting beneath overlays and Undo. Photoshop showed that selecting RGB or Red clears saved mask eyes, while toggling eyes keeps the target. The earlier implementation kept those eyes on row selection, so we corrected that behavior and added an HTTP regression. The temporary documents were discarded; the existing Photoshop document was left intact. Exact Photoshop sweep traversal was not established by the synthetic reference drag.

The third run passed all 370 cases on each architecture. A live check then found that re-selecting an already-selected RGB row hid the saved eye but left the red overlay on the canvas. We added the missing redraw condition and strengthened the HTTP test to check the actual awaited canvas and revision. That failed native interaction and its screenshot remain saved.

The final Source04 run passes all 370 affected cases on each architecture, including 27 new cases. Independent Python checks verify four literal 2×2 RGBA outputs. The corrected universal package and extracted copy pass signature/content checks, with macOS 14 minimums in both slices. Current 4,016-case discovery is not full execution. Full S05/C01, exact output/defaults, all supported physical systems, dense capacity and sustained 60 fps remain open.

App Store wording still describes familiarity with a professional image editor, without named Photoshop comparisons. Free pricing and manual release policy stay unchanged; no new portal write is claimed. [Evidence](CHANNEL_VISIBILITY_397.json).


## 2026-11-04 — Step 398: Temporary mask channels

The next mask-workflow gap is in the Channels panel. Photato already has layer-mask and Smart Filter-mask edit targets and gray/overlay views, but their temporary channel rows are missing.

We checked Photoshop on an owned 256×256 RGB document. A layer-mask row stays available when returning to RGB; selecting its name changes the edit target, while its eye changes display. With image channels hidden, the mask can be viewed in gray. A vector mask appears in Paths rather than as another raster channel. Quick Mask and saved alpha channels can coexist with these rows.

After adding a Smart Filter and a new pixel mask, both raster-mask rows are visible. Backslash toggles a mask overlay without changing RGB editing. The observed shortcut chooses the layer mask in the tested RGB context when both masks exist. Row ordering and naming vary during creation and need further checks. Thirteen reference screenshots are retained; the owned document was discarded and the prior Photoshop document was left unchanged.

The next implementation will connect those rows to native target selection, independent visibility, previews, the applicable shortcut and the API. At the maintainer’s first diary refresh, no application code had changed yet and build 397 remained the tested software. Implementation and testing followed that reference investigation. [Investigation](MASK_CHANNEL_ROWS_398.json).


The native rows and API are now implemented. Testing first caught an assertion looking at the editor’s projected mask instead of the stored layer. After correcting the inspection, an actual API issue remained: Fill rejected a selected Filter Mask. Its prepared transaction now accepts the matching mask and retains the target. Source review also found that row availability had used the same projection; it now reads the stored owner, with a Filter-Mask-only case to prevent a phantom row.

All 404 targeted cases pass on both architectures, including 16new cases. Independent checks cover560 literal display and stored-mask bytes each. The universal build 398 package passes signature and extraction checks. In the actual app, both mask eyes retain RGB editing; Filter Mask can be viewed in gray, painted and undone. The Filter-Mask-only file keeps one temporary row after selection. A screenshot comparison initially included the brush cursor; the retained correction checks the canvas away from it. No raw output tolerance was changed.

This completes the398 increment, not the full mask/channel package. Footer commands, display options and further factory gestures remain, along with the original full-parity gates. No installation, source push, App Store upload or software release was made. [Build 398 evidence](TEMPORARY_MASK_CHANNELS_398.json).


## 2026-11-04 — Step 399: Consolidated S05 validation

S05 had drifted into adjacent Channels work. This step returns to its Quick Mask and saved-selection requirements and runs a single consolidated set of 195 cases. The current inventory contains 4,032 cases; only the selected set executes here.

The first pass ran 194 successfully on each architecture. The remaining test expected 239 API commands, although the catalogue already contains 242. Its actual HTTP, file encoding, decoded mask and history assertions passed. Only the stale count was corrected, using the shared expected-count constant. The rebuilt test bundles pass all 195 cases on both architectures. The application executables are byte-identical to build 398.

The native check uses disposable RGB8 artwork. Options Cancel preserves the starting defaults; OK retains a changed indication and opacity within the process. Black and white paint change mask coverage, Q returns to the selection, and image colors return. Save/Load, a q-containing name field, cancellation, subtraction and Undo/Redo work. Save Selection into a new document produces a standalone channel; that document can supply a selection to the original image. Saving and reopening a native file retains alpha and active Quick Mask together.

File-picker automation also had failed attempts. A reordering file list initially left the chooser open; exact-path selection established the actual reopen later. Format-popup navigation did not select PSB and produced two disposable native files. They remain in the evidence. This pass makes no new native PSB-export or Photoshop-reopen claim. Earlier PSB interoperability checks and current automated codec/API results remain separately recorded.

The consolidated pass is finished. Full S05 acceptance stays open for the remaining independent settings, gestures and original output/platform requirements. Custom-color restart checks were not performed in this native subset. The old locked-Mac wording has been corrected in the current assessment while earlier records remain intact. No installed app, repository delivery or App Store record was changed. [Validation](S05_VALIDATION_399.json) · [Requirement assessment](S05_ACCEPTANCE_399.json).


## 2026-11-04 — Step 400: Quick Mask colour options and reference conflict

The remaining S05 check starts with a custom green overlay in Photoshop, Selected Areas and 37% opacity. Cancel restores the original red, Masked Areas and 50%; OK retains the custom settings. Tracing the complete double-click sequence shows its mode change matches Photato, so that initial suspicion is withdrawn. An owned Fill probe changed its remembered choice; it was restored and verified before the disposable document was discarded.

In Photato’s unchanged build 398, the options sheet’s colour well did not open a usable colour panel after normal and accessible actions. The existing foreground colour button did. The repair reuses that control with the same sRGB colour binding. A dialog releases its own panel when removed, and cannot close a panel that another control has since claimed. Old callbacks cannot alter a discarded draft. The existing API colour parameters and shared native transaction remain unchanged.

Four regression cases were added. Both optimized builds and all 227 selected S05/workspace/dock cases pass. The exact slices are packaged as universal build 400. In the actual app, a custom colour can be entered through RGB fields, cancelled, committed and retained after normal quit and relaunch. The entered defaults are restored afterwards. No installed app or App Store record changed. [Evidence](S05_OPTIONS_GESTURES_400.json).


The restart check exposed another S05 problem. With Selected Areas and no initial selection, Photato shows a full overlay; Photoshop starts clear. A controlled 8×8 white image was opened in Photoshop and saved with that mask active. An independent PSD reader confirms the initially-empty flag, display record and all 64 mask samples. This case was absent from the passing tests.

The next work will establish how raw channel gray, selection coverage and indication changes relate, including painting and Q exit. Changing only the initial screen appearance could leave file interchange or selection behavior wrong. The counterexample stays open, and the current core-workflow completeness flag is corrected accordingly. The colour-panel repair and restart checks remain valid within their stated scope.


## 2026-11-04 — Step 401: Quick Mask reference matrix; repair parked

Seven owned Photoshop documents establish the relationship between selected areas, mask gray and Q exit. Changing the active mask indication preserves the selection but inverts its gray samples. In Selected Areas, black produces an explicit full selection on exit; white produces none. The partial test selected five columns, confirmed from the saved files. Earlier filenames saying half are retained with that correction.

The native model and PSD conversion need a shared repair, including initially-empty masks and Float32 source retention. No application code changed. The exact documents, parser reports, screenshots and failed UI attempts are retained, and the entered Photoshop mask/Fill settings were restored before closing the owned probes. This work is now parked under major still needed. S05 stays open.

## 2026-11-04 — Step 402: Seven-pass work order

The maintainer asked us to stop spending successive increments on the tail of one feature while other workflows remain incomplete. Every active package now has quick-win, still-needed and cleanup tracks. The order is major quick wins, major still needed, minor quick wins, minor still needed, major cleanup, minor cleanup, then final settings and checks.

We will visit each package once per pass. A quick win should fit one normal implementation checkpoint and include its native controls, menu/API behavior, history and focused tests. If investigation reveals a larger project, we will record what was found under still needed and move on. Packages without a credible small change skip the quick-win pass. Completed track work does not close a package or waive exactness and platform requirements.

Delete All Empty Layers is selected first. The command is pending and absent from the current source search; its Photoshop behavior still needs an owned-document check. It is shared by L01 and AUT02 and will count as one delivery. D01 follows, then L07/S01/G01/A03 candidates. C01 no longer waits for full S05 closure. The detailed inventory retains all 104 original active package scopes and 651 command records.

The current priority, diary, plan and dashboard now use this work order. Both offline diary copies are refreshed. No native application code or version changed, and no new native test result is claimed. Build400 remains the latest tested candidate. The full goal is still active.


The local dashboard checks pass: all 13 existing Python tests and JavaScript syntax validation. In the browser, the seven passes filter the correct package lists and every package displays its three tracks alongside the original acceptance criteria. The mobile layout fits without horizontal overflow. These are dashboard checks, not new editor tests.

The complete current work list follows. Candidates still need a source audit; a dash means no small implementation was identified.

## Major functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| L01 — Layer organization and Background semantics | Implement Delete All Empty Layers through one native transaction and the optional API | Complete remaining Background/locks/links/selection/arrangement/filter/isolation operations |
| D01 — Open, save, close and revert workflows | Repair a bounded failing Close All/Others or Save a Copy case before broad lifecycle expansion | Complete remaining open/save/revert/quit, read-only access and persistent permissions |
| L07 — Artboards and frames | Add a missing artboard duplicate/background command on existing geometry | Complete artboard coordinates/guides/export and Frame tool content replacement |
| S01 — Basic selection completeness | Implement confirmed missing Grow/Similar commands with native/API selection history | Complete marquee variants, Reselect, border/move/transform and selection options |
| G01 — Transform and crop completeness | Wire Transform Again to the retained transform operation | Complete multi-target/mask transforms, reference/snapping and nondestructive crop/resize |
| A03 — Remaining classic adjustments | Connect existing Brightness/Contrast to native destructive and adjustment-layer menus | Complete remaining classic adjustments, presets, masks and dialogs |
| I05 — Production export workflows | Add native LUT export for an existing supported color transform | Complete Save for Web/slices/assets, presets/scales and layer/artboard/comp exports |
| B05 — Patch, Content-Aware Move and Red Eye | Complete Red Eye controls using the existing removal engine | Complete Patch adaptation and Content-Aware Move/Extend protected-region workflow |
| C01 — Component visibility and edit targeting | Bring RGB8 component rows to existing high-depth Shift-selection behavior where supported | Complete multi-target editing/visibility, temporary masks, eye gestures and factory shortcuts |
| AUT01 — Actions and batch processing | Expose an existing action reorder/duplicate command in native UI | Complete semantic targets, dialogs/conditions/ATN/droplets/batch/Image Processor |
| G03 — Live shape tools and vector operations | Expose a missing shape property backed by existing live shapes | Complete shapes/arrows/corners/stroke/booleans/presets and pixel/shape/path modes |
| G04 — Pen and Paths completion | Expose a missing Fill/Stroke Path action using the existing path engine | Complete pen variants/modifiers, multi-anchor editing, fitting and clipping-path export |
| T01 — Full native text editing | Add a missing Character/Paragraph control already supported by rich type | Complete on-canvas/rich type editing, point/box conversion and editable PSD text |
| T04 — Path, warped and Dynamic Text | Expose an existing path/warp text parameter in native controls | Complete text-on/inside paths, Dynamic Text, auto-fit/reflow and persistence |
| A01 — Levels, Curves and Auto correction closure | Expose a missing Levels/Curves preset or Auto option backed by existing engine | Complete sampling/clipping/targeted/freehand curves, mask/HDR and presets |
| A04 — Current2026 adjustment layers | Add a missing native control for an existing modern adjustment | Complete 2026 nondestructive adjustments and editable PSD behavior |
| A05 — Gradients and gradient-fill completeness | Expose an existing gradient transform/preset through on-canvas controls | Complete modern editing/interpolation/noise/dither and GRD/preset behavior |
| A07 — Pattern fills and pixel fills/strokes | Add a missing Fill/Stroke placement option backed by current engine | Complete pattern transforms/libraries/interchange and fill/stroke target semantics |
| F01 — Filter framework and ordinary blur/sharpen/noise | Expose a supported filter's missing preset or repeat-last action | Complete ordinary blur/sharpen/noise catalogue and consistent preview/cancel pipeline |
| F02 — Distort, Pixelate, Stylize, Render and Other | Implement one bounded missing ordinary filter with shared native/API path | Complete remaining Distort/Pixelate/Stylize/Render/Other and available legacy filters |
| F03 — Blur Gallery | Add an existing Blur Gallery parameter missing from controls | Complete field/iris/tilt/path/spin handles, bokeh/noise and editable Smart Filters |
| F04 — Liquify | Expose existing freeze/thaw/reconstruct operations in the Liquify workspace | Complete mesh/push/twirl/pucker/bloat/face-aware controls and persistence |
| F05 — Perspective and lens filter workspaces | Expose a missing manual lens-correction parameter backed by existing engine | Complete perspective planes/constraints, Adaptive Wide Angle and lens workspace |
| F06 — Filter Gallery and legacy applicability | Expose existing gallery-stack reorder or preset commands | Complete legacy effect catalogue and applicability across supported document modes |
| B01 — Brush engine and brush settings | Add a missing brush setting control backed by existing deterministic engine | Complete tip families, dynamics/scatter/texture/symmetry/ABR and input curves |
| B02 — Missing paint and eraser tools | Complete one missing option on an already working Pencil/eraser tool | Complete Mixer/Replacement/Pattern/Background/Magic Eraser target and sampling behavior |
| B04 — Clone, heal, blur and toning completeness | Expose a missing clone-source control backed by the current renderer | Complete healing/sample modes/dynamics/overlays and toning/focus behavior |
| B06 — Content-Aware Fill and Scale | Expose an existing output-layer choice in Content-Aware Fill | Complete sampling workspace, adaptation, crop fill and protected content-aware scaling |
| B07 — Tablet, stylus and eyedropper qualification | Add missing persistent Color Sampler point controls using current sampling | Complete real stylus/eraser/button replay, averaging and cursor/latency handling |
| D04 — Clipboard interoperability | Add one missing channel/path clipboard format using existing serializers | Complete external layered/vector/PDF clipboard, depth/profile and Background Cut semantics |
| L03 — Advanced blending | Add a missing native control for an already implemented advanced-blend property | Complete Fill opacity, split Blend If, knockout/channel/clip/mask flags and PSD persistence |
| L04 — Layer styles and effects | Expose missing Copy/Paste/Clear Layer Style actions on the existing style engine | Complete effect options, contours/global light, multiple effects, presets and editable interchange |
| L05 — Embedded and linked Smart Objects | Finish a bounded missing-link or relink action without reopening precision research | Complete nested/shared/independent source editing, replace/update/export/package and transforms |
| L06 — Smart Filters | Add a missing enable/reorder/copy operation on existing Smart Filters | Complete editable stacks, masks/blending and supported metadata/fallback behavior |
| S02 — Color Range, Focus Area and Magnetic Lasso | Add an omitted preset/control to existing Color Range | Complete focus-region detection, edge-following lasso and averaged sampling |
| S03 — Object, Quick, Subject, Sky and People selection | Expose a supported subject/sky/person selection as a context-sensitive action | Complete object finder, all-object/person-part/quick selection and manual correction |
| S04 — Select and Mask workspace | Wire missing output choices to the existing selection/mask transaction | Complete refine workspace, edge/hair/smart radius, decontamination and outputs |
| S06 — Pixel/vector mask workflow closure | Expose a missing apply/delete-mask confirmation using existing mask commands | Complete target transforms/filters/clipboard, compound masks, defringe/decontamination |
| C02 — Alpha and spot channels | Expose a missing duplicate/reorder/rename channel action on existing core | Complete alpha/spot ink/solidity and native/PSD channel persistence |
| COL02 — Document color modes and separations | Expose a supported mode conversion missing from menus with its true restrictions | Complete all mode/depth/palette/dither/ink semantics and editable storage |
| COL03 — Proofing, HDR/EDR and print | Expose an existing proof preset missing from native controls | Complete proof/gamut/HDR/EDR, print/page setup and output profiles/overprint |
| RAW02 — Photo alignment and merging | Expose an existing stack statistic through a native command | Complete align/blend/panorama/HDR/focus stacking, masks/crop and deghosting |
| I03 — Original PhotoCraft .pcraft migration | Add an omitted supported upstream metadata migration with a licensed fixture | Complete all represented pcraft layers/types/metadata and safe original retention |
| I04 — Export and interchange formats | Expose an existing encoder option missing from export UI | Complete layered TIFF/EPS/DCS/PDF/SVG/EXR/HDR formats, profiles/depths/metadata |
| AI07 — AI job/document lifecycle and persistence | Expose already tracked model/seed/provenance in result inspection where available | Complete immutable jobs, stale/cancel/results, editable persistence and offline reopening |
| SP01 — Timeline, frame animation and video | Expose an existing frame-timeline command missing from native controls | Complete timeline/video/keyframes/transitions/audio and import/render/animation export |
| AI09 — Sky Replacement | Expose an existing sky-library import/delete action in native controls | Complete replacement masks/horizon/light/color and nondestructive manual refinement |
| B08 — Adjustment Brush | Expose an existing Adjustment Brush preset or targeting option in native controls | Complete adjustment painting, automatic target/refine and native workflow |
| Q03 — Responsiveness and cancellation | Remove one measured remaining main-thread blocker in an ordinary tool path | Complete progressive preview/cancel/low-memory and sustained interactive responsiveness |
| Q04 — Independent Photoshop oracle and corpus programme | Add focused independent fixtures for each newly implemented quick win | Expand independent modes/depths/profiles/formats/workflow corpus and malformed input coverage |
| REL01 — App Store archive, sandbox and release CI | Repair one confirmed archive/sandbox validation defect using existing project | Complete production identity/entitlements, reproducible archive CI and disclosures |
| AUD01 — Reconcile all inventories and freeze the target | Keep new function/menu/API inventories synchronized as each quick win lands | Reconcile all tools/commands/scenarios and current 2026 platform/service boundaries |
| AUT02 — Scripts, variables and command automation | Implement Delete All Empty Layers jointly with L01; one deliverable, not two completions | Complete scripts/events/variables/data-driven output and extension contracts |
| S05 — Quick Mask and saved selections | Add channel-row double-click to existing Quick Mask options | Repair confirmed selected-gray/initially-empty/explicit-full semantics; complete save/load/combine/shortcuts |
| A02 — Hue/Saturation and Color Balance exactness | — | Complete targeted sampling and Hue/Saturation/Color Balance range semantics |
| A06 — Gradient and RGB32 fill exactness | — | Resolve RGB16/32 gradient transfer and fill semantics |
| AI01 — Model evaluation and native runtime | — | Complete licensed model selection/download/hash/remove and native inference memory/latency |
| AI02 — Apple local text and Private Cloud Compute validation | — | Complete real local/PCC generation, disclosure/cancel and unavailable-device behavior |
| AI03 — Remove, distractions and generative fill | — | Complete offline remove/distractions/prompted edits, protected pixels and reversible variants |
| AI04 — Generative expand and backgrounds | — | Complete reversible expand/background/full-image generation with retained subject/source |
| AI05 — Reference-guided edits, prompts and markup | — | Complete reference-guided/markup/prompt edits, variants and provenance |
| AI06 — Harmonize, generative upscale and Neural Filters | — | Complete harmonize/restoration/upscale and available Neural Filter equivalents |
| AI08 — Assistant and provider capability differences | — | Complete assistant capability audit and user-reviewed native command planning |
| AUD02 — Resolve model, language and ecosystem boundaries | — | Resolve model-quality/locales/services/plugin boundaries and acceptance decisions |
| AUT03 — Third-party plugin compatibility | — | Define and implement supported native plugin/extension compatibility and isolation |
| COL01 — ICC working-space and color management | — | Complete import/profile policies, assign/convert, intents/BPC and calibrated display |
| D02 — Crash recovery and autosave durability | — | Complete crash-safe journal/recovery, fault handling and restoration UX |
| G02 — Warp, Puppet Warp and Perspective Warp | Expose a missing warp preset backed by existing geometry | Complete editable grids, Puppet pins and perspective/nondestructive smart transforms |
| G05 — Vector rasterization fidelity | — | Complete winding/sample/raster coverage behavior and supported PSD path forms |
| I01 — Editable PSD feature coverage | — | Complete missing editable PSD feature records and safe unknown-block editing restrictions |
| I02 — PSB and large/streaming file support | — | Complete bounded PSB streaming, multi-GB editable round trips and malformed-file guards |
| L02 — Layer composition and merge exactness | — | Complete group/clipping/mask blends, multi-layer rasterize and merge/flatten correctness |
| Q01 — Large-document storage and scratch engine | — | Complete scratch/tile paging, bounded undo and large mask/vector/group storage |
| Q02 — Metal and incremental rendering | — | Complete incremental GPU/CPU composition and deterministic rendering fallbacks |
| Q05 — End-to-end professional acceptance and runtime matrix | — | Complete professional scenarios, real runtime/device/input/display matrix and soak testing |
| Q06 — Universal byte-identical Photoshop results | — | Resolve sample/render/file identity boundaries and known cross-architecture/output differences |
| RAW01 — Camera RAW development | — | Complete native RAW development, local masks, lens/highlight/XMP and nondestructive sources |
| RAW03 — RAW restoration and reflection removal | — | Implement/evaluate RAW restoration and reflection-removal equivalents |
| S07 — AI edge enhancement | — | Implement and evaluate editable Enhance Edge refinement for hair/translucency |
| SP03 — Cross-application and asset ecosystem | — | Complete native local/open-service asset and cross-application equivalents |
| T02 — Multilingual and OpenType typography | Expose a supported variable-font axis or ligature option in native controls | Complete bidi/RTL/Indic/East Asian/vertical typography and font fallback/composers |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Minor functions

| Package | Quick-win candidate | Still needed |
|---|---|---|
| B03 — History and Art History Brush | Expose a missing history-source selector over current history state | Complete pixel-compatible History Brush and artistic styles/constraints |
| C03 — Channel calculations and interchange | Expose an existing Apply Image/Calculations setting absent from native controls | Complete split/merge/spot merge, cross-document sources and mode/depth interchange |
| C04 — Channel display and thumbnail parity | Finish thumbnail-size preference persistence with existing panel options | Complete channel color display, preview samples and menu/cancel lifecycle |
| D03 — History, snapshots, Fade and purge | Expose Toggle Last State through existing history state | Complete snapshots, nonlinear history, Fade, history source/logs and purge |
| G06 — Rotate Object and pattern preview | — | Implement object-reorientation equivalent and seamless Pattern Preview |
| I06 — Metadata and content provenance | Expose a missing copyright/description field in File Info | Complete EXIF/IPTC/XMP retention, provenance and supported credentials/signatures |
| L08 — Layer comps and local libraries | Expose a missing Layer Comp update/rename action on the existing engine | Complete comp capture/apply/appearance, reusable local assets and cross-document workflow |
| SP02 — Slices, measurement and scientific workflows | Expose a supported Ruler/Count measurement through the native panel | Complete slices/measurement/logs/annotations/DICOM and image-stack analysis |
| T03 — Text styles and utilities | Add Find/Replace for existing editable text runs | Complete styles, spelling, font resolution, type masks and conversion/rasterization |
| U01 — Post-dialog panel command state | Reproduce and repair stale Panel Layout validation after options Cancel | Complete document-switch, Escape and OK command-state coverage |
| U03 — Docking and document-window interaction | Add one missing document-arrangement command using the existing arrangement engine | Complete tab tear-off, floating/docking and synchronized multi-view workflows |
| U04 — Canvas navigation and view modes | Add missing Fit Layers or Fit Artboards command through existing view geometry | Complete scrubby/animated zoom, view modes, print/pixel-aspect and Retina behavior |
| U05 — Rulers, guides, grids and snapping | Expose missing guide locking/clearing commands over existing guides | Complete unit-aware origins, smart guides, layouts and snap targets |
| U06 — Remaining utility panels | Finish one existing utility panel's missing menu action | Complete Navigator, Histogram, Info, Notes, Measurement and Tool Presets |
| U07 — Home, New Document, search and contextual actions | Add a reusable New Document preset using the existing creation path | Complete recent/clipboard presets, search discovery and contextual actions |
| U08 — Menu and shortcut closure/customization | Wire confirmed missing alternate shortcut bindings to implemented commands | Complete custom shortcut/menu/toolbar sets and context validation |
| U09 — Preferences and settings | Expose a working engine preference missing from Settings | Complete preference categories, migration, reset and factory defaults |
| U10 — Numeric input and dialog behavior | Add arithmetic expression entry to an existing unit-aware input | Complete ranges, scrubbing, modifiers, preview and modal keyboard behavior |
| U11 — Color and asset panels | Add search to existing local swatch/pattern groups | Complete grouped assets, import/export and Photoshop color picking |
| U12 — Accessibility and localization | Repair confirmed missing accessible names/focus in a working editor panel | Complete keyboard-only/VoiceOver workflows and localization architecture |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.

## Final details and release completion

| Package | Quick-win candidate | Still needed |
|---|---|---|
| REL03 — Open-source fork publication | — | Complete curated upstream-history fork, notices/provenance and public release preparation |
| REL04 — Beta, documentation and release readiness | — | Complete help/migration/known-limits, installation/update and release documentation |
| U02 — Workspace appearance and factory defaults | — | Match workspace geometry, icons, contrast, compact layouts and factory defaults |

Cleanup for every package: Independent output/default/shortcut fidelity, remaining combinations, numerical residuals, broad regression and supported physical-platform/performance qualification. A bug that makes the chosen path unsafe or unusable stays with implementation.



## 2026-11-04 — Step 403: Delete All Empty Layers native baseline

File > Scripts > Delete All Empty Layers now runs through native Swift and the optional layers.deleteEmpty API. It examines stored alpha, so hidden, zero-opacity and off-canvas layers with content are kept. Plain groups made empty by deletion are removed. Clipping bases and extended editable content are preserved. Surviving selection and the active layer stay intact, with one Undo step when anything changes.

The first test run passed 80 of 81 cases on each architecture. Its failing test assumed the API view revision could not advance after a redraw; the established API includes view state in that token. The document, history and dirty-state checks passed. We corrected that new assumption and documented the distinction. The failed run remains available.

Review also found a real safety case: deleting an empty clipping base could reveal its nonempty clipped layers. The second source preserves clipping bases. New graph and rendered-output tests demonstrate the unsafe result and verify that corrected deletion keeps the exact pixels. An overstated Adobe-compatibility sentence was corrected too: the automatic empty selector is Photato-only, and the general Adobe deletion adapter remains an open gap.

Both corrected builds pass all 83 selected tests, including 14 new cases. In the actual universal app, two owned empty layers disappear through the native menu, return with one Undo, and disappear again with Redo. The entered panel is restored and owned artwork discarded. Final normal Quit is confirmed by process absence without a UI query that could reopen the app. Discovery finds 4,050 cases; that does not mean the full suite passed.

Photoshop reference automation did not produce a verifiable deletion result. The public command documentation and observed menu establish its presence, not full selector parity. Masks, effects, retained source data, native-mode and other extended types remain protected while their behavior is qualified. The full L01/AUT02 packages stay open. No installation or release occurred.

The native baseline is delivered and D01 is selected next, followed by L07 and S01. Optimized builds took 8–10 minutes each while the selected tests took seconds. Subsequent quick wins will use focused development builds, with optimized universal/runtime qualification batched at stable milestones unless needed earlier. The seven passes and all original acceptance requirements remain unchanged.

## 2026-11-04 — Step 404: Single-pixel marquee and quick-win audits

The quick-win sweep checked two candidates already present in the app. All 25 document-closing cases and 15 artboard cases pass on each architecture without source changes. The old closing failures did not reproduce, and artboard duplication/background controls already exist. Those candidates can leave this pass; their full major packages remain open.

Single Row and Single Column Marquee were disabled placeholders. They now draw a live row/column outline and commit one selection on release, with captured add/subtract/intersect mode and feathering, cancellation and Undo/Redo. The API accepts row/column indices through the same geometry/history path. All 87 focused arm64 development tests pass, including 7 new cases and both tools across all 16 modifier combinations. Sparse 300,000-square native persistence is covered; dense capacity is not implied.

The first Debug build crashed in a Swift compiler optimization pass before tests ran. The retained retry disables that pass for development only; production settings stay unchanged. Normal optimized universal and physical-platform qualification remain open. Grow/Similar requires larger color-selection work and moves to stillneeded. G01 Transform Again is next, followed by A03. Full S01 and all original acceptance remain open. [Detailed record](DEVLOG.md#dev-step-404).

The isolated development app was also checked through its native flyout and canvas. A row spanned the width, a column spanned the height, and Undo/Redo restored the selection. The disposable document was returned to its clean state and the candidate quit normally. This is separate from normal optimized universal and Photoshop fidelity qualification.

## 2026-11-04 — Step 405: Color Lookup export and quick-win audits

The existing LUT export saved a table already loaded in an adjustment. File > Export > Color Lookup Tables now creates a CUBE table from the document's global color adjustments. It uses the native compositor at the document's bit depth and leaves the image and history unchanged. Spatial effects that cannot be represented by this path reject with a reason. The native file chooser and optional API share preparation and cancellation, including a matching operationID for direct API cancellation.

All 80 focused normal Release tests pass on each architecture, including 12 new tests. The first run's independent test parser counted domain headers as samples; that fixture was corrected and the failed attempt retained. Both the development app and final optimized universal app saved the same owned 181-byte inversion table. Its eight corners match independently expected values. One Undo removed the original Invert layer and restored the clean document; both apps quit normally. The universal package passes signing, minimum macOS 14 and ZIP extraction checks. Full Photoshop, physical-platform and remaining export qualification stay open.

Transform Again has no retained operation state to wire up, and the existing Brightness/Contrast model is an acknowledged approximation. Those larger candidates move to stillneeded. Red Eye's Pupil Size and Darken controls already work and pass their current checks. C01 is next, then AUT01. The checkpoint 404 source-label typo was corrected against preserved commands and hashes. [Detailed record](DEVLOG.md#dev-step-405).

The complete native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/9421bbc320dcbaad28e53eba926d042386eeefe9), with all 7,150 included qualified inputs matching the tested source. The 34 excluded inputs are listed with reasons in the portable source manifest. All 1,061 non-native root/Rust files remain unchanged. The repository becomes public on release day; no app binary or software release was uploaded.

## 2026-11-04 — Step 406: RGB8 component selection

Ordinary RGB8 channel rows ignored Shift, despite the shared engine already supporting component sets. The rows and existing `mode.channel.select` API now select pairs. Single-channel compatibility is preserved. The selected set feeds existing Fill, Invert, Brush/Eraser and filter commands; visible channels remain independent. The API reports both sets accurately. Selection itself adds no pixel edit or Undo entry.

Eight new focused development tests pass. They cover row dispatch, modifier combinations, literal unselected/alpha values, native/API results and previews, captured targets, cancellation/history, errors and a maximum sparse canvas. The first affected run is 103/104 with an existing maximum-CMYK HTTP timeout, which also fails on preserved 405. Additional component/view and painting tests pass; separate broader clipboard processes terminate by signal 10, also reproduced on preserved 405. The failures are retained without changing their limits or fixtures. The union of 121 passing current IDs is not a single passing test suite.

The actual native app passes a singleton row/shortcut/Invert/Undo/Redo/Quit check on an owned document. Physical held Shift-click pair selection was not verified; the attempted focused Shift-Space made no accessibility change. Exact Photoshop last-target/composite behavior and full channel acceptance stay open. This is the selected development baseline, followed by AUT01 and G03 in the major quick-win sweep. Normal optimized packaging waits for a stable breadth batch. [Detailed record](DEVLOG.md#dev-step-406).

## 2026-11-04 — Step 407: Duplicate saved actions

Step reordering already existed in the Actions panel and API. A dedicated Duplicate operation was missing. The panel menu and existing `actions.manage` API now copy one saved action through the same atomic library transaction. New action and step IDs keep the copy independently editable; ordered commands, names and enabled flags are retained. Copying changes no document pixels or Undo history.

All 34 focused arm64 Debug tests pass, including eight new cases. They check payload/identity independence, Unicode and naming bounds, persistence/reopen/import/export, limits and write/corrupt-library rollback, availability and API guards, and source/copy playback producing identical native document bytes with one Undo. The fixed older offscreen capture was preserved; the new capture is saved separately.

A separate native sandbox provided an isolated test library. The app recorded Invert on owned artwork, created and selected the copy, then played it. Independent reading of the saved library confirms fresh IDs and an unchanged source/payload. Undo reverses playback in one step, then returns to the original clean image; duplication added no image-history entry. The app quit normally, and the existing shared library hash remains unchanged. Full AUT01 and exact Photoshop naming/order/hierarchy/drag behavior remain open. G03 is next, then G04. [Detailed record](DEVLOG.md#dev-step-407).

## 2026-11-04 — Step 408: Shape stroke presets

The shape editor already had geometry, corners, arrows, paints and detailed stroke controls. The small missing control was a Solid/Dashed/Dotted selector. It now uses the existing dash/cap renderer and native preview/history path. Custom patterns remain editable and retain their values. Tool Settings and the existing shape API commands share the same transformation; no file-format change was needed.

Eight new cases cover rendering at RGB8/16/32, native/API document-byte equality, preview/Cancel/Undo, captured settings, persistence/playback and invalid/busy/stale requests. They pass in Debug. The wider Debug run retains a curved-stroke Rust mismatch and signal10 in an existing shape API test. In a separate standard optimized batch, all 156 selected cases pass on each architecture, including24 new cases across406–408. The two earlier timeout/crash IDs pass there. No cause or full-suite repair is claimed.

Packaging first encountered a PATH conflict with a Python xattr utility. That failed attempt was preserved; using the macOS system command allowed strict signature, both minimum macOS 14 targets and fresh ZIP extraction checks to pass. All37 available protected baseline hashes remain unchanged; three historical missing files remain unresolved.

The Mac locked before the live native check. The isolated candidate is retained, and its control/drawing/history/Quit validation awaits human unlock. This gate stays open while G04 source audit proceeds, followed by T01. Exact Photoshop defaults/output and all original G03 scope remain open. [Detailed record](DEVLOG.md#dev-step-408).

The source backup is verified on [private main](https://github.com/ForensicIntelligence/Photato/commit/004b0f4625d99008f2bc3ae2e76a0d34f1074e50). All 7,153 included qualified inputs match the tested snapshot; the exclusions and pending live check are documented. Original root/Rust files and Git history are retained. No binary, App Store change or software release was uploaded.

## 2026-11-04 — Step 409: Quick-win source audit

Four candidates were checked against the source before choosing more implementation work. Paths already had Fill and Stroke controls and a shared API. The existing rich-text fields were already exposed, as were the shaped-text layout parameters. The selected 13 path, 20 typography and 18 tonal tests all pass on both architectures using the preserved optimized build. No new software or tests were needed for this audit.

The audit also found two real gaps. Curves has no Auto operation or Auto Color Correction Options; the reusable estimator returns Levels settings. Window > Character and Paragraph remain pending even though their controls are available in Properties. Proper separate panels require integration with the retained workspace layout and native lifecycle. These gaps stay under stillneeded, with full original scope and independent compatibility requirements intact.

The quick-win queue advances to A04, current 2026 adjustments, then A05. This is a source and regression audit, not four completed Photoshop features. The prior Debug failures, full-suite and physical-platform gates, and pending live stroke-preset check remain recorded. [Detailed record](DEVLOG.md#dev-step-409).

## 2026-11-05 — Step 410: Gradient Fill API and Actions

The source audit found that modern adjustment controls and native gradient transforms/presets were already exposed. A direct API for editing a live Gradient Fill was missing. The new command uses the existing native transaction and publishes its request, active state and capabilities. It preserves masks, transforms, selection and unrelated data, and supports one-step Undo/Redo.

The first new test run exposed an older recorder limitation: Gradient Fill edits were saved as unsupported steps. A portable target-and-fill payload now records, validates, exports, imports and plays back those edits. New payloads require Actions 47. A separate existing mask-gradient test assumed the image palette while editing a mask; it now selects its intended ramp explicitly, and a new test checks the actual default mask ramp independently. No rendering kernel or palette default changed.

All 74 focused Debug tests and82normal optimized cases on each architecture pass, including eight new cases. Both Release runs execute the same ordered IDs. The universal package passes macOS 14 minimum, signature and ZIP extraction checks. Failed attempts remain in the detailed record. Actual native interaction, full Photoshop behavior, the current full suite and physical-platform/performance checks remain open. Next is the Pattern Fill/Fill/Stroke audit, then ordinary filters. [Detailed record](DEVLOG.md#dev-step-410).

## 2026-11-05 — Step 411: Last Filter

The Pattern Fill audit confirmed that the existing angle, scale, offsets, linking, origin and canvas controls were already present. Stroke already supported Inside, Center and Outside placement. Selected model, native, API and interchange checks pass on both architectures. Full pattern and fill/stroke compatibility remains open.

The next package had a useful missing command: Last Filter was visible but unbound. It now recalls successful native filter settings, shares them between attached documents and repeats them with the current selection and target. Option invocation opens copied settings for preview or cancellation. The new API command publishes recall state and follows the same transaction and revision checks. Existing portable filter Actions handle recording; no document or action format change was needed.

All eight new tests and 42 focused Debug cases pass. Failed attempts are retained, including two corrected test assumptions and an existing Adobe-job Debug signal-10 failure reproduced on the previous build. Release, actual UI and full Photoshop acceptance remain open. The quick-win queue continues at the ordinary filter catalogue, followed by Blur Gallery. [Detailed record](DEVLOG.md#dev-step-411).

## 2026-11-05 — Step 412: Filter Gallery dragging

The filter-workspace audit confirmed that the selected ordinary filter, Blur Gallery, Liquify and manual Lens Correction controls already existed. Their 59 regression tests pass on each architecture. Calibrated lens profiles, complete effect behavior and independent output/default comparisons remain open.

Filter Gallery had arrow buttons for reordering effects but no direct row dragging. The new private drag transfer checks the workspace, settings revision and individual gesture before moving anything. It rejects delayed drops after an edit or Cancel, transfers from other workspaces and superseded gestures. All effect values and hidden states survive moves. The existing native transaction, local history, document commit, Actions payload and ordered-array APIs are retained.

Eight new tests cover transfer, order/field retention, rejection, delayed callbacks, preview/Cancel/history/recording, desktop/API bytes, stack limits and modal cursor restoration. All 53 focused Debug tests pass. Normal builds pass 116 main cases and two additional metadata cases on each architecture, including all 16 new Last Filter/Gallery tests. The two metadata tests were omitted from the initial Release selector and then run separately on the same binaries; this was not a single 118-case run.

The universal package passes signing, macOS 14 minimum and archive extraction. The windowless capture is layout evidence with material/thumbnail limitations. Physical dragging and system feedback remain unverified while the unlock request is pending. Full F06 and all original Photoshop requirements remain open. Next is the brush-settings source audit, then B02. [Detailed record](DEVLOG.md#dev-step-412).

The private full-source backup is verified at commit `1a7845d308aae9ddffb0f81a4ad0dbd15bbaefe5`. All 7,160 included qualified inputs match the tested source. The 34 excluded inputs are generated/cache material or the restricted external PSD, with acquisition and provenance instructions preserved. All 1,061 original root/Rust files and prior history remain unchanged. This is a source backup; it does not release the software.

## 2026-11-05 — Step 413: Brush Settings sidebar controls

The painting audit found that current brush-model settings, Pencil Auto Erase, Clone Source transforms/overlays and Content-Aware output choices already had native controls and API paths. Their 50 selected regression tests pass on both architectures. We kept those implementations and preserved the larger gaps in their full work packages.

One useful brush interaction was missing: enabling a group directly from the sidebar. Eleven checkboxes now use the existing setting flags, with preset locks kept separate. Tip Shape, Smoothing and Symmetry retain their existing controls without invented enable flags. Public Adobe guidance documents sidebar group checkboxes; this is not a new live Photoshop observation.

One new end-to-end regression checks all checkbox mappings, no-op/history behavior, busy/stale/type guards and subsequent native/API stroke bytes and Undo. All 62 focused Debug tests pass after a test-only compile correction and a runner-only capture-directory correction. Failed attempts remain in the detailed record. No kernel or file format changed. Normal universal and actual pointer/layout checks remain open. Next is clipboard interoperability, then layer styles. [Detailed record](DEVLOG.md#dev-step-413).

## 2026-11-05 — Step 414: Smart Filter dragging

The layer-workflow audit found existing native/API controls for current clipping and fill settings, copying/pasting/clearing styles, and relinking/updating linked artwork. Clipboard support is still limited to composite image content; adding mask/channel/path targets needs new routing, transactions and API behavior. Those larger requirements remain in stillneeded.

Smart Filter rows had arrow-menu reordering but no direct drag or copy interaction. A private process-local transfer now supports single-filter copying within one document and reordering within a stack. It carries a random token rather than document content and checks source identity, generations and document attachment again after loading. Option feedback and the dispatched operation share one resolver. The existing stack transaction preserves target masks and source bytes, validates rendering and supports Undo and portable Actions.

Three new tests cover private transfer, copies across pixel depths and new/existing masks, desktop/API saved bytes, history/Actions, invalid and delayed transfers, limits and all modifier combinations. A test-fixture constructor mistake was corrected without production changes. All 53 focused Debug tests pass. Normal builds pass 99 of 100 cases on each architecture; the single linked-PSD/PSB alpha mismatch is unchanged from the earlier baseline and remains open. No tolerance was changed. The universal package passes signing and archive checks. Physical interaction, cross-document/group/mask transfers and full Photoshop acceptance remain open. [Detailed record](DEVLOG.md#dev-step-414).

## 2026-11-05 — Step415: Select Subject options

The selection audit found that all settings represented by the current Color Range, Focus Area and Magnetic Lasso engines already had controls. Their41existing tests pass on both normal baseline architectures. Missing classifiers, gamut selection and Adobe preset semantics stay in stillneeded; full Photoshop acceptance remains open.

Object/Quick Selection lacked the Select Subject action in its Options bar. The new button uses the existing on-device foreground-selection transaction and captures the tool’s visible sampling choice. It does not overwrite the separate Properties/Menu preference. The optional API uses the existing selection.subject operation; availability and capability metadata now explain the native action.

One new regression checks both tools against input-dependent masks, including sampling capture, locked16-bit source preservation, replacement despite paint-mode settings, matching native/API documents and saved bytes, one Undo/Redo and guards. All81focused Debug tests pass. An initial baseline driver guessed three test paths incorrectly and was corrected before any worker launched; that failed attempt is preserved. No application/test repair was needed after compilation. Normal universal and actual pointer/layout checks remain open. Next: Select and Mask, then mask confirmations. [Detailed record](DEVLOG.md#dev-step-415).

## 2026-11-05 — Step 416: Selected-mask removal and API

The mask audit found all six Select and Mask outputs already wired to native/API transactions. Current alpha/spot rename, duplicate, reorder and options controls also exist. Those packages retain their larger missing workflows and fidelity requirements.

Layers trash always requested layer deletion, even with a mask selected. It now routes pixel/vector/Smart Filter masks to their own operations, preserving the layer and compound masks. Native confirmation captures the source and editing context, blocks API edits and rejects stale replies. Properties trash shares the pixel-mask prompt; explicit menu commands keep their meaning. The new mask.manage operation fills the missing typed pixel/vector apply/delete API path and uses the same prepared engine/history.

Three new regressions check RGB 8/16/32 results, exact native/API files, one Undo/Redo, existing pixel/filter Actions, all modifiers, invalid/stale/busy/locked contexts and native alert choices/bounds. All 102 focused Debug tests pass after one real API admission correction and two new-fixture corrections. Failed sources, binaries and logs remain. No imaging kernel, file format or capacity limit changed. Vector portable recording, current Photoshop dialog/default/physical fidelity and normal universal qualification remain open. [Detailed record](DEVLOG.md#dev-step-416).

## 2026-11-05 — Step 417: Statistical image stacks

The mode and proofing audits found existing controls rather than omitted menu actions. All eleven stack modes were also present, but five mathematical definitions differed from Adobe’s current public documentation. This was a useful correctness fix within RAW02; its larger photo-merging workflows stay open.

The shared Swift engine now uses sample variance, its standard deviation, signed skewness, raw kurtosis and Shannon entropy without the earlier binning or normalization. Four owned tests include 14 rational and high-precision Decimal cases, 70 exact Float32 expectations, native RGB32 pixels, persistence, history and both API interfaces. The original Rust fixture remains intact; its differential check now covers the six unchanged operators. Photoshop behavior takes priority over conflicting Rust formulas.

The first new action-job fixture requested PNG for RGB32, which the encoder correctly rejected. That failed attempt and its binaries are retained. Changing only the fixture to TIFF gave 41 passing Debug tests. Normal builds each ran the same 159 tests and passed 157, including all eight new tests from 415–417. The two failures match preserved baselines exactly: four alpha bytes in linked PSD/PSB previews and a master-palette CancellationError. Neither is waived or claimed fixed.

Both architectures match the independent 70-word reference. Universal packaging, signature verification and extracted ZIP equality pass. Actual native interaction, complete Photoshop output and edge behavior remain unqualified. All original scopes and prior failures remain recorded. Next: I03 migration audit, then I04 export/interchange. [Detailed record](DEVLOG.md#dev-step-417).

## 2026-11-05 — Step 418: Frame Timeline dragging

The migration audit found the currently supported metadata already preserved. Adding nondefault notes, compositions, timelines and other source fields needs new adapters and reference files. Save/Copy already exposes the fourteen represented encoding options. AI generation currently has no durable model/seed result record to inspect; its lifecycle foundation remains stillneeded.

The frame Timeline had reorder arrows but no thumbnail dragging. A private process-local transfer now selects the source frame, previews an insertion edge and invokes the same reorder command. Source/session/panel/ownership checks reject stale or foreign drops. Frame contents remain in the document, and one Undo reverses the move. API capability metadata explains the existing selection and reorder operations; no new route or format is introduced.

All 49 selected baseline tests pass on both preserved normal architectures. After a test-only compile correction, all 50 focused Debug tests pass, including three new regressions. They compare native/API files, pixels and history across three depths, insertion positions and delayed-transfer rejection. Physical feedback, auto-scroll, multi-frame and modifier duplication, complete animation interchange and normal 418 acceptance remain open. Next are the Sky Replacement library and Adjustment Brush audits. [Detailed record](DEVLOG.md#dev-step-418).

## 2026-11-05 — Step 419: Rename sky presets

Sky import/removal and API rename already existed, but the native workspace had no rename action. Adobe’s current sky-preset instructions include Rename Sky. The new native dialog uses the existing library method, captures its source and revision, and preserves IDs, order, image bytes and document history. Preview names update after a successful save. Library changes persist independently of cancelling the document replacement, matching import and removal.

All 26 selected baseline tests pass on both normal architectures. All 57 focused Debug tests pass after a test-only compile correction, including three new checks for native/API file equality, unchanged pixels/history, persistence, Cancel, invalid Unicode names, failed storage with retry and stale contexts. No generation model, rendering kernel, command or archive version changes. Existing Adjustment Brush controls were verified rather than rewritten.

Normal 419 and physical/current Photoshop dialog/hierarchy/default behavior remain open, along with full Sky Replacement and Adjustment Brush workflows. Next: measured responsiveness, then independent references. [Detailed record](DEVLOG.md#dev-step-419).

## 2026-11-05 — Step 420: Rasterization responsiveness

The existing optimized brush benchmark retained all 240 samples in each of four cases. Its24MP input/render/offscreen-draw p95 values were about0.006ms,12.73ms and3.55ms. Those CPU measurements do not establish physical60fps. Source review instead found a synchronous native rasterization path. An unchanged419Debug probe and main-thread profile confirmed the blocker before product changes.

Native rasterization now uses the existing detached geometry preparation and shared API command. No image mathematics changed. Three functional regressions cover18depth/content combinations, exact native/API/old-command documents and archives, Undo/Redo, cancellation, source replacement and busy/locked/modal guards. The new tests passed before an unchanged Debug Shape API case crashed; the same case also crashes on retained419. Both optimized builds execute195identical cases with193passes and two exact recorded failures. All18new methods from415–420pass, including the actual opt-in performance measurement. Independent stack checks still match70Float32words per architecture.

Optimized24MP submission takes0.023ms on Apple Silicon and0.046ms under translated Intel, with preparation about6.94s/12.25s in the worker. The pinned old expression replay is explicitly a same-process reference, not a measurement of an old optimized binary. Universal packaging checks pass. Physical/UI/performance/Photoshop output and full Q03 remain open. Next: Q04, then REL01. [Detailed record](DEVLOG.md#dev-step-420).

## 2026-11-05 — Step 421: Channel thumbnail options

The Channels panel had an Options context menu but no thumbnail double-click route. The new native control selects the captured alpha, spot or Quick Mask target and opens the same dialog. It preserves existing modifier clicks, validates document/session/channel identity, and leaves pixels and history unchanged on open or Cancel. Committing uses the existing native/API operation and Undo behavior.

All 56 focused Debug tests pass. Three new methods cover nine depth/target combinations, exact native/API documents and archives, pixels and history, 64 modifier/click cases, a hosted native mouseDown event and stale/busy/modal/deleted/replaced contexts. The earlier 39-test reference/channel baseline and final 11-test warp/typography baseline pass on both retained optimized architectures. Independent statistics checks match 70 words each.

Source review found existing independent fixtures, production identity/sandbox configuration, per-increment inventories, every represented warp preset and installed-font axis/OpenType control. Their broader gaps remain. The old step058package checker is already documented as historical; it was not counted as a new archive defect or rewritten. No current optimized build, native installation, source push, archive, Store action or release occurred in this checkpoint.

The major quick-win sweep is finished. Major stillneeded work starts with L01 layer collection workflows and D01 document workflows. All original scope, byte/default/shortcut requirements and earlier failures remain. [Detailed record](DEVLOG.md#dev-step-421).

The final filesystem audit found 11 additional older temporary build binaries missing, alongside three previously recorded gaps. All 26 surviving protected files retain their expected hashes. The current source, 5,320 retained Debug outputs and 10,640 retained optimized outputs remain intact; the latest420candidate and ZIP also match. The cause and disappearance time of the older files are unknown. Their expected hashes and missing paths are recorded, and historical preservation remains incomplete.

## 2026-11-05 — Step 422: Arrange selected layers

Layer > Arrange now has all five commands. They preserve selected sibling order when moving, reverse only selected positions, carry complete group subtrees and retain every stored layer field. The native operation prepares in the background and commits one history entry after checking its source and target. The Photato API has strict parameters, state and availability; Actions 48 stores semantic targets. The supported Adobe MoveLayer placements run through the same primitives in isolated resource jobs.

All 106 focused tests pass, including 12 new regressions. An owned Python rank reference supplies 310 cases, checked at RGB8/16/32. The two first attempts each passed105tests and found one new test-fixture mistake: missing PSD IDs and an invalid translucent/masked Background. Both full attempts were retained before repair. Review also corrected the new adapter's bottom insertion index above Background. Source03 is test-only relative to Source02 and has the same app binary.

Both optimized architectures execute the same 281 cases and pass 279, including all 33 new methods from checkpoints 415–422. Existing failures remain recorded and are not waived. The universal macOS 14 package passes signature and extracted-ZIP content checks. This is feature qualification, not a passing full suite or complete Photoshop parity. Current physical checks still await Mac unlock.

The existing PSD writer omits regular layer-ID tags when no comp resources are active. The job fixture explicitly emits and verifies its IDs; a general ID-retention repair is not claimed. L01 filter/isolation, extended-empty and remaining lock/group workflows stay in major stillneeded. No minor or cleanup pass has started. [Detailed record](DEVLOG.md#dev-step-422).

The complete native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/9c9723749d107c98cdbe9871879115edc6dcfdfb). All 7,187 included qualified inputs match422Source03; 34 generated/cache/restricted inputs are excluded with provenance. The 1,061 original root/Rust files are unchanged. Repository visibility remains private until release day. No binary was uploaded and no software release occurred.

## 2026-11-05 — Step 423: Layer filtering and isolation

The old filter lived in each SwiftUI view, permitted only one kind and compared display labels. It missed specific adjustment types. A shared document-local filter now drives native panel rows, Find Layers, Isolate Layers and the API. Multiple kinds and known Smart Object statuses can be combined. Name, effect, blending mode, metadata attributes, color, selected layers and artboards are available. Selection ranges follow filtered rows. Filtering retains the document's pixels, visibility, stored bytes and content history.

All 77 current focused tests pass, including the 13 new native/API methods. Final review corrected case-sensitive artboard UUID handling; lowercase references and idempotence now have regression coverage. The earlier 85-test affected run passed 83 cases. Its two capacity errors reproduce in the retained 422 Debug bundle and pass in 422 optimized ARM64/Rosetta. The first compile attempt failed on two overlapping accesses in the new linked-source fixture; the failed source and outputs were preserved before repair. Parameter review also corrected NUL/UTF16-limit errors to return400. No test tolerance was relaxed.

The owned nine-mode native control image was rendered and inspected. Current Photoshop comparison remains unavailable while the Mac is locked. Exact defaults and the complete attribute/hierarchy/path-selection behavior are unqualified. Empty/NotEmpty requires asynchronous pixel scanning, and library-linked sources require integration that is not present. Those controls are unavailable and remain major stillneeded work. Background-only/no-active-layer selection and extended empty-layer behavior also remain open.

Typed API inventory is 248; native archive86 and Actions48 stay unchanged. Configuration is presentation state and has no published Adobe panel-state counterpart. Current optimized/universal/private-source qualification is batched for the next meaningful milestone; latest packaged/private source remains422. No new install, archive, upload or release occurred. [Detailed record](DEVLOG.md#dev-step-423).

## 2026-11-05 — Step424: Asynchronous layer content filters

Added Empty and Not Empty to the native panel and optional API. A cancellable worker checks stored alpha without a full-canvas allocation. It retains source storage while running, rejects changed sessions and revoked shares, and refreshes after edits. Pixels, layer visibility, Undo/Redo and recorded Actions stay unchanged. View selection can change when the active layer is filtered out; earlier whole-archive-unchanged expectations were corrected to test that observed distinction.

The owned Photoshop2026 document showed transparent raster and embedded Smart Object layers matching Empty, childless groups matching Not Empty, and no automatic selection when rows return. Group mode and the Advanced Blending attribute pair were observed but remain unimplemented. No proprietary code was inspected or executed as part of these comparisons.

All88focused Debug tests pass, including11new methods. The first build rejected a new Core test's dependency on an Imaging helper. The next run passed86of87cases; the mapped fixture had requested less storage than the existing index requires. Both attempts were preserved before test-only repairs. Later review found a read/close hook defect; optimized compilation was deliberately stopped before delivery, corrected, and covered by an actual NSDocument read/re-query/close test. The corrected source passes88of88. Subsequent optimized and packaged results are recorded below.

This remains major stillneeded L01 work. Full library/Group/Advanced Blending/special-content/default/platform qualification and all original104package scopes stay open. No installation, Xcode archive, AppStore upload or release was performed. [Detailed record](DEVLOG.md#dev-step-424).

Later qualification caught an API compatibility defect: revision tokens had grown beyond the existing 256-character source-reference limit. A 64-character hash preserves all change tracking without increasing that limit. The affected stack and Smart Object tests now pass. Final source424Source05 passes91focused tests and358of360normal cases on each architecture, including all57new415–424methods. The two residual failures have the exact build422 diagnostics. Universal minimum14/signature/ZIP checks pass. In the packaged native app, an owned brush stroke left the Empty filter and cleared selection; one Undo restored the empty layer. Complementary filters and normal Quit passed. The owned document was discarded; no user document was edited. No physical60fps or full Photoshop qualification is claimed.

The full native source backup is saved in the [private repository](https://github.com/ForensicIntelligence/Photato/commit/ce9c535ef80b8ccfb8b8f6ce4bcc82bf8276bb41). The 7,196 included build inputs match the tested source; 34 generated, cache or restricted inputs are excluded with recorded reasons. All 1,061 original root/Rust files are unchanged. The repository stays private until release day. This was a source backup; no binary was uploaded and no app was released.

## 2026-11-05 — Step 425: Layer selection and deselection

Added Select > Deselect Layers, fixed Command-clicking the final selected row, and made the unused space below layer rows deselect on a plain click. The native blank-area control fills the available viewport, exposes an accessibility action and rejects drags and stale owners. The rows remain lazy and their eye/thumbnail controls remain separate. All Layers now keeps a selected layer as its active target.

New `layers.selection` API operations share native behavior and expose selection and availability. User deselection can be recorded as a portable Actions 49 step. Pure selection recipes validate targets atomically, preserve pixel history/Redo and avoid scanning image buffers on the main actor. Mixed recipes still commit edits through one prepared Undo. Native archive 86 is unchanged. No unpublished Adobe selection endpoint or ATN compatibility is claimed.

The new code passes 127 focused Debug tests, including nine new methods. Initial attempts exposed a test method-name error, an inaccessible offscreen SwiftUI control, and the empty native button's default accessibility role/return value. Sources, binaries and failed logs were retained before repairs. The expanded clipboard suite also stopped with signal10 in a method with earlier Debug crash evidence; current cause remains unproven and optimized testing includes it. These failures are recorded, not erased by the passing focused run. The first optimized run also found six catalog-count checks still expecting 248 after the new API raised the total to 249. Only those expectations were corrected; the app binary stayed unchanged. The expanded focused run passes 127 tests, and the full affected optimized set was repeated.

Adobe's public selection instructions were used; the Mac locked again before a fresh owned Photoshop comparison. Offscreen native layout/event tests are not physical UI proof. Both optimized architectures pass 393 of the same 395 cases, including all 66 new methods from checkpoints 415–425 and the clipboard method that crashed in Debug. The two remaining linked-alpha/master-palette failures have the same diagnostics as checkpoint 424; no Debug crash repair or full-suite pass is claimed. The universal package passes both macOS 14 slices, signature and ZIP checks. D01 document workflows follow. The substantive L01 remainder stays in major stillneeded, and no minor or cleanup pass begins. [Detailed record](DEVLOG.md#dev-step-425).

## 2026-11-05 — Step 426: Customize Save Dialog File Formats

Added the Edit command documented by Adobe in August 2026. Its native dialog lets users select formats, restore defaults, clear the list, cancel or save the choices. Save As also respects the existing checks for preserving editable content; Save a Copy uses the selected supported encoders. This adds format visibility, rather than new codecs. Full Photoshop format support remains outstanding.

Choices are saved with File Handling settings through the existing atomic writer. Older settings load without being rewritten; a later commit writes settings version 4. Unknown or duplicate formats, malformed current settings, failed storage, active file operations and stale/external changes retain the earlier settings. Other recovery, recent-file and compression values are preserved. An empty or incompatible list cancels native panel creation with guidance, without silently inserting a hidden format. Exact Photoshop empty-list behavior is still unqualified.

The existing File Handling API accepts the same choices under its separate permission and revision guard. Document state exposes dialog choices separately from available encoders. Ordinary Save, recovery and explicit API output keep their existing behavior and bytes. Native archive 86 and Actions 49 are unchanged. The newly documented menu command supplements the earlier capture; all 651 tracked identities, captured hierarchy and factory shortcuts are retained. Exact placement, punctuation and default selections still need a live comparison.

All 101 focused Debug tests pass, including seven new methods. The initial run passed 100 of 101: a new API test reinitialized AppKit's document-controller singleton during the service and compared an unnegotiated legacy download with current archive bytes. Failed sources, binaries and logs were preserved before test-only corrections. The app binary is unchanged between those attempts. A normal-build helper then failed before compilation because its hash helper had been dropped during adaptation; that diagnostic was preserved and the helper repaired. Both optimized architectures pass the same 101 selected cases, including all seven new methods. The universal package passes minimum macOS 14, signature and ZIP checks. Earlier full-suite and checkpoint 425 residual failures remain open; this is not a full-suite pass. The owned offscreen dialog capture checks fit, not physical UI or visual Photoshop equivalence.

The Mac remains unavailable for live comparison pending the existing unlock request. L07 is next after this batch; remaining D01 and L01 functions stay in major stillneeded. No minor or cleanup pass starts, and no full package is declared complete. [Detailed record](DEVLOG.md#dev-step-426).

## 2026-11-05 — Step 427: Adjacent artboards

Added the canvas + controls described in Adobe's public artboard guide. A click adds an empty neighbour with the source dimensions and background; Option held when pressing copies the existing board and its contents. Releasing elsewhere or pressing Escape cancels. Tool, focus, document/session and selected-artboard changes also cancel the press. Temporary Hand does not create a board. Placement uses logical pixels and the existing sparse-canvas rebase without resampling source content.

The existing artboard.edit API now accepts adjacent, a side and optional copy/spacing/name parameters. Both entry points use the same request and prepared editing engine, including one Undo/Redo transaction. The API's older32,768 dimension bound was corrected to match the current300,000-pixel engine extent. Canvas union and memory guards remain. Native spacing is100 logical pixels; the API accepts explicit spacing. Exact Photoshop spacing, naming, background inheritance and occupied-neighbour behavior still need live reference checks. No new menu, shortcut, typed command or file format was introduced. Native archive 86 and Actions 49 remain unchanged, including the outstanding artboard Action-recording coverage.

The first build failed because the app called an internal Core validator. After preserving that attempt, it was changed to the existing public validation path. The second build passed the editing checks, but a new test looked at the wrong level of the API schema. The broader run then crashed in an existing Frame draw-over-image case. The retained previous 426 Debug binary reproduces the same signal10. This establishes an earlier reproduction, without identifying a cause or fixing the crash. The corrected focused selection retains the other Frame tests and explicitly excludes that one case.

All 41 focused tests now pass, including all eight new methods, 24 side/depth/create-copy combinations and 16 modifier combinations. They check exact native/API rendered results, stored content, archive round trips, history, cancellation and invalid/busy/stale/unshared requests. Offscreen inspection found the top control overlapping the name on a small board; its spacing was corrected and the same tests rerun successfully. The final owned capture shows the controls clear of the label. This is layout evidence, not a physical Photoshop comparison. Failed attempts and binaries remain in the technical record.

Normal/universal 427 and physical qualification remain batched. The prior Frame crash, exact defaults, nesting/dissolve and the remaining artboard/frame functions stay open. S01 is next in major stillneeded; all 104 original package scopes and acceptance criteria are retained. [Detailed record](DEVLOG.md#dev-step-427).

## 2026-11-05 — Step 428: Animated selection borders

The selection border was drawn with a fixed dash phase. It now uses native Core Animation layers for committed selections, Transform Selection and marquee previews. White strokes and black dashes stay the same screen width while zooming. Existing hole contours and bounded sparse-document geometry are reused. The layer animation does not request a Swift canvas redraw or recomposite the image for each frame.

Inactive, hidden, occluded, minimized or detached windows stop playback. Reduce Motion retains a static border. Selection Brush keeps its coverage overlay. The API exposes the presentation policy and requested animation, rather than claiming to report the compositor's actual playback state. This adds no editing command, menu, shortcut, cursor action or file-format field. Native archive 86, Actions 49, typed commands 249 and settings 4 remain unchanged.

The first focused run passed 81 of 82 tests. A new hole/zoom test installed a temporary path, then changed zoom, which correctly cleared that path. After preserving the failed source and outputs, the test was changed to use actual holed document coverage and await its render. The same 82 cases then passed. A further eight-method probe used asymmetric owned artwork to verify that the border follows the selected pixels in the native layer capture. The production binary was identical across those attempts. No selection algorithm or tolerance was changed to satisfy the test.

Both optimized architectures pass the same 98 selected cases, including all 23 new methods from checkpoints 426–428. The old Frame draw-over-image case also passes optimized; this does not explain or fix its earlier Debug crash. The universal package passes minimum macOS 14, signature and ZIP checks. Exact Photoshop dash timing, physical refresh-rate performance, complete Extras controls and broader platform/full-suite qualification remain open. All captures are owned offscreen evidence; no live Photoshop interaction is claimed.

The source audit confirmed that Grow and Similar are missing. The existing Magic Wand matcher uses the licensed PhotoCraft RGBA8 comparison and full-canvas buffers. The recorded plan calls for independent Photoshop fixtures, bounded sampling, paged coverage and shared native/API transactions. It remains a functional gap in major stillneeded. G01 is next; no major package is declared complete and no minor or cleanup pass begins. [Detailed record](DEVLOG.md#dev-step-428).

The full native source was backed up to the existing private [GitHub repository](https://github.com/ForensicIntelligence/Photato/commit/dd9f86229b43d0989a6fa8dfd7e48fd19cb75087). All 7,207 included qualified inputs match the tested snapshot; 34 generated, cached or restricted inputs are excluded with provenance. The original 1,061 root/Rust files are unchanged. The repository remains private until release day. This backup does not publish or release a binary.

## 2026-11-05 — Step 429: Transform reference point

The transform reference point can now be shown and moved freely, including outside the transform bounds. A shared nine-position locator remains available in Options. Rotation, numeric scaling and Option scaling use the chosen point. X and Y show its coordinates. The existing transform engine still prepares and applies the final matrix.

This works with the existing selection, pixel, mask, saved-channel, layer and Content-Aware Scale drafts. Moving the point or changing its visibility does not alter document bytes, add Undo, record an Action or request another preview. A Content-Aware Scale worker can finish after a reference-only change. Escape, focus or tool changes cancel a captured pivot drag, while owner/session/source checks prevent it restoring over later work. The scope cursor stays with the captured action for all 16 modifier combinations; Space before press retains Hand.

The API adds transform.reference and observable workspace state. It requires the current document revision plus a separate workspace UUID, preventing an old request from changing a newer transform. Ordinary editing commands remain blocked during the native transform. Typed commands total 250; native archive 86, Actions 49, settings 4, menu identities and shortcuts are unchanged. No Adobe route is invented for an operation outside the published contract.

The first attempt failed compilation because a cancellation call was placed before super.init. Its source, diagnostics and pre-existing outputs were retained before the call was moved to the tool-change lifecycle. The second attempt passed 123 of 125 tests, including every new method; two shared catalogue assertions still expected 249 commands. After preserving that run, only the two genuine count expectations were updated. The final run passes all 130 focused Debug tests in 41.571 seconds, including the additional affected layer-filter API checks. Production app bytes are identical between the last two attempts. Existing pixel fixtures and tolerances were not changed. The owned offscreen control capture shows the toggle and full locator grid; it is not a live Photoshop or performance test.

Transform Again still needs retained transform state across targets and commits. Remaining transform/crop functionality, exact Photoshop defaults, persistence, pixels and broader platform/performance checks are open. A03 classic adjustments follow in major stillneeded. [Detailed record](DEVLOG.md#dev-step-429).

## 2026-11-05 — Step 430: Large-document Equalize

The source audit found that the classic tone processors stopped at 8,388,608 pixels. Match Color's source-document/layer pickers and tone preset files were already present. Brightness/Contrast still needs a properly referenced modern transfer and native workflow; its menu was not connected to the licensed approximation. The selected capacity work is Equalize.

The histogram now counts paged and implicit samples without allocating a full image array. Edge-tile padding is excluded. The existing 256-bin CDF, depth quantization, selection blending and transform/storage rules are retained. Native controls, API and portable Actions share one prepared edit and Undo. Maximum 300,000 × 300,000 implicit rasters and sparse selections pass at every native depth. This does not prove dense maximum throughput or exact Photoshop bins and output.

The first run passed 23 of 26 tests. It exposed an unrelated Smart Filter size gate in the reused bounds helper. The failed source and outputs were retained before Equalize received its own equivalent ordinary-pixel bounds calculation. All 26 then passed, but profiling found that the selected-area preview composed a whole 11-megapixel image before reducing it. The preview path now reuses exact sparse composition where eligible and paged composition otherwise, then reduces a bounded overview. A later memory assertion caught identical pixels being materialized in a constant overview. That source was retained before an exact implicit constant path was added. Expected pixels and tolerances were not relaxed.

The final 30 focused tests pass, including eight new methods. They include analytical CDF bytes, the frozen pre-change array engine, six canonical display-byte comparisons, implicit-versus-stored HDR/alpha comparisons, maximum sparse capacity, native/API/Actions/archive/Undo and preview/cancellation/source guards. Both optimized architectures pass the same 127 selected cases, including all 38 new methods from checkpoints 426–430. The universal package passes minimum macOS 14, signature and ZIP checks. Current source and binary hashes are recorded. Earlier full-suite and Debug failures remain open.

The large dialog labels its overview and disables controls that would falsely imply full-resolution inspection. A full-resolution interactive dialog viewport is still needed; full-resolution output can be inspected in the document after Apply. Other large classic tone families, Brightness/Contrast, presets/interoperability and independent Photoshop fidelity remain A03 work. The API advertises per-kind limits and overview state; its existing operation and archive/menu/shortcut identities are unchanged. Adobe Equalize descriptor coverage is not claimed. Photoshop remains behind the locked Mac screen; no live check or physical refresh-rate result is invented.

I05 color lookup/export follows. No major package is declared complete and no minor or cleanup pass begins. The private source backup follows the standing request after this optimized batch. [Detailed record](DEVLOG.md#dev-step-430).

The [private source backup](https://github.com/ForensicIntelligence/Photato/commit/8400eb8e3bddc8bbbfeb9bd8e9e4e644d29daa39) contains the qualified source for this batch. The repository remains private until software release day. No app was installed, Xcode-archived, uploaded to the Store or released.

## 2026-11-05 — Step 431: Color Lookup output formats

The RGB adjustment-stack exporter now writes 3DL, CSP and ICC device-link files alongside CUBE. All selected formats use one bake through the existing compositor. CUBE and CSP retain extended floating values; the integer 3DL and ICC formats reject samples outside0–1. An ICC device link carries a transform between RGB values; it is not a document working profile.

The native dialog adds Copyright, base filename and four format checkboxes. Named FileDocument wrappers feed the native multiple-document exporter. The optional API adds individual format routes and ZIP output, with matching metadata, filename, date and format validation. Creation time defaults to request time and can be pinned for byte comparisons. Explicit cancellation, busy/source/revision checks and share revocation cover both preparation worker types. Exports leave the document and history untouched. Menu identities, shortcuts and the250 typed editing commands are unchanged. No unsupported Adobe endpoint or export descriptor is invented.

The first build failed in a test helper whose internal method accepted a private gate type. Its source, diagnostics and outputs were retained before only that method was marked private. The app binary is identical in both attempts. The repaired run passes all34 focused Debug tests in4.528seconds, including eight new methods and the affected existing LUT/PSD/API/archive tests. No old pixel fixture, expected value or tolerance was weakened. Offscreen inspection shows the metadata controls, all four choices and Export button. Owned named FileWrapper output was written and checked; this does not qualify live save-panel behavior.

Independent OpenColorIO2.4.2 reads the owned CUBE/CSP/3DL files. LittleCMS reads the ICC device link. Thirty vertices and interior samples reproduce the asymmetric test transform within bounds set before the checks. Apple ColorSync verifies the ICC without errors or warnings. The reader driver initially failed to discover the existing LittleCMS library from its isolated environment; that failure and script were retained before an observed absolute library path was supplied. No runtime dependency was added to the Swift app. The public ICC specification was available as web text, while direct PDF download returned403; the failed download was not retried or bypassed. Public OCIO source is retained as a format reference, not copied implementation.

Full256 grids/streaming, LAB/CMYK conversion, general CSP/ICC import, exact Photoshop presets/files/interpolation, live multi-file overwrite/error behavior and the rest of I05 remain open. Dark3DL tables are ambiguous to some readers that infer bit depth from their largest value; Photato's explicit metadata solves its own import only. B05 painting workflows follow within major stillneeded, thenC01. Current optimized universal/full-suite/physical qualification is unclaimed;430 remains the latest optimized/private-source batch. [Detailed record](DEVLOG.md#dev-step-431).

## 2026-11-05 — Step 432: Pattern Patch

The existing Patch tool had Source/Destination and adaptation controls, but lacked Use Pattern. Normal mode now offers a saved-pattern picker and button. Document resources take precedence over library resources with the same ID. The chosen resource is captured when preparation starts. It supplies texture to the Normal healing solver, rather than applying an ordinary Pattern Fill.

Only the selected solve window and transformed output are prepared and written. A small repair therefore works on the maximum300,000×300,000sparse canvas. The current solve/output limit is4megapixels; larger solves and the other retouch tools' capacity remain unfinished. The source image, selection representation, outside pixels, layer/mask geometry, metadata and protected alpha are retained. Cancel, changed documents/sessions and revoked API requests publish nothing. Successful native/API edits share one Undo. Existing menus, shortcuts, archive formats and250typed commands are unchanged; retouch.patch gains a strict patternID alternative to the original drag parameters. No unsupported Adobe action descriptor is invented.

The first build stopped on a new test that tried to mutate a read-only session property. After preserving that attempt, the test installed an immutable locked document instead. The second run passed38of39methods; its255new outside checks expected ideal0.5rather than storedRGB8gray128/255. Those checks now compare the exact unchanged before/after bits. A separate donor comparison then exposed a representation difference: legacy Normal Patch materializes rectangle coverage, while the new path preserves it compactly. The final comparison requires equal coverage and every other document field after normalizing only the legacy selection representation. All previous outputs and helpers were retained. A slow read-only text-diff diagnostic was stopped separately; no compiler/test was terminated. No old fixture or tolerance changed, and production app bytes are identical across all four Debug attempts.

The final run passes40focused tests, including nine new methods. They cover analytical texture/diffusion, soft coverage, transparency, HDR, outside bits, maximum sparse capacity, transformed layers, native/API/Undo/archive and cancellation/stale/revocation. The new donor comparison matches old Normal Patch pixels exactly across three depths and three diffusion settings. Those are existing-engine and analytical checks, not Photoshop output evidence. The offscreen swatch/name is visible; live button appearance remains unqualified.

The stable batch also includes431's Color Lookup formats. Both optimized architectures pass the same199selected tests, including all55new methods from426–432. All eight current normal LUT files match the independently checked431files. Universal macOS14slices, signature and ZIP extraction checks pass. A packaging helper initially corrupted a pinned resource-hash literal while replacing a test count; its original script/output were retained and the original oracle restored, without changing any resource or app bytes. No install, launch, Store action or software release occurred. After workers finished, a fresh Photoshop binding confirmed the Mac is still locked. The earlier unlock request remains pending.

C01is next, with Channels quick-save/direct-load identified for source/reference audit. Full B05, mask/channel and projected targets, larger solve regions, exact Photoshop behavior and all broader platform/performance acceptance stay open. The private source backup includes7,220qualified inputs and preserves1,061original root/Rust files; generated/cache/restricted inputs are excluded with provenance. No test fixture changed. [Source commit](https://github.com/ForensicIntelligence/Photato/commit/315a12121fd1fc8f323a242316d1a60ef21ade67). [Detailed record](DEVLOG.md#dev-step-432).

## 2026-11-05 — Step 433: Channels footer Save and Load

Footer Save used to open the Save Selection dialog every time. It now creates an automatically named alpha channel directly; Option-click retains the dialog. It does not change the selection, source image, current editing target or channel eyes. At channel capacity it reports the limit instead of silently replacing another channel. Footer Load now uses the selected source directly, including a saved channel other than the first, rather than opening a dialog or choosing the first ink target. Ambiguous partial multi-channel sets remain unavailable pending reference-driven handling.

Smart Filter masks are now selection sources in the native/API source lists. The implementation reuses the existing projected raw layer-mask sampler, including the filter mask's document transform and outside value. Display density, feathering and enabled state are kept separate. Existing source masks and layer metadata remain unchanged. The optional API keeps channel.edit and adds the strict smartFilterMask owner descriptor, source discovery and footer availability metadata. Native and API use the same prepared Core Save/Load commands. New-alpha UUIDs remain independent per request. Menus, shortcuts,250typed commands and archive/Actions versions are unchanged; no unsupported Adobe endpoint or action descriptor is invented.

The first build compiled the app but stopped on a new test fixture's access to an internal surface helper. Full source, diagnostics and outputs were retained before the fixture was rebuilt with public sparse Surface/SelectionMask APIs and the same2×2coverage. No production code, old fixture or tolerance changed; both app hashes are identical. The repaired run passes all58focused Debug tests in5.211seconds, including eight new methods. Known raw arrays test mask placement at all depths. Maximum sparse canvas tests check source memory and all-depth quick-save/archive/Undo. Other tests cover16Save modifier policies, options Cancel/capacity, selected targets/eyes, native/API material equality, strict descriptors and cancellation/stale/session/revocation guards. No live screenshot or physical UI check is claimed.

Full C01still needs other source/destination, thumbnail/drop, multi-target and paint/filter workflows wherever missing or unqualified. Exact Photoshop defaults/output/modifiers, earlier numerical/full-suite residuals and supported-platform/60fps qualification remain open. AUT01Actions/Batch follows in major stillneeded. Current optimized universal/private-source qualification remains at432and will be batched at the next meaningful milestone. [Detailed record](DEVLOG.md#dev-step-433).

## 2026-11-05 — Step 434: Batch file naming

Batch previously generated a numbered source name with a suffix. It now offers up to six ordered fields, including document names, text, numbers, letters, extensions and dates. The native panel has add/remove/reorder controls, a starting serial, compatibility flags and an example. Run captures the current configuration and sources. The optional API uses the same planner; clients that omit naming keep their existing output contract.

Adobe's public Batch guidance and the installed declarative scripting dictionary supplied the supported field inventory and bounds. Microsoft documentation supplied Windows filename restrictions. No proprietary implementation was examined. Exact Photoshop naming, sanitization and uncommon date/overflow/default behavior remain to be checked. The current implementation validates names instead of silently rewriting them, rejects a duplicate plan before processing and keeps the existing protected per-file publication. Completed files remain after cancellation or later errors.

The first run compiled successfully and passed 24 of 25 tests, but the six-field panel requested 787 points of height for a 620-point window. The failed source, diagnostics, outputs and screenshot were retained. An explicit viewport ideal height repaired that production behavior; the original assertion was kept. Source02 then passed all 25 tests. Source03 strengthened the new HTTP test with busy and revoked-save checks and passed the same 25 tests, including eight new methods. Its app binary is identical to Source02. Literal field vectors, date/timezone and number/letter boundaries, canonical collisions, unsafe names, symlinks, input bytes, cancellation/revocation, native binding/run snapshots and native/API output equality are covered. No old fixture or tolerance changed. The offscreen capture checks geometry; it does not qualify live scrolling, focus or control appearance.

All 104 original package scopes and 652 command identities remain. Full Actions/Batch is still open, including conditions, interactive dialogs, Open/Save overrides, other source/destination modes, subfolders/import/Bridge, ATN, droplets and Image Processor. G03 live shapes follows in major stillneeded, then G04. Latest optimized universal/private-source batch is 432; no new install, archive, App Store action or release occurred. [Detailed record](DEVLOG.md#dev-step-434).

## 2026-11-05 — Step 435: Create Rectangle and Ellipse

A click without dragging used to create a 1×1 rectangle or ellipse. It now opens a native dialog with Width, Height and From Center. Rectangles also have individual corner radii and a link control. Dragging keeps its existing behavior. The dialog captures the clicked point, output mode, target, operation and pattern resources. Cancel leaves the document and history unchanged. Apply uses the existing shape, path or pixel renderer and one prepared Undo; changed or closed sources are rejected.

The existing shape.edit API now accepts point placement, an optional center flag and shape combination. Strict request schemas and native draft state accompany it. Existing transform requests and default API names retain their behavior. Native and API output bytes and document material match in the tested workflows; independently created layer/path identifiers remain separate. No dedicated Adobe endpoint or proprietary action descriptor was invented. Public Adobe rectangle and ellipse instructions supplied the workflow reference; exact Photoshop defaults and output remain unqualified.

The first build found an initialization error in the new draft model. The next compiled the app but stopped on two new fixture declarations. Both attempts were retained before repair, with old cached test outputs distinguished from current binaries. The first runtime run then crashed in native pixel creation. A debugger captured a large Layer copy near the worker stack boundary. Splitting the new combination branch from ordinary creation let the full depth/mode test pass. A second crash occurred on the API pixel path; its debugger trace included the stack probe. Separating unrelated path/configuration Layer lookups from API creation repaired that selected path without changing Core/Imaging algorithms or removing validation.

All 28 initial selected cases then passed. A selector audit caught a misspelled cursor-test method, so the final run added the correctly named cursor matrix and an existing imported-shape HTTP path-edit case. All 30 cases pass, including eight new methods and 880 cursor rows. The final two source manifests and app binaries are identical. Tests cover known placements, all depths and output modes, linked radii, Cancel/Undo/Redo/archive, captured patterns, rotated combinations, native/API document material and exact PNG output, malformed/busy/stale requests and source/session/settings/lifecycle/cancellation guards. No old fixture, assertion or tolerance was weakened. The offscreen sheet image checks bounds; it does not qualify physical appearance or live gestures.

G04 Pen and Paths follows in major stillneeded, then T01. Other shape click dialogs, on-canvas widgets and the existing geometry/raster limits remain substantive G03 work. Earlier unrelated crashes, full-suite/numerical failures, exact Photoshop pixels/defaults and supported-platform/performance checks remain open. Latest optimized universal/private-source batch is 432; no new install, archive, App Store action or release occurred. [Detailed record](DEVLOG.md#dev-step-435).

## 2026-11-05 — Step 436: Fill Path options

The Paths context menu and Option-click on the Fill footer now open a native Fill Path dialog. It supports foreground, background, custom colour, black, gray, white and saved patterns, blend modes, opacity, Preserve Transparency, feather and anti-aliasing. Clear changes alpha while retaining hidden RGB values and cannot clear a Background layer. History is unavailable because a history source has not been implemented. Ordinary footer fill retains its previous behaviour while conflicting Adobe default instructions await verification.

The implementation reuses the existing Core paint engine. Captured path coverage multiplies the current selection without replacing selection metadata. Expanded layer storage, mask positions, patterns and protected alpha follow the existing fill rules. The optional path.paint fill request, exposed state and schemas use the same builder and transaction. Recorded Actions version 50 carries captured coverage and resources; older feature formats remain readable. No Adobe endpoint or proprietary descriptor was invented.

Testing caught a parser declaration error before linking the app. The next attempt passed 41 of 44 methods: a new test incorrectly required identical sparse storage layouts, and two older tests still expected the current Actions version to be 49. The RGB test now compares exact stored RGB words at corresponding coordinates. Version assertions were updated for 50 while retaining old format and pixel expectations. All 44 cases then passed. An optimized batch passed 338 of 340 cases on each architecture, with only two more stale current-version assertions failing. An audit found 16 remaining assertions of that kind; all were corrected. The original source archive confirms that these 18 one-line changes are the only changes to pre-existing tests or assets. Every failed source, log and output was retained before repair.

The final development run passes 60 cases, including all 10 new methods. Both optimized architectures pass the same 354 cases in the same order, including all 89 new methods from checkpoints 426–436. Tests cover literal coverage products, Clear RGB preservation at every depth, expanded masks and geometry, native/API document and PNG equality, options state, Undo/archive, Actions compatibility, Cancel, malformed requests and stale source/settings/session guards. Optimized app binaries are identical before and after the test-only version repairs. Universal macOS 14 minimum, signature and extracted ZIP checks pass. Intel tests ran under Rosetta on Apple Silicon; this does not qualify physical Intel or macOS 14.

The fresh native-app check after all workers finished again reported the Mac locked. Live UI, exact Photoshop output/defaults and 60 fps remain unqualified. Extended Fill currently has a 16 MP canvas and 100 px feather working limit. History and remaining Pen/Stroke/target workflows stay major stillneeded. T01 typography follows, then T04. All 104 original scopes and 652 tracked command identities are retained. No install, Xcode archive, App Store action or release occurred. [Detailed record](DEVLOG.md#dev-step-436).

The full-source backup is verified in the private repository. It includes 7,237 qualified inputs, the Xcode project and development records; 34 generated, cached or restricted inputs are excluded. All 1,061 root/Rust files are unchanged. No fixtures changed and no stale native files were removed. A final documentation-only commit follows the history and standalone diary refresh. [Source commit](https://github.com/ForensicIntelligence/Photato/commit/76527a7b791685b21fc9248ef6e50cfdb8c21a05) · [Backup record](SOURCE_PUBLICATION_436.json).

## 2026-11-06 — Step 437: Character and Paragraph panels, in development

Window > Character and Window > Paragraph now open separate tabs. Type > Panels has the matching commands. The panels use the existing dock, multiple columns, collapsed icons, floating stacks and saved-workspace system. Their controls reuse the text engine and Properties controls. Existing saved layouts are validated before migration to panel catalog 3; old placements, closed panels and floating frames are retained. New panels start hidden. Loading does not overwrite the old file.

The optional workspace.panels API can show or hide a panel and apply a complete validated layout. It has its own workspace revision and a native permission for changing the shared saved workspace, which resets off each API session. A failed write leaves memory, revision and disk unchanged. Panel changes add no image Undo or recorded Action. Existing text APIs and supported Adobe text jobs retain their contracts.

Testing found that replacing selected text with new attributes collapsed its selection. The native editor now restores the original range, including when paragraph formatting expands the edited paragraph. Character and Paragraph controls can also remain available during typing; document switching, other modal work and layout rearrangement retain their guards. A test using the actual native numeric field editor and Return confirms that changing size affects exactly the selected characters.

The first build linked the app but found two errors in the new test fixture. After those were repaired, 75 of 79 tests passed. Three older workspace tests assumed the previous default panel visibility; their setup and expected catalog were updated while retaining the full transfer and sizing checks. The new panel test also found a probe that looked for the wrong native accessibility property, the selection collapse, and a point-text alignment failure. Native field metadata corrected the probe. A manual callback without editing a native field did not prove numeric input, so the next test used the real field editor and retained the same expected values. Sources, logs and binaries from every attempt were kept before repair.

The latest run passes 79 of 80 tests, including nine of ten new methods, with five assertions failing in the original right-aligned point-text workflow. There are no unexpected errors or crashes. The diagnostic records a used width of 32,768 pixels and a padded width of 32,770 for ten characters. The existing dimension check rejects the result with a misleading 16 MP error. All 528 Core/Imaging source files are unchanged from checkpoint 436; this diagnostic is new evidence, not a rerun against an older binary. The desired right-alignment, commit and Undo assertions have not been removed, relaxed or replaced with an easier input.

T01 remains current. The next work is a coherent correction to point-text anchors, layout, rendering and the native editor, preserving existing left-point and paragraph behaviour and qualifying output independently. Full typography, detailed paragraph composition, dynamic panel menus and shortcuts, defaults, PSD fidelity and physical-platform checks remain open. T04 follows afterward. Four represented menu commands advance from pending to partial; none is complete. The repository remains private, and the latest stable source backup and universal qualification are still checkpoint 436. No new install, archive, upload or release occurred. [Detailed record](DEVLOG.md#dev-step-437).

The offscreen panel capture does not establish visual appearance: the final image chiefly shows the title. Native control metadata and the numeric input test provide separate functional evidence, but complete rendering and live panel appearance remain unverified. No cause for the incomplete capture is claimed.

The final expanded run passes 93 of 94 tests. It retains all original 80 cases and adds the 14 older methods whose current command-count assertions needed to change from 250 to 251. All 14 pass. The same point-text workflow still fails with five assertions; the app binary is unchanged from Source03 through Source06. No image fixture, pixel expectation or tolerance was changed.

A final review found that placing Character and Layers in one floating stack disabled the type controls during typing. The guard now applies separately to non-type content, leaving type tabs usable. The new regression first used the old host identifier after stacking; it now resolves the actual shared-stack identifier and checks both rows and the enabled native Size control. The final run, Source08, passes 94 of 95 tests, including ten of eleven new methods. The same point-text workflow remains the only failing method, with five assertions. Source07 and Source08 app binaries are identical. T01 stays active; this is not a stable qualification.

## 2026-11-06 — Step 438: Point-text alignment and native editing

The previous panel work exposed a long-standing point-text layout problem. Right-aligning ten characters produced a 32,770-pixel-wide raster and hit the 32,768-pixel dimension limit. Before changing the engine, we captured fifteen owned regression images and their metrics from the unchanged application. They cover ordinary left-point, paragraph and vertical text at each depth. They are references for prior Photato output, not Photoshop output.

The repair gives each non-left point-text line a common insertion coordinate in TextKit's positive layout space. Raster allocation uses the resulting glyph bounds, excluding newline control tails. Rendering, outlines, the native editor's crop and its layer placement use the same geometry. No capacity constant was raised, and no document format changed. Existing native/API text edits, supported Adobe text jobs and portable Actions retain their shared engine.

The first build found a new tuple-versus-point compile error. The next run passed 129 of 132 tests, with native caret checks exposing a second alignment offset applied by NSTextView. Removing that duplicate fixed ordinary horizontal and vertical carets and typing at an empty insertion point. A repeated-layout test then caught stale line bounds for rich paragraphs with a centred or right-aligned final line. The shared paragraph adjustment now updates those bounds along with glyph positions. It runs after a fresh layout with a reentrancy guard. Tests retain selected ranges, test real native caret/hit coordinates and verify commit, Cancel and Undo. All failed sources, logs and binaries were preserved before repair; the original desired alignment test was not weakened.

The final affected Debug run passes 132 of 133 tests, including all ten new point-layout methods and all eleven panel methods. Its three remaining assertions are the same imported-text source mismatch seen in the unchanged baseline. The same 468 optimized methods run on both architectures: Apple Silicon passes 467, and Rosetta passes 466. There are no unexpected errors or crashes. All selected native caret, typing, formatting, API and history workflows pass both.

The exact image checks found an additional architecture difference. Five 8-bit ordinary-text outputs differ under Rosetta: 225 to 344 pixels per case, with alpha differences up to one byte and straight RGB differences too. All ten 16/32-bit planes match exactly. The mismatch is larger than a one-ULP conversion residual. Its cause and whether it predates this repair have not been established by an old Intel binary rerun. The fixtures and exact assertions remain unchanged. Cross-architecture output fidelity stays open, and neither affected suite is described as completely green.

A separate validation app contains both architectures with a macOS 14 deployment target. Its signature, extracted ZIP and file hashes verify. It has not been installed or launched for a live check, archived in Xcode, uploaded to App Store Connect or released. These checks do not establish physical Intel/macOS 14 or Photoshop equivalence. The new readonly textGeometry API state reports the active/draft type's metrics, separate model and TextKit origins, and layout errors without adding a command or changing request schemas.

The selected Character/Paragraph and point-editing workflow is usable, so the major still-needed queue advances to T04. Source inspection and Adobe's public guide identify direct Type-tool creation on a path as a missing entry workflow; the shaped engine and existing dialog controls are already present. That candidate still needs its native hover/click/cursor behavior, draft lifecycle, shared API and tests. T01's remaining functional work, old centred-document placement, large-type limits, defaults, PSD and exact output remain open. No full package closes, and the seven-pass order is unchanged. [Detailed record](DEVLOG.md#dev-step-438) · [Point-text guide](POINT_TEXT_LAYOUT.md).

The full development source checkpoint is now verified in the private repository: 7,262 frozen inputs are included, 34 generated/cache/restricted inputs are excluded, and all 1,061 root/Rust files are unchanged. The seventeen new fixture files contain owned generated text data and provenance. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/211a318af342788a705334992f7adb28f05f90fc) · [Backup record](SOURCE_PUBLICATION_438.json).

## 2026-11-06 — Step 439: Type directly on a path

The Type tool could previously create ordinary point or box text, while path layouts were entered through a separate dialog for an existing layer. Even an existing curved layer used a straight text box for canvas editing. The native editor now creates a draft by clicking a selected connected path, and keeps typing, carets and selection on the curve. It copies the path and insertion fraction, preserving the saved path. Existing horizontal Path, Circle, Arch and Bow layers use the same editor.

Before editing the engine, we captured thirty-six owned render references from unchanged production code. They cover the four baseline layouts, fitting, reverse direction, offsets and each pixel depth. Shared preparation now supplies the same flattened baseline, CoreText line, fitting and alignment to rendering and editing geometry. Grapheme-safe UTF-16 positions keep combining marks and surrogate pairs together. The existing renderer's output stays pinned by exact word and metric comparisons; the fixtures contain generated test data, with no redistributed font or Adobe artwork.

The canvas editor retains NSTextView's rich text storage, marked input, local typing Undo and existing keyboard policy. It supplies curve caret/range drawing, hit testing and IME window coordinates, with layer and viewport transforms. Preview runs in a cancelled/generation-guarded worker. Detaching and reattaching restarts an interrupted preview, and cancelled work cannot commit a document. Straight-text insertion drawing is suppressed. The offscreen native canvas capture shows the complete curved text, selection and underline; it is not a live Photoshop or physical-device check.

A wavy insertion cursor indicates path entry. The press captures the source, document and tool; document/tool changes and a drag beyond the click threshold cancel it. All sixteen modifier combinations currently share the same path-entry dispatch and cursor. Unsupported vertical path typing shows an unavailable cursor. Exact Photoshop alternate behavior remains unobserved. The existing text.create/set/layout API uses the same model and renderer; readonly pathTypeEditing state adds selection, caret count, overset and preview/error information. No command, Adobe route, menu shortcut or serialized version was added.

The first build found a Swift concurrency error in mutable preview captures. Immutable snapshots repaired it. The next runs passed the new workflows and exact ordinary render comparisons. Source review then corrected preview reattachment and straight-caret behavior. An explicit tool-switch assertion found that an earlier insertion had matched the constructor instead of the actual tool-synchronization hook. The failed assertion was retained, and the production hook was repaired. Every attempt's inputs, logs and binaries were kept before repair; no exact fixture, old assertion or tolerance was relaxed.

The final Debug run passes 158 of 159 methods, including all ten new methods and the existing point/panel workflows. Its three remaining assertions match the older imported-text reference failure. The same 485 optimized methods pass 484 on Apple Silicon and 482 under Rosetta, with no unexpected errors or crashes. All six new native workflow methods pass both. Apple Silicon matches all thirty-six old path planes; Rosetta matches thirty-three. Thirteen alpha words in three Float32 planes differ by one ULP. Their RGB words and a separate 8-bit diagnostic match, but the original Float32 assertions still fail. The prior 8-bit point-text mismatch also remains. No old Intel baseline rerun or cause has been established. Neither suite is called completely green.

The isolated universal validation package verifies its macOS 14 target, both architectures, signature and extracted ZIP. It has not been installed, launched for a live test, archived in Xcode, uploaded to the store or released. The selected native path workflow is tested; full T04 is still open. Vertical/inside/warped inline editing, delimiters and flip/drag gestures, fully composited mask/opacity/effect appearance during typing, full fitting/composers/affinity, PSD and maximum capacity remain functional work. Exact defaults/output, platforms and performance remain unqualified. The next major item is Auto Color Correction Options for Curves; the current Curves UI lacks Auto/Options, while Levels provides some supporting foundation. [Detailed record](DEVLOG.md#dev-step-439) · [Path typing guide](DIRECT_PATH_TYPE.md).

The full source checkpoint is verified in the private repository: 7,307 frozen inputs included, 34 generated/cache/restricted inputs excluded, and all 1,061 root/Rust files unchanged. Thirty-eight new fixture/provenance files contain owned generated text data. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/1e138cfb64a0851c90396e198049836dfa6bec66) · [Backup record](SOURCE_PUBLICATION_439.json).


## 2026-11-06 — Step 440: Histograms for large sparse documents

The Curves and Levels histograms still visited every pixel. A document could use sparse storage successfully and then spend an impractical amount of time on statistics. The new traversal examines stored image and coverage tiles and counts the remaining cells in bulk. UInt64 bins retain exact counts at the 90-gigapixel logical limit. Tile padding is excluded, and the existing depth, alpha and selection rules are preserved.

Ordinary layers translated by whole cells are clipped to the canvas and selection. Their image and mask are cropped into the same sample grid using existing paged storage. Fractional and rotated affine layers retain the previous sampling path. Adjustment layers use the same paged histogram reader after their existing input composition. This change does not establish maximum-size capacity for every compositor or editing operation.

The optional tone.histogram API shares the native Curves/Levels request. It exposes three 256-bin channels and the sample, transparency, invalid and endpoint counters, with strict parameter/result schemas. It rejects invalid, stale, busy or unavailable sources. Successful queries do not change pixels, document revision or Undo history. No Adobe endpoint or document-format version was added.

Two new-fixture compile failures were preserved and repaired. A first runnable test attempt caught two stale catalogue counts and an incorrect expectation for the existing revoked-share response. The first optimized selector also named seven helper classes instead of their test classes. All 54actuallyselected methods passed, but that run failed qualification for missing intended tests. The corrected selector ran all 61methods on the same source and binaries; both architectures passed. All old fixture bytes and numerical assertions are unchanged. Fifteen existing test files only update their current API catalogue count from 251 to 252.

The final focused run passes 27 Debug tests, including eight new methods. The same 61optimized methods pass on Apple Silicon and under Rosetta; universal macOS 14 packaging, strict signature and ZIP extraction also verify. These are selected tests. Existing full-suite failures, cross-architecture text-output differences, Photoshop fidelity, physical-platform qualification and 60 fps remain open.

The original A01 Auto Options candidate needs further work, including independent Photoshop references and native point-sampling transactions. It is not marked complete. This checkpoint delivers its statistics dependency, records the remaining scope and moves the major still-needed sweep to A04, then A05. The seven-pass order and every original acceptance criterion remain in force.

The private source backup includes 7,310 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/097bf4ddf55224176fe85066d51d95600a1bd65a) · [Backup record](SOURCE_PUBLICATION_440.json).


## 2026-11-06 — Step 441: Pause Light while painting below

Light's Highlights and Shadows require neighborhood processing. Previously, that processing stayed in the live painting path. The editor now pauses the affected Light layers during native paint and retouch gestures and restores them at release or Cancel. Exposure, Contrast, Whites and Blacks remain live when no neighborhood controls are used. A passive notice in the document tabs and Properties explains the temporary appearance; the API exposes the same state.

The pause belongs to display snapshots. Stroke sampling and prepared edits keep the original document and full Light parameters. The structural plan follows visible layer order, isolated/pass-through groups and clipping boundaries. No command, shortcut, cursor, preference or document-format version was added.

The first projection hid the Light layer. A new regression showed why that was wrong: it also hid layers clipped to Light. The repair substitutes identity Light settings and Normal blending while preserving visibility and clipping topology. An independent red-clip assertion retains the base's exact alpha. Final brush and retouch results still match the full original commands, with their usual Undo and Cancel behavior.

A fixture compilation failure and two incorrect fixture assumptions were preserved before repair: API revisions already include view renders, and a no-op mask stroke creates no Undo entry. The final run passes 43 Debug tests and the same 43 optimized methods on each architecture, including all nine new methods. Existing tests, fixtures, Core adjustment math and the Adobe API contract are unchanged. Universal macOS 14 packaging, signature and ZIP extraction also verify.

This closes a selected A04 painting workflow, not the whole package. Modern PSD/PSB descriptors, actual Light version switching, larger neighborhood processing, other editing contexts and independent Photoshop/platform/performance qualification remain open. The major still-needed sweep moves to A05, then A07; no minor or cleanup pass has begun.

The private source backup includes 7,314 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added; existing tests and Core math are unchanged. A final documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/350101b8245a25386a9add2f5a25b2721196eb16) · [Backup record](SOURCE_PUBLICATION_441.json).


## 2026-11-06 — Step 442: Gradient creation and recorded Actions

The Gradient tool previously applied several Options settings to the selected fill. Adobe’s current guide says these controls configure new gradients. Options and toolbar preset selection now keep creation defaults separate; canvas and Properties controls continue to edit existing fills. Delayed presets, drags and colour-stop changes reject a replaced document or tool context.

Three optional API commands configure the defaults, create a live Gradient Fill, or paint a captured Classic Gradient. They use the same native factories and prepared history. Tool configuration changes only session defaults and the view revision. Creation and painting use their usual Undo transactions. Tests compare native and HTTP documents and saved bytes across RGB8/16/32, five gradient shapes and pixel/mask targets.

A new recording test found that creation and painting still produced unsupported Action entries. Portable recipes now preserve their settings and layer references without saving document UUIDs or raster snapshots. Actions format 51 gates the new operations; older operations keep their minimum versions. Custom creation templates containing unsupported metadata still reject instead of silently losing it.

The selected Debug run passes 69 tests, including eleven new methods and older Actions workflows. Both architectures run the same 99 optimized methods: 99 pass on Apple Silicon and 98 under Rosetta. The first optimized run also caught an old catalogue assertion fixed at 251; it now checks the current 255 commands. The remaining Intel Rust interpolation assertion reports 15,580 of 15,633 exact samples and reproduces exactly in the preserved checkpoint 441 bundle. It remains selected, with its original expectation and fixture. No numerical cause or Photoshop equivalence is claimed.

The rendering math and old image fixtures are unchanged. Older tests changed only for current API/Actions counts or to request existing-fill edits explicitly while keeping their numeric assertions. Universal macOS 14 packaging, signature and ZIP extraction verify. The Mac remains locked for live reference checks; no live pass, install, archive or store release is claimed.

This completes the selected creation, painting, API and recording paths. The full gradient package remains open, including canvas opacity, preset/noise/GRD cases, remaining transforms, numerical/default fidelity, platform and performance checks. Work moves to A07 under the seven-pass order; no minor or cleanup pass has begun.

The private source checkpoint includes 7,319 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/4f7c736d74f1bf276e1fc5674dee2b2ec4f53c7e) · [Receipt](SOURCE_PUBLICATION_442.json).


## 2026-11-06 — Step 443: Pattern groups and PAT folders

The Patterns panel previously stored a flat list. Its PAT reader recognized folder metadata but discarded the grouping. The native library now keeps a flat node graph with parent links, and the panel shows groups with preset grids. Shift selects ranges, Command toggles selection, and private native dragging moves groups or presets with insertion feedback. Duplication creates independent resources; renamed or deleted presets do not alter resources already captured in documents.

PAT import and export retain nested and empty groups and repeated preset occurrences. Existing pixel records and compression are unchanged. Native user-library format 2 stores the hierarchy; format 1 loads without rewriting the original file. Selection and disclosure changes stay in memory until the next persisted mutation. Candidate data is prepared in a worker, authorized before atomic replacement and then published to matching memory.

The optional pattern.library API shares native selection, organization, import/export and Define Pattern. It publishes operation-specific schemas and shared library revisions. Initial document revisions still reject stale requests. Accepted work checks document/session/library/lifecycle, token and sharing at completion, allowing harmless display redraws while rejecting real document changes or revoked sharing.

Early constructor and actor-type compilation errors, followed by two test-fixture errors, were retained before repair. An offscreen panel test initially over-released its AppKit window. An own-binary NSZombie diagnostic identified release after deallocation; the fixture now keeps Swift ownership through normal teardown and retains its original view check. Product code was unchanged for that test repair.

Optimized tests then exposed valid HTTP library edits returning 409. A paused real import proved that a view redraw alone could invalidate accepted work. Removing that extra view comparison fixed the controlled Debug case, but did not finish optimized qualification. An explicit short-lived request lease now holds accepted inputs and checks each relevant server-side predicate separately. The final optimized runs pass on both architectures. No compiler or ARC root cause is asserted, and all failed attempts remain recorded.

The final result is 54 Debug tests and 71 identical ordered optimized methods per architecture passing, including all seventeen new methods. Existing image kernels, PAT pixel writer, version 1 encoder, image fixtures and numeric expectations remain unchanged. Older tests changed only for catalogue counts, optional library injection and the intended retained-folder behavior. The actual SwiftUI panel was rendered offscreen; live Photoshop and physical-platform checks remain pending.

This completes the selected pattern-library organization and transport workflows. History Fill still needs a shared source/snapshot mechanism. Scripted Fill, remaining application/drop semantics, arbitrary PAT metadata, capacity and exact Photoshop defaults/output remain open. Work continues with F01 under the seven-pass order; no minor or cleanup pass has begun.

The private source checkpoint includes 7,319 frozen inputs, excludes 34 generated/cache/restricted inputs and preserves all 1,061 root/Rust files. No new image fixtures were added. A documentation-only backup follows the history and standalone diary checks. [Source checkpoint](https://github.com/ForensicIntelligence/Photato/commit/0f4c25b920f135ebb2fc637965e5b0a08fea73b8) · [Receipt](SOURCE_PUBLICATION_443.json).

## 2026-11-06 — Step 444: Public repository and filter development

The maintainer asked to make GitHub public now. We changed the existing [ForensicIntelligence/Photato](https://github.com/ForensicIntelligence/Photato) repository from private to public and checked GitHub’s returned visibility and access without signing in. This exposes the existing repository and its history. No app binary, App Store release or live website deployment accompanied the change. Current source-availability wording is updated; earlier private-backup entries remain as dated history. [Visibility evidence](REPOSITORY_VISIBILITY_444.json).

Before that request, work began on F01’s missing custom Shape Blur kernels. Native preset snapshots, the chooser, shared vector geometry, archive87/Actions52 and optional API schemas are implemented locally. The first attempt failed to compile a new HTTP fixture; the second passed40of43methods with seven new-test assertions failing. After correcting stored-alpha, linearRGB and generated-ID expectations in the new fixtures, Source03 passes42of43methods. The independent convolution oracle still fails at all three depths. No expected byte output or tolerance was relaxed. This feature remains in development; the public source checkpoint remains443 until a qualified source delivery. [Development evidence](CUSTOM_SHAPE_BLUR_444.json).

A correction to step443’s narrative: its publication includes7,327frozen inputs, not7,319. The original curation receipt and source manifest already record7,327; the narrative number was a transcription error. Historical receipt data is unchanged.

F01 remains current, followed byF02. All major, minor and final scope is retained.

## 2026-11-06 — Step 445: Public repository credential audit

At the maintainer’s request, checked the newly public [GitHub repository](https://github.com/ForensicIntelligence/Photato) for secrets. A fresh public mirror contains 69 commits and 10,680 unique historical file versions, totaling about 2.63 GB. Full history, every unique file version and commit metadata were scanned with Gitleaks 8.30.1. Its download was checked against the official release checksum. A separate byte scan checked provider-key formats, private keys, literal passwords and credential URLs; historical filenames were checked for credential files.

No exposed real credentials were found. Every scanner candidate was reviewed. The history findings include 145 SHA256 digests that match actual committed file bytes; the remaining matches are prose, JSON property names and a TIFF metadata enum. The separate scan found only test inputs: passwords for owned encrypted-PDF fixtures, deliberately wrong passwords and synthetic credential URLs used in rejection tests. Fixture provenance explicitly documents the test-only password. No credential was sent to a service for validation.

GitHub secret scanning and push protection were disabled and are now enabled. GitHub currently reports zero alerts; completion of its initial background scan is not inferred. Generic/non-provider scanning remains disabled on GitHub, so the independent scans also covered generic patterns. No public releases or Actions artifacts were present. The five existing prerelease drafts remain unpublished. Raw candidate values stay private, outside the repository. [Audit report](SECRET_AUDIT.md) · [Evidence](SECRET_AUDIT_445.json).

This changed no app code, tests, API, menu, shortcut or cursor. No new build, source upload, history rewrite or software release was needed. Custom Shape Blur resumes from checkpoint 444’s retained numerical failure; F01 remains current, then F02.

<a id="dev-step-446"></a>

## 2026-11-06 — Step 446: Custom Shape Blur reference and native validation

The first custom-kernel comparison assumed a binary shape mask. An owned Photoshop triangle and impulse image showed that assumption was wrong: edge cells receive fractional coverage, the footprint spans 2r+1 pixels, and convolution preserves the kernel’s orientation around an impulse. We saved 8-bit PNG and uncompressed 32-bit PSD outputs through Photoshop’s normal interface, checked the public PSD records, and retained the raw planes and provenance. No Adobe artwork or proprietary implementation was copied.

The Swift custom path now uses antialiased coverage and weighted convolution. Original built-in kernel arithmetic and previous fixtures are unchanged. An independent square/direct-sum check passes at all three depths. Two new exact Photoshop byte tests remain red: one coverage rounding difference changes 3 bytes in the owned RGB8 output and 435 bytes in RGB32. We retained the incorrect earlier model with its frozen source, replaced that new expected model with observed references, and kept exact assertions without increasing tolerances or patching an individual sample.

The original selector also expected 55 methods, rather than the 43 reported outcomes. Its process stopped after 43 with signal 10; earlier entries incorrectly omitted that failure. The same Adobe-job Debug method fails in preserved 443 and 446 binaries. We excluded only that reproduced method from focused Debug and kept it in normal optimized qualification, where it passes on both architectures. Debug executes 56 methods, with 54 passing; optimized builds execute the same 57 methods each, with 55 passing. The two strict Photoshop tests account for the failures. All nine new functional methods pass. Frozen inputs, 10,760 normal products, logs and failed attempts are retained. A postrun evidence-script syntax error and subsequent missing-proof rejection were repaired without rebuilding the app.

Both architectures package into a universal app with macOS 14 deployment metadata. Signature and extracted ZIP checks pass. The first isolated validation signature omitted user-selected file access; AppKit’s error log identified it, and the project’s existing App Store entitlement already provided the correct permission. A second validation signature used that permission with the same compiled code and resources. In the running app we opened our PNG, defined an owned shape, chose it in Shape Blur, checked local Undo/Redo, committed, and checked document Undo/Redo. The file stayed unchanged; the app was quit normally. Early native path/popup observations lagged actual state, so failed attempts and the automation reset are recorded separately rather than counted as passes.

F01’s remaining functions and exact output/default/platform/performance requirements remain open. Under the breadth order, F02 is next: Photoshop ACF Custom Kernel preset Load/Save, shared API conversion and retained JSON compatibility. Source inspection confirms the current controls are JSON-only; implementation has not started. All 104 original scopes and 652 command identities remain. No source upload, app installation, App Store change or software release accompanied this checkpoint. [Evidence](CUSTOM_SHAPE_BLUR_446.json).

<a id="dev-step-447"></a>

## 2026-11-06 — Step 447: Custom Filter ACF presets

Custom Filter previously loaded and saved JSON only. It now supports Photoshop ACF files through the native Load/Save dialogs and optional API. We created an asymmetric preset in Photoshop with distinct values, including negative weights, and checked the file against the public format description. It contains 27 signed big-endian values: 25 kernel weights, Scale and Offset, in 54 bytes. No Adobe preset or implementation code was copied.

The shared Swift codec rejects malformed lengths and out-of-range values. JSON remains available for existing presets and fractional Scale/Offset settings. ACF cannot represent those fractions, so Save selects JSON and disables ACF instead of rounding. The new `filter.custom.preset` API converts bounded base64 data or settings using the same codec. It returns the existing filter recipe without editing a document or history; `filter.apply` remains the editing path. Schemas, capabilities and error checks were added. The typed catalogue has 257 commands; native format 87 and portable Actions 52 are unchanged.

Six preserved build attempts record the problems encountered. The first used an unavailable Save-panel property and failed compilation. The next two runs passed all new tests but found old catalogue counts; one rerun was unnecessary because its repair preparation failed before making a change. The corrected tests passed, but the actual native dialog exposed a doubled filename extension. Giving AppKit an extension-free name fixed that. Actual sandbox Save then failed despite passing ordinary unit writes. The small preset publisher now coordinates an atomic write to the selected file, using the existing production entitlement. The generic streaming writer and pixel math were left unchanged. Other native export paths require their own file-access audit; this does not claim they are all broken or repaired.

The final source passed all 36 selected Debug tests, including 13 new tests, with no unexpected failures, signals, skips or missing cases. The app built in 43.33 seconds and tests ran in 8.479 seconds. We retained 7,378 frozen inputs and 5,384 Debug products. Changes to 20 old test files were confined to current command counts and one owned test window's lifetime flag; numerical assertions and old fixtures remain unchanged.

In the actual sandboxed app, Load showed all 27 values correctly. Local Undo/Redo, ACF and JSON Save, filter commit, document Undo/Redo and normal Quit passed. Photoshop then loaded Photato's ACF and saved it again: the original, Photato export and Photoshop reexport are byte-identical. The original image stayed unchanged. These checks cover the selected preset workflow on this Apple Silicon host; no optimized, Intel, universal or full-suite checkpoint 447 result is claimed. Checkpoint 446 remains the latest optimized universal qualification, with its two strict Shape Blur failures still open.

F02's remaining catalogue, capacity, depth, descriptor and exact-output requirements remain open. The breadth queue moves to F03 Blur Gallery, then F04. We also rechecked the unchanged public repository and private audit evidence: no exposed real credentials were found, GitHub reports zero alerts, and secret scanning and push protection remain enabled. No source upload or software release was made. [Preset evidence](CUSTOM_KERNEL_PRESETS_447.json) · [Credential recheck](SECRET_AUDIT_447_RECHECK.json).

<a id="dev-step-448"></a>

## 2026-11-06 — Step 448: Save Blur Gallery masks

Photoshop's Blur Gallery can save a blur mask to the Channels panel. Photato had a mask preview but no reusable channel output. An owned five-pixel Field Blur reference also showed that our preview scaled coverage incorrectly: Photoshop saves full white for a uniform positive field. We added Save Mask to Channels and made preview and saved output share one calculation. Photoshop also confirmed the second channel name, Blur Mask 2. An Iris mask was captured for further comparison; its geometry and exact values are not yet qualified.

The filter and channel are prepared on a private document copy and commit together. Existing channels and selection survive. Cancel, invalid inputs, protection, channel limits, cancellation and revoked API access leave neither half applied. Smart Filter re-editing uses the input before the edited filter. Large empty canvases retain sparse storage; the current source and transformed mask processing bounds are 8,388,608 pixels, so full dense maximum-size support remains unfinished.

The native checkbox starts off. The optional `filter.blurGallery.apply` command offers the same output flag and Smart Filter re-editing, with schemas, availability and workspace state. Portable output Actions use format 53 and resolve layer targets and filter indexes at playback. Native document format 87 and ordinary filter recipes remain unchanged. No new Adobe endpoint or action descriptor was invented.

The first build failed because the new command was missing from an exhaustive routing guard. The next build passed ten methods, failed an exact constant-normalization assertion, then crashed in the new HTTP Smart Object test. We retained both runs. Debugging our own frozen test binary showed a worker stack exhausted beneath a redundant nested command transaction. Keeping one outer transaction and calling the same modular pixel/channel engines directly repaired the selected case. Uniform Field coverage now has an exact constant proof; the assertion was kept. This does not identify or repair earlier unrelated crashes.

The final source passed all 31 selected Debug methods, including 11 new ones. Optimized builds ran the same 57 methods each, covering 24 new methods across checkpoints 447–448; all passed on Apple Silicon and Rosetta. We retained 7,383 frozen inputs and 10,772 optimized products. Old filter math, settings, imaging code, fixtures and numerical assertions are unchanged. Changes to 37 old test files only update current command and maximum Actions counts.

Both architectures package with macOS 14 deployment metadata. Signatures and extracted ZIP contents verify. In the actual sandboxed app we set Field Blur to five pixels, checked the white mask preview, enabled Save Mask to Channels and committed. One Undo removed both the edit and mask; Redo restored them. Reopening started with the output option off, and Cancel after enabling it created no extra channel. Final Undo restored the owned image, and the app quit normally without modifying the original file.

Full F03 remains open: endpoint controls, Selection Bleed, Focus, High Quality, larger processing, editable Photoshop descriptors and remaining output-recipe behavior still need work. Nonuniform, combined, selection and transformed masks need independent comparisons, as do defaults and pixel outputs. Physical Intel/macOS14, full regression and 60fps remain unqualified. The next work is the authorized source/build backup of this qualified checkpoint, then Liquify and lens workspaces. No software release was published. [Evidence](BLUR_GALLERY_MASK_448.json).

<a id="dev-step-449"></a>

## 2026-11-06 — Step 449: source and unpublished build backup

The qualified build 448 source is on public GitHub, including the Xcode project, tests and development records. Every one of the 7,349 included frozen inputs matches the tested snapshot. Thirty-four generated/model/cache/restricted inputs are explicitly excluded, and all 1,057 original Rust files are unchanged. Existing Git history is preserved. A documentation-only follow-up records delivery verification.

The universal app uses the retained optimized Apple Silicon and Intel binaries, production bundle identifier and unchanged sandbox entitlements. It includes the verified optional model with its Apache license, credit and conversion notice. This package was not launched in the production container. It is ad-hoc signed and not notarized. No application code or tests changed during this backup.

All four draft files were uploaded, downloaded and compared by hash. The downloaded app signature and all 18 packaged file contents match. The five earlier drafts are unchanged. This remains an unpublished alpha backup; software releases require manual approval and Photato remains completely free.

Before upload, full source/build scans and an independent byte/name scan found no exposed real credentials. Every scanner finding was reviewed as a verified digest, existing prose/key or intentional test input. Raw candidates stay private. GitHub secret scanning and push protection remain enabled, with no alerts at recheck. This is evidence for the pinned revision and assets, rather than a guarantee for future changes.

The readable diary's index had stopped at 426 although later entries existed. Its missing 427–449 rows now come from the recorded milestone dates/titles. The standalone diary and website mirror are regenerated from these records.

The software remains 448: 31 focused Debug and 57 identical ordered optimized methods per architecture passed, including 24 new across 447–448. Earlier numerical and wider-suite failures remain open, as do all 104 full scopes. Next is F04 Liquify, then F05. No new API operation, Adobe route, menu, shortcut or modifier cursor was introduced. [Source](https://github.com/ForensicIntelligence/Photato/commit/77b14d5eedf88f5b70dab96b9d8140d1fbc121c3) · [Delivery record](SOURCE_PUBLICATION_449.json).

<a id="dev-step-450"></a>

## 2026-11-06 — Step450: Liquify last mesh reuse

Liquify already had its main brushes, freeze/thaw and face sliders. It lacked a separate last-mesh path: applying another filter replaced Last Filter, leaving no quick way back to the previous Liquify program. Load Last Mesh now copies the last committed program into a new draft, with local history and Cancel. OK uses the same undoable document edit as before.

The default app retains one program across launches. Writes run in order, replace files atomically and finish before normal Quit. An unreadable file is preserved; a write failure keeps the current mesh usable for the session and reports the problem. A later successful edit can retry saving. Closing the source document preserves the shared cache and detaches a separate memory snapshot. Source image pixels are not stored in it.

The optional API exposes the program and any persistence warning through filterRecall state. Clients apply the reported settings with the existing filter.apply operation. State schema, discovery and revisions include the cache. There is no new command, Adobe route or document/Actions format. Existing zero/current-target coordinate semantics are preserved. Photoshop mesh files and exact last-mesh size, freeze, face and persistence behavior still need comparison.

The first build found two catch-block property assignments that needed self.error. After that repair, 32 of 33 methods passed. The failing new Smart Filter fixture used the layer ID from before conversion; conversion creates a new target. We corrected that fixture and strengthened the HTTP test to retrieve the reported program through the actual document-state route before applying it. All 33 methods then passed, including all eleven new tests. Failed attempts and 5,386 Debug products are retained. Old Core/Imaging math, fixtures and tests are unchanged.

An isolated arm64 Debug app has verified signing, macOS 14 metadata and unchanged sandbox entitlements. Its unsigned executable payload matches the tested binary. It has not been launched or installed. Light/Dark offscreen captures show the loading state; they do not qualify ready-state controls, live interaction or VoiceOver. The Mac unlock request is still pending. Optimized universal qualification remains build 448.

This selected workflow is implemented and tested in Debug; full F04 and earlier numerical/full-suite failures remain open. Work moves to F05, then F06 under the existing seven-pass order. No source push, App Store change or software release occurred. [Evidence](LIQUIFY_LAST_MESH_450.json).

<a id="dev-step-451"></a>

## 2026-11-06 — Step451: Local build cleanup; lens-default audit

The local build history had grown to roughly 400 GB. At the maintainer's request, we removed 1,252 superseded product paths: old compiled app and test bundles, packaged ZIPs, validation staging directories, nineteen numbered installed previews and the older Xcode archive. Measured available space increased by approximately 277.1 GB, reaching 312.5 GB after verification.

The current Debug 450 and optimized universal 448 builds remain, along with the current production package, both working compiler caches, the installed default and Verified apps, the latest installed preview and Xcode archive 332. All 16,311 protected files and 7,385 current source/build inputs match their saved hashes. Strict signature checks pass for the current development and packaged apps. The Xcode project and source backups are intact.

Original source snapshots, test fixtures, reference artwork, build manifests and test/crash logs were kept. Old copies of fixtures inside retired compiled test bundles were removed with those builds. Earlier entries that say a binary was retained describe its status at that checkpoint; this cleanup deliberately removes those superseded payloads. Their manifests and test results remain as historical evidence, rather than as a promise that every old binary can still be run locally.

No GitHub commands were run. No repository content, release, tag or uploaded asset was removed. There was no source push, App Store change or software release, and this cleanup did not alter application code or API behavior.

Before the cleanup request, we audited camera-linked Lens Correction defaults. Existing manual controls and settings-file import/export already work. Saved defaults matched by camera, lens, focal length and aperture, plus Previous Conversion, are the selected next work. That implementation has not started. F05 remains current, followed by F06; no feature package was closed by this housekeeping step. [Evidence](LOCAL_BUILD_CLEANUP_451.json).

<a id="dev-step-452"></a>

## 2026-11-06 — Step 452: Camera and lens defaults

Lens Correction had manual controls and settings files, but no defaults tied to the image's capture metadata. It now reads the camera make/model, lens model, focal length and aperture from supported EXIF/XMP data. Users can save a correction for an exact match. New drafts load it automatically; the Settings menu can recall Lens Default, Previous Conversion or Default Correction with local Undo/Redo.

Defaults belong to application preferences, separate from image edits. Set and Remove do not make the document dirty. Cancel leaves an explicitly saved default intact, while Previous Conversion changes only after a successful correction. Existing Smart Filters, Actions and Last Filter retain their explicit settings. Saved records are bounded atomic files. Corrupt files are preserved, removal retires them, and a write failure reports a warning while retaining usable settings.

The optional API adds filter.lens.defaults with the existing preference-change permission and request guards. It reports identity, settings, availability and warnings, and uses filter.apply for actual editing. There are now 259 typed commands; document version 87 and Actions version 53 are unchanged. No Adobe route or unsupported Lens Correction descriptor was added.

The first new test build failed because a helper needed explicit actor isolation. After that test-only repair, all 32 methods passed. Native same-session controls also worked, but checking the saved directory found that settings were not reaching disk. Actual executable startup used a designated initializer and omitted both persistent filter libraries. The earlier last-mesh convenience-initializer tests did not exercise that path. We corrected actual startup to use a shared tested factory and added a test for normal and isolated launches. The earlier application-persistence claim was too broad; its original tests and failed native attempt remain recorded.

All 33 focused Debug tests then passed, including 13 new tests and eleven last-mesh regressions. The same 33 pass in optimized Apple Silicon and Intel builds, with Intel tested under Rosetta. Native sandboxed testing verifies saving a default, Cancel, normal quit/relaunch, automatic restoration, committed Previous Conversion and document Undo. A fresh optimized native launch restores both records saved in the preceding Debug session. The original owned TIFF is unchanged. Universal deployment metadata, unchanged sandbox entitlements, signing and exact ZIP extraction verify.

These checks do not establish full Photoshop parity. Manufacturer calibration profiles, exact saved-field and matching policy, session behavior, preset transport, numerical output, wider metadata and physical-platform tests remain open. Photoshop's normal interface recognized the owned camera, focal length and aperture, but Custom/Settings behavior was not fully qualified. No proprietary implementation or stock artwork was copied. Filter Gallery is next, followed by Brush Settings. No installation, source push, App Store change or software release occurred. [Evidence](LENS_DEFAULTS_452.json).

<a id="dev-step-453"></a>

## 2026-11-06 — Step 453: Custom Filter Gallery textures

Filter Gallery already had 47 effects, an editable stack, visibility and ordering controls. It lacked custom texture loading. Rough Pastels, Underpainting, Glass, Conté Crayon and Texturizer now accept a merged PSD or PSB height texture through a native file picker. Loading runs away from the main thread and can be cancelled. An old or closed draft cannot receive a late result. A load error preserves the previous usable settings and preview.

The loaded texture becomes a bounded embedded height plane. Choosing a built-in texture removes the custom override. Local Undo/Redo includes that choice. Committing uses the existing editing engine, document history and Smart Filters. Native archive version 88 and Actions version 54 retain the samples; ordinary Gallery edits keep their older minimum versions. The optional API adds a read-only filter.gallery.texture conversion command and uses filter.apply for the edit. There are 260 typed commands. Existing Adobe routes are unchanged, and unsupported Gallery action descriptors remain explicit.

The first new test build failed because it called a sharing helper that does not exist. The next run found a missed archive-output version guard and an HTTP test that had not enabled document transfer. Both attempts were preserved before repair. All 34 focused methods then passed, including sixteen new tests for sampling, PSD/PSB decoding, history, persistence, cancellation, stale requests, HTTP guards and large payloads. Adding output captures did not change the application binary. The same 34 methods pass in optimized Apple Silicon and Intel builds, with Intel tested under Rosetta. Ten of fifteen effect/depth output buffers match byte-for-byte between those optimized builds. Five Float32 buffers differ in 55 color values by one floating-point step, with identical alpha. The strict comparison remains failed and its cause has not been isolated; the original comparison and all captured data are retained for numerical cleanup.

Actual sandboxed native testing loads PSD and PSB textures, checks local history, commits a Smart Filter, uses document Undo/Redo and saves a Photato file. A fresh optimized launch reopens that file with its embedded PSB texture and settings intact. Cancel leaves the saved file unchanged. The universal package has both macOS 14 deployment targets, the production sandbox entitlements, a valid ad-hoc signature and identical contents after ZIP extraction. An initial Debug packaging comparison found one signing-allocation metadata difference in LINKEDIT; the record preserves that exception and does not claim whole unsigned binaries are identical. Two incorrect independent archive-parser assumptions were also retained and corrected without changing the saved file.

The current height conversion and sampling describe Photato's implementation. Photoshop's normal Filter Gallery interface was inspected, but the custom texture probe could not complete and produced no independent pixel oracle. Exact conversion, alpha/profile behavior, light and tiling defaults, output fidelity, the rest of Filter Gallery and broader platform/performance tests remain open. No proprietary Photoshop code or artwork was used. Brush Settings is next, then B02. The maintainer's plug-in question was answered separately: Photoshop plug-in hosting is not implemented, and Firefly API compatibility does not supply it. No installation, source push, App Store change or software release occurred. [Evidence](GALLERY_TEXTURES_453.json).

<a id="dev-step-454"></a>

## 2026-11-06 — Step 454: Brush pattern textures

The brush engine already supported bitmap textures, and imported brushes could contain them. The Brush Settings panel could only choose generated textures. It now has a Choose Pattern menu that follows the saved Patterns library and its groups. Choosing a pattern enables Texture and keeps the other settings. Generated patterns remain available. Preparing a texture runs in a cancellable worker, with an enabled Cancel button while other controls are disabled.

The brush stores its own height samples. Changing or deleting a library pattern does not alter a saved brush, a started stroke or a recorded Action. The implementation shares the existing ABR texture conversion and preserves the brush rendering algorithms. Textures retain the existing 2500-pixel limit per axis; oversized patterns are rejected without resizing. Document pixels and Undo history do not change until painting begins.

The optional API adds texturePatternID to brush.configure. Its existing brush patch is still required and may be empty. The complete patch and prepared texture publish together, after cancellation, document, brush, library and sharing checks. The API reports loading state and documents the conversion and limits. Command count 260, native archive version 88 and Actions version 54 are unchanged. No Adobe endpoint or unsupported brush descriptor was added.

The first build failed because a trailing closure bound to the preparation parameter instead of authorization. After making that argument explicit, the application compiled. New tests then needed the actual initializer argument order and a private helper declaration. The first complete run passed 38 of 40 tests. Two new API tests had mismatched initial brush centers, expected a changed revision for a repeated no-op, and read the command schema at the wrong level. Those setups were corrected while retaining full brush and pixel comparisons. An explicit no-op revision check was added. The application binary is identical across the last three attempts.

All 40 selected Debug methods now pass, including ten new tests. They cover literal color/alpha/depth conversion, the prior ABR formula, cancellation, dimensions, preset locks, JSON/ABR/disk persistence, captured painting and Actions, native/API pixel equality, busy and stale requests, and revocation during preparation. Existing brush, ABR and all-tool modifier cursor tests also pass. Actual native testing selects Diagonal Lines, shows its embedded 8 × 8 texture and a ready preview, paints a textured stroke and verifies document Undo/Redo before restoring the disposable document and quitting normally. Deployment metadata, production sandbox entitlements, signing and unsigned payload identity verify for the isolated Debug app.

This is a selected workflow delivery, not full Brush Settings parity. Normal optimized qualification is deferred under the breadth policy; universal build 453 remains the latest. Offscreen Light/Dark captures have incomplete controls and do not qualify appearance. Photoshop's normal Brush Settings probe did not expand the panel, so no independent texture pixel reference was obtained. Exact conversion, defaults, positioning, physical bristles, complete ABR/input behavior, platform/tablet tests and sustained 60fps remain open, alongside earlier failures. Painting tools are next, then B04. No installation, source upload, GitHub deletion, App Store change or software release occurred. [Evidence](BRUSH_PATTERN_TEXTURES_454.json).

<a id="dev-step-455"></a>

## 2026-11-06 — Step 455: Eraser mode reference

The six special painting and eraser tools already exist. A prior audit identified a remaining ordinary Eraser gap: Brush, Pencil and Block modes. Before changing the engine, we used an owned uniform gray image in Photoshop to measure Block behavior. Each result was saved separately and decoded with an independent PSD merged-plane parser.

A click at 100% changes exactly 16 × 16 pixels to the background color. At 200% it changes 8 × 8; at 125%, 12 × 12; at 1600%, one pixel. Two tested 6400% clicks change nothing. These selected results agree with truncating 16 divided by zoom. They do not establish every position or stroke, but they rule out a forced one-pixel minimum. No proprietary code or artwork was accessed. The original image is unchanged; Photoshop's Brush mode, 100% zoom and Brush tool were restored before closing the owned reference document.

The integration plan preserves the existing brush eraser's fast, paged and component-target paths, adds native and shared API modes, captures settings for strokes and Actions, and checks cursor feedback for all 16 modifier combinations. Pencil controls still need qualification. Erase to History requires a real history source and remains part of the original scope. Photoshop also displayed a 5000 px Eraser Brush, beyond Photato's 2048 px brush limit; that separate B01 capacity gap is recorded without claiming an Adobe maximum.

This checkpoint adds evidence and a concrete implementation plan, with no application source, tests, build or API changes. All 7,409 frozen inputs remain unchanged. B02 remains current, followed by B04. The prior 40-test Debug qualification belongs to 454; optimized universal remains 453. All previous output, platform, capacity and 60 fps requirements remain open. No source upload, GitHub deletion, installation, App Store change or release occurred. [Evidence](ERASER_MODES_455.json).

<a id="dev-step-456"></a>

## 2026-11-06 — Step 456: Eraser modes

The ordinary Eraser now offers Brush, Pencil and Block. Brush retains the existing settings. Pencil uses the existing hard, aliased pencil behavior and ignores Flow. Block uses a solid square whose document size follows the current view zoom; it ignores brush diameter, opacity and Flow. At high magnification the inferred footprint can be zero, so the operation leaves pixels and history unchanged. This follows the six selected Photoshop reference results, not a claim about every position or continuous stroke.

The native toolbar disables controls that do not apply. Stroke settings and the mode are captured at gesture start. Cursor policy reports the selected mode and keeps temporary Hand behavior and modifier restoration. Erase to History and its Option alternate remain explicitly unavailable. The previous notes incorrectly assigned that work to B06, which is Content-Aware Fill and Scale. History-source selection belongs to D03, History and Art History Brush to B03, and ordinary Eraser integration to B02. No original package scope is removed.

The optional API adds eraserMode to brush.configure, with its existing required brush patch. paint.stroke accepts an explicit mode and optional captured zoom. Omitting the mode preserves the older brush.erase behavior. Both paths reuse the current native stroke, target, history and Actions engines. Command count 260, native archive version 88 and Actions version 54 remain unchanged. No Adobe endpoint or unsupported action descriptor is invented. Photoshop plug-in hosting remains separate, unimplemented work under AUT03.

The first attempt compiled the application but failed to compile a new test that assigned a read-only property. Its source, logs and 5,401 products were retained before repair. The test now uses the actual mask-selection operation. API schema metadata, explicit zoom capture and stationary cursor observation were also completed. All 44 focused Debug methods then passed, including ten new methods for the independent RGB8 Block references, all three depths, masks, maximum sparse canvas, captured modes, cancellation, Undo/Redo, Actions and real HTTP validation. The same 44 methods pass in normal optimized Apple Silicon and Intel builds, with Intel tested under Rosetta on the current host. All ten new methods pass on both. The six RGB8 Block buffers match the owned Photoshop outputs byte-for-byte in Debug and both optimized builds. Older tests, fixtures and existing Core/Imaging files are unchanged.

Photoshop's normal Pencil Eraser toolbar was checked on an owned reference document: opacity remains available and Flow is disabled. Brush mode and the Brush tool were restored before closing the unchanged reference. Native Photato testing painted a black stroke, used all three Eraser modes, and verified Block Undo/Redo before restoring a clean disposable document. The Debug app's Open and Quit commands were disabled, and the app remained open. That is an unresolved failure, not a successful Quit check. A preflight check caught the still-running process; an early release-driver invocation then exited before starting any compiler because its test-list file had not yet been prepared. The normal builds subsequently passed. A fresh optimized application with a distinct test identity opens the exact owned gray PSD, performs a Block erase at 400%, verifies clean/dirty transitions through Undo/Redo, closes the restored image and quits normally. The original file is unchanged. Its universal macOS 14 package verifies sandbox entitlements, signature and identical ZIP extraction contents. The earlier Debug session still had disabled Open/Quit after idle, settings inspection and workspace cancellation. Its cause is unresolved. Activity Monitor was used to stop only that clean disposable test process; a normal stop request did not exit, so force quit was required. Both owned Photato processes are now absent. This cleanup is not recorded as a successful native Quit.

Full Eraser and painting parity, independent Pencil pixels, continuous strokes, transforms, profiles, factory defaults, the observed 5000 px versus 2048 px brush-capacity gap, physical input and 60 fps qualification remain open, along with earlier numerical and full-suite failures. The next B04 source audit found that Blur, Sharpen and Smudge expose only a fixed Normal label and ignore the brush blend mode; Photoshop's supported choices and output need checking before implementation. No installation, source upload, GitHub deletion, App Store change or software release occurred. [Evidence](ERASER_MODES_456.json).

<a id="dev-step-457"></a>

## 2026-11-06 — Step 457: Blur, Sharpen and Smudge blend modes

The three focus tools previously displayed a fixed Normal label. Their validation also rejected other modes; the earlier statement that the renderer simply ignored the setting was incomplete. They now offer Normal, Darken, Lighten, Hue, Saturation, Color and Luminosity. Each tool retains its own selection during the session and captures it at stroke start. The existing processed sample is blended with the original target before stroke opacity and selection. Alpha, locked transparency, hidden color and scalar-mask policies are explicit. The Normal arithmetic path, neighborhood kernels and Smudge pickup are unchanged.

The optional retouch.stroke API accepts the same modes, exposes them in discovery and conditional schemas, and rejects unsupported modes before publication. Native Mode changes advance the API revision without adding image history; unchanged values retain it. Explicit stroke overrides preserve native defaults. Non-Normal focus recipes require Actions version 55, while ordinary retouch recipes retain version 21. Native archive version 88 and 260 typed commands are unchanged. No Adobe route or plugin host was added.

Photoshop's seven-item Blur list was observed on an owned image through its normal interface. Attempts to select Sharpen and Smudge did not qualify their desktop lists. An unexpected Eraser state was undone and the unchanged owned image closed. Adobe's desktop help describes mode controls; its iPad list and the public W3C color-blending definition supply related evidence, not a Photoshop numeric oracle. The current Adobe Smudge help says R, but installed Photoshop selects Rotate View with R; factory shortcuts were retained. No proprietary implementation or artwork was copied.

Before editing the engine, an owned Swift helper captured 18 Normal buffers from the preserved build456 Core module. Those are Photato regression fixtures. The first new test attempt assigned a read-only property and did not run tests. A second attempt found an ambiguous BlendMode type in the new app test. Both sources, logs and products were retained before test-only repairs. The first retained cache app was stale456 and is labeled accordingly. Source02 and Source03 application hashes are identical; Source03 passed 56 tests. Source04 added the native-mode API revision guard and a tenth test. All 57 focused Debug tests pass. The optimized builds pass 57 methods on Apple Silicon and 56 of the same 57 on translated Intel; all ten new methods pass on both. The remaining Intel comparison reproduces all 234 failure messages and actual/expected hashes on the preserved456 test bundle. Its assertion and fixture remain unchanged. Twenty-nine older tests change only the maximum Actions-version counter. All 18 preserved Normal buffers match exactly. Of 126 mode buffers, 120 match across Debug and both optimized architectures; six Float32 buffers differ in 16 Intel color values by 1–4 ULP, with all alpha values exact. Debug and optimized Apple Silicon match all 126. No tolerance was substituted.

The native checks use the owned hard-edge image. Sharpen Lighten and Smudge Color drags each produce a dirty document, Undo restores clean, Redo returns dirty, and a final Undo restores clean. Blur retains its separate Darken setting. The initial rapid single-click/history sequence was inconclusive; the image was reopened and the drag/history actions observed separately. Open-panel navigation also produced a clipboard timeout and delayed selection; the selected file subsequently opened through the normal Open button. These attempts remain documented without a cause claim. The clean reference closed, and the validation app quit normally. The optimized universal application opened the same image, painted with Blur Darken, passed separately observed Undo/Redo and clean close, and quit normally. Its sandbox entitlements, macOS 14 metadata, signature and ZIP contents verify. Original artwork is unchanged. The earlier456 Debug Open/Quit failure is not claimed repaired by a successful fresh457 session.

Full B04, independent Photoshop pixel outputs and per-dab behavior, exact defaults, profiles and component contexts remain open. Physical Intel/macOS14, tablet input, 60 fps, capacity and all earlier strict/full-suite failures remain open. B06 Content-Aware Fill and Scale is next, followed by B07. All 104 original scopes and acceptance criteria, 652 command mappings, 81 major memberships and the seven-pass order are retained. No current build or GitHub content was removed, and no source upload, installation, App Store change, Xcode archive or software release occurred. [Evidence](FOCUS_BLEND_MODES_457.json).

<a id="dev-step-458"></a>

## 2026-11-06 — Step 458: Apply Content-Aware Fill and continue editing

Content-Aware Fill previously offered only OK to commit and close. Apply now commits one fill while leaving the workspace open. It rebuilds its source from the committed document, retains settings and sampling strokes, and resets local selection edits and history. New output keeps the original source layer; Duplicate continues from the new duplicate. Exact Photoshop source and layer behavior still needs direct comparison.

Selection strokes now support New, Add, Subtract and Intersect. Native controls and Shift/Option modifiers capture the selected operation at gesture start, and cursor feedback follows it. The optional contentAware.fill API accepts the same explicit selectionMode, while old requests retain their add behavior. Discovery and read-only state expose Apply availability, applied-fill count and preview/commit status. Remote commands still reject a busy native workspace. Native archive88, Actions55 and260 typed commands are unchanged; existing Content-Aware recording and Adobe action-descriptor limitations remain.

Cancel discards the current preview and keeps earlier applied fills. OK commits a pending fill and closes; after an unchanged Apply it closes without another output layer or Undo. Each published fill uses the existing prepared edit and history path. Synthesis, output pixels, Content-Aware Scale, channel and history engines are unchanged.

The first run executed29 of38 selected methods:27 passed, two failed, and nine cursor methods were missing because the selector used a helper window's class name. The new HTTP test tried document Undo while the native modal remained open; it now closes the unchanged workspace first, retaining exact document equality. An older Scale fixture tried saving a protection channel without any selection. The preserved457 test bundle reproduced the same error. The fixture now selects explicit full coverage before saving, then clears selection before whole-layer scaling. All its original assertions remain. A new selection test also gained literal per-pixel expectations, and real HTTP state was checked. Source01/02 application binaries are identical.

All38 selected Debug methods now pass, including seven new methods. The tests cover all three bit depths and output choices, two Applies, Cancel, unchanged OK, stale and cancelled work, Undo/Redo, native archives, selection modes, HTTP equivalence/state/errors and all16 modifier combinations for captured selection cursors. Frozen7445 inputs and5421 retained products bind to the passing build. The isolated Debug package passes macOS14 metadata, full production sandbox entitlements, signature and exact unsigned-payload checks. Normal458 is deferred under the breadth policy; the latest universal remains457 with its known strict failures.

Adobe's current Apply/cancel guide describes continued filling and new Lasso selections. Photoshop Home was visible, but its Open and menu input calls timed out, so no new Photoshop reference was opened. In native Photato, the owned two-object PSD opened through the system panel. The first drag had no visible marquee and left Content-Aware Fill disabled; repeating the drag produced a visible selection and enabled the command. No cause is claimed. A stale menu index briefly opened File; its native Cancel action dismissed it before selecting the actual Edit command. The automation native pipe then closed while opening the fill workspace. Re-observation, a REPL reset and rebinding all failed. Photato is still running with the disposable document; only selection editing was observed, the post-disconnect UI state is unknown, and no live Apply, close or Quit result is claimed. The original image is unchanged. A single unlock-status question is pending while independent work continues.

Multi-image sampling and alignment, the existing16MP workspace/4MP synthesis and scaling limits, exact Photoshop output/defaults, full current-suite, physical Intel/macOS14, tablet input and60fps qualification remain open. The hosted Light/Dark control construction is not full visual or accessibility acceptance. All104 original scopes and acceptance criteria,652 command mappings,81 major memberships, seven passes and prior failures are retained. B07 is next, then D04; resume the pending458 native check when the connection returns. No current builds or GitHub content were removed, and no upload, installation, App Store change, Xcode archive or software release occurred. [Evidence](CONTENT_AWARE_APPLY_458.json).

<a id="dev-step-459"></a>

## 2026-11-06 — Step 459: Eyedropper averaging and layer sources

The previous Eyedropper picked a single displayed pixel. It now offers Point Sample and 3, 5, 11, 31, 51 or 101 square averages, plus Current Layer, Current & Below, All Layers and the two choices that exclude adjustments. Dragging updates the foreground colour; Option at press captures background instead. The optional ring shows the new colour above the captured colour, with a gray surround. Settings are shared between documents and saved by the production startup path. Detached documents receive independent copies. No image edit, dirty state or Undo entry is created by sampling or these settings.

The optional color.sample API uses the same native sampler. Sampling is read-only unless foreground or background is explicitly requested. Overrides leave tool settings unchanged; configuring saved settings requires the existing preference-change permission. Results include colour, coverage, clipped region and contributing-pixel counts. Cancelled, revoked, busy and stale requests do not publish. Captured cursor feedback covers all 16 modifier combinations. Shift Color Sampler remains unavailable because persistent sampling points are not yet implemented.

The first build failed because a validation hook was placed in the schema loop. The second linked the app but found Swift 6 isolation and permission-setter errors in new tests. Both attempts were preserved before repair; the first retained executable was explicitly identified as cached build 458. The third executed 44 tests:42 passed. Investigation found that displayed composites use Float32 storage even for integer documents, so their averaging must capture the document depth. The new whole-composite reference and displayed-channel implementation now use that semantic depth, retaining exact result equality. Unsupported size 2 also returned HTTP 422 instead of HTTP 400; validation now returns400. A separate every-depth displayed-target regression was added.

All 45 focused Debug tests now pass, including 19 new methods. The same 45methods pass on normal optimized Apple Silicon and translated Intel. Tests cover literal averaging, transparency, HDR, source filtering, transforms/groups, bounded sampling on a 300,000 pixel canvas, native/API agreement, shared preferences and both startup factories, cancellation/stale/revoked results, palette/history effects and cursor capture. Strict sample-buffer hashes and any differences are in the [evidence](EYEDROPPER_SAMPLING_459.json); no tolerance substitutes for byte equality. The 7,452 frozen inputs and retained build products bind these results to the tested source. Native 88 and Actions 55 are unchanged;261 typed commands are exposed. Only catalogue counters changed in28 old test files.

The universal validation package passes macOS 14 metadata, full production sandbox entitlements, signature and extracted ZIP checks. Debug staging also preserves the exact unsigned executable payload. A final event-dispatch audit also found that the canvas rejected Eyedropper before reaching the sampler when a channel was active. That admission guard now permits the implemented read-only tool. Controlled AppKit mouse events verify the sampled result and active foreground at all three depths, without changing pixels or history. The API now accepts every coordinate below the full 300,000 pixel boundary; the endpoint itself remains invalid.

The UI automation native pipe is still disconnected when selecting the earlier458validation app, so no459app was launched and live controls, dragging, ring appearance, relaunch, close and Quit are not claimed. The earlier disposable app remains open; no force quit or alternate input mechanism was used. Offscreen native controls are not live visual/accessibility acceptance.

Current public Adobe help and a first-hand Adobe-employee article guided the controls. The older article describes zoom-dependent sampling and shared sample size with other tools. This implementation uses document-pixel regions, and installed Photoshop 2026 footprint/source/alpha/profile/default/numerical comparisons remain required. Native/API agreement does not prove Photoshop equality. Persistent Color Sampler/Info points, real tablet pressure/tilt/eraser/buttons and replay, external-desktop sampling, physical-platform/60fps/full-suite checks and all prior failures remain open. All 104 original scopes/acceptance,652 reference command mappings,81 major memberships and seven passes remain. D04 clipboard interoperability is next, then L03. No current builds or GitHub content were removed, and no upload, production installation, App Store change, Xcode archive or release occurred.

<a id="dev-step-460"></a>

## 2026-11-06 — Step 460: Copy and paste masks and channels

Copy and Paste previously rejected auxiliary editing targets. They now work on alpha channels, Quick Mask, layer masks and Smart Filter masks using the existing menus and shortcuts. Cut and Paste In Place use the same target selection. Copy preserves grayscale samples, selection opacity, document depth and copied position. It does not change image pixels or history. Cut writes the clipboard before changing the document, and Cut/Paste each produce one Undo transaction. Cancelled work, changed targets and clipboard publication failures leave the document intact.

The implementation uses the existing grayscale document representation and native clipboard envelope. It does not flatten raw scalar values through an RGB preview. Colour sources use the existing native grayscale conversion with the captured working Gray profile. Transformed masks retain their geometry, outside value, density and feather; pasting expands stored mask bounds when needed. Standard TIFF/PNG generation was also preventing large native copies. Those fallbacks are now omitted above their materialization budget, preserving full native data instead of substituting a reduced image. This does not solve every large-document or cross-application clipboard case.

The optional API accepts an explicit channel or mask target without changing the desktop target or using the Mac clipboard. It shares the native engine and transaction history. Targeted Cut can take a numeric background value; Paste supports ordinary centered placement and Paste In Place. New Document accepts the grayscale payload while an auxiliary target is selected, with the existing transfer permission. State/capability schemas and limits are exposed. There are still 261 typed commands, native format 88 and Actions format 55. Targeted clipboard Action recording remains explicitly unsupported.

The first build failed because the existing 24MP clipboard benchmark assumed TIFF and PNG were always present. Its contract still requires both, now with an explicit throwing guard. No tests ran, and the retained executable was identified as cached build 459. The second attempt compiled and ran all 45 selected tests: 41 passed. Four new methods stopped at an invalid Smart Object media type in their test fixtures. Both fixtures now use the accepted native document type. The application executable is byte-identical before and after this test-only correction; the failed source, logs and products are preserved.

All 45 focused Debug tests and the same 45 optimized methods pass on Apple Silicon and translated Intel, including 20 new methods. Native/API comparison exercises all three depths and four targets. Other checks cover Undo/Redo, irregular selection opacity, spot samples, translated mask expansion, failed/cancelled/stale native edits, HTTP errors and a 300,000 × 300,000 sparse transfer. The 984-byte raw sample captures are compared across configurations and against independent literal rational values without tolerances. These own-fixture results do not establish Photoshop output equality. The 7,459 frozen inputs, retained products, exact commands and results are in the [evidence](TARGETED_CLIPBOARD_460.json).

The isolated universal package passes macOS 14 metadata, full production sandbox entitlement, signature and extracted ZIP checks. Native UI acceptance is pending the existing automation connection issue. The Debug staging comparison differs only in the verified LINKEDIT virtual-size allocation changed by signing; all other unsigned bytes are exact. No build 460 app was launched or installed, no normal Quit is claimed, and the earlier disposable app has not been force-quit. Controlled native methods and a named test pasteboard are separate from physical UI acceptance. The user's system clipboard was not used by the tests.

Adobe's public guide confirms pasting image content into a displayed layer-mask channel. Exact mask-thumbnail versus mask-only context, floating selection, gray conversion, profiles, rounding and numerical output still require an installed Photoshop 2026 reference. The current layer-copy guide also says whole-layer Cut is unavailable; that discrepancy is retained for a contextual check. No Adobe implementation code or artwork was copied.

D04 remains open for RGB component-set/path clipboard, external vector/PDF/layered formats, Background Cut, scalar Paste Into/Outside, portable targeted Actions and the remaining fidelity/capacity/platform/performance checks. Existing earlier failures remain. All 104 original scopes and acceptance criteria, 652 command mappings, 81 major memberships and seven passes are preserved. L03 advanced blending is next, then L04. GitHub content and current builds were not removed; there was no upload, production installation, App Store change, Xcode archive or software release.

<a id="dev-step-461"></a>

## 2026-11-06 — Step 461: Channel blending

Blending Options now has native Red, Green and Blue checkboxes. Deselecting a channel preserves that component of the backdrop while the enabled channels use the existing composite. The layer context menu opens the same sheet. Preview changes stay private until committed; Cancel discards them. The setting participates in Undo/Redo and style copy, paste and clear. Pointwise channel-only styles are available on adjustment layers and large RGB documents without allocating an effect map. Other effects keep their separate availability and resource limits.

The renderer carries the setting through ordinary layers, groups, pass-through groups, clipping, masks, transforms and existing effects. Stored source pixels are unchanged. Existing unrestricted composition paths and their measured rounding remain intact. The current alpha, transparent-backdrop, all-off and group policies are implementation choices awaiting independent Photoshop 2026 comparison. They are not recorded as measured Photoshop behavior.

The optional API uses the existing layer style operations and returns the same setting in document state. RGB component IDs must be distinct and in range. Non-RGB exclusions reject explicitly. Native format 89 and Actions format 56 retain the new field, including styles stored in timeline keys, frames, Layer Comps and retained sources. Timeline channel choices hold until the next key. PSD and PSB use the public brst component-ID records, including an empty record for explicit all-on state. Earlier archive feature minima remain unchanged. There are still 261 typed commands. The published Firefly BlendOptions schema has blend mode and opacity, so no undocumented channel endpoint or plug-in compatibility was added.

The first test run used a helper class instead of the real cursor test class for nine selectors. Its new maximum-size reference also confused encoded fill values with stored linear samples. The second run executed the corrected selectors and a new temporal regression, but its maximum-size expectation still missed ordinary Normal composition rounding. That existing math was left unchanged. The new reference now compares excluded channels with the backdrop and enabled channels with the ordinary unrestricted composite, using exact words and no tolerance. The third attempt passed all 57 selected methods. The application executable is identical across attempts two, three and four.

A further regression test then demonstrated that a small raster edit under unchanged channel-only styles caused full-canvas redraws. Its pixel comparisons passed, but both bounded-damage assertions failed. The source and results were retained before changing invalidation. Channel-only settings now permit the existing bounded tile update; changing channel settings or using rich effects still forces full invalidation. This reduces unnecessary work but does not establish a measured 60 fps result. The fifth attempt passes all 58 selected Debug methods, including all 17 new methods.

The same 58 methods pass optimized on Apple Silicon and translated Intel. Tests cover all eight channel combinations at three depths, represented blend modes, groups, clips, masks, effects, adjustments, sparse maximum geometry, bounded/full-render agreement, native/API history and validation, native/Actions negotiation, and strict PSD/PSB records. Seven existing independent Photoshop RGB32 regression methods also pass on both retained build 460 architectures and the new selected configurations. Those regressions protect unrestricted output; they are separate from the earlier unresolved Intel failures and do not prove the new exclusion semantics.

The selected 384-byte captures match exactly across Debug and both optimized architectures. The 7,465 frozen inputs, five failed/passing attempts, retained products, exact commands and package checks are linked in the [evidence](CHANNEL_BLENDING_461.json). The universal validation package passes minimum macOS 14 metadata, full production entitlements, signature and extracted ZIP checks. Any Debug signing-allocation difference is identified separately in its payload comparison. No build 461 app was launched or installed. Native checkbox, menu, focus, preview, history and Close/Quit acceptance remains pending the existing automation connection issue.

L03 remains open for non-RGB component exclusion, split Blend If controls, shallow/deep knockout, advanced interior-effects and transparency/mask flags, complete editable interchange, and the recorded default, alpha, numerical and output checks. Full-suite, physical platform, capacity, performance and earlier failures remain open. All original scopes and acceptance criteria are retained. L04 layer styles and effects is next, then L05. Current builds and GitHub content were preserved; there was no upload, installation, App Store change, Xcode archive or software release.

<a id="dev-step-462"></a>

## 2026-11-06 — Step 462: Saved layer styles

The existing editor had ten effect types, multiple effects, expanded controls and scaling, but no saved preset workflow. New Style now captures private Layer Style settings without committing them to the document. Window > Styles opens a native panel for applying, grouping, renaming, duplicating, moving and deleting presets. Effects and blending options can be saved separately. Saving and organizing leave document content and image Undo unchanged; applied styles remain independent of later preset edits.

Patterns are stored with a preset. Applying remaps conflicting IDs without replacing existing document artwork. A regression test demonstrated that recording a preset when its pattern was already installed omitted that dependency, causing replay to use foreign artwork. The repair embeds every dependency and remaps collisions during replay too. Applying uses one shared style transaction with Undo/Redo. New resources and general blending require Actions 57; native document format 89 remains current.

The library validates groups, resources and names before atomic persistence. Failed writes, corrupt files, cancelled preparation, stale sources and revoked API sharing retain the prior state. The Styles panel participates in the existing dock, floating windows and workspaces. Panel catalogue 4 migrates complete older layouts without moving their panels and adds Styles hidden. The new API uses the same model, source guards and history. Routine state carries metadata; inspect retrieves bounded full descriptors. Existing pattern and gradient effect schemas now describe their actual native fill objects. There are 262 typed commands.

Early attempts caught incorrect new model assumptions, a Swift Sendable test error and a missing try. The first retained executable was identified as cached build 461; later cached products are also labeled explicitly. The first executable test run passed 69 of 74 methods and exposed the dependency/replay bug, an overstrict duplication rule, incomplete fill schemas and two old metadata assertions. Source02 and Source03 applications are identical, confirming that the intervening Task-result repair was test-only. Every source, log, product and later correction is retained in the [evidence](LAYER_STYLE_PRESETS_462.json).

The fifth attempt passed 75 of 76 methods. Its remaining new hierarchy assertion incorrectly ignored the copied group already preceding the moved entry; the reference was corrected to check the intended relative order. The final attempt also aligned the style-override schema with its existing object-only decoder. No old numerical assertion or tolerance changed.

The final selected run passes all 76 focused Debug methods, including 18 new methods. Tests cover all ten effects at three depths with exact native composites, resource conflicts, private draft saving/Cancel, native/API agreement, image history, portable replay, group operations, persistence/corruption/failure, synchronized cancellation/revocation, schemas and old-layout migration. Seven existing independent Photoshop RGB32 tests protect old output. Existing Imaging code, numerical fixtures and effect math are unchanged. Own round trips and equality do not establish new Photoshop preset output or defaults.

The packaging helper completed its checks but stopped copying its driver into a missing evidence directory. The driver was retained and the existing package reverified without rebuilding the app.

The isolated Debug package passes macOS 14 metadata, production entitlement, signature and payload checks. It is unlaunched; live controls, focus, appearance, accessibility and Close/Quit remain pending the native automation connection issue. Normal optimized/Intel/universal 462 testing is deferred under the existing breadth policy; optimized universal 461 remains the latest separate package. Adobe ASL Import/Export is still unavailable and visibly disabled. Internal library persistence is not an ASL substitute. Default artwork, thumbnails, hover/drag/display variants, complete effect/interchange behavior, convert-to-layers, exact defaults/output and all earlier platform/capacity/performance failures remain open.

All original scopes and acceptance criteria are retained. L05 Smart Objects is next, then L06 Smart Filters. Current builds and GitHub content were preserved. There was no source upload, production installation, App Store change, Xcode archive or software release.

<a id="dev-step-463"></a>

## 2026-11-06 — Step463: Convert Smart Objects to layers

The Layer > Smart Objects menu contained Convert to Layers, but the command had no implementation. It now restores the original editable layers through the factory menu, Layers context menu and optional API. Multiple layers become a group. The selected source Layer Comp is applied first. Following Adobe's public guide, conversion discards the original outer transforms and Smart Filters. It does not replace the command with Rasterize.

The transfer retains type, shapes, masks, styles, patterns and nested source contents. Conflicting resource IDs receive new identities without replacing existing document artwork. Nested instances keep sharing within their original source class. Imported appearance caches are rebound from their captured reference so that a stale cache does not become active accidentally. The parent selection, channels, paths and metadata are retained. All selected instances use one prepared transaction and Undo/Redo. Unsupported mode/profile, PDF/RAW, temporal, source-artboard and variable contexts reject the operation. Portable Actions replay remains unsupported.

The first compile caught a Swift exclusivity error in the new mask transfer. Subsequent tests caught two invalid new fixtures: shape dimensions omitted the geometry's padding, and a profile test changed the document's fixed metadata label instead of installing an ICC profile. The failed attempts were retained before repair. The three later applications are byte-identical; those repairs changed tests only. No existing rendering code, numerical fixture or tolerance changed.

All15new methods pass. The55selected methods include53passes, one older linked PSD/PSB test with two byte mismatches, and an older archive/API method that exits bysignal10. Retained build462reproduces both older problems. A separate continuation ran the methods blocked by that crash, including all nine cursor regressions. Seven existing independent Photoshop RGB32 regressions pass. This is not a full-suite pass or new independent Photoshop output qualification.

The isolated arm64 Debug package passes minimum macOS14, production-entitlement, signature, resource and unsigned-payload checks. It has not been launched or installed. Normal463and live acceptance are pending; optimized universal461remains separate. Native window and screenshot access partly recovered, but Open/File actions still timed out. The new reference copy did not open, so placement, outer attachments, defaults and numerical output remain unqualified. The full Smart Object package remains open; Smart Filters is next, followed by S02.

The plugin compatibility question was also checked against current source and Adobe's documentation. Photato has no Photoshop native-binary, UXP or CEP/ExtendScript host. The REST API is separate from desktop plugin compatibility. Future support needs its own implementation and testing for each supported plugin.

[Guide](SMART_OBJECT_CONVERT_TO_LAYERS.md) · [Evidence](SMART_OBJECT_CONVERT_TO_LAYERS_463.json) · [Technical record](DEVLOG.md#dev-step-463).

<a id="dev-step-464"></a>

## 2026-11-06 — Step 464: Smart Filter stack and mask transfers

Smart Filter stacks and shared masks can now be moved or copied between Smart Objects. Drag the Smart Filters label for the whole stack, or its thumbnail for the mask; Option copies. The API uses the same operation, and one Undo restores both layers. Portable Actions record the source and destination by layer name so they can replay in another matching document. Actions now use version 58; the native document format stays at 89.

An existing destination stack keeps its mask and enable state. A new stack inherits those from the source. Mask transfers retain the original samples and document-space properties. Source pixels and original Smart Object contents stay intact. All 15 new transfer tests pass, including native/API equivalence, a layer with both mask types, stale requests, cancellation and Undo.

The first optimized runs exposed two saved-style API failures. Investigation found that weak request owners could disappear while an otherwise valid operation was preparing. The operation now retains its owners until completion and still checks whether the document was closed or sharing was revoked. A synchronized Close test verifies that the write is rejected. Failed runs, sources and binaries are retained alongside the passing repair.

The final optimized batch passes all 87 selected methods on Apple Silicon and translated Intel, including 49 new methods from saved styles, Convert to Layers and this work. The Debug record accounts for 56 methods: 55 pass and one older API test crashes, also reproduced in retained build 463. Three depth fixtures produce identical raw output across Debug and both optimized architectures: 1,152 bytes, checked without tolerance. That comparison does not prove Photoshop output equivalence.

Photoshop automation recovered enough to open our synthetic document, create two Smart Objects and apply a Gaussian Blur Smart Filter. Coordinate dragging still failed with a tool error. The fixture was saved and closed; transfer behavior remains unverified. The fresh universal validation app passes macOS 14 minimum-version, entitlements, signing and extracted-ZIP checks. It has not been launched or installed. Its only unsigned packaging differences are verified signing-allocation fields; all other bytes match the tested slices.

Full Smart Filter parity, independent Photoshop output, live gestures, physical Intel/macOS 14 and performance checks remain open. Work proceeds to **S02 — Color Range, Focus Area and Magnetic Lasso**, then S03.

[Guide](SMART_FILTER_TRANSFER.md) · [Evidence](SMART_FILTER_TRANSFER_464.json) · [Technical record](DEVLOG.md#dev-step-464).

<a id="dev-step-465"></a>

## 2026-11-06 — Step 465: Magic Wand averages

The Magic Wand Sample Size control was fixed at Point Sample. It now offers Point Sample and 3 by 3, 5 by 5, 11 by 11, 31 by 31, 51 by 51 and 101 by 101 Average. Those choices were checked in the installed Photoshop 2026 popup. The test setting was restored and the owned reference document closed without saving changes.

The native tool and optional API use the same captured request. Samples can come from the current layer, visible composite or ordinary layer mask, including locked sources. Source pixels stay intact and the resulting selection has one Undo. The API can configure window-local options or select with temporary overrides; overrides leave the defaults unchanged. Existing W/Shift-W and selection modifiers remain.

The first build stopped because Swift integer SIMD vectors do not support checked addition. A second attempt caught an incorrect property name in the new availability check. Both attempts and their cached 464 products were retained before repair. The final code uses checked scalar sums and the existing pathTarget property. A live check then caught a truncated picker value. The control was widened, and the same 57 tests passed again. The final native app shows the full 101 by 101 label, makes a canvas selection, and completes Edit-menu Undo/Redo/Undo. Quit was verified by process termination. All 11 new tests and 57 selected Debug methods pass. They cover seven sizes, three bit depths, masks, captured settings, history/archive and request guards. A separate literal arithmetic reference agrees with all 74,263 captured mask bytes, and the old point-sampling regression still agrees with its 66,096 bytes.

These checks do not establish Photoshop pixel equivalence. Alpha, hidden-color, rounding, connectivity and profile details still need independent comparison. Full S02, dense/maximum capacity, restart preferences, semantic Actions, live controls and physical-platform/performance checks remain open. Normal 465 will join the next stable optimized batch; the latest optimized universal remains 464. Work moves to S03, then S04.

[Guide](MAGIC_WAND_SAMPLING.md) · [Evidence](MAGIC_WAND_SAMPLING_465.json) · [Technical record](DEVLOG.md#dev-step-465).

<a id="dev-step-466"></a>

## 2026-11-07 — Step 466: Selection sources and Wand Subject

With Sample All Layers off, object and people analysis could still use the whole visible image for type, shape or fill sources. It now renders the selected source through the existing renderer. Sample All Layers explicitly chooses the composite. Groups and adjustments currently require that choice; their full Photoshop eligibility remains to be checked. The initial audit incorrectly included Smart Objects in the affected cases. They already retain raster previews and already used the current-layer path. That statement was corrected before implementation.

The installed Photoshop Magic Wand Options bar includes Select Subject. Photato now exposes the same entry, using Magic Wand’s own Sample All Layers flag. Object/Quick and Properties/Menu preferences stay independent. The existing Subject detector and raster/Smart Object eligibility were retained. No model, Core arithmetic or rendering kernel was replaced.

Twelve new tests cover source choice, rich layer families, masks/transforms, three depths, caches, HTTP/native behavior, history/archive and cancellation. All 82 selected Debug methods pass. The same 83 optimized methods pass on Apple Silicon and translated Intel, including all 23 new methods from this step and step 465. All 7,487 source inputs retain their hashes. Separate literal source samples and prior averaged-Wand masks match every captured byte on all three builds. These checks do not establish Photoshop or model-output equivalence.

The first native connection failed before launching this build. Resetting the computer-use session recovered it. In the isolated Debug app, the new button ran Apple Vision on a copy of the project icon and produced a visible subject selection. Menu Undo/Redo/Undo, closing the clean owned tab and Quit passed. The old validation app was left alone. A new optimized universal package passes macOS14 metadata, entitlements, signature, extracted-ZIP and compiled-payload checks; it has not been launched or installed.

A separate source/documentation audit answered the plug-in question: Photoshop native plug-ins, UXP and CEP/ExtendScript are not currently supported. They remain open under AUT03. HTTP API compatibility does not supply a desktop plug-in runtime.

Detailed face features, full S03, exact Photoshop source-kind/default/output behavior, broader target/capacity support, physical-platform/performance checks and earlier failures remain open. Work moves to Select and Mask, then pixel/vector masks.

[Guide](SELECTION_SOURCE_POLICY.md) · [Evidence](SELECTION_SOURCE_POLICY_466.json) · [Technical record](DEVLOG.md#dev-step-466).

<a id="dev-step-467"></a>

## 2026-11-07 — Step 467: Smart Object refinement

Photato rejected Smart Objects at the Select and Mask entry point. Photoshop accepted the owned reference image after conversion to a Smart Object. Its Layer Mask output kept Edit Contents available, while New Layer with Layer Mask created a raster copy. Both neutral RGB8 references were saved and closed cleanly.

The existing native workspace and API now support that workflow. Selection and mask outputs retain source pixels, embedded data and Smart Filters. Copy outputs use the existing renderer, preserving supported geometry/effects in raster output. The source stays intact. Existing source, lock, cancellation, history and document-transfer checks remain. Smart Filter masks stay unavailable for refinement; Focus Area keeps its previous source boundary.

The first test build caught two fixture writes to a read-only property. After that repair, 123 of 124 tests passed. The remaining reference test exposed a valid empty Anno block inside Photoshop’s embedded PSD. Its documented annotation data is now preserved opaquely and re-exported unchanged, rather than removing it from the fixture. This does not add a Notes editor. After annotation retention, 124 of 125 passed; the embedded PSB’s explicit missing-composite declaration then exposed a second importer gap. Decoded layers are now authoritative only for an unambiguous complete false declaration and when decoded layers are present and no auxiliary channel planes are required. Ordinary malformed-cache rejection remains. Those repairs and two extra negative-case tests bring the selected run to 127 methods, including 17 new methods.

The neutral mask matches all 3,072 literal bytes. An isolated Debug app also passes packaging checks and native import; interactive refinement remains pending. Normal optimized 467 is deferred after the 466 batch. Detailed edge/hair algorithms, exact Photoshop defaults/output, full S04, broader contexts/capacity, physical platforms/performance and earlier failures remain open. Work moves to pixel/vector masks, then channel workflows.

[Guide](SMART_OBJECT_REFINEMENT.md) · [Evidence](SMART_OBJECT_REFINEMENT_467.json) · [Technical record](DEVLOG.md#dev-step-467).

<a id="dev-step-468"></a>

## 2026-11-07 — Step 468: filters on masks

The filter dialogs rejected selected masks even though the same masks could be painted. Layer and Smart Filter masks now support Gaussian Blur, Box Blur, Motion Blur, High Pass, Unsharp Mask, Add Noise, Average and Mosaic through the existing menus. The API exposes the same targets. Color pixels, embedded Smart Objects, filter settings and mask properties stay intact. Preview and Cancel leave source history unchanged; commit and Repeat use one prepared Undo transaction.

The first run exposed a real API admission defect: an explicit color-pixel filter was rejected while a mask thumbnail was selected. That path now retains the thumbnail selection while applying the requested pixel edit. Two new-test expectations were also corrected: inverted mask storage needs a complement after filter-depth quantization, and irrelevant filter parameters omitted by the API should not be compared as retained settings. Original failures, source archives, products and the incorrect reference remain in the record.

97 selected Debug methods pass, including all 15 new methods. The planned 98th Debug method crashes with signal 10 on both 468 and retained 467. All 98 selected optimized methods pass on ARM and translated Intel, including that method. The separate 384-byte scalar-average reference matches exactly, as does the prior 3,072-byte neutral Photoshop refinement mask. That earlier reference does not establish mask-filter output parity.

The isolated Debug app and optimized universal ZIP pass checks for macOS 14 deployment metadata, entitlements, signatures and payloads. They remain unlaunched because the native automation connection still fails. Live preview/history/Close/Quit, wider filters, vector rasterization, compound masks, matte removal, exact Photoshop defaults/output, full S06 and earlier failures stay open. The readable index's missing 457–468 rows now link to their recorded entries. Work moves to channel workflows, followed by color adjustments.

[Guide](MASK_FILTER_TARGETS.md) · [Evidence](MASK_FILTER_TARGETS_468.json) · [Technical record](DEVLOG.md#dev-step-468).

<a id="dev-step-469"></a>

## 2026-11-07 — Step 469: large channel filters

Alpha, auxiliary spot and Quick Mask channels stopped at an 8-megapixel filter-preparation limit. Simply removing the check would have kept full-canvas heap loops. Preparation now maps numeric samples sparsely or through file-backed storage, then runs the existing basic filter kernels. The native Filter dialogs and channel API use the same path, with Preview, Cancel, Repeat and one Undo. Channel identity, display/spot metadata, original spot-gray planes, other channels and image pixels stay intact.

Before changing production code, two new tests captured 288 small programs from unchanged build 468. They cover three depths, three target types, eight filters, selection and display indication. All 442,368 captured bytes remain exact. A separate scalar calculation verifies 576 mean-output bytes. A real 8.39-megapixel Noise operation matches its frozen selected row, while sparse 300,000-by-300,000 channel tests verify seven constant filters, native/API history, persistence and standalone selections without image layers.

The first implementation run passed 70 of 72 tests. The two failures were new-test assumptions: normalized output compacted to a single 64 KB backed tile rather than remaining dense, and invalid filter values retained the existing channel API's HTTP422 response. Only those assertions changed. The repaired run passes all 72 methods, including 12 new methods; both implementation attempts have identical application hashes. Source, logs, products and the original assertions are retained.

The audit also found that the existing direct channel API accepted bounded Liquify although native channel dialogs excluded it. That path is preserved with its previous 8 MP bound and checked against the old dense preparation. It is not presented as a new native workspace. Wider families and printing plates remain separate work.

The isolated ARM64 Debug app passes macOS 14 deployment metadata, entitlements, signature and payload checks. It is unlaunched because native automation still fails. Optimized 469 joins a later stable batch; latest universal remains 468. Full C02, exact Photoshop defaults/filter output, live controls, dense physical capacity, platforms, 60 fps and earlier failures remain open. Work moves to document color modes and separations.

[Guide](CHANNEL_FILTER_CAPACITY.md) · [Evidence](CHANNEL_FILTER_CAPACITY_469.json) · [Technical record](DEVLOG.md#dev-step-469).

<a id="dev-step-470"></a>

## 2026-11-07 — Step 470: Split Channels

Split Channels was disabled in the Channels panel. It now prepares a grayscale document for each channel in a flat source, registers every output, then closes the original without saving. The source file is untouched. Outputs have fresh identities, empty history and no file association. Native Fill, Clear, Brush, Undo and grayscale native/PSD persistence are tested. Preparation reads channel numbers directly rather than sampling the rendered composite.

The API uses the same engine and publication path. It requires both document-transfer and document-closing permissions and replaces the source lease with all results together. Cancellation, revoked permissions/sharing, changed source/session/settings and document lifecycle checks prevent late publication. The eight-share limit applies to the final API set; native separation has no eight-document cap.

The first run passed 67 of 68 executed tests. A new grayscale numeric fixture had only one channel and correctly failed the selected minimum-two-channel policy. Six planned selectors also named a helper instead of the actual test class. The original attempt is retained. Adding a companion alpha to that Gray fixture and correcting selectors produced 74 passing Debug tests, including 15 new tests. Production and application hashes are identical before and after those test-only repairs. The same 74 tests pass in optimized ARM and translated Intel builds. All 416 component-word bytes match an independent literal calculation across all three runs, including float signed zero, subnormal and HDR samples.

Universal 470 passes deployment metadata, full entitlements, signature, archive extraction and payload checks. It remains unlaunched because native UI automation still reports a closed connection. Adobe documentation describes the intended lifecycle, but exact Photoshop context/spot eligibility, naming, profiles, metadata, defaults and Split output still need direct verification. Merge Channels, Merge Spot and the rest of COL02 remain unfinished. Dense physical capacity, supported machines/OS versions, 60 fps and earlier failures remain open. Work moves to proofing, HDR/EDR and print.

[Guide](CHANNEL_SEPARATION.md) · [Evidence](CHANNEL_SEPARATION_470.json) · [Technical record](DEVLOG.md#dev-step-470).

<a id="dev-step-471"></a>

## 2026-11-07 — Step 471: large soft proofs

Soft proofing rejected documents above 8 megapixels even though the canvas could hold larger images. Preparation now uses sparse/file-backed patches around the existing color proof engine. A constant evaluation represents implicit pixels; stored component and composite tiles supply the remaining patches. Native numbers and working profiles are retained. Proofing happens before area reduction, so the viewport and API overview average proofed colors and gamut warnings. The large native canvas image cache also receives the proofed image. Source pixels, history, dirty state and normal exports stay unchanged.

Before production edits, two new tests captured 104 programs from unchanged build 470. The baseline passes 17 selected tests and has the same application hash as 470. All 159,744 sample bytes and the separate 240-byte reduced preview remain exact through both the old and paged paths. The small proof-kernel body is unchanged. These are regression references made from owned samples, not independently captured Photoshop proof output.

The first implementation passes all 62 selected Debug tests. Two further tests cover custom Display P3 working profiles at 16 and 32 bits, plus maximum-size native Gray32/CMYK16 Preserve Numbers through the desktop and API. The final run passes all 64 tests, including 14 new tests; production and application hashes are identical between the two implementation runs. Patch boundaries, sparse 300,000-pixel dimensions and an allocated 8.39-megapixel source also pass. Every source, log and product is retained.

The isolated Debug app passes deployment metadata, full entitlements, signature and payload checks. It is unlaunched because native automation still reports a closed connection. Optimized 471 joins a later stable batch; latest universal remains 470. Printing still has its separate preparation limit, and HDR/EDR proof display remains unfinished. Exact Photoshop gamut algorithms/defaults, legacy/color-blind presets, PSF interchange, per-window behavior, live controls, supported machines, dense capacity, 60 fps and earlier failures remain open. Work moves to photo alignment and merging.

[Guide](LARGE_SOFT_PROOF.md) · [Evidence](LARGE_SOFT_PROOF_471.json) · [Technical record](DEVLOG.md#dev-step-471).

<a id="dev-step-472"></a>

## 2026-11-07 — Step 472: large image stacks

Statistics rejected a combined sample grid above 16 megapixels and more than 16 source frames. Preparation now evaluates implicit pixels once and processes stored sample support in file-backed patches. The eleven scalar operators are unchanged. Source order, visibility, masks, group treatment, transparent-sample exclusion and maximum alpha retain their previous behavior. Source photos remain editable in the Smart Object; mode switching, None, native saving and Undo use the same native and API implementation.

The native source picker follows the existing document-layer target. Automatic alignment keeps its separate limits, and HTTP creation keeps seven shared source slots plus one output slot. Source frames spill through the existing exact-copy Core operation before embedding. The native dialog reduces the finished result for display, without reducing input photos or changing the statistics.

The unchanged previous application first captured 99 programs across all eleven modes, three depths and three source arrangements. That baseline passes 10 tests. The first implementation build stopped at a missing `try` in a new Undo test; the next stopped at an internal renderer called across the module boundary. Both compile attempts and their cached products are retained. Preview preparation was moved into Imaging. The next run passes 43 of 44 methods; its new API test used the first source share instead of the new output share. That test address was corrected without changing production code. One request still raced the new window’s initial rendering; the test now waits for the existing tasks and fetches the public revision before editing. All failed runs remain recorded. The final 44 selected Debug tests pass, including 13 new tests. All 152,064 captured sample bytes remain exact, and the old small scalar loop is unchanged. Tests also cover 65 frames, a 17-source editable stack, maximum sparse geometry, an allocated 8.39 MP input and an owned source above 256 MiB.

All 44 selected checks pass on Apple Silicon and translated Intel. The broader batch passes 92 tests on Apple Silicon and 90 on Intel. Two Intel soft-proof reference tests still fail; the old and paged proof paths agree on Intel. Universal build 472 is an unreleased validation candidate. The latest fully qualified universal build remains 470. The isolated package is unlaunched. Live controls, full RAW02, independent Photoshop statistics pixels/defaults, complete alignment/blend/HDR workflows, physical capacity, supported machines, 60 fps and earlier failures remain open. These captured buffers establish regression retention; they do not establish Photoshop parity. Work moves to original PhotoCraft project migration.

[Guide](PAGED_IMAGE_STATISTICS.md) · [Evidence](PAGED_IMAGE_STATISTICS_472.json) · [Technical record](DEVLOG.md#dev-step-472).

<a id="dev-step-486"></a>

## 2026-11-07 — Step 486: Classic RGB16 gradient boundaries

Two samples in the retained Classic RGB16 Gradient Map corpus differed from Photoshop by one working level. An exact-rational interpolation experiment made the result worse, increasing the differences to six. Using a fused second multiplication and addition removes the linear mismatch and leaves the older curved sample open. The rule applies to every Classic RGB16 linear segment; it has no preset-name or sample-position exceptions.

The candidate was fixed before three new owned references were recalculated and saved in Photoshop. Their controls cover linear, partial-smoothness and curved gradients with opaque and partial-alpha rows. New core, native-file/PSD/PSB and native/API/history tests exercise the actual path. A separate public-format reader finds all 786,624 merged sample bytes exact in each Debug, optimized Apple Silicon and translated Intel variant: 2,359,872 checked bytes. This does not establish whole-PSD or all-gradient equality.

All 61 selected Debug tests pass. Optimized Apple Silicon passes 61/61; translated Intel passes 60/61. All three new methods pass on both. The remaining Legacy float-transfer vector170 failure has exactly the same values on the retained build485 Intel binary. Its test, fixture and failure remain; no tolerance was widened and the batch is not recorded as wholly passing.

The isolated universal app opens an owned two-layer RGB16 reference. Reverse, Command-Z and Command-Shift-Z edit and restore it with the expected dirty state. At 100% the strip stays within the canvas viewport. The restored document closes without a Save prompt and the app quits normally; older running apps remain. Minimum macOS14 metadata, unchanged entitlements, signatures, payload and extracted ZIP pass. The package is a validation candidate; build480 remains the latest fully qualified selected universal.

The record retains an initial zero-test filter error, genuine pre-repair failures, a private staging-driver path error and all repaired attempts. No original numeric fixture was changed. One prior linear-corpus allowance was tightened to require zero differences; the curved allowance remains. Native92, Actions60, commands, menus, keys and cursors are unchanged. API discovery documents the shared kernel and its remaining limits.

The requested disk cleanup removes 20 unused old secondary app extractions only after matching every file, mode, symlink and signature against a retained primary copy. It reclaims about 5.1 GB. Every primary/current/running/failed app, archive, source and GitHub item is retained. A failed first read-only verifier is also preserved. Separate model-runtime probes establish the next AI01 investigation without claiming model or Photoshop equivalence.

Full A06 remains open: Smooth, the curved residual, RGB32 fill bits, dither/profiles/defaults, physical platforms and performance still need work. Earlier API and Fill-modal failures remain. Next: AI01 on-device model infrastructure, then AI02. All original package requirements remain.

[Detailed record](DEVLOG.md#dev-step-486) · [Guide](CLASSIC_RGB16_BOUNDARIES.md) · [Evidence](CLASSIC_RGB16_BOUNDARIES_486.json)

<a id="dev-step-485"></a>

## 2026-11-07 — Step 485: sampled Hue/Saturation ranges

Photato rejected Photoshop files after a color was sampled in Hue/Saturation. The saved adjustment record contains the sampled swatch’s hue, saturation and lightness; our reader expected fully saturated swatches at fixed lightness.

Four owned Photoshop files cover plain orange sampling, adding green, subtracting orange and sampling gray. Two native regression tests reproduce the rejection. The repair stores those display values separately from the pixel adjustment. Native Properties uses the stored color, presets and PSD/PSB preserve it, and existing API settings can read, replace or clear it. Native files require version 92 and recorded Actions require version 60 when the new data is present. Older documents and recipes keep their previous minimum versions.

All 68 selected Debug tests and the same 68 optimized tests pass on Apple Silicon and translated Intel, including 14 new tests. A separate public-format reader checks 16 fresh and retained PSD/PSB exports per variant: all 6,528 adjustment-record bytes match the Photoshop references. The Hue/Saturation transfer code and old numerical fixtures are unchanged. This verifies the captured settings records, not every Photoshop image operation.

Failed attempts remain in the record. A relocated compiler cache prevented the first isolated build. A driver reused an exclusive receipt name. Later new-test repairs corrected an enum name, an expectation that a constrained range handle would pass its neighbor, and a selected-frame setup that contradicted the document. The application implementation stayed unchanged through those final test repairs. The qualified source was copied into the main project only after checkpoint 484’s audit finished; all 7,619 inputs match the tested copy.

In the actual universal app, the orange reference opens with a 37°/65%/50% swatch and the saved 352°/22°/52°/82° range. Changing the end to 60° changes the swatch hue to 41°, retaining saturation and lightness. History Undo restores the original values. After canvas focus, Command-Shift-Z and Command-Z redo and undo the edit and restore the clean document state. Accessibility button actions had left the numeric editor focused during the first shortcut attempt; that context is recorded separately. The gray reference opens with a 0°/0%/50% swatch. Both owned documents close unchanged and the validation app quits normally. Older running builds are preserved.

The universal candidate’s two architectures, macOS 14 minimum metadata, unchanged entitlements, signatures, payload and extracted ZIP pass. Full Hue/Saturation and Color Balance output fidelity, on-canvas sampling, prominent colors, targeted dragging, physical platforms, accessibility and 60 fps remain open. The older Fill modal and broader API failure remain unresolved. Build 480 remains the latest fully qualified selected universal. Next: A06 gradient and RGB32 fill differences, then AI01. All original package requirements remain.

[Detailed record](DEVLOG.md#dev-step-485) · [Guide](SAMPLED_HUE_RANGES.md) · [Evidence](SAMPLED_HUE_RANGES_485.json)

<a id="dev-step-484"></a>

## 2026-11-07 — Step 484: Quick Mask selection semantics

A full selection could disappear when leaving Quick Mask. Selected Areas also started with the wrong coverage when there was no selection, and selected-area PSD planes were interpreted as coverage rather than editing gray. These are distinct states, even when their pixels look similar.

Owned Photoshop documents establish the behavior for no selection, explicit full and partial selections, switching the display indication, and filling with Black through the dialog. Seven PSD fixtures are included with provenance. An earlier shortcut attempt saved white rather than black; it is retained as a diagnostic and is not used as the Black-fill reference.

The shared native/API commands now retain the selection origin and preserve explicit full selections. Selected Areas starts without an overlay when there is no selection. PSD/PSB readers and writers convert selected-area editing gray consistently, including auxiliary-only Multichannel files. Imported Float32 gray samples are retained separately because inversion loses some source bits. That retained data requires native format 91; older features keep their existing minimum versions.

The first baseline ran 18 checks: eight passed and ten exposed the defects. The first repair had a new-test compilation error. The next batch passed 60 of 64; two older expectations contradicted the new independent reference/version requirement, and two new tests had incorrect permission or sparse-metadata assumptions. The corrected source passes all 64 focused Debug checks and all 82 selected optimized checks per architecture, including 17 new methods. Failed attempts remain available. The 81 earlier auxiliary fixtures retain all 1,230,240 checked raw bytes per run. Eight finite Float32 source words survive native/PSD storage exactly across all three variants; that is not a claim about every Photoshop HDR operation.

The actual native app shows the expected red overlay when the indication changes with full coverage, a full selection on exit, and no overlay on fresh Selected Areas entry without a selection. The Fill check is incomplete. Selecting Black through accessibility stops exposing the dialog, but a process trace shows it still running in NSAlert.runModal. Keyboard cancellation, rebinding and window controls did not recover it through the available interface. It is not yet established whether this is an application defect or automation/window targeting. The owned temporary document and validation process are preserved; no successful Fill, Undo or normal quit is claimed.

The first final source check reported a mismatch in an older gradient-map fixture. Immediate rereads matched the frozen hash; no file was rewritten. A separate full rerun passes all 7,608 inputs. The failed check is retained and its cause remains unknown.

The universal candidate has both architectures, macOS 14 minimum metadata, unchanged entitlements, verified signatures and an exact extracted ZIP. Native API discovery and download negotiation describe the updated semantics and retained data. Factory menus, shortcuts and cursor policy are unchanged. Full S05, earlier failures, dense maximum-size documents, physical platforms, accessibility and 60 fps remain open. Build 480 remains the latest fully qualified selected universal. Next: A02 Hue/Saturation and Color Balance, then A06.

[Development record](DEVLOG.md#dev-step-484) · [Guide](QUICK_MASK_SEMANTICS.md) · [Evidence](QUICK_MASK_SEMANTICS_484.json)

<a id="dev-step-483"></a>

## 2026-11-07 — Step 483: Script Events Manager

Photato can now run a recorded Action when a document is created or opened. File > Scripts > Script Events Manager has Enable, a registration table, event and Action pickers, Add, Remove, Remove All and Done. Configuration saves as it changes and starts disabled. Scripts and the other listed application events remain unavailable.

The manager uses the existing native Actions engine. Events wait for opening to finish, then run in order. Each Action has its normal Undo. Changes to the document, Action library, configuration or document lifecycle reject stale work before it commits. Recovery and focusing an already-open document do not run the event again. Earlier completed Actions remain undoable if a later Action fails.

The optional API exposes the same configuration and results through GET/POST /v1/automation/events. Its separate permission explains that registrations can affect unshared documents. That permission also protects edits to registered Actions, including temporarily disabled registrations. Stopping the API resets permission; it does not erase saved native event configuration. Complete request, state and result schemas are included. This endpoint does not implement an Adobe script runtime or desktop plug-in host.

The first attempt compiled the app but failed to compile a new test that tried to assign a read-only document property. The repaired test uses a real edit. Later source review caught a startup wiring issue that would have kept normal registrations only in memory; the actual startup factory was corrected and tested. An API review then found that ordinary Action editing could bypass the new permission, so registered Action edits were fenced and tested. Every attempt and its products are retained.

All 58 focused Debug checks and the same 58 optimized checks pass on Apple Silicon and translated Intel, including 20 new tests. Nine event-versus-manual native, PSD and PNG files across 8/16/32-bit depth match across all three variants: 14,470 bytes each. Those comparisons test our own shared engine; they do not establish Photoshop pixel equivalence.

The broader optimized batch passes 128 of 129 methods on each architecture. One old API check expects HTTP422 and receives400. The unchanged test fails the same way on the retained build480 binaries. Its assertion was preserved. Build483 is a validation candidate, while480 remains the latest fully qualified selected universal. The universal candidate’s minimum-system metadata, architectures, entitlements, signature and extracted ZIP were checked.

In the actual native candidate, an Invert Action was recorded, registered for New Document and run automatically on a white canvas. The canvas became black; Command-Z restored white. Reopening the manager showed one completed Action. Shrinking the manager retained Done and exposed scrolling. The owned registration was removed and disabled; the test documents were restored and the validation app quit normally. The older running builds were preserved. Screenshots are in the chat transcript; no local screenshot file is claimed.

Photoshop27.2 supplied the observed manager controls; its original empty, disabled configuration was restored and rechecked. Exact event timing/order/defaults, live OpenDocument, physical supported-platform and accessibility coverage remain open. Photoshop plug-ins remain unsupported: native C++, UXP and CEP require separate hosting work under AUT03. The HTTP API does not provide that hosting.

No source was published, app installed over a current build, build deleted, Store record changed or software released. All original package requirements remain. Next: S05 channels, then A02 adjustments.

[Development record](DEVLOG.md#dev-step-483) · [Guide](SCRIPT_EVENT_ACTIONS.md) · [Evidence](SCRIPT_EVENT_ACTIONS_483.json)

<a id="dev-step-482"></a>

## 2026-11-07 — Menu inventory reconciliation

The saved menu CSV had fallen behind the app. It listed 802 entries; the verified Apple Silicon and translated Intel captures both contained 809. Seven paths were missing and 88 selector bindings were stale. The replacement CSV comes from those captures, with the old file and proposed replacement retained. Its labels distinguish submenus, partial native operations and disabled placeholders.

A new reconciliation script checks the captures against the current native source, tests, fixtures, assets and project files. It requires matching architecture reports, the original Photoshop menu order and factory shortcuts, consistent command identities and statuses, and all 16 modifier combinations for each captured main tool. It refuses existing report files and output locations inside product or tooling directories. It writes a proposed CSV for review rather than replacing the tracked inventory itself.

Twenty new tests passed first. Combined with the archive-tool tests, 36 passed. A further output-location guard and test were added; all 37 then passed, including 21 new inventory tests. The original failed drift report is retained alongside the corrected passing report. The manual CI template now discovers both test files and retains their fixture folders; it has not been dispatched.

The measured inventories are 652 tracked commands, 809 menu entries, 55 main tools with 880 modifier contexts, and 40 professional acceptance scenarios. The commands remain 459 partial and 193 pending. Every professional scenario remains planned. These counts describe different things and do not provide a Photoshop completion percentage.

The original 801-entry Photoshop menu fixture and all 102 primary and eight alternate shortcuts are unchanged. Later Adobe commands and Photato-specific additions remain separate. Installed Photoshop is 27.2; Adobe's documentation also describes 27.11 features, betas, services and platform-specific behavior. The records distinguish those references and preserve the gaps, including plug-in hosting.

Application build 480 and all 7,499 native product inputs match the captured source. No editing code, native control, numerical fixture, entitlement or product API changed. No new application build, live UI check, full-suite run or archive is claimed. All original package requirements remain open where unqualified. Next: AUT02 automation, then S05.

[Development record](DEVLOG.md#dev-step-482) · [Evidence](INVENTORY_RECONCILIATION_482.json)

<a id="dev-step-481"></a>

## 2026-11-07 — Repeatable archive validation

The package checker still used fixed build paths and historical test counts. We retained it and added a separate archive validator that takes an explicit archive, source manifest and new report path. It checks production identity and version, both architectures targeting macOS 14, required resources and an exact executable/dSYM UUID match for each architecture.

A new local pipeline runs the tool tests and the selected editing checks, creates an unsigned universal archive through the existing Xcode project, verifies it, and compares its ZIP extraction with the original. It preserves logs and failed outputs, detects source changes and refuses existing output directories. Capacity checks stop it before another step if disk space is low. Existing builds are retained.

Sixteen new tests use real Swift-built ARM and Intel executables and dSYMs, plus damaged copies. They check missing or mismatched symbols, stale metadata, altered resources, source mutations, unsafe release settings, path escapes and report overwrite refusal. The first private runner failed to parse before any test started; its source and error remain in the record. The tool tests then passed twice before the full pipeline run.

The pipeline exposed an old menu test writing a report into the source checkout. It now uses the existing capture-directory setting when supplied and creates the destination. All original menu, shortcut and row assertions are retained; the fallback output path remains available.

The complete local run passes: 16 tool tests, all 104 selected editing checks on Apple Silicon and translated Intel, and 34 archive checks. Both dSYM UUIDs match their binaries; every extracted archive file matches the verified original. The seven controlled lookup cases still retain all 1,474,560 original Photoshop RGB bytes on each architecture.

The application remains build 480. No editing algorithm, native control, API, menu, shortcut, cursor, fixture, entitlement or project setting changed. The archive is unsigned and unlaunched. A manual-only GitHub workflow template is prepared with pinned official actions and read-only repository permission; it has not been installed in the public fork or dispatched. Signing, Apple validation, actual sandbox behavior, privacy declarations, hosted execution and full REL01 remain open. No software was uploaded, submitted or released.

Next: AUD01 inventory reconciliation, followed by AUT02 automation workflows. Full Photoshop parity remains open.

[Development record](DEVLOG.md#dev-step-481) · [Evidence](ARCHIVE_VALIDATION_481.json)

<a id="dev-step-480"></a>

## 2026-11-07 — Independent Color Lookup references

We created our own patch images and two small Cube lookup tables, then saved editable results in Photoshop at 8, 16 and 32 bits. A second 8-bit image used odd-valued samples to distinguish rounding rules. A separate Python parser extracted the saved composite planes; Photato's renderer did not produce the expected data.

Those files exposed differences our earlier self-comparisons missed. Native creation and Reset now use Tetrahedral interpolation. The 8-bit path uses the observed working-code conversion, while 32-bit lookup edits retain linear samples. The interpolation expression also needed a different evaluation order to preserve low Float32 bits. Old documents and omitted Photato API parameters retain their explicit Trilinear choice.

The PSD reader previously rejected Photoshop's embedded lookup cache. It now accepts a bounded float CLUT only when its values exactly match the embedded table. The writer needed repair too: Photoshop rejected a fresh export after all pixel tests passed. Live diagnostic files isolated the descriptor's declared padding and required cache. Fresh exports now contain correctly framed records, the proper name field and a newly encoded cache with Photato metadata. No proprietary Adobe lookup or cache implementation was copied.

All 95 selected Debug checks and the same optimized checks on Apple Silicon and translated Intel pass, including 16 new methods. All 1,474,560 reference RGB bytes match through editable and destructive native editing code, Photato HTTP and both action-job routes. Structure, source-table retention, cancellation, Undo/Redo, guards, file transfers, menus and cursors are tested separately. Nine additional auxiliary-channel and PSD-transfer checks also pass in Debug and both optimized architectures. Earlier failed sources, compile errors, incorrect test headers and selectors, and rejected native files remain in the record.

Photoshop opened fresh Cube3 exports at RGB8, RGB16 and RGB32 without warnings. We toggled Dither on and off, saved separate copies and independently compared them with the original references: all 688,128 RGB bytes matched. Those derived files verify interchange; they do not replace the original independent oracles.

The selected lookup increment is complete; Q04 and full Photoshop parity remain open. Other modes, profiles, LUTs, domains, shapers, masks, blends, stochastic Dither, wider files, physical platforms, 60 fps and full-suite qualification still need work. The universal validation package is unlaunched and unreleased. Next: REL01 archive, sandbox and release CI, followed by AUD01 inventory reconciliation.

[Development record](DEVLOG.md#dev-step-480) · [Evidence](INDEPENDENT_COLOR_LOOKUP_480.json)

<a id="dev-step-479"></a>

## 2026-11-07 — Color Lookup property responsiveness

Editing a Color Lookup layer used the synchronous command path, including full document validation. Properties now sends that preparation to the existing background worker. The controls disable competing edits and offer progress and Cancel. Publication, Undo history and dirty notifications stay on the main actor; cancellation or a replaced/closed document discards unfinished work.

The LUT and pixel kernels are unchanged. Tests compare the resulting document, native file and rendering with the former expression and the API at every supported depth. They also check masks, Undo/Redo, recorded Actions, locks, invalid tables, busy/modal/transform/component targets and stale/cancelled work. Two older tests await completion before their original assertions. The first compile caught a new test attempting a private setter; the failed source and products remain preserved. The first implementation shortened submission but left main-actor timer gaps unchanged. A sampled run found repeated sorting of unchanged raster keys in document comparisons. A positive shared-storage identity proof now skips that work while preserving the original logical pixel-bit fallback. Four new Core tests and the existing surface, mapped storage, validation and serialization suites cover the change.

The benchmark measures 20 edits for each combination of three document cases and two LUT sizes. It uses owned dense gradients, fresh sessions and excludes initial/final rendering. The first two multi-layer fixtures exceeded Photato’s counted raster budget and measured rejection; those failed runs are retained. The corrected 32-layer case uses 1024 × 1024 images and validates before timing. The other cases are 24 MP and 36 MP single-image-layer documents.

All 161 selected Debug checks and the same optimized checks on Apple Silicon and translated Intel pass, including twelve new correctness checks. The separate benchmark records submission, completion and a main-actor timer. Exact measurements and their limits are in the evidence record. Faster submission is useful, but does not prove physical input latency, sustained painting or 60 fps. History spilling/rendering, the existing raster budget, broader platforms and full Q03 remain open.

Next: independent Photoshop references, then release-readiness work. The master goal remains active and incomplete.

[Guide](LOOKUP_PROPERTY_RESPONSIVENESS.md) · [Evidence](LOOKUP_PROPERTY_RESPONSIVENESS_479.json) · [Detailed record](DEVLOG.md#dev-step-479)

<a id="dev-step-478"></a>

## 2026-11-07 — Local Color Lookup painting

Photoshop’s current Adjustment Brush menu includes Color Lookup. Photato already had a LUT engine and layer editor, but its brush type list omitted it. That prevented painting a local LUT adjustment through the tool. The existing native picker and validation now accept it, and Properties keeps the lookup file, interpolation and Dither editable.

Painting creates or refines the same masked adjustment layer. Preview/Cancel, Add/Subtract, object masks and Undo/Redo keep their existing transaction path. The API can use an uploaded lookup or a Photato Look, retain the embedded table during partial edits, or explicitly clear it. Clearing an API cache does not change a table already in a layer.

Portable Actions 59 records the new brush operation with its table, so replay does not depend on an upload session. Earlier action minima and native lookup layer storage remain. Native creation currently uses an identity lookup. The reference’s filmstock_50.3dl setting was observed in its current context, not established as a factory default; no Adobe lookup assets were bundled.

The first compile caught a malformed schema literal and an attempt to call a command initializer that does not exist. The failed source/logs and cached477 products were retained. The fix split the schema and reused the existing strict lookup parameter resolver directly. All 94 selected Debug checks and the same94 optimized checks on Apple Silicon and translated Intel pass, including 8 new checks. 38 older tests advance only their global supported Actions-ceiling expectation from 58 to 59; per-feature version gates and numerical/sample checks remain intact.

Live reference inspection used an owned synthetic photo. The test stroke was undone, the original tool selection restored and the photo closed without saving. It also exposed Photoshop’s newer Color and vibrance option; its semantics need separate investigation. The current native validation package is verified and unlaunched. Native-code gestures are tested; current physical interaction and exact Photoshop pixels remain unqualified.

Full lookup formats/defaults/interpolation/dither/profile output, saved Tool Presets, large object masks, physical platforms, performance and the original B08 scope remain open. Next: responsiveness and cancellation, then independent reference coverage.

[Guide](ADJUSTMENT_BRUSH_LOOKUP.md) · [Evidence](ADJUSTMENT_BRUSH_LOOKUP_478.json) · [Detailed record](DEVLOG.md#dev-step-478)

<a id="dev-step-477"></a>

## 2026-11-07 — Sky preset groups and batch import

The sky library was a flat list, and native Import accepted one image. It now stores named groups and image memberships, with controls to create, rename and remove groups, filter the list and move a sky. Removing a group requires a choice: keep its images in Ungrouped, or remove them from the library. Layers already in a document retain their pixels.

Import accepts several images and validates the whole batch before saving any. An invalid image, storage/capacity failure, cancellation or changed library/selection prevents partial publication. The API exposes the same operations and returns groups and memberships. Library management leaves document pixels, selection and Undo history unchanged.

Version 1 libraries open without being rewritten. Their next successful edit stores version 2 while retaining image IDs, names and original bytes. Unknown versions and corrupt files stay preserved. The internal format is separate from Adobe `.sky` files.

The first compile caught an initializer using a field before the observed object was fully initialized. Its source, logs and cached476 products were retained before repair. The private test runner also needed module-qualified test names; no tests had run before the compile failed. The corrected source passes all 51 selected Debug methods and the same51 optimized methods on Apple Silicon and translated Intel, including 9 new methods. Existing sky, menu/cursor and independent RGB32 checks pass. No prior numerical fixture or tolerance was changed; older float32 sky flattening differences remain recorded.

The owned offscreen view shows the added controls fitting its scrolling sidebar. Live Photoshop inspection now opens Sky Replacement on an owned synthetic photo and shows its thumbnail gallery and an existing Blue Skies group. On that input Photoshop shows Foreground Lighting 48 and Edge Lighting 70, while Photato currently initializes 50 and 0. These are observed context values, not proven factory defaults; automatic initialization and exact output remain open. The preview was cancelled and the owned photo closed unchanged. This does not qualify current Photato live interactions. The universal validation package is verified and unlaunched.

Large sky canvases/masks, exact Photoshop detection/output/defaults/layer structure, `.sky` transport, recents/default skies, wider library organization, live controls, physical platforms/performance and full AI09 remain open. Next: Adjustment Brush, then Q03.

[Guide](SKY_PRESET_GROUPS.md) · [Evidence](SKY_PRESET_GROUPS_477.json) · [Detailed record](DEVLOG.md#dev-step-477)

<a id="dev-step-476"></a>

## 2026-11-07 — Blank video drawing layers

Video-frame painting already existed, but the New Blank Video Layer command was unavailable. This workflow adds separate drawing footage for animation and rotoscoping. The Layer menu, Timeline menu and video.edit API now create the same transparent clip with one Undo step.

A dense frame array would impose the existing imported-media limit on empty drawing footage. The new collection stores one prototype and only frames that differ from it. Logical indexing stays constant-time; validation, archive and memory accounting visit stored samples. Existing imported clips keep their old array encoding and decode budgets. Native version 90 retains sparse footage, including sources kept during animation conversion.

The first compile caught an old fixture assigning an array directly to the changed collection type. Two old test expressions now wrap the same expected surfaces; their values and assertions remain. The first retained executable was still cached from build 475, and its initial origin label was corrected rather than counted as a new pass. Later runs pass the full selected suite. Recovery-header checks also cover indexed versions 89 and 90.

All 111 selected Debug methods and the same 111 optimized methods on Apple Silicon and translated Intel pass, including 13 new tests. These cover native/API creation, exact brush results, gesture preview/Cancel/commit, neighbouring-frame isolation, history, file/conversion recovery, strict parameters, busy/stale/mask contexts and explicit native90 downloads. Existing video/rendering, menu/cursor and independent RGB32 regressions pass.

An owned 300,000 × 300,000 canvas with a 24-hour timeline at 240 fps keeps one empty stored frame and remains below the tested document/archive storage bounds. This is a logical storage test, not dense-capacity or 60 fps proof. The selected native universal package is verified and unlaunched. Live native inspection remains unavailable.

Photoshop’s exact creation defaults and group placement, additional frame/source editing, footage interpretation/replacement, longer imported media, codec/HDR/interchange, physical platforms, performance and the full SP01 scope remain open. Sky Replacement is next, followed by Adjustment Brush.

[Guide](BLANK_VIDEO_LAYERS.md) · [Evidence](BLANK_VIDEO_LAYERS_476.json) · [Detailed record](DEVLOG.md#dev-step-476)

<a id="dev-step-475"></a>

## 2026-11-07 — Generated image jobs and saved originals

The old system-image callback used the current document and a mutable prompt. It now captures a request ID, initial prompt and document revision before opening the system interface. Cancel, close, duplicate and late callbacks share that identity; one accepted placement is one Undo step.

Returned originals are saved atomically before decoding or placement. A separate Generated Results window can recover them after the source changes or closes. It opens a new unsaved document without a model. Explicit Move to Trash is the only removal action; the inbox has file/count/byte limits and no automatic purge. Native archives keep original bytes and descriptive records with generated layers.

The API exposes the same job, records, original downloads and saved-result recovery. Private-inbox access is tied to the real document session, so imported UUIDs cannot grant access. Preparation opens the native prompt sheet and never starts a model from HTTP. File transfers and local Trash have separate permissions and revision/lifecycle checks.

Tests found an invalid metadata-key length and a physical-path mismatch in the new inbox. The metadata now follows the existing four-byte Core contract. A POSIX path resolves the macOS /var alias for the unchanged strict atomic writer after Foundation resolution failed to do so. Testing also caught a surviving closed document still permitting another image request; closing now disables that source, and the API reports eligibility.

A new fixture closed an unregistered document before creating Photato’s custom AppKit document controller. The debugger caught a nil paint palette when a later test published a recovered document. The fixture now follows application startup and registers its document before closure. The complete selected batch passes afterward on unchanged production code. Failed attempts remain in the record; this does not explain or close every earlier crash.

All 67 selected optimized methods pass on Apple Silicon and translated Intel, including 30 new methods. Source09 passes 67 focused Debug methods. Storage failure, interrupted publication, corruption, quotas, symlinks, stale/failed/cancelled/closed placement, native archive reopening and API session/permission behavior are covered with owned images. Existing menu/cursor checks and independent RGB32 regressions pass in the optimized batches. No model was invoked.

The SDK does not provide typed model, seed or final edited-prompt fields, so those remain unknown. Original file metadata is retained but not interpreted or independently qualified. Full variations, generative workflows, provider/native live checks, physical-platform/performance qualification, exact Photoshop output/defaults and the complete AI07 package remain open. The next selected package is SP01.

Photoshop plugins do not run in this build. Matching menus or the Firefly web API does not supply Adobe’s desktop plugin interfaces. AUT03 remains open.

[Guide](AI_GENERATION_LIFECYCLE.md) · [Evidence](AI_GENERATION_LIFECYCLE_475.json) · [Detailed record](DEVLOG.md#dev-step-475)

<a id="dev-step-474"></a>

## 2026-11-07 — OpenEXR HDR files

The file-format audit found that layered TIFF and several PDF export paths already worked. OpenEXR was missing. An Apple encoder probe wrote Half samples from 32-bit input, so the new file codec follows the public ASWF layout directly, using Swift and system ZIP compression. It preserves tested negative, above-white and zero-alpha colors without SDR tone mapping.

Open, Save, Save a Copy and API file transfers now share this codec. The save dialog offers compression, precision and transparency. Ordinary Save rejects choices that would discard editable content, remove meaningful alpha, reduce precision or convert the working profile. Copy makes those choices explicit. EXR output avoids the old 36-megapixel dense-raster Save guard; broader size and workspace limits remain.

The first compile caught a new test calling a nonexistent helper. Debug batches later crashed in shared revision/native paths; isolated replays against the same retained binary passed, without establishing a cause or repair. The first optimized run passed 94 of 96 checks on Apple Silicon. The remaining two fixtures needed the new format title and the required API replacement field. Intel compilation exposed unavailable Float16 conversions. Native Swift bit conversion now handles Half on both architectures, with independent reference words for every finite pattern.

The final optimized batch passes all 97 selected checks on Apple Silicon and translated Intel, including all 14 new tests. Seven captured EXR files match across architectures; an independent Python reader verifies 6,168 sample bytes each. The validation-only universal package passes minimum-system, entitlement, signature, payload and extracted-archive checks. It has not been installed or released.

These are owned synthetic format references, not Photoshop-generated EXR results. Other EXR compression, tiled/deep/multipart/AOV files, wider profiles/metadata, dense maximum capacity, live controls, exact Photoshop defaults/output and all earlier failures remain open. The complete I04 package remains in progress. Next is AI07, then SP01.

[Guide](OPENEXR.md) · [Evidence](OPENEXR_474.json) · [Detailed record](DEVLOG.md#dev-step-474)

<a id="dev-step-473"></a>

## 2026-11-07 — Step 473: embedded originals in source projects

The source importer rejected every linked Smart Object, including references to originals already embedded in project metadata. The import now looks up those embedded records with the existing native linked-data decoder. Original bytes, shared identity, placement, filters and retained appearance remain separate editable data. External records, aliases, missing sources, duplicates and malformed data reject without opening archive-supplied paths. Unrelated globals remain source provenance.

Nine owned fixture derivatives cover affine placement, shared sources and statistical modes at three depths. Before production changes, build472 rejected them even though the native block decoder could recover every original. Their 737,280 cache bytes were captured and remain exact after migration. The original payloads also match exactly. Native Open, Edit Contents, shared-child updates, Undo, Save As and API upload/download/rasterization tests pass. Imports cannot overwrite the original source project.

All 11 new tests pass. The broader run has 41 planned checks: 39 pass, an older uncached-render method retains nine original-Rust assertions, and an older nested-source HTTP test crashes by signal10. The same crash reproduces in preserved build472; the uncached changed-word report is identical before and after this change. The 22 checks skipped after the crash pass separately with unchanged sources and application bytes. Every attempt and product is retained; no old assertion, fixture or numerical kernel was changed.

The isolated Debug app passes macOS14 metadata, entitlements, signature and payload checks. Native automation still reports a closed connection, so the app is unlaunched and live checking remains pending. Optimized473 joins a later batch. Full I03, additional source formats/features, independent Photoshop output/defaults, physical capacity, supported machines, 60 fps and earlier failures remain open. Work moves to export and interchange formats.

[Guide](PCRAFT_LINKED_ORIGINALS.md) · [Evidence](PCRAFT_LINKED_ORIGINALS_473.json) · [Technical record](DEVLOG.md#dev-step-473).
