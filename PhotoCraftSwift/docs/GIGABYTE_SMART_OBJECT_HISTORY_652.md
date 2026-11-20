# Undo and Redo for gigabyte-scale originals

19 November 2026 · Development checkpoint 652

When a history state moves to disk, it can retain an existing private file-backed original. Snapshots of the same original share one disk charge. Undo and Redo restore the mapped source with its original bytes, and disposing of the last history reference releases the charge. Ordinary history blobs still use their checked scratch files.

Build 651 rejected a forced history spill on the 1,181,384,274-byte original. Build 652 kept two spilled undo states using 1,181,387,085 bytes of the history allowance. Undo and Redo preserved the exact source and edit. A smaller disk allowance rejected the edit without changing the document or adding a history entry. Optimized Apple Silicon and Intel under Rosetta gave identical results. Prior failure (local evidence) · Apple Silicon result (local evidence) · Intel result (local evidence)

All 29 selected Debug tests passed across history, Smart Objects and native archive negotiation. The new test checks shared disk accounting, Undo and Redo, and atomic rejection. Broader qualification remains open. Focused tests (local evidence) · Source patch and manifest (local evidence)
