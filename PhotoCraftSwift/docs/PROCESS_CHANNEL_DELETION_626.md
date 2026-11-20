# Delete process channels

19 November 2026 · Development preview 626

In an 8- or 16-bit RGB, CMYK or Lab document, select one or more process components in Channels, then choose **Delete Channels** or use the panel trash. Photato converts the surviving components into editable Multichannel plates in their original order. It keeps saved alpha and spot channels, the selection and resolution. At least one process component must remain. The layer merge and channel deletion create a single Undo entry. [Adobe’s channel deletion behavior](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html)

## Implementation

`ProcessChannelDeletion.swift` validates component indices against the current color mode and accepts only a single still canvas outside Quick Mask. `NativeModeRaster.swift` and `InkModeInput.swift` share the existing Multichannel conversion, with a retained-index list so it only extracts the requested plates. The simple aligned path can share native sparse storage. For supported layered CMYK and Lab raster documents, the component compositor can preserve numerical separations, including the independent CMYK black. Other eligible layered inputs use the existing color-mode conversion compositor. Deleting process components from layered artwork requires consent to merge visible layers and discard hidden layers.

`ChannelsPanel.swift`, its native mode rows and `ProcessChannelDeletionControls.swift` route the existing menu command, row menus and trash to the shared prepared edit. The controller checks the document and edit generations after confirmation. Option-clicking the process-channel trash bypasses confirmation. `Engine.swift` shares the prepared commit with automation, including edits made while a process component is active. The saved alpha and spot delete paths retain their own behavior. The native recorder stores the source color mode and component positions in portable Actions format 75.

The typed `channel.deleteProcess` command uses the same prepared edit, with an explicit `mergeVisible` argument for layered inputs. The authenticated capability catalogue documents its schema and document-state eligibility. The Photoshop v2 service has no published process-channel deletion route. [Photato API](AUTOMATION_API.md#delete-process-channels-preview-626)

## Validation

The Apple Silicon SwiftPM Debug build targeted macOS 14 and completed in 139.44 seconds. The selected XCTest run passed 29 cases, including six new cases covering all three modes and two depths, the 300,000 × 300,000 sparse native archive, stored black values in a layered CMYK example, PSD and PSB reopen, malformed and stale requests, confirmation, Undo, and replay. Logs and the verified forward and reverse source patch are in the local experiment directory for 626. The signed Apple Silicon ZIP passed signature and offscreen launch checks after extraction.

A standalone diagnostic linked the compiled imaging engine to write six owned PSD and PSB samples. A separate parser checked their headers and all 48 raw composite words, including the position of surviving components and saved alpha. The initial diagnostic link used the protected default module cache. The second command supplied the existing build cache explicitly and passed. These are comparisons with independently specified sample words. The read-only Photoshop version and document-count request timed out, so live Photoshop numerical equivalence, rich layered case parity, drag-to-trash behavior and broader platform testing remain open.
