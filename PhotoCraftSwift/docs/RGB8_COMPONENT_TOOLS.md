# RGB8 component tools

Checkpoint394 tests these paths on Apple Silicon and translated Intel. All13new cases pass; see [the qualification record](RGB8_COMPONENT_TOOLS_394.json). Full current-suite, live/platform/dense/60fps and exact Photoshop gates remain open.

Ordinary RGB8 documents retain the existing Red, Green, Blue and composite target selector, together with independent preview and visibility state. Effective component targets bridge that representation to the same component command used by native and high-depth documents. Brush/Eraser, Invert and eight basic filter drafts use that target. Unsupported tools and unsafe prepared or mismatched-target writes still reject.

The existing neutral `channel.fill` command and its Fill history label remain. Its small-document byte arithmetic is unchanged. Large ordinary RGB8 fills delegate inside that primitive to the bounded component engine. Unselected colour channels and alpha remain intact. Non-neutral colour-to-gray conversion, profiles and complete Photoshop numerical fidelity retain separate qualification.

Brush gestures retain their captured brush, points, source and session generation. Selected-target changes remain unavailable while a gesture or filter draft is active. Existing paced component preview and final preparation share the same command; cancellation does not add history, and release commits once. This is not a claim of sustained physical60fps or incremental component-stroke acceleration.

The existing `mode.channel.edit` command now accepts an edit matching a legacy RGB8 target. `paint.stroke` with a pixel target captures the selected RGB8/native components and verifies them before prepared commit. Auxiliary and mask targets retain their explicit routes. `documentMode.editingComponents` reports effective indices; the legacy target and view state remain available. No new endpoint or Adobe descriptor is invented. Published Adobe contract coverage remains separately qualified.

Adobe's [Channels panel documentation](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html), updated6October2026, documents editing a selected channel and distinguishes selection from visibility. Its [channel basics](https://helpx.adobe.com/sg/photoshop/using/channel-basics.html) also distinguishes editable-but-hidden from visible-but-unselected channels. These sources establish workflow requirements, not output, CMM, brush-kernel or default equivalence.

Full S05 and C01 remain open. Other component tools, simultaneous visibility and selection contexts, clipboard/transforms, Actions, profile/custom-gray behavior, default/settings/shortcut parity, maximum physical dense capacity, current full-suite success, supported physical Macs/macOS14+, live UI and sustained60fps still require work and evidence. The prior Gray32 one-ULP difference, retained strict failures and three missing older temporary binaries remain recorded.
