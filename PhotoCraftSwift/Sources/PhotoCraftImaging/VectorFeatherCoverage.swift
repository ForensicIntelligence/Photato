import CoreGraphics
import PhotoCraftCore

/// Rasterize only the regions occupied by resolved contours. The scalar
/// source keeps the padded coordinates even where no raster pages are needed.
struct VectorFeatherCoverage: Sendable {
  private let plane: FeatheredMask
  private let padding: Int
  private let density: Float
  private let isRegionLimited: Bool
  private let globalRectangle: IntRect?
  let support: [IntRect]
  let maximumResidentBytes: Int
  let transferredInputPixels: Int

  var isIdentity: Bool { density == 0 || (!isRegionLimited && plane.isConstantOutside && adjustedOutside == 1) }
  var adjustedOutside: Float { adjusted(plane.implicitInterior) }

  init(mask: VectorMask, width: Int, height: Int, outside: Float, viewport: IntRect? = nil) throws {
    density = mask.density
    isRegionLimited = viewport != nil
    let radius = Int(MaskSampler.featherDamageRadius(mask.feather))
    // Bilinear sampling at a document edge can touch one additional position.
    let pad = radius + 1
    padding = pad
    let rawWidth = width + 2 * pad, rawHeight = height + 2 * pad
    let region = try VectorPathGeometry.filledRegion(mask.path)
    let contours = Self.contourBounds(region.path, padding: pad, width: rawWidth, height: rawHeight)
    let fill = Pixel(outside, outside, outside)
    // Retain the full source footprint of every cache tile touched by the
    // viewport. This also preserves the origin and order of both filter passes.
    let margin = radius + FeatheredMask.vectorTileSide(radius: mask.feather)
    let window = viewport.map {
      IntRect(x: $0.x + pad - margin, y: $0.y + pad - margin,
        width: $0.width + 2 * margin, height: $0.height + 2 * margin)
        .clipped(toWidth: rawWidth, height: rawHeight)
    }
    let source: FeatherSamplePlane
    let residentBytes: Int
    let hasSamples: Bool
    let rawSupport: [IntRect]?
    let integerRectangle = VectorRasterizer.integerRectangle(mask.path)
    globalRectangle = viewport == nil ? integerRectangle : nil
    if let rectangle = integerRectangle {
      let scope = window ?? IntRect(x: 0, y: 0, width: rawWidth, height: rawHeight)
      var local = IntRect(x: rectangle.x + pad - scope.x, y: rectangle.y + pad - scope.y,
        width: rectangle.width, height: rectangle.height).clipped(toWidth: scope.width, height: scope.height)
      local.x += scope.x
      local.y += scope.y
      source = FeatherSamplePlane(width: rawWidth, height: rawHeight, outside: outside, rectangle: local)
      residentBytes = 0
      transferredInputPixels = 0
      hasSamples = local.width > 0 && local.height > 0
      rawSupport = nil
    } else {
      let pieces = try Self.preparePieces(contours, mask: mask, region: region, padding: pad,
        fill: fill, window: window)
      source = FeatherSamplePlane(width: rawWidth, height: rawHeight, outside: outside, pieces: pieces.samples)
      residentBytes = pieces.residentBytes
      transferredInputPixels = pieces.transferredPixels
      hasSamples = !pieces.samples.isEmpty
      rawSupport = pieces.rawSupport
    }
    plane = FeatheredMask(vectorPlane: source, radius: mask.feather, outside: outside)
    maximumResidentBytes = residentBytes + plane.maximumResidentBytes
    if !hasSamples {
      support = []
    } else {
      let boundingSupport = contours.compactMap {
        let rect = IntRect(x: $0.x - pad - radius, y: $0.y - pad - radius,
          width: $0.width + 2 * radius, height: $0.height + 2 * radius)
          .clipped(toWidth: width, height: height)
        return rect.width > 0 && rect.height > 0 ? rect : nil
      }
      if let rawSupport, boundingSupport.count <= 32 {
        // Wide window sums can retain a tiny residual within their cache tile.
        // Admit the whole cache footprint, intersected with the original support.
        let margin = radius + (mask.feather > 100 ? FeatheredMask.vectorTileSide(radius: mask.feather) : 0)
        support = Self.refinedSupport(rawSupport, within: boundingSupport, padding: pad, margin: margin)
      } else {
        support = boundingSupport
      }
    }
  }

