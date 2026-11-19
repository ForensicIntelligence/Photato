import CoreGraphics
import PhotoCraftCore

/// Rasterize only the regions occupied by resolved contours. The scalar
/// source keeps the padded coordinates even where no raster pages are needed.
struct VectorFeatherCoverage: Sendable {
  private let plane: FeatheredMask
  private let padding: Int
  private let density: Float
  let support: [IntRect]
  let maximumResidentBytes: Int

  var isIdentity: Bool { density == 0 || (plane.isConstantOutside && adjustedOutside == 1) }
  var adjustedOutside: Float { adjusted(plane.implicitInterior) }

  init(mask: VectorMask, width: Int, height: Int, outside: Float) throws {
    density = mask.density
    let radius = Int(MaskSampler.featherDamageRadius(mask.feather))
    // Bilinear sampling at a document edge can touch one additional position.
    let pad = radius + 1
    padding = pad
    let rawWidth = width + 2 * pad, rawHeight = height + 2 * pad
    let region = try VectorPathGeometry.filledRegion(mask.path)
    let contours = Self.contourBounds(region.path, padding: pad, width: rawWidth, height: rawHeight)
    let fill = Pixel(outside, outside, outside)
    let pieces = try Self.preparePieces(contours, mask: mask, region: region, padding: pad, fill: fill)
    plane = FeatheredMask(vectorPlane: FeatherSamplePlane(
      width: rawWidth, height: rawHeight, outside: outside, pieces: pieces.samples),
      radius: mask.feather, outside: outside)
    maximumResidentBytes = pieces.residentBytes + plane.maximumResidentBytes
    if pieces.samples.isEmpty {
      support = []
    } else {
      support = contours.compactMap {
        let rect = IntRect(x: $0.x - pad - radius, y: $0.y - pad - radius,
          width: $0.width + 2 * radius, height: $0.height + 2 * radius)
          .clipped(toWidth: width, height: height)
        return rect.width > 0 && rect.height > 0 ? rect : nil
      }
    }
  }

  func coverage(x: Double, y: Double) -> Float {
    if density == 0 { return 1 }
    return adjusted(plane.sampleInSource(x: x + Double(padding), y: y + Double(padding)))
  }

  private func adjusted(_ raw: Float) -> Float {
    density == 1 ? raw : 1 - density * (1 - raw)
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
    region: VectorPathGeometry.FilledRegion, padding: Int, fill: Pixel
  ) throws -> (samples: [FeatherSamplePlane.Piece], residentBytes: Int) {
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
    var samples: [FeatherSamplePlane.Piece] = []
    var bytes = 0
    for rect in cells.values.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
      try Task.checkCancellation()
      let origin = PathPoint(Double(rect.x - padding), Double(rect.y - padding))
      var surface = try Surface(width: rect.width, height: rect.height, fill: fill)
      if mask.path.components.first?.operation != .subtract,
        VectorRasterizer.coversCanvasRectangle(mask.path, width: rect.width, height: rect.height, origin: origin)
      {
        let value = 1 - fill.r
        surface = try Surface(width: rect.width, height: rect.height, fill: Pixel(value, value, value))
      } else if rect.width * rect.height > 1_048_576 {
        surface = try VectorRasterizer.pagedCoverage(region, template: surface, origin: origin)
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
      }
      if surface.tileCount != 0 || surface.defaultPixel.r != fill.r {
        samples.append(.init(x: rect.x, y: rect.y, samples: surface))
        bytes += surface.allocatedBytes
      }
    }
    return (samples, bytes)
  }
}
