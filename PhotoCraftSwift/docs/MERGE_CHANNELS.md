# Merge Channels

Build 512 adds Channels panel > Merge Channels. Open flat, opaque grayscale documents with matching pixel dimensions and bit depth. Choose the output mode and channel count, then assign one image to each output channel. The defaults follow document opening order. A source cannot supply two channels.

| Output | Sources | Bit depth |
| --- | ---: | --- |
| RGB Color | 3 | 8, 16, 32 |
| CMYK Color | 4 | 8, 16 |
| Lab Color | 3 | 8, 16 |
| Multichannel | 2–56 | 8, 16 |

Multichannel uses a page for each assignment, with Next, OK, Cancel and Mode. It creates ordinary Alpha channels without image layers or printing plates. Alpha 1 starts selected and visible. The Mode button returns to the mode/count choices. Escape cancels the sheet. Unavailable output modes are disabled.

The result opens as a new, unsaved, untitled document with empty history. Only assigned sources close; unused sources remain open. Original source files are not saved or overwritten. Merge is a document lifecycle operation, so it is not an Undo step in a source that has closed. Subsequent edits use the result's normal history.

Samples are assigned directly to destination components. Source grayscale profiles do not color-convert the values. At 16 bits, assignment follows the independently measured Photoshop working grid: map the input word to 0…32768, then back to a stored 0…65535 word using integer rounding. All 65,536 input words were checked in each RGB output channel. RGB32 keeps raw finite floating-point components, including the tested negative and HDR values. CMYK stores ink density, the inverse of the source grayscale brightness. Results are untagged; process modes retain the captured working profile for interpretation. Resolution currently follows the first assigned source. Exact Photoshop resolution, selection and other metadata defaults remain under qualification.

Auxiliary-only documents admit 56 total channel slots, including Quick Mask when present. Ordinary documents keep their existing 52 auxiliary-channel allowance. Paged storage is retained. A sparse 300,000 × 300,000 RGB document and a 56-channel document are tested without allocating sample tiles. This proves logical geometry and sparse admission, not dense 90-gigapixel physical capacity or 60 fps.

## Optional API

Enable document transfers and document closing in the native API window, and explicitly share every source. Submit `channel.merge` through the existing authenticated `POST /v1/documents/{shareID}/commands` route. Supply the current anchor revision and parameters:

```json
{
  "mode": "rgb",
  "sources": [
    {"shareID": "<red-source-share-id>", "revision": "<current-revision>"},
    {"shareID": "<green-source-share-id>", "revision": "<current-revision>"},
    {"shareID": "<blue-source-share-id>", "revision": "<current-revision>"}
  ]
}
```

Replace the placeholders with the UUIDs and revisions returned by the service. Sources are ordered by destination channel. The route anchor must be an eligible grayscale document but may remain unused. The existing eight-document sharing policy applies; the API does not expose unshared files or grant access to 56 open documents automatically.

HTTP 201 returns `document`, containing the new full shared state, and `closedSources`, containing each consumed share ID and source document ID. The old source leases are replaced only after the new result is registered. Source edits, closed documents, stale revisions, revoked leases or permissions, color-setting changes, cancellation and conflicting lifecycle operations cannot publish a partial result or close only some sources. Preparation runs away from the main actor; final registration and source closing use one synchronous transaction.

`channel.merge.cancel` requests cancellation of an active API merge authorized by its anchor or selected source share. It takes no parameters beyond the normal command/revision envelope. The acknowledgment may arrive before the worker has finished stopping. `channelMerge.active` reports that state. Native sheet cancellation and API cancellation share the same cancellable preparation. Native and API use the same numerical implementation and publication helper. The typed command count is 271; native format 92 and Actions format 60 are unchanged.

Adobe's pinned HTTP contract has no dedicated Merge Channels endpoint. No endpoint or unsupported multi-document Action descriptor is invented. Existing resource serializers remain shared, while multi-document UXP/Actions compatibility remains separate work.

## Validation and remaining work

All 15 new methods pass in Debug, optimized Apple Silicon and translated Intel. Each broader run passes 68 of 69 methods. The remaining Multichannel sample test reports 192 assertions, identical and in the same order on the retained executable from public build 511. That requirement remains failing. Three other stale test expectations were corrected against the established 809-item menu inventory and current 271-command catalogue; no numerical tolerance or sample assertion was relaxed.

Six small Photoshop-owned references match every merged component word: RGB 8/16, CMYK16, Lab16 and Multichannel 8/16. The complete RGB16 reference covers 196,608 component words. Tests also cover raw RGB32 values, supported CMYK/Lab8 construction, 56-channel native/PSD/PSB round trips, sparse maximum geometry, validation, cancellation, revoked sharing, changed sources, rollback, unused anchors and source history/state retention.

Current native UI checks pass for RGB16 and Multichannel16, including mode availability, channel order, the Multichannel Mode/Next/OK flow, source closing, unused-source retention, separate PSD Save As, reopen and normal Quit. The saved outputs match 960 independently read Photoshop reference component words. Source files are byte-identical across the Multichannel pass. The earlier native sheet publication failure and its repair are retained in the diary; a unit/API pass was not treated as a live UI pass.

An existing PSD reader policy rejects neutral unmanaged metadata in one non-RGB Photoshop reference. Small output comparisons therefore use an independent literal raw-plane parser, with no production decoder or color transform. That reader limitation remains open. The Multichannel PSD writer omits resource 1041 while the Photoshop reference includes its untagged flag; both omit an ICC profile and their numerical planes match. This container metadata difference remains open. Full CMYK8/Lab8 and RGB32 Photoshop output/reference coverage, resolution/selection/profile defaults, unusual source eligibility, dense capacity, physical supported platforms, optimized live UI, accessibility and performance qualification remain required. Full COL02 and Photoshop parity are not claimed.
