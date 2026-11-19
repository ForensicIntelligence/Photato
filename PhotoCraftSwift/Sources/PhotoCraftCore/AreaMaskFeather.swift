/// A staged box filter for the measured whole-pixel RGB32 path and wide layer masks.
/// The source is extended once across the canvas, raster and mask envelope.
/// Each pass narrows to Float32 after division by the area of the square window.
struct AreaMaskFeather: Sendable {
  let bounds: IntRect
  let widths: [Int]
  private let extendEdges: Bool
  private let streamed: Bool
  var support: Int { widths.reduce(0) { $0 + $1 / 2 } }

  static func widths(at radius: Double) -> [Int]? {
    guard (3...MaskProperties.layerFeatherRange.upperBound).contains(radius) else { return nil }
    let r = Int(radius)
    let integer = Double(r) == radius
    guard integer || radius > 100 else { return nil }
    // Whole-pixel settings use the measured main windows and variance correction.
    // For unmeasured wide fractional settings, choose nearby odd windows and
    // match the requested variance as closely as the discrete widths allow.
    let increments = integer ? 0 : Int(3 * (radius - Double(r)) + 0.75)
    var widths = [2 * r + 1, 2 * r - 1, 2 * r - 1]
    for i in 0..<increments { widths[2 - i] += 2 }
    widths.sort(by: >)
    let baseVariance = widths.map { let h = $0 / 2; return h * (h + 1) }.reduce(0, +)
    var remainder = integer ? r : max(0, Int((3 * radius * radius).rounded()) - baseVariance)
    while remainder >= 2 {
      var k = 1
      while (k + 1) * (k + 2) <= remainder { k += 1 }
      widths.append(2 * k + 1)
      remainder -= k * (k + 1)
    }
    return widths
  }

  init?(layer: Layer, source: Surface, radius: Double, canvas: (width: Int, height: Int)?) {
    guard let widths = Self.widths(at: radius) else { return nil }
    let wide = radius > 100
    let raster: Surface?
    if case .raster(let value) = layer.content { raster = value } else { raster = nil }
    guard wide || source.depth == .f32 && raster?.depth == .f32 else { return nil }
    self.widths = widths
    streamed = wide
    if let canvas, let (mx, my) = Self.translation(layer.maskCoordinateTransform),
      let (rx, ry) = Self.translation(layer.coordinateTransform),
      (1...Surface.maxDimension).contains(canvas.width), (1...Surface.maxDimension).contains(canvas.height) {
      let left = min(0, rx, mx), top = min(0, ry, my)
      let right = max(canvas.width, rx + (raster?.width ?? 0), mx + source.width)
      let bottom = max(canvas.height, ry + (raster?.height ?? 0), my + source.height)
      bounds = .init(x: left - mx, y: top - my, width: right - left, height: bottom - top)
      extendEdges = true
    } else {
      guard wide else { return nil }
      let pad = widths.reduce(0) { $0 + $1 / 2 }
      bounds = .init(x: -pad, y: -pad, width: source.width + 2 * pad, height: source.height + 2 * pad)
      extendEdges = false
    }
  }

  private static func translation(_ t: Transform2D) -> (Int, Int)? {
    guard t.a == 1, t.b == 0, t.c == 0, t.d == 1,
      abs(t.tx) <= 1_000_000, abs(t.ty) <= 1_000_000,
      let x = Int(exactly: t.tx), let y = Int(exactly: t.ty) else { return nil }
    return (x, y)
  }

