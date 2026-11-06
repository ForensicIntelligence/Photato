# Animated selection borders

Selection borders now animate through Core Animation. The existing half-coverage contours, including holes, are retained. The overlay follows zoom, pan and Transform Selection; rectangular, elliptical, row, column and rectangular Object Selection previews use a separate clipped layer. Selection Brush continues to display its coverage overlay.

The white stroke and black dashes stay one screen point wide. The current dash pattern is 4 on/4 off with a 0.8-second cycle. These are implementation values; exact Photoshop timing and visual defaults have not been measured. Core Animation changes the dash phase without a Swift frame timer, canvas redraw request, source render or contour rebuild for every frame. This architecture does not by itself prove physical 60fps.

Playback pauses when the application or document window is inactive, hidden, minimized, occluded or detached. Reduce Motion retains a static border. Repeated geometry updates retain the animation and reuse unchanged mapped paths. Empty selections clear the layers. Zoom/backing/view changes update presentation geometry without changing source pixels.

This adds no editing command, menu, shortcut, cursor action, archive field or Action format. Native archive 86, Actions 49, typed commands 249 and settings 4 remain. Existing menu inventories and modifier behavior are retained. Full Extras/Selection Edges controls, exact Photoshop visual/lifecycle parity and supported physical-platform/performance qualification remain open.

## API

Existing document state adds `selectionDisplay`, with `hasSelection`, `selectionBrushOverlay`, `selectionTransformPreview`, `reduceMotion`, `animationRequested` and `playbackControlledByNativeWindow`. Capabilities and state schemas describe the native presentation. Requested animation is distinct from actual playback in a particular native window. There is no remote frame/keyboard/cursor injection operation, and document revisions, history and output bytes are unchanged. Adobe's published Firefly v2 contract has no selection-border presentation endpoint; none was invented.

## Evidence

The current feature tests cover native layer configuration, cached paths, lifecycle gates, hidden/detached views, coverage/depth/viewport behavior, creation and transform previews, Deselect/Undo, the maximum sparse document extent, native/API data preservation and owned phase/alignment captures. They do not establish exact Photoshop output or physical compositor timing. See [checkpoint 428](SELECTION_BORDERS_428.json) and [the development log](DEVLOG.md#dev-step-428).
