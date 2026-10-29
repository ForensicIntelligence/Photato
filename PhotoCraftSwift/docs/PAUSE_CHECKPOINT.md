# Photato — pause checkpoint, 0.2.0 (build 2)

The user explicitly requested: **“Pause after the next minor version increment. But remember exactly where you were and what you were doing.”** Version 0.2.0, build 2 is that increment. Stop here and resume development only when the user asks. The goal is paused, not achieved. No further feature was started for this release.

## Exact stopping point

Development step058 completed native Normal raster **Merge Down / Merge Layers (Command-E)** and **Merge Visible (Shift-Command-E)**. Its full tests, optimized tests, package checks, live keyboard/undo workflows and independent Photoshop pixel comparisons all passed. Step059 changes only bundle version metadata from 0.1.0/build1 to 0.2.0/build2, packages the same tested Swift code, and records this handoff. There is no unfinished code edit or running test to resume.

Workspace: `/Users/johnczlonka/Desktop/notadobe`.
Native project: `/Users/johnczlonka/Desktop/notadobe/notphotoshop/PhotoCraftSwift`.
Rust reference: `/Users/johnczlonka/Desktop/notadobe/notphotoshop/photocraft-main`.

Current output: `build/Photato.app` and `build/Photato.zip`. The app is universal arm64/x86_64, with macOS14 minimum. The clean extracted package has a verified ad-hoc signature. It has not been published, notarized or submitted to the App Store. The native subtree is untracked in the enclosing repository; no source commit or upstream-history fork has been created. Preserve the original Rust source and licenses.

