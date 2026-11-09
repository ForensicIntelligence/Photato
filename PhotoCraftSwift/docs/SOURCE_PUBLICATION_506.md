# Build 506 source delivery

8 November 2026 in Vancouver; final validation receipts are dated 9 November UTC. This snapshot includes native Swift source, the Xcode project, tests, scripts, licenses and the repository diary through checkpoint 506. Photato remains completely free and open source. Every software release still requires manual approval.

Image > Generative Upscale now offers local Real-ESRGAN 2×/4× enlargement through native Swift and Apple Core ML. Work has measured tile progress and cancellation, then opens a separate unsaved merged document. The source remains unchanged. Bit depth, working RGB profile and resolution are retained. The optional API uses the same preparation with strict create/cancel commands and publication checks. There is no runtime Python, subprocess, download, credential, external service or silent resize fallback. See [workflow, model preparation and API](LOCAL_SUPER_RESOLUTION.md).

The optional pinned BSD-3 model is separately identified from Firefly and Topaz. The current provider requires macOS 26+ Apple Silicon; the converted model itself declares macOS 15 compatibility. Ordinary editing still targets macOS 14+. Still SDR RGB is supported; unsupported modes/HDR and remaining rendering/profile/storage limits reject without replacing the source. This is learned super-resolution, not proof of Photoshop model or output equality.

## Validation

All 7,742 Source06 inputs remain unchanged through Debug, optimized Apple Silicon and translated-Intel runs. Each passes all 46 selected methods, including 12 new app tests. No case is missing, unexpected, duplicated, skipped or signalled. All 19 archive-tool methods pass, three new. These are focused checks, not a full-suite pass. Intel exercises portable conversion/engine integration and unsupported-provider admission; it does not run this optional model.

Independent Python readers match all 145,600 analytical tile/alpha fixture bytes per variant. The real acquired-model CPU test runs on Apple Silicon; all 768 captured output bytes match Debug and optimized ARM. The portable bridge regression covers all 63,488 finite half codes and 46,080 SDR rounding-boundary cases, also comparing native Float16 on ARM.

The current sandboxed Debug app performs real 512×512 to 1024×1024 photo inference, opens the independent output, saves it and quits normally. The original photo hash is unchanged. A previous Source03 native run separately verified save/reopen and cancellation of a running 4× job. An independent reader checks both native manifests and every blob, matching complete raster descriptions and all 249 unique decoded image tiles between the earlier and current native results: 16,318,464 unique raw Float32 RGBA bytes. This proves consistency of that photo across the bridge repair, not Photoshop or general learned-output equality. Screenshots were returned in the conversation; raw evidence stays private.

The universal validation package contains the retained tested optimized executables. Both slices declare macOS 14. Unchanged production entitlements, strict signatures, both optional models/provenance, BSD license, full unsigned payload with independent signing replay, and extracted ZIP contents are verified. It is unlaunched. Physical Intel/macOS 14 and optimized live UI remain unqualified.

Failed compile variants, the first optimized Intel Float16 failure, and the inherited archive path-alias guard failure are recorded. The guard now resolves its source root; the original rejection assertion remains. No original numerical fixture or assertion was weakened. The existing command-count expectation advances from 267 to 269 for the two new typed operations. Native format 92 and Actions format 60 are unchanged; multi-document Actions transport remains open.

## Source, licensing and diary

The [source manifest](SOURCE_SNAPSHOT_506.json) identifies 7,729 distributable frozen inputs and 13 explicit exclusions: two optional generated model/provenance sets and one restricted external PSD fixture. Pinned preparation/acquisition instructions and licenses remain. All 1,057 original Rust files, existing repository paths and Git history are preserved. Generated apps, signing credentials, user documents and private raw evidence are excluded. No proprietary Adobe source or binary implementation was inspected for this work.

The repository diary reaches 506. The original canonical checkpoint 486 evidence pair remains untouched; canonical source and standalone website promotion are pending. The public source-copy history refresh/check is limited by intentionally absent historical private references. It is not claimed as a successful canonical full-evidence audit. Included source/test/project bytes independently match the tested source.

## Remaining work

Full AI06 remains open: Harmonize, other Neural Filters, complete model catalogue, exact provider/default/output fidelity, broader quality and supported platforms. Full-suite, dense capacity and 60 fps qualification, plus all earlier editable-shape/API/Intel/color/vector and other failed acceptance targets remain required. All 104 scopes, 652 original tracked command identities, 81 major memberships and seven scheduling passes are preserved. Next is AI08 in the major-stillneeded queue, auditing the distinct Assistant and AI Assisted Editor capabilities before choosing a missing native workflow.

No binary upload, GitHub software release, production installation, App Store change, review submission or automatic distribution is included.
