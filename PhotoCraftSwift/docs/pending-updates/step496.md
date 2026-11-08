> Integrated into the source-delivery diary on 8 November 2026 UTC from the retained checkpoint496 working record. Status statements below describe that checkpoint. Local raw logs, user documents, reference sessions and app bundles are excluded from the public repository. The canonical historical-evidence audit is still pending; see the [delivery record](../SOURCE_PUBLICATION_500.md).

# Photato developer diary — checkpoint 496

Photato can now open a PSD vector mask that starts with Subtract and later uses Intersect. It also imports joined contours with Even-Odd filling when that changes the region, so holes remain holes. Even-Odd paths can be exported to PSD and PSB. Nonzero paths whose filled area would change during export are rejected explicitly; complete winding-preserving transport still needs work.

The renderer evaluates a finite boundary and its complement through each boolean operation. It retains the original component order and Bezier handles and does not insert a synthetic canvas-sized path. Dense and paged masks use that result, including final inversion, density and feather. Gradient alignment now recognises a filled exterior. Finite custom shapes and text-inside layouts reject an unbounded filled region before an edit is published. Text-on-path continues to follow the contour.

The existing native commands and optional API share these changes. API discovery describes the behavior and limits. Native92/Actions60 encoding, command identities, menus, shortcuts, cursors and permissions are unchanged. Older builds render the formerly ignored first Subtract operation differently.

For the reference, I built an independent synthetic PSD, opened it in Photoshop 2026, moved its ordinary black background behind the test layers, and saved a separate recomputed file. The owned document was closed after saving. No user document or application preference was changed. An independent Python reader extracted its merged RGB bytes. Photato matches all 24,576 red and green bytes for the rectangle operations and joined contours. The blue diagonal still differs at 32 pixels by one 8-bit level. That antialiasing difference remains open.

All twelve new tests passed in Debug, optimized Apple Silicon and translated Intel. Each selected run passed 71/73. The two failing exact Shape Blur references also fail in retained build 495. All 160,000 Debug actual bytes and 320,000 optimized actual bytes match their corresponding prechange outputs. Their cause is not fixed. No existing fixture, tolerance or assertion was changed.

The universal validation app and extracted ZIP pass architecture, minimum macOS 14, signature, unchanged entitlement and payload checks. It is explicitly a partial validation candidate and has not been launched, installed, uploaded or released. Build 480 remains the latest fully qualified selected universal build. Physical Intel, macOS 14 runtime and current native UI qualification remain open.

The first imported-reference test reproduced the old rejection. Two later regressions reproduced the gradient frame and finite-outline admission defects before their repairs. Earlier failures, logs and products remain. Current source and the first optimized source have separate hash-verified snapshots. The first snapshot was reconstructed retrospectively from retained inputs and exact edit reversals; its record identifies the reconstruction date and origins.

G05 remains open: wider PSD forms, winding transport, sample grids, feathering, uncommon contexts, exact Photoshop output and physical platform/performance checks still need work. All earlier failures and the complete original scope remain. The next major package is I01, editable PSD coverage. The source audit identifies native vector-shape interchange as a missing workflow.

The canonical history audit and queued delivery are still pending. This private diary is current through 496; the project and website copies have not yet received this checkpoint. Existing applications, pending dialogs, documents, failed builds and sources are preserved. No GitHub or distribution change was made.

Development notes (local record: development-notes01.md) · Qualification (local record: qualification-final01.json) · Implementation (local record: PSD_PATH_SEMANTICS.md) · Reference provenance (local record: reference01/native-reference01.json)
