/// Staged square windows and measured short kernels for raster-layer masks.
/// The source is extended once across the canvas, raster and mask envelope.
/// Each square pass stores either a Float32 average or a rounded integer sample.
struct AreaMaskFeather: Sendable {
  let bounds: IntRect
  let widths: [Int]
  let extendEdges: Bool
  private let streamed: Bool
  private let integerDepth: PixelDepth?
  private let taps: [Int]?
  private let quarterPixel: Bool
  var support: Int { widths.reduce(0) { $0 + $1 / 2 } }

  private static let dyadicTaps: [Double: [Int]] = [
    0.5: [1, 55, 144, 55, 1],
    1.25: [1, 6, 25, 57, 78, 57, 25, 6, 1],
  ]

  // Photoshop's two builds select different discrete windows at some fractional
  // settings. These sequences come from matching saved RGB32 mask samples.
  private static func fractionalRGB32Widths(at radius: Double) -> [Int]? {
    switch radius {
    case 0.125: return [1]
    case 0.25: return [3]
    case 2.0625: return [5, 3, 3, 3]
    case 2.25: return [5, 5, 3, 3]
    case 2.5: return [5, 5, 5, 3]
    case 3.25: return [7, 7, 5, 3]
    case 3.5: return [7, 7, 7, 3]
    case 4.5: return [9, 9, 9, 3]
    default: break
    }
    #if arch(x86_64)
    switch radius {
    case 2.125: return [5, 3, 3, 3]
    case 2.1875: return [5, 5, 3]
    case 2.75: return [5, 5, 5, 3, 3]
    case 3.125: return [7, 5, 5, 3, 3]
    case 3.75: return [7, 7, 7, 3, 3]
    case 4.25: return [9, 9, 7, 3]
    default: return nil
    }
    #else
    switch radius {
    case 2.125: return [5, 5, 3]
    case 2.1875: return [5, 5, 3, 3]
    case 2.75: return [7, 5, 5]
    case 3.125: return [7, 7, 5, 3]
    case 3.75: return [9, 7, 7]
    case 4.25: return [9, 9, 7, 3, 3]
    default: return nil
    }
    #endif
  }

  static func squareSupport(at radius: Double) -> Int {
    (fractionalRGB32Widths(at: radius) ?? widths(at: radius))?.reduce(0) { $0 + $1 / 2 } ?? 0
  }

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

  init?(layer: Layer, source: Surface, radius: Double, canvas: (width: Int, height: Int)?,
    roundsIntegerStages: Bool = true) {
    let wide = radius > 100
    let raster: Surface?
    if case .raster(let value) = layer.content { raster = value } else { raster = nil }
    let envelope: IntRect?
    if let canvas, let (mx, my) = Self.translation(layer.maskCoordinateTransform),
      let (rx, ry) = Self.translation(layer.coordinateTransform),
      (1...Surface.maxDimension).contains(canvas.width), (1...Surface.maxDimension).contains(canvas.height) {
      let left = min(0, rx, mx), top = min(0, ry, my)
      let right = max(canvas.width, rx + (raster?.width ?? 0), mx + source.width)
      let bottom = max(canvas.height, ry + (raster?.height ?? 0), my + source.height)
      envelope = .init(x: left - mx, y: top - my, width: right - left, height: bottom - top)
    } else {
      envelope = nil
    }
    let integerDepth = roundsIntegerStages && envelope != nil && raster?.depth == source.depth && source.depth != .f32
      ? source.depth : nil
    let rgb32 = source.depth == .f32 && raster?.depth == .f32
    let taps = integerDepth == nil ? nil : Self.dyadicTaps[radius]
    let measuredFractional = rgb32 ? Self.fractionalRGB32Widths(at: radius)
      : integerDepth != nil && radius == 3.5 ? [7, 7, 7, 3] : nil
    guard let widths = taps.map({ [$0.count] }) ?? measuredFractional ?? Self.widths(at: radius),
      wide || integerDepth != nil || rgb32
    else { return nil }
    self.widths = widths
    self.integerDepth = integerDepth
    self.taps = taps
    quarterPixel = rgb32 && radius == 0.25
    streamed = wide
    if let envelope {
      bounds = envelope
      extendEdges = true
    } else {
      guard wide else { return nil }
      let pad = widths.reduce(0) { $0 + $1 / 2 }
      bounds = .init(x: -pad, y: -pad, width: source.width + 2 * pad, height: source.height + 2 * pad)
      extendEdges = false
    }
  }

  init?(wideRadius radius: Double, width: Int, height: Int) {
    guard radius > 100, let widths = Self.widths(at: radius) else { return nil }
    self.widths = widths
    integerDepth = nil
    taps = nil
    quarterPixel = false
    streamed = true
    extendEdges = false
    let pad = widths.reduce(0) { $0 + $1 / 2 }
    bounds = IntRect(x: -pad, y: -pad, width: width + 2 * pad, height: height + 2 * pad)
  }

  func interiorSample(_ value: Float) -> Float {
    guard let integerDepth else { return value }
    return NormalLayerComposite.normalized(NormalLayerComposite.working(value, depth: integerDepth),
      depth: integerDepth)
  }

