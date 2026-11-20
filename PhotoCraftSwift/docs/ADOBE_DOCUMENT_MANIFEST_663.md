# Inspect PSD and PSB templates through the manifest API

## 20 November 2026

Adobe exposes `POST /v2/generate-manifest` to inspect a template before modifying its layers. Photato's earlier JSON manifest was limited to artboard output and used stack-position IDs. An ID returned to a caller could therefore differ from the original Photoshop layer ID used by a later composite edit. This checkpoint uses one identifier strategy for the new manifest and resource composites. It preserves PSD layer tags and assigns deterministic IDs in an isolated job copy when the input has none. The PSD writer retains those tags even when the document has no Layer Comps. [Manifest request](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-migration) · [Manifest fields](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/manifest-response-migration)

`AdobeDocumentManifest.swift` reads actual dimensions, bit depth, resolution, available XMP, layer hierarchy, Smart Object placement, blend and mask state. XMP appears only when requested. The job uses the existing authenticated transfer, cancellation, and result expiry paths in `AdobeActionJobs.swift`. Embedded JSON, string and base64 are returned in job status. Hosted assets use the authenticated local download route. External HTTPS writes use the existing authorized output transport. The shared output budget counts embedded status payloads as well as hosted files.

`AdobeLayerOutput.swift`, `AdobeActionAssets.swift` and `PSDCodec.swift` connect the same IDs to downstream composite outputs and edits. The app's existing artboard manifest route keeps its previous response. `AutomationActionJobs.swift`, `AutomationHTTP.swift` and `AutomationService.swift` route and advertise the new job.

## Validation

`AdobeDocumentManifestTests.swift` checks 16-bit document metadata, XMP opt-in, mask bounds and opacity, duplicate IDs, all supported result destinations, and an authenticated local job that edits using an ID obtained from a manifest. Generated test documents and an in-memory resource transport keep fixture data local.

The first Debug build found an existing layer-move test that assumed every completed result contained a URL. The test now unwraps the URL explicitly and still checks the reopened PSD and exact bytes. This revision also checks the file information for embedded Smart Objects and round-trips an existing Background layer ID in a PSD without Layer Comps.

The first runnable candidate added a layer ID record even when an edit left a formerly untagged layer in the same stack position. The corrected full-document export keeps a synthesized ID implicit when the output stack can reconstruct it. The published baseline reproduced the existing grayscale profile and invalid-move status assertions from the broader legacy test run. The next candidate put that ID work in the common encoder and exceeded the Debug worker's stack while rendering the masked RGB32 golden files. The current candidate does the identifier work before the common encoder, in the composite job path. The manifest output destination test now uses a PSB fixture.

The RGB32 case still exhausted the worker stack after moving identifier work to the composite path. The next revision chooses the job type before launching the worker. Each worker captures only its request and inputs. Job priority and cancellation remain shared.

The smaller worker still reached the stack limit on nested masked groups. The latest candidate splits group and raster node preparation so the recursive group frame carries less data. The existing RGB32 desktop and HTTP golden test is included in the regression bank.

All 31 focused checks passed on the revised Debug build. In the first cumulative run, the new selector count shifted the older shard boundaries. One channel drag test then crashed in the document controller and passed on isolated rerun. All 135 cases in that shard passed when rerun by suite on the same Debug executable. The optimized runs use the previous checkpoint's shard boundaries and run the six additional selectors together in a separate process.

The Intel run reproduced the previous build's 32 failed assertions against the RGB32 fixtures, including the exact mismatch count in each assertion. A separate comparison exported the same eight documents from the previous and current optimized Intel libraries. All 524,288 merged bytes matched. The manifest tests passed on both architectures.

Layer thumbnails and original Smart Object extraction remain open. Adobe-hosted result fidelity has yet to be measured.

1,498 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional masked RGB32 test passed on Apple Silicon. On Intel, eight PSD composites matched the previous build byte for byte and reproduced its existing differences from the Photoshop fixtures. Both slices of the signed macOS 14+ universal preview launched offscreen.

An authenticated manifest-to-edit round trip reopened the edited PSD and retained the original and fallback layer IDs. The tests also checked XMP opt-in, layer hierarchy, mask and blend state, destination equality and rejection of unauthorized downloads.

[Qualification](SOURCE_PUBLICATION_663.md)