  func coverage(x: Double, y: Double) -> Float {
    if density == 0 { return 1 }
    return adjusted(plane.sampleInSource(x: x + Double(padding), y: y + Double(padding)))
  }

  func rectangleIsUnit(width: Int, height: Int) throws -> Bool? {
    guard let rectangle = globalRectangle else { return nil }
    // Density is monotone over unit coverage, including when Float32 rounds
    // even the least possible coverage back to one.
    if adjusted(0) == 1 { return true }
    if adjustedOutside == 1 {
      let x = max(0, min(width - 1, rectangle.x + rectangle.width / 2))
      let y = max(0, min(height - 1, rectangle.y + rectangle.height / 2))
      if coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) != 1 { return false }
    } else {
      for y in [0, height - 1] {
        for x in [0, width - 1] {
          if coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) != 1 { return false }
        }
      }
    }
    return try plane.rectangleSamplesAreUnit(in: IntRect(x: padding, y: padding, width: width, height: height)) {
      adjusted($0)
    }
  }

  private func adjusted(_ raw: Float) -> Float {
    density == 1 ? raw : 1 - density * (1 - raw)
  }

  private struct RawSupport {
    static let maximumRectangles = 4_096
    var rectangles: [IntRect] = []
    var remainingTiles = 65_536

    mutating func record(_ surface: Surface, at rect: IntRect, outside: Float) throws -> Bool {
      if surface.defaultPixel.r != outside {
        rectangles.append(rect)
        return rectangles.count <= Self.maximumRectangles
      }
      guard surface.tileCount <= remainingTiles else { return false }
      remainingTiles -= surface.tileCount
      let side = Surface.tileSide, columns = (surface.width + side - 1) / side
      let keys = surface.storedTileKeys.makeIterator()
      var next = keys.next()
      while let first = next {
        try Task.checkCancellation()
        let row = first / columns
        var end = first + 1
        next = keys.next()
        while let key = next, key == end, key / columns == row {
          end += 1
          next = keys.next()
        }
        let x = first % columns * side, y = row * side
        rectangles.append(IntRect(x: rect.x + x, y: rect.y + y,
          width: min(surface.width - x, (end - first) * side), height: min(side, surface.height - y)))
        if rectangles.count > Self.maximumRectangles { return false }
      }
      return true
    }
  }

  private static func refinedSupport(_ raw: [IntRect], within original: [IntRect],
    padding: Int, margin: Int
  ) -> [IntRect] {
    var result: [IntRect] = []
    for run in raw {
      for boundary in original {
        let x = max(boundary.x, run.x - padding - margin)
        let y = max(boundary.y, run.y - padding - margin)
        let endX = min(boundary.x + boundary.width, run.x + run.width - padding + margin)
        let endY = min(boundary.y + boundary.height, run.y + run.height - padding + margin)
        if endX > x && endY > y {
          result.append(IntRect(x: x, y: y, width: endX - x, height: endY - y))
          if result.count > RawSupport.maximumRectangles { return original }
        }
      }
    }
    return result
  }

  private static func contourBounds(_ path: CGPath, padding: Int, width: Int, height: Int) -> [IntRect] {
    var result: [IntRect] = []
    var contour = CGMutablePath()
    func append() {
      let bounds = contour.boundingBoxOfPath
      if bounds.isNull || bounds.isEmpty { return }
      let left = Int(floor(bounds.minX)) + padding - 1
      let top = Int(floor(bounds.minY)) + padding - 1
      let right = Int(ceil(bounds.maxX)) + padding + 1
      let bottom = Int(ceil(bounds.maxY)) + padding + 1
      let rect = IntRect(x: left, y: top, width: right - left, height: bottom - top)
        .clipped(toWidth: width, height: height)
      if rect.width > 0 && rect.height > 0 { result.append(rect) }
    }
    path.applyWithBlock { element in
      let points = element.pointee.points
      switch element.pointee.type {
      case .moveToPoint:
        append()
        contour = CGMutablePath()
        contour.move(to: points[0])
      case .addLineToPoint: contour.addLine(to: points[0])
      case .addQuadCurveToPoint: contour.addQuadCurve(to: points[1], control: points[0])
      case .addCurveToPoint: contour.addCurve(to: points[2], control1: points[0], control2: points[1])
      case .closeSubpath: contour.closeSubpath()
      @unknown default: break
      }
    }
    append()
    return result
  }

  private static func preparePieces(_ contours: [IntRect], mask: VectorMask,
    region: VectorPathGeometry.FilledRegion, padding: Int, fill: Pixel, window: IntRect?
  ) throws -> (samples: [FeatherSamplePlane.Piece], residentBytes: Int, transferredPixels: Int, rawSupport: [IntRect]?) {
    let block = 8192
    struct Cell: Hashable {
      let column: Int
      let row: Int
    }
    var cells: [Cell: IntRect] = [:]
    for rect in contours {
      let right = rect.x + rect.width, bottom = rect.y + rect.height
      for row in (rect.y / block)...((bottom - 1) / block) {
        try Task.checkCancellation()
        for column in (rect.x / block)...((right - 1) / block) {
          let left = max(rect.x, column * block), top = max(rect.y, row * block)
          let x1 = min(right, (column + 1) * block), y1 = min(bottom, (row + 1) * block)
          let key = Cell(column: column, row: row)
          if let previous = cells[key] {
            let x = min(left, previous.x), y = min(top, previous.y)
            cells[key] = IntRect(x: x, y: y, width: max(x1, previous.x + previous.width) - x,
              height: max(y1, previous.y + previous.height) - y)
          } else {
            cells[key] = IntRect(x: left, y: top, width: x1 - left, height: y1 - top)
          }
        }
      }
    }
    let rectangle = VectorRasterizer.axisAlignedRectangle(mask.path) != nil
    var samples: [FeatherSamplePlane.Piece] = []
    var rawSupport = window == nil ? RawSupport() : nil
    var bytes = 0, transferredPixels = 0
    for rect in cells.values.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
      try Task.checkCancellation()
      let entire = IntRect(x: 0, y: 0, width: rect.width, height: rect.height)
      let scope = window.map {
        IntRect(x: $0.x - rect.x, y: $0.y - rect.y, width: $0.width, height: $0.height)
          .clipped(toWidth: rect.width, height: rect.height)
      } ?? entire
      guard scope.width > 0, scope.height > 0 else { continue }
      let origin = PathPoint(Double(rect.x - padding), Double(rect.y - padding))
      var surface = try Surface(width: rect.width, height: rect.height, fill: fill)
      if mask.path.components.first?.operation != .subtract,
        VectorRasterizer.coversCanvasRectangle(mask.path, width: rect.width, height: rect.height, origin: origin)
      {
        let value = 1 - fill.r
        surface = try Surface(width: rect.width, height: rect.height, fill: Pixel(value, value, value))
      } else if rect.width * rect.height > 1_048_576 {
        surface = try VectorRasterizer.pagedCoverage(region, template: surface, origin: origin,
          window: scope == entire ? nil : scope, clipRectangle: rectangle, compactTransfer: window == nil)
        transferredPixels += scope.width * scope.height
      } else {
        let raw = try VectorRasterizer.coverageBytes(region, width: rect.width, height: rect.height,
          origin: origin)
        for y in 0..<rect.height {
          try Task.checkCancellation()
          for x in 0..<rect.width {
            let value = Float(raw[y * rect.width + x]) / 255
            if value != fill.r { surface.setPixel(x: x, y: y, Pixel(value, value, value)) }
          }
        }
        transferredPixels += rect.width * rect.height
      }
      if surface.tileCount != 0 || surface.defaultPixel.r != fill.r {
        samples.append(.init(x: rect.x, y: rect.y, samples: surface))
        bytes += surface.allocatedBytes
        if try rawSupport?.record(surface, at: rect, outside: fill.r) == false { rawSupport = nil }
      }
    }
    return (samples, bytes, transferredPixels, rawSupport?.rectangles)
  }
}