  private static func translation(_ t: Transform2D) -> (Int, Int)? {
    guard t.a == 1, t.b == 0, t.c == 0, t.d == 1,
      abs(t.tx) <= 1_000_000, abs(t.ty) <= 1_000_000,
      let x = Int(exactly: t.tx), let y = Int(exactly: t.ty) else { return nil }
    return (x, y)
  }

  /// For an unclamped binary rectangle, relative coordinates identify every
  /// input word, including padding. Tile dimensions also fix stage selection.
  struct RectangleWindow: Hashable, Sendable {
    let width: Int
    let height: Int
    let columns: Range<Int>
    let rows: Range<Int>

    func uniformCoverage(outside: Float) -> Float? {
      if columns.isEmpty || rows.isEmpty { return outside }
      // All window sums of binary constants are exact integers.
      if columns.count == width && rows.count == height { return 1 - outside }
      return nil
    }
  }

  func rectangleWindow(source: FeatherSamplePlane, outside: Float, x: Int, y: Int,
    width: Int, height: Int) -> RectangleWindow? {
    guard streamed, !extendEdges, integerDepth == nil, source.implicit == outside,
      outside == 0 || outside == 1, let rectangle = source.rectangle
    else { return nil }
    let pad = support
    let inputWidth = width + 2 * pad, inputHeight = height + 2 * pad
    let overlap = IntRect(x: rectangle.x - (bounds.x + x - pad),
      y: rectangle.y - (bounds.y + y - pad), width: rectangle.width, height: rectangle.height)
      .clipped(toWidth: inputWidth, height: inputHeight)
    return RectangleWindow(width: inputWidth, height: inputHeight,
      columns: overlap.x..<(overlap.x + overlap.width), rows: overlap.y..<(overlap.y + overlap.height))
  }

  func filterRectangle(_ window: RectangleWindow, outside: Float) -> [Float]? {
    let padding = 2 * support
    if window.columns.count == window.width {
      var column = [Float](repeating: outside, count: window.height)
      for y in window.rows { column[y] = 1 - outside }
      guard let filtered = StreamingAreaFeather.filterRepeatedColumns(column, widths: widths) else { return nil }
      let columns = window.width - padding
      var samples: [Float] = []
      samples.reserveCapacity(columns * filtered.count)
      for value in filtered { samples.append(contentsOf: repeatElement(value, count: columns)) }
      return samples
    }
    let background = [Float](repeating: outside, count: window.width)
    var foreground = background
    for x in window.columns { foreground[x] = 1 - outside }
    if window.rows.count == window.height {
      guard let filtered = StreamingAreaFeather.filterRepeatedRows(foreground, widths: widths) else { return nil }
      var samples: [Float] = []
      let rows = window.height - padding
      samples.reserveCapacity(rows * filtered.count)
      for _ in 0..<rows { samples.append(contentsOf: filtered) }
      return samples
    }
    return StreamingAreaFeather.filter(width: window.width, height: window.height,
      widths: widths, integerSamples: false) { y in
      window.rows.contains(y) ? foreground : background
    }
  }

  /// A nil sample plane means the result is uniform across the requested tile.
  func prepare(source: FeatherSamplePlane, outside: Float, x: Int, y: Int, width: Int, height: Int)
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
    let implicit = source.implicit
    if read.width == 0 || read.height == 0 { return (nil, outside) }
    let fullyInside = left >= 0 && top >= 0 && right < source.width && bottom < source.height
    if !source.hasFeatherSamples(in: read), implicit == outside || fullyInside {
      return (nil, interiorSample(implicit))
    }
    func stageSample(_ value: Float) -> Float {
      guard let integerDepth else { return value }
      return Float(NormalLayerComposite.working(value, depth: integerDepth))
    }
    func storedSamples(in region: IntRect) -> [Float]? {
      let samples = source.featherInput(in: region)
      guard integerDepth != nil else { return samples }
      return samples?.map(stageSample)
    }
    func outputSamples(_ values: [Float]) -> (samples: [Float]?, uniform: Float) {
      guard let integerDepth else { return (values, outside) }
      return (values.map { NormalLayerComposite.normalized(Int($0), depth: integerDepth) }, outside)
    }
    let stageOutside = stageSample(outside)
    let stageImplicit = stageSample(implicit)

    func inputRow(stored: [Float]?, offset: Int) -> [Float] {
      let leading = read.x == bounds.x && extendEdges ? stored?[offset] ?? stageImplicit : stageOutside
      let trailing = read.x + read.width - 1 == boundRight && extendEdges
        ? stored?[offset + read.width - 1] ?? stageImplicit : stageOutside
      let start = max(0, read.x - inputX), end = min(w, read.x + read.width - inputX)
      var values: [Float] = []
      values.reserveCapacity(w)
      values.append(contentsOf: repeatElement(leading, count: start))
      if let stored {
        let first = offset + inputX + start - read.x
        values.append(contentsOf: stored[first..<first + end - start])
      } else {
        values.append(contentsOf: repeatElement(stageImplicit, count: end - start))
      }
      values.append(contentsOf: repeatElement(trailing, count: w - end))
      return values
    }

