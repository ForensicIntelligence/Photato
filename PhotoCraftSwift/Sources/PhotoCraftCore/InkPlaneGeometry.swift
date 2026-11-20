import Foundation

/// Numeric printing plates share the existing interpolation and immutable
/// component scratch store. Geometry never assembles a dense RGBA cache.
enum InkPlaneGeometry {
  static func render(_ source: InkPlane, in bounds: IntRect, transform: Transform2D, inverse: Transform2D,
    method: Resampling, grid: RasterGridMap?, fill: UInt32, background: Float, clampEdges: Bool,
    budget: ComponentScratchBudget) throws -> InkPlane {
    try Task.checkCancellation()
    if let grid {
      let first = grid.destination(0, 0), last = grid.destination(source.width - 1, source.height - 1)
      let inside = IntRect(x: min(first.0, last.0), y: min(first.1, last.1),
        width: abs(first.0 - last.0) + 1, height: abs(first.1 - last.1) + 1)
        .clipped(toWidth: bounds.width, height: bounds.height)
      if !clampEdges || inside == bounds {
        return try renderGrid(source, in: bounds, grid: grid, inside: inside, fill: fill, budget: budget)
      }
    }
    return try resample(source, in: bounds, transform: transform, inverse: inverse,
      method: grid == nil ? method : .nearest, fill: fill, background: background,
      clampEdges: clampEdges, budget: budget)
  }

  private static func renderGrid(_ source: InkPlane, in bounds: IntRect, grid: RasterGridMap,
    inside: IntRect, fill: UInt32, budget: ComponentScratchBudget) throws -> InkPlane {
    let width = bounds.width, height = bounds.height
    let implicit = inside.width * inside.height > width * height / 2 ? source.defaultWord : fill
    let template = try ComponentPlane(width: width, height: height, depth: source.depth, defaultWord: implicit)
    guard inside.width > 0, inside.height > 0 else { return try InkPlane(storage: template) }
    let builder = try ComponentPlaneBuilder(plane: template, reserve: budget.reserve)

    func write(_ area: IntRect, word: UInt32) throws {
      for y in area.y..<(area.y + area.height) {
        try Task.checkCancellation()
        for x in area.x..<(area.x + area.width) { try builder.setWord(word, at: y * width + x) }
      }
    }
    if implicit != source.defaultWord {
      try write(inside, word: source.defaultWord)
    } else if implicit != fill {
      let right = inside.x + inside.width, bottom = inside.y + inside.height
      try write(.init(x: 0, y: 0, width: width, height: inside.y), word: fill)
      try write(.init(x: 0, y: bottom, width: width, height: height - bottom), word: fill)
      try write(.init(x: 0, y: inside.y, width: inside.x, height: inside.height), word: fill)
      try write(.init(x: right, y: inside.y, width: width - right, height: inside.height), word: fill)
    }
    try source.forEachNondefaultWord { index, word in
      let (x, y) = grid.destination(index % source.width, index / source.width)
      if inside.contains(x, y) { try builder.setWord(word, at: y * width + x) }
    }
    return try InkPlane(storage: builder.finish())
  }

  private static func resample(_ source: InkPlane, in bounds: IntRect, transform: Transform2D,
    inverse: Transform2D, method: Resampling, fill: UInt32, background: Float, clampEdges: Bool,
    budget: ComponentScratchBudget) throws -> InkPlane {
    let width = bounds.width, height = bounds.height
    let scale: Float = source.depth == .u8 ? 255 : 65535
    let halo = method == .nearest ? 0 : method == .bilinear ? 1 : 2
    let inset = method == .nearest ? 0 : Double(halo) - 0.5
    let corners = [inverse.point(0.5, 0.5), inverse.point(Double(width) - 0.5, 0.5),
      inverse.point(0.5, Double(height) - 0.5), inverse.point(Double(width) - 0.5, Double(height) - 0.5)]
    let complete = corners.allSatisfy {
      $0.x >= inset && $0.y >= inset
        && $0.x < Double(source.width) - inset && $0.y < Double(source.height) - inset
    }
    let resize = clampEdges && transform.b == 0 && transform.c == 0 && transform.tx == 0 && transform.ty == 0
      && abs(transform.a * Double(source.width) - Double(width)) < 1e-8
      && abs(transform.d * Double(source.height) - Double(height)) < 1e-8
    let implicit = complete || clampEdges ? source.defaultWord : fill
    let canProject = clampEdges ? resize || complete : complete || source.defaultWord == fill
    let template = try ComponentPlane(width: width, height: height, depth: source.depth, defaultWord: implicit)
    let regions = try canProject ? projectedSupport(of: source, with: transform, in: bounds, halo: halo) : nil
    let builder = try ComponentPlaneBuilder(plane: template, reserve: budget.reserve)
    for region in GeometryPatchRegions(width: width, height: height, rectangles: regions ?? [bounds]) {
      for y in region.y..<(region.y + region.height) {
        try Task.checkCancellation()
        for x in region.x..<(region.x + region.width) {
          var point = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
          if clampEdges {
            point.x = min(Double(source.width) - 0.5, max(0.5, point.x))
            point.y = min(Double(source.height) - 0.5, max(0.5, point.y))
          }
          guard point.x >= 0, point.x < Double(source.width),
            point.y >= 0, point.y < Double(source.height) else { continue }
          let word: UInt32
          if method == .nearest {
            word = source.rawWord(at: Int(point.y) * source.width + Int(point.x))
          } else {
            let sample = RasterGeometry.sampleValues(width: source.width, height: source.height,
              x: point.x, y: point.y, method: method, clampEdges: clampEdges) { sx, sy in
              guard sx >= 0, sx < source.width, sy >= 0, sy < source.height else { return .clear }
              let value = source.value(at: sy * source.width + sx)
              return Pixel(value, value, value)
            }
            word = UInt32((unit(sample.r * sample.a + background * (1 - sample.a)) * scale).rounded())
          }
          if word != implicit { try builder.setWord(word, at: y * width + x) }
        }
      }
    }
    return try InkPlane(storage: builder.finish())
  }

  private static func projectedSupport(of source: InkPlane, with transform: Transform2D, in bounds: IntRect,
    halo: Int) throws -> [IntRect]? {
    var support: [IntRect] = []
    func project(x: Int, y: Int, width: Int, height: Int) {
      let left = Double(x - halo), top = Double(y - halo)
      let right = Double(x + width + halo), bottom = Double(y + height + halo)
      let corners = [transform.point(left, top), transform.point(right, top),
        transform.point(left, bottom), transform.point(right, bottom)]
      let x0 = Int(floor(corners.map(\.x).min()!)) - 1, y0 = Int(floor(corners.map(\.y).min()!)) - 1
      let x1 = Int(ceil(corners.map(\.x).max()!)) + 1, y1 = Int(ceil(corners.map(\.y).max()!)) + 1
      let rect = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        .clipped(toWidth: bounds.width, height: bounds.height)
      if rect.width > 0, rect.height > 0 { support.append(rect) }
    }
    for (block, range) in source.storedSampleRanges.enumerated() {
      try Task.checkCancellation()
      if block == 256 { return nil }
      let first = range.lowerBound / source.width, last = (range.upperBound - 1) / source.width
      let x = range.lowerBound % source.width
      if first == last {
        project(x: x, y: first, width: range.count, height: 1)
      } else {
        project(x: x, y: first, width: source.width - x, height: 1)
        if last > first + 1 { project(x: 0, y: first + 1, width: source.width, height: last - first - 1) }
        project(x: 0, y: last, width: (range.upperBound - 1) % source.width + 1, height: 1)
      }
    }
    return support
  }
}
