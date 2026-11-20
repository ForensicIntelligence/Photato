# Workflow Guide highlights

19 November 2026 · Development preview 621

Choose a lesson in **Window > Workflow Guide** to highlight its first target. **Back** and **Next** highlight the new step, and **Show Me**, between them, repeats the current cue. The outline is click-through and leaves keyboard focus alone. Reduce Motion uses a steady outline.

For a menu command, the guide first points to the menu bar and then to the exact row or submenu as you open it. It can outline the confirmation in Duplicate Layer, New Layer and Save or Load Selection, the format and Export controls in Export As, and the format picker or confirmation in Save As. An unavailable target gives a text hint. A dialog belongs to its own lesson step, so Save As instructions do not highlight a Duplicate Layer sheet.

## Implementation

`PhotoshopMenus.swift` and `DocumentWindowMenus.swift` forward open and close events from the app’s own menus. In a native AppKit probe, the row lacked a screen frame until AppKit laid out the menu. `WorkflowGuideHighlight.swift` waits briefly for that frame in the tracking run loop, draws above the popup, and removes the cue when the menu closes. Menu identifiers locate each command and keep the existing shortcuts and hierarchy intact.

`WorkflowGuide.swift` keeps Show Me in the walkthrough and clears old cues when leaving a step, document, or sheet. `WorkflowGuideContent.swift` binds modal steps to named dialogs. SwiftUI sheets draw on their own controls. The native Save As accessory can live in a different window from the AppKit panel, so the outline is attached to the actual picker. The authenticated Photato catalogue adds the optional step-target `dialog` field. Highlighting does not record usage or change document history. [API contract](AUTOMATION_API.md#workflow-guide-menu-and-dialog-highlights-preview-621)

## Validation

The first probe needed a main-actor entry point and host access to the macOS UI service. The initial build rejected a timer argument sent across actor isolation. The timer now stops through its main-actor owner. The first modal tests exposed a bad width assumption and a 65-point positioning error when a separate overlay window was used for the Save As format picker. The accessory now draws its outline in the picker’s own view. The individual attempts are retained in the local `artifacts/621-workflow-cues/` directory.

The Apple Silicon preview builds with `swift build --build-tests --triple arm64-apple-macosx14.0`. The first passing focused run covered 11 tests, including native AppKit popup tracking, exact submenu and sheet targets, replay without advancing, the authenticated API catalogue, the menu and shortcut reference, and the Image Processor settings regression. Its signed preview ZIP verified after extraction and produced a 1,000 × 650 native workspace snapshot. The preview has its own bundle identifier for local testing. Physical menu-bar navigation, VoiceOver and the new cues on Intel are pending.

A follow-up removed the manual replay from the Duplicate Layer and Save As setup in `WorkflowGuideTests.swift`. The selected-layer cue appeared on the first start. Neither sheet received its automatic cue in `focused-guide-recheck01.log`, leaving nine passes out of 11. The guide now listens to the parent window’s sheet presentation event and waits for its matching control. The wait ends if the sheet closes or the lesson, step or document changes. [AppKit sheet notification](https://developer.apple.com/documentation/appkit/nswindow/willbeginsheetnotification)

The repaired macOS 14-targeted Debug build took 124.54 seconds on Apple Silicon. Running XCTest against the repaired bundle passed all 11 selected cases in 5.73 seconds on macOS 27.2. The guide outlined the Duplicate Layer confirmation and native Save As format popup on presentation, before the test called Show Me. The same tests confirmed click-through behavior, replay on the same step, correct submenu rows, and an unrelated sheet receiving no cue. The build and native test logs are `build-recheck02.log` and `focused-guide-recheck02.log`. All seven changed Swift source and test files match the tested snapshot.

The rebuilt Apple Silicon archive passed strict signature verification after extraction. Its executable produced a native 1,000 × 650 workspace snapshot in the offscreen launch check. Package and source receipts are in the local `automatic-sheet-preview` directory. Its ZIP SHA-256 is `88fe9f42f36482c7b7ff7786da8a4519b7b194eb9ae3d7d2c51eb8aa6754040c`.
