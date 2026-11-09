# Source checkpoint 514

9 November 2026 UTC. Native Swift 0.3.0/build 514, Source05. Auto-Blend now retains editable corrected source layers and masks when transparent-area fill is off. Photomerge keeps photograph names. Fill adds a merged result; partial alpha retains the previous isolation fallback. Full RAW02 remains open.

| Configuration | Selected passed | New passed |
| --- | ---: | ---: |
| Debug, Apple Silicon |37/37|9/9|
| Optimized Apple Silicon |37/37|9/9|
| Optimized Intel, translated |36/37|8/9|

All 7,773 source inputs remain frozen across qualification. There are no missing, extra, duplicate or skipped methods or signals. Debug and optimized ARM match all 983,040 frozen linear-RGBA bytes. Intel differs in 252 Float32 RGB values by one ULP across four 8/16-bit programs; alpha and all native Float32 programs match. Actual retained build 513 and current transfer functions match every one of 65,792 quantized levels per architecture. Inverting those injective tables recovers equal stored component values across all 24 programs. This is an inference about stored samples, not an actual old Auto-Blend replay; the exact failed linear assertion and first qualification refusal remain unchanged. Independent owned PSD input planes also match memory/file/native opening paths, and every preview alpha is opaque. These checks do not establish Photoshop numerical equality.

The actual signed native app passed controls, commit, two visible editable masks, Undo/Redo, separate PSD save/reopen and normal Quit. Cancel was checked in the app-identical earlier candidate. Independent parsing retains source names, bounds, masks and all 12,288 alpha values; the original owned input file is unchanged. Universal signatures, both macOS 14 minimum declarations, full unchanged production entitlements, whole unsigned payload and signing replay, model files, provenance, licenses and extracted ZIP checks pass. The universal candidate is unlaunched.

Earlier failures and their repairs are recorded in [the detailed entry](pending-updates/step514.md). No equality assertion, frozen reference or numerical tolerance was waived. Full-suite, earlier known failures, Photoshop masks/colors/defaults/fill, large-photo blending, fractional contexts, physical platforms and 60 fps remain open.

The [source manifest](SOURCE_SNAPSHOT_514.json) records 7,760 distributable tested inputs and 13 unchanged generated/restricted exclusions with preparation instructions. All original upstream files and Git history remain. Native format 92, Actions 60 and 271 typed commands, 104 scopes, 652 original IDs, 81 major memberships and seven passes are preserved. Next I03, major-stillneeded. Canonical history remains failed and standalone website promotion pending; no restart or subsequent promotion is claimed.

[Workflow/API](EDITABLE_PHOTO_BLEND.md) · [Evidence](EDITABLE_PHOTO_BLEND_514.json) · [Diary](DEVELOPMENT_DIARY.md).

Free and open source. No binary upload, production installation, App Store change, review submission or software release. Software releases require manual approval.
