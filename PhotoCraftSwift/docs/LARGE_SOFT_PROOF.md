# Large-document soft proofing

Proof Colors, Gamut Warning and Custom Proof Setup can now prepare displays beyond the former 8-megapixel proof limit. Existing View menu commands, Command-Y/Command-Shift-Y, proof settings, Preview and Cancel remain in place. Proofing changes the display, not document pixels, Undo history, dirty state, normal previews or image exports.

Preparation uses the existing ColorSync proof kernel on bounded source patches. A sorted union of allocated component/composite tiles identifies stored samples; one constant evaluation represents implicit pixels. Native component numbers and profiles remain authoritative. RGB composite patches retain the original working profile and encoding. Temporary valid document wrappers supply that interpretation and the exact composite patch to the unchanged kernel; their placeholder layer is never the proof input. No working-image resampling, color roundtrip or requantization is introduced.

The output is an immutable sparse/file-backed Float32 display surface. Proofing happens before area reduction. This matters because gamut warnings and nonlinear color transforms cannot generally be applied after averaging source colors. The native large-canvas image cache now receives the proofed image and its document region. The optional API produces its existing bounded overview from the proofed samples.

Logical dimensions follow the native canvas maximum of 300,000 pixels per side. Composition, content-specific mode limits, scratch space and memory remain separate resource constraints. Maximum sparse geometry and one allocated 8.39-megapixel source are tested; these do not establish dense 90-gigapixel capacity or 60 fps on supported hardware. HDR/EDR proof display remains unfinished: this path retains the existing SDR preview behavior.

## API

Use existing `proof.configure`, `proof.settings.read` and `/v1/documents/{id}/proof-preview.png`. Settings and result/state schemas are unchanged. `proofing.maximumPixels` now describes logical canvas capacity; `proofing.largeDocuments` describes patch/preview sizes, proof-before-reduction behavior and remaining limits. The API overview is at most 2,048 pixels per side; native viewport buffers retain the existing 4,194,304-pixel budget.

Large proof previews no longer return the former generic HTTP413 rejection. Large onion-skin previews retain their separate unsupported response. Invalid settings/profile/Preserve Numbers contexts, stale/busy requests and revoked shares retain existing errors and publication guards. Native89, Actions58 and266 typed commands are unchanged. Adobe's pinned Firefly v2 contract has no display-proof route; no unverified descriptor or plug-in runtime support is implied.

`SoftProof.maximumPixels` remains the legacy kernel/print budget for source compatibility; `maximumDocumentPixels` describes proof geometry. Printing still has its independent 8-megapixel preparation limit. Removing the proof check does not claim that printing or HDR/EDR work is finished.

## Evidence and remaining work

[Checkpoint471 evidence](LARGE_SOFT_PROOF_471.json) records unchanged build470 captures, source/log/product manifests, focused tests, strict comparisons and packaging. The 104 owned proof programs contain159,744 sample bytes; a separate240-byte reference checks proof-before-reduction. Exact comparisons establish regression retention, not independently measured Photoshop proof output.

Photoshop gamut algorithms, profiles, factory defaults, legacy/color-blind presets, AdobePSF interchange, per-window proof behavior, live controls, physical platforms, print, HDR/EDR, dense capacity,60 fps, full-suite results and earlier failures remain open under COL03. Current Adobe [gamut-warning guidance](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-modes/identify-and-correct-out-of-gamut-colors.html) documents the intended View workflow; it is not a numerical kernel specification. Historical proof-guide URL redirects and failed retrievals are recorded explicitly.
