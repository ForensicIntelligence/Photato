import Foundation
import PhotoCraftCore

public struct RemoveWiresResult: Sendable {
  public let edit: RegionRetouchEdit
  public let candidateTracks: Int
  public let applied: Bool
}

public enum RemoveWiresPreparation {
  public static func prepare(_ document: CraftDocument, layerID: UUID,
    settings: RemoveToolSettings) throws -> RemoveWiresResult {
    try settings.validate(); try document.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb, settings.mode != .generativeOn,
      let index = document.layers.firstIndex(where: { $0.id == layerID }),
      case .raster = document.layers[index].content,
      document.layers[index].smartObject == nil, document.layers[index].sourceProjection == nil,
      !document.ancestors(of: layerID).contains(where: { $0.protection.fullyLocks }),
      settings.createNewLayer || !document.isImageLocked(layerID) else {
      throw CraftError.unsupported("Wire removal requires an ordinary RGB raster layer. Unlock image pixels or choose Create New Layer.")
    }
    var layer = document.layers[index]
    layer.visible = true; layer.style = nil; layer.opacity = 1
    let guide = try settings.sampleAllLayers ? Renderer.compositePaged(document)
      : Renderer.clippingCoverage(layer, in: document)
    let preview = try RasterPreviewRequest.overview(width: document.width, height: document.height,
      maximumSide: WireRidgeDetection.analysisSide)
    let image = try ColorManagement.converted(preview.reducing(guide), from: document, to: CraftDocument(width: 1, height: 1))
    var luma = [Float](repeating: .nan, count: image.width * image.height)
    for y in 0..<image.height {
      try Task.checkCancellation()
      for x in 0..<image.width {
        let pixel = image.pixel(x: x, y: y)
        if pixel.a >= 0.5 { luma[y * image.width + x] = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114) * 255 }
      }
    }
    let reduced = image.width != document.width || image.height != document.height
    let wires = try WireRidgeDetection.detect(luma: luma, width: image.width, height: image.height, reduced: reduced)
    var result = document
    if wires.trackCount > 0 {
      let donors = reduced ? try wires.expanded() : wires
      let patch = try fill(wires, donorExclusion: donors, guide: guide, in: document, reduced: reduced)
      if let bounds = try patch.contentBounds() {
        result = try apply(patch, bounds: bounds, to: document, index: index, newLayer: settings.createNewLayer)
      }
    }
    let changed = result != document
    let label = changed ? "Remove Wires and Cables" : "No wires or cables removed"
    return .init(edit: .init(source: document, result: result, label: label),
      candidateTracks: wires.trackCount, applied: changed)
  }

  private static func fill(_ wires: WireRidgeMap, donorExclusion: WireRidgeMap, guide: Surface,
    in document: CraftDocument, reduced: Bool) throws -> Surface {
    let width = document.width, height = document.height
    let linear = document.depth == .f32
    var patch = try Surface(width: width, height: height, depth: document.depth,
      colorEncoding: linear ? .linearRGB : .sRGB)
    let sx = Double(width) / Double(wires.width), sy = Double(height) / Double(wires.height)
    let normals = (UInt8(1)...8).map { code in
      let unit = WireRidgeMap.unitNormal(code)
      let n = unit * SIMD2(sx, sy)
      return n / hypot(n.x, n.y)
    }
    let scale = max(sx, sy)
    let search = min(512, Int(ceil((reduced ? 20 : 14) * scale)))
    for row in 0..<wires.height {
      try Task.checkCancellation()
      let top = (row * height + wires.height - 1) / wires.height
      let bottom = ((row + 1) * height + wires.height - 1) / wires.height
      for column in 0..<wires.width {
        let code = wires.normals[row * wires.width + column]
        guard code > 0 else { continue }
        let index = Int(code) - 1
        let directions = reduced ? [normals[index], normals[(index + 7) % 8], normals[(index + 1) % 8]] : [normals[index]]
        let left = (column * width + wires.width - 1) / wires.width
        let right = ((column + 1) * width + wires.width - 1) / wires.width
        for y in top..<bottom {
          try Task.checkCancellation()
          for x in left..<right {
            let coverage = document.selectionCoverage(x: x, y: y)
            guard coverage > 0, var replacement = replacement(x: x, y: y, directions: directions,
              search: search, exclusion: donorExclusion, guide: guide, linear: linear, scale: scale) else { continue }
            replacement.a *= coverage
            if linear { patch.setLinearPixel(x: x, y: y, replacement) }
            else { patch.setPixel(x: x, y: y, replacement) }
          }
        }
      }
    }
    return patch
  }

  private static func replacement(x: Int, y: Int, directions: [SIMD2<Double>], search: Int,
    exclusion: WireRidgeMap, guide: Surface, linear: Bool, scale: Double) -> Pixel? {
    let center = linear ? guide.linearPixel(x: x, y: y) : guide.pixel(x: x, y: y)
    guard center.a >= 0.5 else { return nil }
    func shoulder(_ direction: SIMD2<Double>) -> (pixel: Pixel, distance: Double)? {
      for step in 1...search {
        let px = x + Int((direction.x * Double(step)).rounded())
        let py = y + Int((direction.y * Double(step)).rounded())
        guard px >= 0, py >= 0, px < guide.width, py < guide.height else { return nil }
        let ix = px * exclusion.width / guide.width, iy = py * exclusion.height / guide.height
        guard exclusion.normals[iy * exclusion.width + ix] == 0 else { continue }
        let color = linear ? guide.linearPixel(x: px, y: py) : guide.pixel(x: px, y: py)
        if color.a >= 0.5 { return (color, hypot(Double(px - x), Double(py - y))) }
      }
      return nil
    }
    var best: Pixel?, bestCost = Double.infinity
    var fallback: (pixel: Pixel, distance: Double)?
    for (offset, normal) in directions.enumerated() {
      let a = shoulder(-normal), b = shoulder(normal)
      if let a, let b {
        let delta = a.pixel.rgb - b.pixel.rgb
        let gap = a.distance + b.distance
        let difference = Double(abs(delta.x) + abs(delta.y) + abs(delta.z)) / 3
        let cost = difference * 255 + 0.25 * gap / scale + (offset == 0 ? 0 : 0.35)
        if cost < bestCost {
          let rgb = a.pixel.rgb + (b.pixel.rgb - a.pixel.rgb) * Float(a.distance / gap)
          best = Pixel(rgb.x, rgb.y, rgb.z, center.a)
          bestCost = cost
        }
      } else if let nearest = a ?? b, nearest.distance < (fallback?.distance ?? .infinity) {
        fallback = nearest
      }
    }
    if let best { return best }
    guard let nearest = fallback?.pixel else { return nil }
    return Pixel(nearest.r, nearest.g, nearest.b, center.a)
  }

  private static func apply(_ patch: Surface, bounds: IntRect, to document: CraftDocument,
    index: Int, newLayer: Bool) throws -> CraftDocument {
    var result = document
    var layer = result.layers[index]
    if newLayer {
      guard document.layers.count < LayerLimits.maximumLayers else { throw CraftError.invalid("Remove a layer before adding wire removal output.") }
      let parent = layer.parentID
      layer = Layer(name: "Remove Wires and Cables", content: .raster(try patch.cropped(to: bounds)))
      layer.x = bounds.x; layer.y = bounds.y; layer.parentID = parent
      // Above a base layer's clipping stack so clipped artwork keeps its original base.
      var at = index + 1
      while at < result.layers.count, result.layers[at].parentID == parent, result.layers[at].isClipped { at += 1 }
      result.layers.insert(layer, at: at)
    } else {
      let preserve = document.isTransparencyLocked(layer.id)
      let linear = document.depth == .f32
      let edited = try ClonePainter.paintTarget(mask: false, bounds: bounds, on: &layer,
        clipping: bounds, preserveTransparency: preserve) { target, transform, _ in
        let inverse = try transform.inverted()
        let side = Surface.tileSide, columns = (patch.width + side - 1) / side
        var changed = false
        for key in patch.storedTileKeys {
          try Task.checkCancellation()
          let x = (key % columns) * side, y = (key / columns) * side
          let rect = IntRect(x: x, y: y, width: min(side, patch.width - x), height: min(side, patch.height - y))
          let local = try (inverse * .translation(Double(x), Double(y))).bounds(width: rect.width, height: rect.height)
            .clipped(toWidth: target.width, height: target.height)
          for ty in local.y..<(local.y + local.height) {
            for tx in local.x..<(local.x + local.width) {
              let p = transform.point(Double(tx) + 0.5, Double(ty) + 0.5)
              let dx = Int(floor(p.x)), dy = Int(floor(p.y))
              guard rect.contains(dx, dy) else { continue }
              let ink = linear ? patch.linearPixel(x: dx, y: dy) : patch.pixel(x: dx, y: dy)
              guard ink.a > 0 else { continue }
              let old = linear ? target.linearPixel(x: tx, y: ty) : target.pixel(x: tx, y: ty)
              if preserve && old.a == 0 { continue }
              let out: Pixel
              if preserve {
                let rgb = ink.a == 1 ? ink.rgb : old.rgb + (ink.rgb - old.rgb) * ink.a
                out = Pixel(rgb.x, rgb.y, rgb.z, old.a)
              } else if ink.a == 1 { out = ink }
              else { out = BlendMode.normal.composite(backdrop: old, source: ink) }
              guard out != old else { continue }
              if linear { target.setLinearPixel(x: tx, y: ty, out) } else { target.setPixel(x: tx, y: ty, out) }
              changed = true
            }
          }
        }
        return changed
      }
      guard edited else { return document }
      result.layers[index] = layer
    }
    result.activeLayerID = layer.id
    try result.validate(); try Task.checkCancellation()
    return result
  }
}
