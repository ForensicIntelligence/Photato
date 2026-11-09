# Source checkpoint 510

8 November 2026, Vancouver. This snapshot includes native Swift 0.3.0/build 510, the Xcode project, tests, scripts, licenses and repository diary through checkpoint 510. It is a development checkpoint. The full test suite is not green, and this is not a software release. Photato remains completely free and open source; every software release requires manual approval.

## Changes since 506

Checkpoint 507 adds explicit Exposure, Brightness/Contrast, Hue/Saturation and Vibrance values to reviewed edit plans. Native review and the optional API retain the parameters. The five existing string operations remain compatible. Applying a plan uses the shared Actions transaction and one Undo entry. Real model inference and the earlier AI-sheet live UI remain separately unqualified.

Checkpoint 508 records 17 acceptance requirements, Adobe's 24-entry language catalogue and separate plugin/scripting families. A read-only Foundation Models probe supports 15 of the 24 audited lookup keys. It supports the current locale but reports `modelNotReady`. This does not establish app localization or actual language generation. Full AUD02 remains open.

Checkpoint 509 records an independent UXP command-host plan covering isolation, native transactions, UI, applicable APIs, packaging and real plugin tests. No plugin host was added. No Adobe SDK package, header or implementation was downloaded, copied or used, and no SDK agreement was accepted. Plugin compatibility remains major work.

Checkpoint 510 lets ordinary RGB profile conversion retain gradient fill layers and vector gradient paints. Masks, geometry and Undo history are preserved. Imported caches are converted or invalidated coherently, and opaque source records remain separate provenance. Non-sRGB RGB8/16 PSD/PSB gradient fills with fixed RGB stops can reopen. Raster exports still composite before conversion. Gradient controls currently use bounded SDR values, including RGB32; floating-point raster samples keep extended values. See [the workflow and API coverage](EDITABLE_GRADIENT_PROFILES.md).

## Validation

The same 7,748 Source04 inputs were used for every current build:

| Configuration | Selected methods passed | New checkpoint-510 methods passed |
| --- | ---: | ---: |
| Debug, Apple Silicon | 106/106 | 14/14 |
| Optimized Apple Silicon | 106/106 | 14/14 |
| Optimized Intel, translated | 105/106 | 14/14 |

The failing Intel case compares frozen color-profile output. It reports 294 assertions. The retained executable from public build 506 produces the same ordered assertions and identical complete dense and paged captures: 1,984,272 bytes each. This confirms that the selected failure was not introduced here. It remains a failing requirement.

The current reviewed-plan capture matches all 9,216 decoded bytes between Debug and optimized Apple Silicon. Intel retains the same two Float32 result-word differences recorded at 507. Masks, alpha and unselected samples remain exact. No numerical tolerance or equality assertion was relaxed.

The current sandboxed Debug app passes profile conversion, Undo/Redo, separate Save As, reopen and normal Quit with the three-layer fixture still editable. An independent reader verifies saved metadata/blob hashes, source IDs, controls and 65,536 decoded tile bytes per document against the shared-engine capture. Earlier staging and parser failures are retained. The built-in profile menu's accessibility activation and a repeated live P3-preview Cancel remain unqualified; the explicit ICC loader is verified.

The unlaunched universal candidate passes signatures, unchanged production entitlements, macOS 14 minimum-system metadata for both slices, complete unsigned payload/signing replay, optional-model resources and extracted ZIP checks. Current broader qualification is not fully green. Build 506 remains the last universal whose narrower selected suite passed. Physical Intel/macOS 14, optimized live UI and full-suite qualification remain open.

An owned Photoshop 2026 Apple CMM/Display P3 reference retains its exact fixed RGB gradient controls through native import/re-export. Independent comparison records remaining RGB/HSB precision and working-gray differences. Adobe ACE/default/output fidelity, HDR gradient controls, rich type, vector-gradient PSD export and full COL01 remain open.

## Source and records

The [source manifest](SOURCE_SNAPSHOT_510.json) identifies 7,735 distributable frozen inputs and 13 generated/restricted exclusions with preparation or acquisition instructions. All 1,057 original Rust files, existing repository paths and Git history are preserved. Private raw evidence, user documents, generated apps and signing credentials are excluded. The staged-change secret scan is recorded separately; it is not a new full-history audit.

The diary covers investigations, failed attempts, repairs, implementation and API changes through 510. The original canonical checkpoint-486 audit workers remain untouched. Canonical source and standalone website promotion are pending. All 104 scopes, 652 original command identities, 81 major memberships and seven scheduling passes remain required. Full Photoshop parity, 60 fps and maximum dense capacity are unmet.

No binary upload, production installation, App Store change, review submission, automatic distribution or software release is included.
