# Channels and Workflow Guide integration

19 November 2026 · Development preview 627

The first combined candidate brought the automatic Duplicate Layer and Save As cues from 621 into the current channel work through 626. It retained the menu inventory and inherited API catalogue updates. The build also included the isolated Sky wheel fixtures from the 620 validation repair.

The first Apple Silicon Debug build completed in 142.98 seconds. Its integrated XCTest run passed 43 of 44 cases. Process-channel deletion, both automatic dialog cues, and all five Sky containment cases passed. During native popup tracking, the parent menu row for **Layer > New** was outside its outline at the sample point. The separate 621 Debug regression reproduced the same assertion and passed 973 out of 974 cases. The first candidates' binaries, logs, and source patches are retained.

The menu outline previously stopped polling as soon as AppKit supplied a nonempty row frame. `WorkflowGuideHighlight.swift` now keeps watching for the brief menu opening period and moves the existing click-through outline if AppKit reports a new frame. This reuses the same dismissal and menu-close behavior. `WorkflowGuideTests.swift` records the row and outline frames in any future assertion failure. The original assertion remains in place.

The repaired macOS 14-targeted Apple Silicon Debug build completed in 128.03 seconds. All 44 selected cases passed in 45.87 seconds, and the submenu test passed five further invocations. The repaired source patch verifies in both directions against 626. The ad hoc-signed Apple Silicon archive verified after extraction and produced a 1,000 × 650 native workspace snapshot. This launch check used the exact extracted executable. The inherited 1,120-case matrix is running on Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. The optimized and physical macOS 14 gates remain open.

[Process-channel preview](PROCESS_CHANNEL_DELETION_626.md) · [Workflow Guide preview](WORKFLOW_GUIDE_HIGHLIGHTS_621.md) · [Sky input tests](SKY_WHEEL_TEST_INPUT_620.md)
