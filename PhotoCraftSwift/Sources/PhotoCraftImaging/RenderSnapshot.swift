import Foundation
import PhotoCraftCore

/// Immutable, matched document/composite pair. Only the renderer can create a valid snapshot.
public struct RenderSnapshot: Sendable {
  public enum Update: Equatable, Sendable {
    case full, unchanged
    case region(IntRect)
  }
  public let document: CraftDocument
  public let surface: Surface
  public let update: Update
}

extension Renderer {
  /// Reuses pixels only when every compositing input outside the damaged region is unchanged.
  /// Current adjustments are pointwise. A future spatial adjustment must expand its dependency
  /// footprint or opt out here before it can participate in incremental composition.
  public static func render(_ d: CraftDocument, reusing previous: RenderSnapshot? = nil) throws
    -> RenderSnapshot
  {
    try Task.checkCancellation()
    try d.validate()
    let damage = try previous.map { try renderDamage(from: $0.document, to: d) } ?? .full
    let surface: Surface
    switch damage {
    case .full:
      surface = try compositeValidated(d)
    case .unchanged:
      surface = previous!.surface
    case .region(let region):
      let patch = try compositeValidated(d, region: region)
      var result = previous!.surface
      if result.colorEncoding == .linearRGB {
        for y in region.y..<region.y + region.height {
          try Task.checkCancellation()
          for x in region.x..<region.x + region.width {
            result.setLinearPixel(x: x, y: y, patch.linearPixel(x: x, y: y))
          }
        }
      } else {
        try result.mapPixels(in: region) { x, y, _ in patch.pixel(x: x, y: y) }
      }
      surface = result
    }
    try Task.checkCancellation()
    return RenderSnapshot(document: d, surface: surface, update: damage)
  }

  private static func renderDamage(from old: CraftDocument, to d: CraftDocument) throws
    -> RenderSnapshot.Update
  {
    guard old.id == d.id, old.width == d.width, old.height == d.height,
      old.depth == d.depth, old.colorSpace == d.colorSpace, old.sourceICC == d.sourceICC,
      old.workingICC == d.workingICC,
      old.layers.count == d.layers.count
    else { return .full }
    if old != d, (old.layers + d.layers).contains(where: { $0.style != nil || $0.smartFilters != nil }) { return .full }
    let oldPatterns = old.patterns ?? []
    let newPatterns = d.patterns ?? []
    guard oldPatterns.count == newPatterns.count else { return .full }
    for (before, after) in zip(oldPatterns, newPatterns) {
      guard before.id == after.id, before.name == after.name,
        try before.surface.changedTileBounds(comparedTo: after.surface) == nil
      else { return .full }
    }
    var region: IntRect?
    func include(_ r: IntRect) {
      guard r.width > 0, r.height > 0 else { return }
      if let prior = region {
        let x = min(prior.x, r.x)
        let y = min(prior.y, r.y)
        region = IntRect(
          x: x, y: y, width: max(prior.x + prior.width, r.x + r.width) - x,
          height: max(prior.y + prior.height, r.y + r.height) - y)
      } else {
        region = r
      }
    }
    for (before, after) in zip(old.layers, d.layers) {
      try Task.checkCancellation()
      if case .adjustment(let a) = after.content {
        // Exhaustive switch deliberately makes any new adjustment reconsider locality.
        switch a {
        case .levels, .curves, .hueSaturation, .colorBalance, .classic, .colorLookup, .tonalSteps, .gradientMap, .exposure,
          .brightnessContrast, .saturation, .invert, .grayscale:
          break
        }
      }
      var lhs = before
      var rhs = after
      var rasters: [(Surface, Surface, Transform2D, Double)] = []
      if case .raster(let a) = before.content, case .raster(let b) = after.content {
        lhs.content = .fill(.clear)
        rhs.content = .fill(.clear)
        rasters.append((a, b, after.coordinateTransform, after.affine == nil ? 0 : 1))
      }
      if let a = before.mask, let b = after.mask {
        lhs.mask = nil
        rhs.mask = nil
        let properties = after.effectiveMaskProperties
        let feather =
          properties.enabled && properties.feather > 0
          ? ceil(3 * max(0.05, properties.feather)) : 0
        rasters.append((a, b, after.maskCoordinateTransform, feather + 1))
      }
      guard lhs == rhs else { return .full }
      // Equatable treats -0 and +0 as equal. Their signs can affect floating-point output;
      // compare exact scalar representations too. Raster buffers are already stripped and
      // non-rendering source tags need not be serialized. Sorted keys make this deterministic.
      lhs.sourceTags = nil
      rhs.sourceTags = nil
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      guard try encoder.encode(lhs) == encoder.encode(rhs) else { return .full }
      for (a, b, transform, padding) in rasters {
        // Changed geometry can also change mask edge-extension rules. Fully invalidate it.
        guard a.width == b.width, a.height == b.height, a.depth == b.depth else { return .full }
        if let changed = try b.changedTileBounds(comparedTo: a) {
          if case .gradientFill(let fill) = after.content, fill.aligned,
            try fill.frame(for: before, width: d.width, height: d.height)
              != fill.frame(for: after, width: d.width, height: d.height)
          {
            return .full
          }

          include(footprint(changed, transform: transform, padding: padding, document: d))
        }
      }
    }
    return region.map { .region($0) } ?? .unchanged
  }

  private static func footprint(
    _ r: IntRect, transform: Transform2D, padding: Double, document d: CraftDocument
  ) -> IntRect {
    let left = Double(r.x) - padding
    let top = Double(r.y) - padding
    let right = Double(r.x + r.width) + padding
    let bottom = Double(r.y + r.height) + padding
    let corners = [
      transform.point(left, top), transform.point(right, top),
      transform.point(left, bottom), transform.point(right, bottom),
    ]
    // Clip floating-point bounds before converting to Int. Valid layer transforms may map
    // an off-canvas raster far beyond the supported document extent.
    let x0 = Int(max(0, min(Double(d.width), floor(corners.map(\.x).min()!))))
    let y0 = Int(max(0, min(Double(d.height), floor(corners.map(\.y).min()!))))
    let x1 = Int(max(0, min(Double(d.width), ceil(corners.map(\.x).max()!))))
    let y1 = Int(max(0, min(Double(d.height), ceil(corners.map(\.y).max()!))))
    return IntRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
  }
}
