import AppKit
import PhotoCraftCore

extension CraftCanvas {
  /// Pointer feedback can move while pixel preparation is still in flight.
  /// Invalidate both positions, including same-document source crosses; an
  /// unclipped source overlay is the exceptional whole-image case.
  func retouchFeedbackDamage(from previous: CGPoint?, to next: CGPoint?) -> CGRect {
    let state = store.cloneState
    if store.tool.samplesRetouchSource, state.showOverlay, !state.clippedOverlay,
      !(state.autoHideOverlay && store.cloneDraft != nil) {
      return imageRect.intersection(bounds)
    }
    var dirty = CGRect.null
    for point in [previous, next].compactMap({ $0 }) {
      let center = viewPoint(point), radius = store.retouchSettings.brush.size * scale / 2 + 3
      dirty = dirty.union(CGRect(x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2))
      let mapping = store.tool.samplesRetouchSource
        ? store.cloneDraft?.mapping ?? (try? state.slot.mapping(
            at: PathPoint(point.x, point.y), target: store, aligned: store.retouchSettings.aligned))
        : nil
      if state.slot.store === store, let mapping, let transform = try? mapping.transform() {
        let source = transform.point(point.x, point.y)
        let cross = viewPoint(CGPoint(x: source.x, y: source.y))
        dirty = dirty.union(CGRect(x: cross.x - 9, y: cross.y - 9, width: 18, height: 18))
      }
    }
    dirty = dirty.intersection(imageRect).intersection(bounds)
    guard !dirty.isNull && !dirty.isEmpty else { return dirty }
    guard viewport.resolvedZoom >= 1 else { return dirty.integral }
    // Quartz can choose a different nearest-neighbor sample at a clipped edge
    // that bisects a source pixel. Align to both source and backing pixel grids.
    // A fractional pan or noncommensurate zoom keeps the ordinary full redraw.
    let backing = viewport.backing, pixelScale = scale * backing
    let origin = CGPoint(x: imageRect.minX * backing, y: imageRect.minY * backing)
    guard abs(origin.x - origin.x.rounded()) < 1e-9,
      abs(origin.y - origin.y.rounded()) < 1e-9,
      let denominator = (1...1000).first(where: {
        abs(pixelScale * Double($0) - (pixelScale * Double($0)).rounded()) < 1e-9
      }) else { return bounds }
    let grid = (pixelScale * Double(denominator)).rounded() / backing
    let x = imageRect.minX + floor((dirty.minX - imageRect.minX) / grid) * grid
    let y = imageRect.minY + floor((dirty.minY - imageRect.minY) / grid) * grid
    let right = imageRect.minX + ceil((dirty.maxX - imageRect.minX) / grid) * grid
    let bottom = imageRect.minY + ceil((dirty.maxY - imageRect.minY) / grid) * grid
    return CGRect(x: x, y: y, width: right - x, height: bottom - y).intersection(bounds)
  }
  func invalidateRetouchFeedback(from previous: CGPoint?) {
    let dirty = retouchFeedbackDamage(from: previous, to: cloneHover)
    if !dirty.isNull && !dirty.isEmpty { setNeedsDisplay(dirty) }
  }
}