  /// A nil sample plane means the result is uniform across the requested tile.
  func prepare(source: Surface, outside: Float, x: Int, y: Int, width: Int, height: Int)
    -> (samples: [Float]?, uniform: Float)? {
    let pad = support
    let inputX = bounds.x + x - pad, inputY = bounds.y + y - pad
    var w = width + 2 * pad, h = height + 2 * pad
    let boundRight = bounds.x + bounds.width - 1, boundBottom = bounds.y + bounds.height - 1
    let left = extendEdges ? max(inputX, bounds.x) : inputX
    let top = extendEdges ? max(inputY, bounds.y) : inputY
    let right = extendEdges ? min(inputX + w - 1, boundRight) : inputX + w - 1
    let bottom = extendEdges ? min(inputY + h - 1, boundBottom) : inputY + h - 1
    let read = IntRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
      .clipped(toWidth: source.width, height: source.height)
    let implicit = unit(source.defaultPixel.r)
    if read.width == 0 || read.height == 0 { return (nil, outside) }
    let fullyInside = left >= 0 && top >= 0 && right < source.width && bottom < source.height
    if !source.hasFeatherSamples(in: read), implicit == outside || fullyInside { return (nil, implicit) }

    func inputRow(stored: [Float]?, offset: Int) -> [Float] {
      var values = [Float](repeating: outside, count: w)
      let leading = read.x == bounds.x && extendEdges ? stored?[offset] ?? implicit : outside
      let trailing = read.x + read.width - 1 == boundRight && extendEdges
        ? stored?[offset + read.width - 1] ?? implicit : outside
      let start = max(0, read.x - inputX), end = min(w, read.x + read.width - inputX)
      for x in 0..<start { values[x] = leading }
      for x in start..<end { values[x] = stored?[offset + inputX + x - read.x] ?? implicit }
      for x in end..<w { values[x] = trailing }
      return values
    }

    func sourceY(_ row: Int) -> Int {
      let y = inputY + row
      return extendEdges ? min(boundBottom, max(bounds.y, y)) : y
    }
    if streamed {
      let filtered = StreamingAreaFeather.filter(width: w, height: h, widths: widths) { row in
        let sy = sourceY(row)
        guard sy >= read.y, sy < read.y + read.height else { return [Float](repeating: outside, count: w) }
        let line = IntRect(x: read.x, y: sy, width: read.width, height: 1)
        return inputRow(stored: source.featherInput(in: line), offset: 0)
      }
      guard let filtered else { return nil }
      return (filtered, outside)
    }

    let stored = source.featherInput(in: read)
    var data: [Float] = []
    data.reserveCapacity(w * h)
    for row in 0..<h {
      let sy = sourceY(row)
      if sy >= read.y && sy < read.y + read.height {
        data.append(contentsOf: inputRow(stored: stored, offset: (sy - read.y) * read.width))
      } else {
        data.append(contentsOf: repeatElement(outside, count: w))
      }
    }
    for k in widths {
      data = Self.pass(data, width: w, height: h, side: k)
      w -= k - 1
      h -= k - 1
    }
    return (data, outside)
  }

  private static func pass(_ input: [Float], width: Int, height: Int, side: Int) -> [Float] {
    let columns = width - side + 1, rows = height - side + 1
    var horizontal = [Double](repeating: 0, count: columns * height)
    for y in 0..<height {
      let start = y * width, target = y * columns
      var total = 0.0
      for i in 0..<side { total += Double(input[start + i]) }
      horizontal[target] = total
      for x in 1..<columns {
        total += Double(input[start + x + side - 1]) - Double(input[start + x - 1])
        horizontal[target + x] = total
      }
    }
    var vertical = [Double](repeating: 0, count: columns)
    for y in 0..<side {
      let start = y * columns
      for x in 0..<columns { vertical[x] += horizontal[start + x] }
    }
    var result = [Float](repeating: 0, count: rows * columns)
    let area = Double(side * side)
    for y in 0..<rows {
      let start = y * columns
      if y > 0 {
        let entering = (y + side - 1) * columns, leaving = start - columns
        for x in 0..<columns { vertical[x] += horizontal[entering + x] - horizontal[leaving + x] }
      }
      for x in 0..<columns { result[start + x] = Float(vertical[x] / area) }
    }
    return result
  }
}
