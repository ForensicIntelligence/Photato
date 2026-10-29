import Foundation

/// Flat-mode paste uses the same coverage/compositing intent as ordinary paste,
/// while retaining authoritative samples instead of inserting an illegal layer.
enum RestrictedClipboard {
  static func paste(_ content: ClipboardContent, into target: inout CraftDocument,
    placement: PastePlacement, dx: Int, dy: Int) throws {
    guard let raster = target.restrictedMode, let id = target.activeLayerID,
      !target.isImageLocked(id), content.kind == .pixels,
      case .raster(let source) = content.document.layers[0].content else {
      throw CraftError.invalid("Paste into Indexed Color/Bitmap requires flattened pixels and an unlocked image.")
    }
    let old = try raster.surface(); var edited = old
    let originX = content.bounds.x + dx, originY = content.bounds.y + dy
    let area = IntRect(x: originX, y: originY, width: source.width, height: source.height)
      .clipped(toWidth: target.width, height: target.height)
    func coverage(_ x: Int, _ y: Int) -> Float {
      switch placement {
      case .into: target.selectionCoverage(x: x, y: y)
      case .outside: 1 - target.selectionCoverage(x: x, y: y)
      default: 1
      }
    }
    if area.width > 0, area.height > 0 {
      for y in area.y..<area.y + area.height { try Task.checkCancellation(); for x in area.x..<area.x + area.width {
        let p = source.pixel(x: x - originX, y: y - originY), alpha = unit(p.a * coverage(x, y))
        if alpha == 0 { continue }
        let b = old.pixel(x: x, y: y), a = alpha + b.a * (1 - alpha)
        edited.setPixel(x: x, y: y, a > 0 ? Pixel((p.r * alpha + b.r * b.a * (1 - alpha)) / a,
          (p.g * alpha + b.g * b.a * (1 - alpha)) / a, (p.b * alpha + b.b * b.a * (1 - alpha)) / a, a) : .clear)
      } }
    }
    var updated = try raster.reconciled(with: edited, previous: old)
    if case .indexed(let from) = content.restrictedSamples,
      case .indexed(let to) = updated, from.palette == to.palette,
      from.transparentIndex == to.transparentIndex, from.profile == to.profile,
      area.width > 0, area.height > 0 {
      // Opaque full-coverage copies retain source index identity even where the
      // RGB cache cannot distinguish duplicate palette entries.
      var indices = to.indices
      for y in area.y..<area.y + area.height { try Task.checkCancellation(); for x in area.x..<area.x + area.width {
        let sx = x - originX, sy = y - originY
        if source.pixel(x: sx, y: sy).a == 1, coverage(x, y) == 1 {
          indices[y * to.width + x] = from.indices[sy * from.width + sx]
        }
      } }
      updated = .indexed(try to.replacingIndices(indices))
    }
    target.restrictedMode = updated; target.layers[0].content = .raster(try updated.surface())
    target.setCoverageSelection(nil)
  }
}
