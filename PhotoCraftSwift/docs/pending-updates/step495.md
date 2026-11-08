> Integrated into the source-delivery diary on 8 November 2026 UTC from the retained checkpoint495 working record. Status statements below describe that checkpoint. Local raw logs, user documents, reference sessions and app bundles are excluded from the public repository. The canonical historical-evidence audit is still pending; see the [delivery record](../SOURCE_PUBLICATION_500.md).

# Photato developer diary — checkpoint 495

Warp can now process RGB layers beyond the previous 8,388,608-pixel limit without allocating a document-sized UV table. It prepares bounded colour and mask patches and writes paged output. Small images keep the existing sampling arithmetic. Sparse support includes clamped input coordinates and interpolation edges.

The tests cover an actual dense 4,097 × 2,048 layer with a linked raw mask, retained mask settings, patch seams, folds, all RGB depths and interpolation modes. A sparse 300,000 × 300,000 canvas exercises logical geometry, archive storage and Undo/Redo. These cases do not establish that a densely painted maximum-size document is practical on every supported Mac.

Native Warp previews use an overview capped at 2,048 pixels per side. Closing or replacing a document retires its preview. A preview made before an edit/Undo cycle cannot commit. The optional API shares the prepared native command and reports the logical, mesh and working-buffer limits. Command identities, menus, shortcuts, cursor rules, permissions and archive versions are unchanged.

All 82 selected Debug tests passed. The optimized Apple Silicon run passed 82/82; translated Intel passed 81/82. All 14 new methods passed in both optimized runs. The one failing method compares 24 frozen composition references, and nine comparisons differ under translated Intel. The retained prechange build 494 fails the same nine comparisons. Their complete actual output bytes were not compared directly and the root cause is not established. The fixtures, assertions and tolerances remain unchanged.

The universal validation app and extracted ZIP pass architecture, minimum macOS 14, signature, unchanged entitlement and payload checks. It is explicitly a partial validation candidate. It has not been launched, installed, uploaded or released. Build 480 remains the latest fully qualified selected universal build.

Failed attempts remain available: missing test imports and throwing annotations, an AppKit controller startup-order crash in new test setup, sparse UV edge failures, the old large-canvas compositor guard, and a new test that used a layer identity replaced by Smart Object conversion. The repaired setup follows the application's custom-controller startup order; broader late controller construction safety remains unqualified. No original numerical fixture or assertion was weakened.

G02 remains open. Exact Photoshop output and defaults, other geometry tools' capacity limits, native component contexts, editable PSD Warp transport, physical platform/capacity checks and 60fps interaction still need work. Earlier Intel colour-profile, composition, Legacy adjustment and API failures remain recorded. The next package is G05, vector rasterization fidelity, followed by I01.

The canonical history audit and subsequent delivery pipeline are still running. This private working diary is current through 495; the project and website copies have not yet received this checkpoint. Existing apps, documents, pending dialogs, failed builds and source snapshots are preserved. Nothing was changed on GitHub or in distribution services.

Detailed development notes (local record: development-notes01.md) · Qualification (local record: qualification-final01.json) · Implementation details (local record: PAGED_WARP.md)
