> Integrated into the source-delivery diary on 8 November 2026 UTC from the retained checkpoint489 working record. Status statements below describe that checkpoint. Local raw logs, user documents, reference sessions and app bundles are excluded from the public repository. The canonical historical-evidence audit is still pending; see the [delivery record](../SOURCE_PUBLICATION_500.md).

# Photato development record — validation build 489

Recorded 2026-11-08T06:47:37.615256+00:00. This records the qualified private candidate. The canonical offline diary is still being delivered in checkpoint order; the earlier audit has not been restarted.

The Remove toolbar placeholder now has a separate native implementation. Automatic mode applies each stroke; manual mode accumulates Add/Subtract marks without changing document pixels or dirty state. Return applies one batch and Escape clears it. Sample All Layers and Create New Layer share the same source-bound preparation and history. Near-closed loops fill their interior, although the closing threshold and edge-to-edge corner behavior still need Photoshop qualification.

The optional retouch.remove command supports configure, stroke, apply, cancel and execute with strict schemas, pending state, availability, cancellation, stale-source and authorization checks. All RGB depths are covered. Selection coverage and its original rectangle/mask representation are retained, and unmarked source samples remain exact. The API has 267 typed commands; the original 652 inventory identities and mappings remain unchanged. No UXP, CEP, native plugin host or undocumented Adobe endpoint was added.

Strict Float32 tests exposed rounding drift in existing content-aware completion. Two generic mathematical identities now preserve exact constant Dirichlet boundaries and uniform known RGBA fields. The first attempted blur-only identity did not repair the upstream pyramid drift and was withdrawn; its evidence is retained. Nonconstant inputs use their prior algorithms. No old numerical fixture or tolerance was weakened. Old test updates account for the now-implemented toolbar slot and the new command count.

All 116 selected methods pass in Debug and optimized Apple Silicon and translated Intel runs, including 16 new methods. Earlier zero-test compile failure, fixture error, genuine numeric failures and incomplete repair attempts remain preserved. Source07 and Debug06/release02 match across all 7,644 inputs. This is focused qualification, not the full test suite or independent Photoshop output equality.

The first universal candidate exposed a blank SF Symbol and a generative-mode row that looked available despite backend rejection. A real eraser.fill symbol and native NSPopUpButton with explicit disabled menu items repair those defects. The second candidate shows the icon and disabled row correctly. Automatic removal, Undo/Redo, manual Add/Subtract/Escape, direct mode selection, separate-layer output, original retention, clean close and normal Quit pass. Keyboard popup selection remains unqualified, and Properties/Layers initially retained the previous document panel content until canvas interaction. One UI automation activation failure recovered on the same live process without restarting.

The universal candidate passes macOS14 metadata, full unchanged entitlements, signatures, whole unsigned payload comparisons except independently reproduced signing allocation fields, resources and extracted-ZIP equality. The source, package and owned fixture remain unchanged after UI testing. All older running and failed candidates remain intact.

Full AI03 remains open. Auto uses traditional content-aware processing; Generative AI on rejects and is visibly disabled. There is no distraction detection, generative provider or claimed Photoshop model/output equality. Remove currently admits a 16,777,216-pixel canvas and 4,194,304-pixel solve region; these are tool limits, not the application's final document-size requirement. Larger canvases, remaining source types, temporary-mark Undo, settings/defaults, exact overlays/cursors, supported devices and 60fps remain required. Next is AI04.

## Validation evidence

- Debug116 (local record: debug06-summary.json)
- Optimized ARM116 (local record: release02-arm-summary.json)
- Optimized translated Intel116 (local record: release02-intel-summary.json)
- Native workflow and remaining UI gaps (local record: native-ui02.json)
- Universal package (local record: universal02/staging01.json)
- After-UI source/package verification (local record: native-package-after-UI02.json)
- Current qualification (local record: qualification-selected03.json)

Full AI03 and the Photoshop parity objective remain open. No GitHub content or current/failed build was removed.
