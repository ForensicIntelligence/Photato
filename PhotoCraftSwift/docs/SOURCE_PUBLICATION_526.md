# Source checkpoint 526

Native Swift 0.3.0/build 526, 16 November 2026. Includes increments 525–526 on public build 524.

Selection contour preparation now scans nonzero bounds and retains one exact worker contour. Matching pixel/mask/Adjustment Brush previews keep their displayed outline. Rectangular/elliptical marquees support Space repositioning during creation and continued resizing after Space release. Active polygon vertices take priority over old selection-border movement. Captured settings, cancellation and existing selection.shape/API/Actions/history paths are retained.

| Configuration | Selected passed | New methods |
| --- | ---: | ---: |
| Development Debug | 86/86 | 15/15 |
| Optimized Apple Silicon | 86/86 | 15/15 |
| Optimized Intel, translated | 86/86 | 15/15 |

All 7,875 inputs remain frozen: 7,862 distributable inputs and 13 unchanged exclusions. Optimized test IDs match in order, without skips or signals. Every pre-existing test file is unchanged. The first new polygon cursor assertion failure, interrupted broad run and test-only repair remain recorded; the production application binary was identical across that repair. Normal optimized runs use no Debug SIL workaround.

For a 64×48 selection on owned 24/36MP canvases, optimized contour preparation takes about 0.041ms on ARM and 0.061ms under Intel translation, versus 217/330ms and 372/563ms for the frozen native-524 traversal recompiled in the same test binaries. Exact contour runs match; 120 unchanged requests reuse one contour. These are contour CPU costs, not whole-stroke latency, an old-application replay, Photoshop output or physical FPS.

Universal macOS14 metadata, signatures, unchanged entitlements, model/license resources, executable payload and extracted ZIP checks pass. Signing-only LINKEDIT allocation differences reproduce exactly through an independent codesign replay. The native app launched with the title Photato - Untitled-1 and the expected menu headings. Native automation stalled in macOS's file chooser; live painting/held-Space/save/reopen/normal Quit remain unqualified. The isolated app was preserved without force quit or relaunch.

The development-history inventory is refreshed through 526. Its strict check still fails on the same 631 historical missing references as public 524, with no new missing reference; this gate is not waived.

All 104 scopes, 652 identities, 81 major memberships, seven passes and previous failures remain. Native 92, Actions 61 and 271 typed commands are unchanged. Full Q03/S01, independent Photoshop equality, supported physical machines, 60 fps and complete functionality remain open. This is a source checkpoint and validation candidate, not a software release or App Store upload.

[Contour preparation](SELECTION_CONTOURS.md) · [Selection behavior](SELECTION_INTERACTION.md) · [Evidence](SELECTION_FEEDBACK_526.json) · [Manifest](SOURCE_SNAPSHOT_526.json) · [525 diary](pending-updates/step525.md) · [526 diary](pending-updates/step526.md)
