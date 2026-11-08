# Split Channels

Use **Split Channels** in the Channels panel menu to turn a flat image's channels into separate grayscale documents. The source closes without saving after every output document is registered. Its file is not overwritten. Each result has a fresh identity, no file URL, empty Undo history and an unsaved change state. Save the grayscale documents independently.

Adobe documents this lifecycle and the source-name/channel-suffix naming scheme. Current Photoshop context, naming details, profile defaults and exact output still require direct verification. [Adobe guide](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/duplicate-split-and-merge-channels.html).

The implementation reads native component samples without converting through rendered color. RGB, Gray and Lab keep their stored numbers; CMYK and printing ink density are inverted into grayscale. Alpha coverage ignores display inversion. A Float32 spot channel uses retained source-gray bits only where they still match its current density. Gray sources retain their Gray profile; other outputs use the captured working Gray profile. Resolution, selection, paths, guides and source metadata are retained. The original's history, layer identities, layer comps, variables and file association do not become output history or associations.

Results are opaque Background documents. Native Fill, Clear, Brush and Undo, plus grayscale PSD/native persistence, are covered by the focused tests. Background Clear now accepts retained Grayscale storage through the existing mode reconciliation; its RGB path is unchanged. Selected component Clear accepts neutral colors. Broader color/default fidelity remains open.

Preparation rejects unflattened or translucent images, Quick Mask, restricted color modes, temporal canvases, artboards/frames and fewer than two channels. It supports represented Duotone gray, Multichannel plates and standalone saved channels. Photoshop's exact eligibility for these contexts, including spot channels, is unqualified. Split does not flatten or convert the source implicitly. Merge Channels and Merge Spot Channel remain separate unfinished workflows.

Component preparation retains the existing logical maximum of 300,000 pixels per side. Maximum sparse RGB/Gray/CMYK documents are tested at their supported depths. This does not establish that a dense 90-gigapixel document fits physical RAM or scratch space. Ink-plane storage retains its existing limits.

## API

`channel.split` takes an empty parameter object and requires both document-transfer and document-closing permissions. Supply the current source revision. HTTP201 returns `sourceShareID`, `sourceDocumentID`, `sourceClosed`, and `documents`, each containing a channel descriptor and the new shared document state.

All outputs replace the source lease together. The existing eight-document sharing limit applies to the final set, including other shared documents. Native document separation has no corresponding eight-document cap. Preparation, resource checks and lease admission happen before source close. Cancellation, revoked permissions/sharing, changed source/session/settings or document lifecycle cannot publish a late result. Partial registration is rolled back while the source remains open.

`channelSeparation` state exposes availability, a source-context reason and output count; `channels.separation` exposes schemas and behavior. Permission rejection is403, stale/busy or cancelled work409, insufficient share capacity429, invalid source context422 and unknown parameters400. There are266typed commands. Native89 and Actions58 are unchanged; multi-document Actions remain unsupported. Adobe's pinned Firefly v2 contract has no dedicated Split Channels route; no unverified descriptor or runtime support is implied.

## Qualification

[Checkpoint470 evidence](CHANNEL_SEPARATION_470.json) records every attempt, selected tests, exact component comparisons and package checks. The literal reference is owned analytical evidence, not an independently captured Photoshop Split Channels result. Full COL02, live UI, physical supported platforms, dense capacity, 60fps, full-suite results and earlier failures remain open.
