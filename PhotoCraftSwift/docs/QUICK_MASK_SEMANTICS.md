# Quick Mask selection semantics

Checkpoint484 repairs Quick Mask entry/exit and the PSD editing-gray convention. The shared core command is used by the native Q command, existing options dialog and optional `channel.edit` API. All64focused Debug methods and82selected optimized methods per architecture pass,17new. Current native UI acceptance is partial: the Fill modal remains running but is not exposed by the current automation binding. Build484is a validation candidate; this document does not close S05.

## Selection, editing gray and origin

Photato stores normalized selection coverage: zero protects a pixel and one selects it. Masked Areas displays coverage directly as gray; Selected Areas displays its inverse. Changing the indication preserves normalized coverage and reverses the displayed gray and painting interpretation.

| Entry state | Indication | Initial coverage | Initial editing gray | Exit without editing |
| --- | --- | --- | --- | --- |
| No selection | Masked Areas | One | White | No selection |
| No selection | Selected Areas | Zero | White | No selection |
| Explicit full selection | Masked Areas | One | White | Explicit full selection |
| Explicit full selection | Selected Areas | One | Black | Explicit full selection |

New masks retain whether entry started without a selection in `psdQuickMaskInitiallyEmpty`. An explicit full selection must not disappear on exit. A full-coverage initially-empty mask under Masked Areas exits to no selection; full coverage under Selected Areas exits to an explicit full selection. Empty coverage exits to no selection. Switching an initially-empty Masked Areas mask to Selected Areas preserves its full coverage and can therefore produce an explicit full selection on exit. This behavior is captured from Photoshop27.2, including saved resource1022 and raw gray planes.

Older native files may omit origin metadata. That intent cannot be reconstructed from an all-white plane. Native exit retains the prior full-to-none policy for those files. This compatibility fallback is explicit; it is not evidence of Photoshop behavior for an impossible-to-identify legacy origin.

## PSD, PSB and native storage

Selected-area auxiliary and Quick Mask planes in PSD/PSB contain editing gray. Readers convert it to normalized coverage; writers convert it back. Ordinary supported RGB/Gray/CMYK/Lab containers and8/16-bit auxiliary-only Multichannel documents use the same convention. Printing spot-density handling and its existing limits remain separate.

Float32 inversion is not bijective. Imported selected-area gray is retained in the optional `AlphaChannel.psdSelectedGray` surface. An unchanged source word is reused only when its inverse still matches the current coverage word; changed samples use current coverage. This protects unchanged signed zero, subnormal and other finite source samples through native storage and PSD output. It does not establish independent Photoshop HDR, edited-sample rounding or filter-kernel equivalence.

Retained selected-area Float32 source data requires native archive version91. Older document features retain their existing minimum versions, including sparse video version90 and earlier PSD metadata version77. The new retained surface is validated, included in document/history resource accounting, transformed with geometry and discarded on a depth change. Older native formats remain readable. Complete legacy migration and all output combinations remain subject to the original acceptance requirements.

## Existing optional API

No command or endpoint is added. The existing `channel.edit` operations continue to share native transactions, validation, revision checks and Undo:

```json
{"command":"channel.edit","revision":"<current document revision>","parameters":{"action":"quickMask","enabled":true,"indicates":"selectedAreas"}}
```

Use `action:"fill"`, `target:"quickMask"`, `value:0` and `opacity:1` for black editing gray, or `action:"quickMask"` with `enabled:false` to exit. Existing options, brush, hidden-target, busy and stale rules remain in force. Photoshop/Firefly v2 has no dedicated channel endpoint; unsupported descriptors remain unsupported.

Channel state retains `psd.quickMaskInitiallyEmpty` as Boolean or null and adds `psd.retainedFloat32SelectedGray` as a Boolean. Channel interchange discovery reports `selectedGrayRetentionVersion:91`, normalized coverage/origin semantics and the separate source-word retention limit. Native file discovery advertises versions10through91. A document containing this retained data requires `X-Photato-Archive-Version:91` on native download. File-transfer permission remains separately required: default denial403, old/missing format negotiation422, valid permitted download200. Existing version90 video downloads remain supported.

## Evidence and limits

Seven owned Photoshop PSD fixtures cover explicit partial/full selection, no selection under both indications, active indication change and explicit Black fill. Their source files, hashes and acquisition notes are in `Tests/PhotoCraftImagingTests/Fixtures/quick-mask-semantics484/provenance.json`. The earlier partial selection covers five left columns, not four. A shortcut fill that actually saved white is retained separately as a diagnostic and excluded from the black-fill oracle.

The baseline executes18methods and fails the10new defect checks, with seven existing methods and the new legacy-policy check passing. The repaired source passes64methods,17new. All81older auxiliary fixtures still pass their exact raw-word comparisons. The old test expecting a full selection to become nil is corrected against the independent Photoshop references;16Float32fixture version expectations now require91. No pixel vector or numerical tolerance is changed.

The maximum300000×300000 checks use sparse implicit planes, zero stored raster tiles and bounded index metadata. They do not prove dense90-billion-pixel editing capacity, physical throughput or60fps. Full S05, exact all-input Photoshop output/defaults/shortcuts, broad current-suite acceptance, physical macOS14/Intel/Apple Silicon qualification and all prior recorded failures remain open. [Checkpoint evidence](QUICK_MASK_SEMANTICS_484.json) records the current optimized results and unresolved native Fill modal. The earlier483broader API failure remains open and was not rerun in484.

References: [Adobe Quick Mask instructions](https://helpx.adobe.com/photoshop/using/create-temporary-quick-mask.html), [Adobe alpha-channel display semantics](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/alpha-channels-and-masks-in-photoshop.html). Those documents describe display and painting conventions; the saved independent fixtures establish the specific entry/exit cases recorded here.
