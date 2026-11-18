<a id="dev-step-552"></a>

## 2026-11-18 — Add brush opacity and flow number keys

The installed Photoshop 2026 session was inaccessible because the Mac was locked. The Brush and Pencil guide and Adobe's keyboard reference document number-key opacity, Shift-number flow and the Airbrush modifier reversal. An Adobe employee also records double-zero opacity. The native canvas previously sent these inputs through its unrelated tool and AppKit fallbacks.

BrushEditing.swift maps the Brush and Brush-mode Eraser percentage controls, including Airbrush, and maps opacity for Pencil and Pencil-mode Eraser. A single digit applies its tens value and 0 applies 100%. A second digit combines within Photato's 0.5-second interval. CanvasView.swift holds the prefix per focused canvas, clears it on focus or tool changes and pointer down, and keeps text fields, modal edits and system-modified keys outside the binding. The existing captured Brush value continues through the current stroke. WorkspaceTools.swift adds the active bindings to the Brush field help. An AppKit event probe confirmed that the keyboard layout translation recovers digits from Shift-number punctuation and recognizes keypad input.

AutomationBrushes.swift exposes the corresponding desktop binding and the existing brush.configure paths. The change uses the same settings and API revision, without a new route, menu command, document format or history entry. BrushWorkflowTests.swift covers exact values and Airbrush, focus and active stroke capture, and HTTP state, stale revisions and resulting pixels. Info.plist advances the build to 552.

The saved Photoshop sheets were checked independently of any cursor offset. For all 24 dabs in the larger sheet and all four isolated 13 px dabs in the earlier document, two positive-alpha samples are farther apart than the diameter of Photato's current round-tip support. The 41 px, 0% hardness case spans 66.85 px between its farthest nonzero samples. The 41 px, 100% hardness case spans 43.93 px. Photato's positive support is strictly less than 42 px in both cases. No change of the center or the interior falloff alone can reproduce those samples. A broader raster bound, independent subpixel controls and a coverage law remain open. The Photoshop reference analysis has no effect on the production rasterizer.

A separate fit trained only on 7, 12 and 21 px samples. The first attempt exposed asymmetric low-alpha bounds, so the main sheet uses the recorded click minus one pixel per axis. The corrected 0% hardness Gaussian stayed within two alpha levels on the 3, 13 and 41 px holdouts and the earlier two 13 px soft dabs. The 100% hardness feather model missed the 3 px holdout by up to 103 levels. Both fits remain diagnostic.

The first qualification caught a shared guard that treats an ongoing brush gesture as a modal edit, preventing the keyboard setting from reaching the next stroke. The failed test binaries and logs were preserved. CurvesControls.swift and BrushLibrary.swift now let numeric configuration proceed during a brush gesture while retaining the other edit guards. The stroke entry point retains its existing admission rules.

All 404 selected tests passed in three configurations after the repair. Both packaged runtimes passed the offscreen check. All 146 raster buffers match build 551 on both architectures. [Qualification](SOURCE_PUBLICATION_552.md).
