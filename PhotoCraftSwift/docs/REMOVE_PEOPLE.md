# Find distractions: People

Build 503 adds People detection to the Remove tool. Select Remove in the J tool group, then choose Find distractions > People. Detection runs on device and stages marks for review. It does not change document pixels, selection or history. Use the existing Add/Subtract brush to refine the marks, then Apply. Detected marks require Apply even when Remove after each stroke is enabled. Clear discards the pending marks. A successful applied batch has one Undo.

The person detector and foreground-subject detector use the same normalized input grid and captured source. A whole person is protected when at least half of the person's weighted coverage overlaps the foreground-subject mask. This is Photato's current classifier. It is not a documented Adobe threshold or a claim of equivalent learned results. Valid no-subject results retain candidates; model failures reject instead of silently marking every person. Sample All Layers retains its existing source semantics. Detection cancellation, source changes, document replacement and sharing revocation cannot publish stale marks.

## Optional Photato API

The existing retouch.remove command gains two operations, findPeople and preview. Dispatch them through the existing document command endpoint and authentication/sharing/revision contract. They do not create a new command name or an Adobe route. findPeople returns normal document/tool state and removePeopleResult containing candidates and protectedForegroundPeople counts. It stages the same native pending marks. Existing stroke operations refine those marks, apply commits them, and cancel clears or cancels them.

preview requires document-transfer permission. It returns revision, removeTool and removalMask with width, height, coverageBase64 and meaning equal to marksBeforeDocumentSelection. Decode the payload as row-major UInt8 coverage before document-selection clipping. Width times height gives its byte count. It never changes pixels or history. The final Apply still respects the captured document selection. Current permission/source/revision checks also run after asynchronous encoding; stale or revoked transfers reject. Discovery includes strict operation schemas, busy/detectingPeople/hasPendingMarks state and current limits.

## Scope and limits

Processing remains the existing traditional native Remove engine. Auto resolves to that engine; generativeOn rejects. Wires and general distractions are disabled. The current Remove canvas limit is 16,777,216 pixels and the solve limit is 4,194,304 pixels; these are unfinished capacity constraints, not Photoshop maximums. Masks/channels and other unsupported targets retain explicit rejection. Semantic Remove Actions and Adobe actionJSON are not implemented. No matching endpoint is claimed in the pinned Firefly Photoshop v2 contract.

The focused tests cover seed/refinement coverage, all RGB depths, protected pixels and original selections, one Undo, archive reopen, native/API equivalence, cancellation, stale sources and permission revocation. A real native portrait comparison now leaves the foreground person unmarked, as the observed Photoshop action did on the same public-domain image. A positive background-person native photo, broad detection quality, defaults/output equality, full AI03, physical platforms, maximum document capacity and 60 fps remain open.