    func sourceY(_ row: Int) -> Int {
      let y = inputY + row
      return extendEdges ? min(boundBottom, max(bounds.y, y)) : y
    }
    if streamed {
      var bands = FeatherInputBands(region: read)
      let outsideRow = [Float](repeating: stageOutside, count: w)
      let filtered = StreamingAreaFeather.filter(width: w, height: h, widths: widths,
        integerSamples: integerDepth != nil) { row in
        let sy = sourceY(row)
        guard sy >= read.y, sy < read.y + read.height else { return outsideRow }
        let (samples, offset) = bands.samples(for: sy, load: storedSamples)
        return inputRow(stored: samples, offset: offset)
      }
      guard let filtered else { return nil }
      return outputSamples(filtered)
    }

    let stored = storedSamples(in: read)
    var data: [Float] = []
    data.reserveCapacity(w * h)
    for row in 0..<h {
      let sy = sourceY(row)
      if sy >= read.y && sy < read.y + read.height {
        data.append(contentsOf: inputRow(stored: stored, offset: (sy - read.y) * read.width))
      } else {
        data.append(contentsOf: repeatElement(stageOutside, count: w))
      }
    }
    if let taps {
      return outputSamples(Self.dyadicPass(data, width: w, height: h, taps: taps))
    }
    if quarterPixel {
      return (Self.quarterPixelPass(data, width: w, height: h), outside)
    }
    for k in widths where k > 1 {
      data = Self.pass(data, width: w, height: h, side: k, integerSamples: integerDepth != nil)
      w -= k - 1
      h -= k - 1
    }
    return outputSamples(data)
  }

  private static func quarterPixelPass(_ input: [Float], width: Int, height: Int) -> [Float] {
    let columns = width - 2, rows = height - 2
    @inline(__always) func blend(_ first: Float, _ center: Float, _ last: Float) -> Float {
      let pair = first + last
      let middle = center * (206.0 / 256.0)
      #if arch(x86_64)
      return middle + pair * (25.0 / 256.0)
      #else
      return middle.addingProduct(pair, 25.0 / 256.0)
      #endif
    }
    var vertical = [Float](repeating: 0, count: width * rows)
    for y in 0..<rows {
      let row = y * width
      for x in 0..<width {
        let i = row + x
        vertical[i] = blend(input[i], input[i + width], input[i + 2 * width])
      }
    }
    var output = [Float](repeating: 0, count: columns * rows)
    for y in 0..<rows {
      let row = y * width, destination = y * columns
      for x in 0..<columns {
        let i = row + x
        output[destination + x] = blend(vertical[i], vertical[i + 1], vertical[i + 2])
      }
    }
    return output
  }

  private static func dyadicPass(_ input: [Float], width: Int, height: Int, taps: [Int]) -> [Float] {
    let columns = width - taps.count + 1, rows = height - taps.count + 1
    var horizontal = [Int](repeating: 0, count: columns * height)
    for y in 0..<height {
      for x in 0..<columns {
        var sum = 0
        for i in taps.indices { sum += Int(input[y * width + x + i]) * taps[i] }
        horizontal[y * columns + x] = (sum + 128) / 256
      }
    }
    var output = [Float](repeating: 0, count: columns * rows)
    for y in 0..<rows {
      for x in 0..<columns {
        var sum = 0
        for i in taps.indices { sum += horizontal[(y + i) * columns + x] * taps[i] }
        output[y * columns + x] = Float((sum + 128) / 256)
      }
    }
    return output
  }

  private static func pass(_ input: [Float], width: Int, height: Int, side: Int,
    integerSamples: Bool) -> [Float] {
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
      if integerSamples {
        for x in 0..<columns { result[start + x] = Float((vertical[x] / area).rounded()) }
      } else {
        for x in 0..<columns { result[start + x] = Float(vertical[x] / area) }
      }
    }
    return result
  }
}

/// The streamed stages replay up to four source rows at different offsets.
/// Read them in bands so adjacent rows can share file-backed tile decoding.
struct FeatherInputBands {
  private struct Band {
    let top: Int
    let samples: [Float]?
  }

  private let region: IntRect
  private let bandHeight: Int
  private let capacity = 4
  private var bands: [Band] = []

  init(region: IntRect) {
    self.region = region
    // At most two MiB of Float32 samples per band, including wide canvases.
    bandHeight = min(Surface.tileSide, max(1, 524_288 / region.width))
  }

  mutating func samples(for row: Int, load: (IntRect) -> [Float]?) -> ([Float]?, Int) {
    let top = region.y + ((row - region.y) / bandHeight) * bandHeight
    let band: Band
    if let index = bands.firstIndex(where: { $0.top == top }) {
      band = bands.remove(at: index)
    } else {
      if bands.count == capacity { bands.removeFirst() }
      let height = min(bandHeight, region.y + region.height - top)
      band = Band(top: top, samples: load(IntRect(x: region.x, y: top, width: region.width, height: height)))
    }
    bands.append(band)
    return (band.samples, (row - top) * region.width)
  }
}