- [Step059 version/package evidence](../artifacts/runs/20261009T014041Z-059-minor-release-pause/release-verification.json)
- [Step058 implementation and full verification](../artifacts/runs/20261009T004847Z-058-layer-merging/release-verification.json)
- [Exact 265 tested Swift hashes](../artifacts/runs/20261009T014041Z-059-minor-release-pause/tested-source-hashes.json)
- [Development narrative](DEVLOG.md#dev-step-059), [complete status](STATUS.md), [porting plan](PORTING_PLAN.md), [command matrix](COMMAND_PARITY.csv)

Version-only verification inherits the unchanged step058 code tests: **586 full tests**, zero failures/skips, 108.783 seconds; **133 optimized focused tests**, zero failures/skips, 3.453 seconds. Do not describe them as rerun for step059. There are **138 application Swift files and 127 test Swift files**. Archive format remains v8, reading v1–v8; semantic app version and archive version are separate.

## What was just implemented

- `Sources/PhotoCraftCore/NormalLayerComposite.swift`: independently measured depth-specific Normal raster composition, using integer working grids and fused Float32 operations.
- `Sources/PhotoCraftCore/LayerMerge.swift`: merge planning, bounds, raster generation, metadata, cancellation and atomic document replacement. Root-level, unlocked Normal raster layers without masks/affine transforms only. Groups/clipping, rich layers, locks and entirely transparent results are unsupported.
- `Sources/PhotoCraftCore/Engine.swift`: `.mergeLayers(Set<UUID>, LayerMergeOperation)` and history labels.
- `Sources/PhotoCraft/LayerMergeEditing.swift`: menu validation, dynamic Down/selected routing and asynchronous prepared edits, active selection restoration after success.
- `Sources/PhotoCraft/PhotoshopMenus.swift` and `Application.swift`: command bindings and dynamic Merge Down/Merge Layers title.
- `Tests/PhotoCraftCoreTests/LayerMergeTests.swift`, `Tests/PhotoCraftImagingTests/LayerMergeRenderTests.swift`, `Tests/PhotoCraftAppTests/LayerMergeWorkflowTests.swift`: nine new tests. Existing menu test updated to expect the newly connected Merge Visible action.

Merge Down retains the immediate lower visible layer name/id. If that immediate layer is hidden, the command is disabled and the menu reads Merge Layers. Selected merging keeps the top selected visible name, removes selected hidden layers and retains off-canvas pixels. Merge Visible clips to the canvas, replaces the active visible layer at its stack position, and retains hidden layers. Nonempty results trim transparent bounds. Pixel selection is retained as a native invariant; independent Photoshop selection/history qualification is still needed. All operations use one undo transaction with stale-result/cancellation protection.

**Flatten Image remains disabled.** Do not equate the existing ordinary raster named Background with Photoshop's actual Background semantics.

## Independent evidence and arithmetic to preserve

[Merge reference manifest](LAYER_MERGE_REFERENCES.json) records **34 original procedural Photoshop-saved PSDs**, their hashes, original inputs, fixtures and limitations. Research and immutable attempt logs live in `artifacts/runs/20261009T004847Z-058-layer-merging/`. The independent decoder is `inspect-probes.py`; `inspection-07.json` is the latest full corpus decode. Failed earlier arithmetic and malformed RGB32 inputs are retained intentionally.

Four 65,536-pixel matrices cover RGB8, RGB16, RGB32 and RGB8 top opacity 60%. **262,144 raw RGBA kernel outputs match exactly.** These are independent saved Photoshop samples, not values generated by the Swift implementation. Test resources are original procedural content under MIT OR Apache-2.0 and are excluded from the app.

Integer composition uses M=255 (RGB8) or M=32768 (RGB16 working grid). Convert stored RGB16 samples with `(stored*32768+32767)/65535`. Scale source alpha by the byte layer opacity with round-to-nearest. Then:

```
Ao = Sa + Ba - (Ba*Sa + M/2)/M
q  = Ao == 0 ? 0 : min(M, (Sa*M + Ao/2)/Ao)
C  = (source*q + backdrop*(M-q) + M/2)/M
RGB16 stored = (working*65535 + 16384)/32768
```

Do not rewrite alpha as `Sa + round(Ba*(1-Sa))`: exact RGB16 half-product ties differ.

RGB32 kernel inputs/outputs are **linear** Float32. `Ao = (Sa+Ba).addingProduct(-Ba, Sa)`; `q = Ao == 0 ? 1 : Sa/Ao`; color is `backdrop.addingProduct(source-backdrop,q)`. When source alpha is exactly one, use source RGB directly **but still compute alpha with the measured FMA**. Returning constant alpha one caused a preserved regression. Integer both-zero-alpha samples retain backdrop hidden RGB; the measured float case uses source hidden RGB.

Native stored RGB32 is sRGB-encoded. Its encoded/linear conversion is not bit-reversible. Raw linear kernel exactness does **not** establish native RGB32 PSD RGB byte equality. Workflow tests qualify exact float alpha and a 0.00001 encoded color bound. Additional float/16-bit opacity, HDR edge cases and more contexts remain unqualified.

**The general renderer is unchanged** and still uses the prior floating-point blend math. Only merge transactions use the new kernel. Preserve the independent 972-vector Rust blend oracle; changes to the renderer should be qualified against Photoshop without silently rewriting those expectations.

Three live RGB8 packaged exports match every stored layer RGBA sample and **67,072 merged canvas pixels**. The 256×256 matrix verifies Command-E/undo. Hidden/off-canvas probes verify Shift-Command-E and selected Command-E, name/order/bounds, hidden layer retention/discard and undo. Relevant files: `native-live-pixel-comparison.json`, `native-live-observations.json`, `native-layer-menu-down.txt`, `native-layer-menu-hidden.txt`, `photato-live-{down,visible,selected}.psd`.

## Failures and pitfalls already resolved or recorded

- RGB32 procedural PSD inputs initially used two-byte Lr32 padding. `inputs-03` uses required four-byte padding; only that corrected new RGB32 matrix was acquired successfully. Integer new matrices use `inputs-02`. Do not use failed RGB32 inputs as qualified references.
- The hand-authored native geometry test archive initially serialized Python Double opacity 0.6. The Swift plist Float decoder rejects it as nonrepresentable. The separately named `live-geometry-hidden-rgb8-02.pcswift` stores exact Float32 opacity. The failed original remains. This was a test-fixture repair, not a production source change.
- Native automatic saving rewrote the two successfully opened disposable archives even after undo. Their original creation hashes are historical, not current byte-equality claims. `post-live-inputs/`, `live-input-post-check.json` and `post-live-input-verification.json` show restored samples/bounds/names/visibility/opacity all match the original independent inputs. User Photoshop documents were not modified.
- Desktop may re-add root FinderInfo after copying/signing an app. Keep staged clean ZIP evidence independent. Step058's bounded retry succeeded; step059 package also verifies. If it recurs, inspect attributes and preserve failed attempts before a targeted repair. Do not silently relabel a failed build as an initial pass.
- CUA menus can remain in accessibility state after Escape; invoke the observed Cancel action. File-picker indices and state can change during transitions. Re-read before using indices, verify the entire Go To path, and inspect alerts. Preserve failures; never replay blind actions.
- Existing RasterDecodeBudget Sendable and SwiftPM build-system deprecation warnings remain. Intel/macOS14/macOS26 runtime testing is still unqualified on this Apple Silicon/macOS27 host, despite universal compilation.

## Where to resume

Start by reading this file, AGENTS.md, CONTRIBUTING.md, STATUS.md and the newest DEVLOG entries; verify source hashes and working state. The last feature boundary is step058, and the next development step should follow step059. Do not repeat completed acquisition or test runs without a change or unresolved concern that warrants them.

Immediate pending work was **general Normal-compositor fidelity, richer merge contexts, and true Background/locks followed by Flatten Image**. No implementation of those follow-ups has started:

1. Qualify the new Normal kernel in the general renderer, including initial transparent backdrops, multiple layers, opacity, masks, groups and off-canvas bounds. Do not assume adopting it wholesale preserves all existing render workflows. Close the separate encoded/linear float boundary before claiming RGB32 byte identity.
2. Add explicit Background semantics and independent transparency/pixel/position locks. `Layer` in `Document.swift` currently has only a whole-layer `locked` Bool; PSD protected-transparency/lspf import collapses distinctions. Photoshop Background remains paintable, is opaque/canvas-sized, has RGB channels without a transparency channel, and needs proper convert/unlock/erase/clear behavior and persistence/export. Decide the archive migration only after defining these semantics.
3. Implement Flatten Image as an atomic operation after that model exists: composite visible layers over white, discard hidden layers only through the observed confirmation flow, create the actual Background result, and verify undo/cancellation/selection. Original flatten and Background-plus-empty-layer PSD references already exist in step058.
4. Extend merges to masks, non-Normal blends, groups/clipping, transformed/rich layers, locked/empty/hidden-active cases using fresh independent Photoshop observations. Continue the wider command/preferences/workflow backlog afterward.

These pending tasks do not replace the overall success criterion. Full Photoshop2026 functionality, byte-identical results, matching default shortcuts/settings and 100% native Swift remain unfinished.

## Persistent product requirements

Photato is the application name, using the maintainer-supplied icon. Preserve open-source attribution and the intended upstream Rust fork. Full PhotoCraft parity is intermediate, not final. Use native Swift and Apple frameworks, universal macOS14+ editing; optional Apple Silicon/macOS26+ on-device AI and authorized Private Cloud Compute. Do not label cloud image generation on-device or silently add external providers. App Store support/donations use optional IAP; no payment destination/product enrollment was invented.

Photoshop Defaults menus and shortcuts are the launch baseline with no opt-in: 12 menus, 801 static entries, 102 captured primary and eight alternate bindings. There are 139 bound partial native leaf actions and 585 unavailable entries. Missing actions remain disabled. Command-H is Extras and Control-Command-H hides Photato. Preserve the installed unmodified factory preset, not the user's modified active Photoshop shortcut set. Keep Photato-specific AI/export/IAP entries clearly named. Every meaningful step, failed attempt and qualification boundary must be documented; preserve immutable evidence and run the history audit.

## Runtime state at the checkpoint

The last checked feature build remains `/private/tmp/photato-merge-ui-5ydwb8m9/Photato.app` (step058, old bundle version), clean Untitled-1. Older historical tone/layout test apps were left alone. The original Photoshop Untitled-1 was untouched and disposable Photoshop probes were closed. The step059 package is not a newly live-tested editor session; use the rebuilt `build/Photato.app` or the clean extracted path in the step059 manifest when resuming. Temporary folders/process IDs may disappear: inspect current state rather than trusting old IDs.

No automation was created for this pause. The active long-running goal is to be marked **paused** after this checkpoint, package verification and the final evidence audit. A later explicit user resume is required before more goal work.
