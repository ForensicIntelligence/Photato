import PhotoCraftCore

/// Carries the local color difference inward from opaque protected pixels.
/// The generated subject keeps its original colors beyond the correction collar.
struct GenerativeFillEdgeBlend {
  private let bounds: IntRect
  private let field: Surface

  static func prepare(
    in document: CraftDocument, selection: IntRect, gridLimit: Int,
    context: (Double, Double) -> Pixel, generated: (Double, Double) -> Pixel
  ) throws -> Self? {
    let longest = max(selection.width, selection.height)
    let usefulSide = gridLimit - 2
    let halo = (longest + usefulSide - 1) / usefulSide
    let bounds = IntRect(x: selection.x - halo, y: selection.y - halo,
      width: selection.width + 2 * halo, height: selection.height + 2 * halo)
      .clipped(toWidth: document.width, height: document.height)
    let step = max(1, Double(max(bounds.width, bounds.height)) / Double(gridLimit))
    let width = min(gridLimit, Int((Double(bounds.width) / step).rounded(.up)))
    let height = min(gridLimit, Int((Double(bounds.height) / step).rounded(.up)))
    let stepX = Double(bounds.width) / Double(width)
    let stepY = Double(bounds.height) / Double(height)
    let count = width * height
    var protected = [Bool](repeating: true, count: count)
    var boundary = Array(repeating: SIMD3<Float>.zero, count: count)
    var hasCorrection = false
    for y in 0..<height {
      try Task.checkCancellation()
      let docY = Double(bounds.y) + (Double(y) + 0.5) * stepY
      for x in 0..<width {
        let docX = Double(bounds.x) + (Double(x) + 0.5) * stepX
        let index = y * width + x
        if document.selectionCoverage(x: Int(docX), y: Int(docY)) > 0 {
          protected[index] = false
          continue
        }
        let source = context(docX, docY)
        // At the outside of the patch compare with the nearest generated edge.
        let fillX = min(Double(selection.x + selection.width) - 0.5, max(Double(selection.x) + 0.5, docX))
        let fillY = min(Double(selection.y + selection.height) - 0.5, max(Double(selection.y) + 0.5, docY))
        let fill = generated(fillX, fillY)
        guard source.a == 1, fill.a == 1 else { continue }
        let difference = source.rgb - fill.rgb
        let magnitude = max(abs(difference.x), abs(difference.y), abs(difference.z))
        guard magnitude.isFinite, magnitude > 0 else { continue }
        // A strong edge can belong to the new subject. Limit the color correction there.
        boundary[index] = difference * min(1, 0.125 / magnitude)
        hasCorrection = true
      }
    }
    guard hasCorrection, protected.contains(false) else { return nil }

    let distances = try MattingFilters.distance(protected, width, height)
    let collar = max(2, min(12, Double(min(selection.width, selection.height)) / (8 * step)))
    let solve = distances.map { $0 > 0 && Double($0) <= collar }
    guard solve.contains(true) else { return nil }
    let channels = try (0..<3).map { component in
      try HealingSolver.membrane(width: width, height: height, unknown: solve,
        values: boundary.map { $0[component] })
    }
    var field = try Surface(width: width, height: height, depth: .f32)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let index = y * width + x
        field.setPixel(x: x, y: y, Pixel(channels[0][index], channels[1][index], channels[2][index]))
      }
    }
    return Self(bounds: bounds, field: field)
  }

  func adjusted(_ pixel: Pixel, x: Double, y: Double) -> Pixel {
    guard pixel.a == 1 else { return pixel }
    let fieldX = (x - Double(bounds.x)) * Double(field.width) / Double(bounds.width)
    let fieldY = (y - Double(bounds.y)) * Double(field.height) / Double(bounds.height)
    let offset = RasterGeometry.sample(field, x: fieldX, y: fieldY, method: .bilinear, clampEdges: true)
    guard offset.rgb != .zero else { return pixel }
    return Pixel(unit(pixel.r + offset.r), unit(pixel.g + offset.g), unit(pixel.b + offset.b), pixel.a)
  }
}
