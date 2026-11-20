# Workflow Guide control highlights

19 November 2026 · Development preview 630

Open **Window > Workflow Guide** and choose a lesson. The first step briefly outlines its target. **Back** and **Next** outline the new step, and **Show Me** between them repeats the current outline. For menu commands, the guide points to the menu title, then traces the actual row as the menu or submenu opens.

Duplicate Layer and New Layer can point to the name field and then OK. Save Selection points to Name for a new channel or Channel when replacing an existing one. Load Selection points to its own Channel picker and OK. Export As and Save As have separate format and confirmation cues. The guide leaves focus and editing to the user. The outline uses a brief fade or a steady cue with Reduce Motion. If the floating guide itself hides the target, it moves to the nearest position with room on the display. Unsupported controls still have a written instruction.

`WorkflowGuideContent.swift` holds the instructions and the separation between field and confirmation steps. `WorkflowGuideHighlight.swift` resolves their targets and makes space around the actual controls. `DuplicateLayerControls.swift`, `NewLayerControls.swift` and `ChannelDialog.swift` attach the in-sheet cues. The save and load sheet guards check the selection dialog's mode, so a Channel Options sheet cannot receive their cue. The separate Show Me button has an accessibility identifier and repeats the current step without touching document history.

The authenticated Photato catalogue adds the optional `dialogControl` field to menu targets with a modal cue and uses `loadSelection` for Load Selection. Cue replay remains a desktop interaction. [Photato API](AUTOMATION_API.md#workflow-guide-control-targets-checkpoint-630)

The first Apple Silicon Debug build targeted macOS 14 and passed 19 native and loopback API cases in 11.74 seconds on macOS 27.2. The tests opened the Duplicate Layer, Save Selection, Load Selection and native Save As sheets, checked cue replay and verified that Channel Options received no highlight. This first run preceded the guide-window overlap fix.

The rebuilt Apple Silicon Debug candidate completed in 144.78 seconds and passed the same 19 cases in 8.42 seconds. A real AppKit window was positioned over the highlighted layer and moved clear when the cue replayed. The initial cue, exact submenu placement and all tested dialogs continued to pass. The ad hoc-signed Apple Silicon preview verified after ZIP extraction and produced a 1,000 × 650 offscreen workspace snapshot. All 1,130 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks. Physical pointer interaction, VoiceOver and physical Intel runtime are pending.

[AppKit modal panel events](https://developer.apple.com/documentation/appkit/nspanel/workswhenmodal) · [Motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion)
