# Source checkpoint 513

9 November 2026 UTC. Native Swift 0.3.0/build 513, Source03. This is a development source checkpoint, not a software release or a full-suite pass.

Legacy Macintosh RGB proofing now uses a generated Apple RGB ICC profile through the native Custom controls and shared API. Named Apple RGB creation/output support extends both maintained interfaces. The Swift ICC writer distributes no Adobe profile file or program code. Full COL03 remains open.

| Configuration | Selected methods passed | New methods passed |
| --- | ---: | ---: |
| Debug, Apple Silicon | 54/55 | 7/7 |
| Optimized Apple Silicon | 54/55 | 7/7 |
| Optimized Intel, translated | 52/55 | 7/7 |

The existing Gray8/16 native-versus-isolated-API default ICC comparison reports four assertions. Translated Intel also fails two frozen-proof methods with three assertions: 10,156 Float32 values differ in each small output and 10 in the reduced output. Actual retained public 512 executables reproduce these failures; all current Intel raw outputs are byte-identical to that baseline. No original equality assertion, reference or tolerance was changed. The first optimized gate refusal is retained; the later source assessment records baseline evidence separately.

All 7,767 frozen inputs are unchanged across current builds. The generated ICC bytes are identical in Debug, optimized ARM and translated Intel. Independent ColorSync tests match 888,624 Float32 component values per architecture against the installed standard Apple RGB ICC. This qualifies the tested ICC transforms on this OS, not Photoshop ACE/display rendering or physical platforms.

Actual native menu, Custom defaults, Cancel, Command-Y, OK, Save As/reopen and normal Quit pass. The saved untagged PSD retains all 576 component values and inserts no ICC; its owned source file is unchanged. A screenshot of native controls was captured in the conversation.

The unlaunched universal candidate passes signatures, both macOS 14 minimum declarations, unchanged production entitlements, complete unsigned payload/signing replay, model/provenance/license and extracted ZIP checks. Full suite, physical supported platforms, optimized live UI, 60 fps, dense capacity, defaults/output fidelity and full proof/print workflows remain open.

The [source manifest](SOURCE_SNAPSHOT_513.json) records 7,754 distributable frozen inputs and 13 generated/restricted exclusions with existing preparation instructions. All original Rust files, repository paths and Git history are preserved. Native format 92, Actions 60 and 271 typed commands remain unchanged. One original command row advances from pending to partial; all 652 identities, 104 scopes, 81 major memberships and seven passes remain. Next: RAW02 major-stillneeded, after auditing existing functionality.

The canonical 486 history job is terminal with OS error 89 reading an old retained fixture-license file. Earlier promotion, documentation and static diary phases succeeded; queued487–491 did not obtain a successful history receipt. No restart or subsequent canonical/website promotion is claimed.

[Workflow/API](APPLE_RGB_PROOF.md) · [Detailed record](pending-updates/step513.md) · [Diary](DEVELOPMENT_DIARY.md).

Photato remains free and open source. No binary upload, production installation, App Store change, review submission or software release is included. Every software release requires manual approval.
