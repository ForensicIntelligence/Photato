/// A staged box filter for the measured RGB32 integer-radius pixel-mask path.
/// The source is extended once across the canvas, raster and mask envelope.
/// Each pass narrows to Float32 after division by the area of the square window.
struct AreaMaskFeather: Sendable {
  let bounds: IntRect
  let widths: [Int]
  var support: Int { widths.reduce(0) { $0 + $1 / 2 } }

  static func widths(at radius: Double) -> [Int]? {
    guard (3...100).contains(radius), let r = Int(exactly: radius) else { return nil }
    var widths = [2 * r + 1, 2 * r - 1, 2 * r - 1]
    var remainder = r
    while remainder >= 2 {
      var k = 1
      while (k + 1) * (k + 2) <= remainder { k += 1 }
      widths.append(2 * k + 1)
      remainder -= k * (k + 1)
    }
    return widths
  }

  init?(layer: Layer, source: Surface, radius: Double, canvas: (width: Int, height: Int)) {
    guard let widths = Self.widths(at: radius), source.depth == .f32,
      case .raster(let raster) = layer.content, raster.depth == .f32,
      let (mx, my) = Self.translation(layer.maskCoordinateTransform),
      let (rx, ry) = Self.translation(layer.coordinateTransform),
      (1...Surface.maxDimension).contains(canvas.width), (1...Surface.maxDimension).contains(canvas.height)
    else { return nil }
    let left = min(0, rx, mx), top = min(0, ry, my)
    let right = max(canvas.width, rx + raster.width, mx + source.width)
    let bottom = max(canvas.height, ry + raster.height, my + source.height)
    bounds = .init(x: left - mx, y: top - my, width: right - left, height: bottom - top)
    self.widths = widths
  }

  private static func translation(_ t: Transform2D) -> (Int, Int)? {
    guard t.a == 1, t.b == 0, t.c == 0, t.d == 1,
      abs(t.tx) <= 1_000_000, abs(t.ty) <= 1_000_000,
      let x = Int(exactly: t.tx), let y = Int(exactly: t.ty) else { return nil }
    return (x, y)
  }

  /// A nil sample plane means the result is uniform across the requested tile.
  func prepare(source: Surface, outside: Float, x: Int, y: Int, width: Int, height: Int)
    -> (samples: [Float]?, uniform: Float) {
    let pad = support
    let inputX = bounds.x + x - pad, inputY = bounds.y + y - pad
    var w = width + 2 * pad, h = height + 2 * pad
    let boundRight = bounds.x + bounds.width - 1, boundBottom = bounds.y + bounds.height - 1
    let left = max(inputX, bounds.x), top = max(inputY, bounds.y)
    let right = min(inputX + w - 1, boundRight), bottom = min(inputY + h - 1, boundBottom)
    let read = IntRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
      .clipped(toWidth: source.width, height: source.height)
    let implicit = unit(source.defaultPixel.r)
    if read.width == 0 || read.height == 0 { return (nil, outside) }
    let stored = source.featherInput(in: read)
    if stored == nil && (implicit == outside || (left >= 0 && top >= 0 && right < source.width && bottom < source.height)) {
      return (nil, implicit)
    }

    var data = [Float](repeating: outside, count: w * h)
    for row in 0..<h {
      let sy = min(boundBottom, max(bounds.y, inputY + row))
      guard sy >= read.y, sy < read.y + read.height else { continue }
      for col in 0..<w {
        let sx = min(boundRight, max(bounds.x, inputX + col))
        if sx >= read.x && sx < read.x + read.width {
          data[row * w + col] = stored?[(sy - read.y) * read.width + sx - read.x] ?? implicit
        }
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
