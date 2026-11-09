# Editable gradient profiles

Build 510 extends Edit > Convert to Profile to ordinary RGB gradient fill layers and vector gradient fill/stroke paints. Use an installed or loaded destination RGB profile at the existing 8/16/32-bit depth. Leave Flatten Image to Preserve Appearance off to retain editable controls. Preview does not alter the original. Commit uses one Undo entry. Stops become destination RGB; position, midpoint, opacity, method, placement, masks, layer IDs and vector geometry are retained.

Gradient controls currently have a bounded SDR 0…1 domain, including in RGB 32 documents. Finite converted stop components are explicitly clipped to that range. Extended raster samples remain extended. Same-profile gradient operations retain RGB/HSB/gray stop encodings. This is not HDR gradient support or exact AdobeACE output equivalence. Current gray-stop working-space interpretation remains different from Photoshop.

A pristine imported vector pixel cache is converted with its definition. Stale appearance is invalidated. Original opaque vector bytes and their source ICC are retained in the layer's PtVP source tag as deterministic version 1 JSON with profileBase64 and recordBase64. A conflicting existing tag rejects atomically. Patterns, native component-mode gradients and remaining unsupported stacks require explicit flattening.

## Optional APIs

The existing Photato document.convertProfile operation uses the same native preparation, history and busy/revision fences. Supply profileBase64, optional intent, blackPointCompensation and mergeVisible. It requires an authenticated explicitly shared document; the separate file-transfer permission is not needed for an ICC edit. Existing document.profile.read reports the resulting profile. No new command identity or route was added.

The existing Adobe-compatible output ICC adapter shares this conversion. Raster outputs preserve appearance by compositing the original stack before conversion. Editable output retains stop controls. RGB8/16 PSD/PSB gradient fills with fixed RGB stops now reopen with a non-sRGB document ICC. Other gradient color models, tone-layer profile restrictions, RGB32 gradient descriptors and vector-gradient PSD export retain separate unsupported gates. Native .photato keeps the editable vector workflow. This is coverage of these existing adapters, not a claim that every Firefly endpoint is implemented.

## Validation and limits

All 106 selected Debug and optimized Apple Silicon methods pass. Translated Intel passes 105/106; all 14 new methods pass. The retained frozen color-profile failure reproduces on public 506 with 294 identical assertions and complete dense/paged captures identical byte for byte. The prior two Float32 Intel reviewed-plan word differences remain. No assertion or numeric tolerance was relaxed. Full-suite and Photoshop output/default parity are not qualified.

The sandboxed Debug app passes profile preview through an explicit ICC file, commit, Undo/Redo, Save As, reopen and normal Quit while retaining the three-layer document. The saved controls and decoded tile data match the shared-engine capture through an independent reader. The built-in profile menu's accessibility activation remains unqualified. The unlaunched universal candidate passes signatures, both minimum-system declarations, production entitlements, model resources, unsigned payload replay and extracted ZIP checks. Physical Intel/macOS 14, optimized live UI, dense maximum capacity and 60 fps remain open.

The owned Photoshop 2026 fixture was converted using DisplayP 3, AppleCMM, relative intent, BPC, no dither and no flattening. Its fixed RGB controls and profile are tested on import/re-export. Independent descriptor comparison records remaining conversion differences rather than declaring numerical equality. Full COL 01 remains open.
