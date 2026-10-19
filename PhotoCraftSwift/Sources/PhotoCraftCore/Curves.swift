import Foundation

/// Control coordinates use the 0...255 scale at every document depth.
public struct CurvePoint: Codable, Equatable, Sendable {
  public var input: Int
  public var output: Int
  public init(_ input: Int, _ output: Int) {
    self.input = input
    self.output = output
  }
}

public struct CurveChannel: Codable, Equatable, Sendable {
  public var points: [CurvePoint]
  public init(_ points: [CurvePoint] = [.init(0, 0), .init(255, 255)]) { self.points = points }
  public var isIdentity: Bool { points == CurveChannel().points }
  public func validate() throws {
    guard (2...19).contains(points.count),
      points.allSatisfy({ (0...255).contains($0.input) && (0...255).contains($0.output) }),
      zip(points, points.dropFirst()).allSatisfy({ $0.input < $1.input })
    else {
      throw CraftError.invalid(
        "Curves needs 2–19 points with distinct, increasing inputs from 0 to 255.")
    }
  }

  /// Add a point or select the existing point at this input. Returns its index.
  public mutating func insert(_ point: CurvePoint) throws -> Int {
    try validate()
    guard (0...255).contains(point.input), (0...255).contains(point.output) else {
      throw CraftError.invalid("Curve coordinates must be between 0 and 255.")
    }
    if let i = points.firstIndex(where: { $0.input == point.input }) { return i }
    guard points.count < 19 else {
      throw CraftError.invalid("A curve can contain at most 19 points.")
    }
    let i = points.firstIndex(where: { $0.input > point.input }) ?? points.count
    points.insert(point, at: i)
    return i
  }
  public mutating func move(_ index: Int, to point: CurvePoint) {
    guard points.indices.contains(index) else { return }
    let low = index == 0 ? 0 : points[index - 1].input + 1
    let high = index == points.count - 1 ? 255 : points[index + 1].input - 1
    guard low <= high else { return }
    points[index] = .init(min(high, max(low, point.input)), min(255, max(0, point.output)))
  }
  public mutating func remove(_ index: Int) {
    guard points.count > 2, points.indices.contains(index) else { return }
    points.remove(at: index)
  }

  /// Natural cubic spline ported from PhotoCraft's curve_lut. This reproduces
  /// upstream math, which has not yet been qualified against Photoshop 2026.
  public func table() -> [Float] {
    guard (try? validate()) != nil else { return (0..<4096).map { Float($0) / 4095 } }
    let n = points.count
    // Preserve upstream f32 normalization before its f64 spline solve.
    let x = points.map { Double(Float($0.input) / 255) }
    let y = points.map { Double(Float($0.output) / 255) }
    var second = Array(repeating: Double(0), count: n)
    if n > 2 {
      var c = second
      var d = second
      for i in 1..<(n - 1) {
        let h0 = x[i] - x[i - 1]
        let h1 = x[i + 1] - x[i]
        let a = h0 / 6
        let b = (h0 + h1) / 3
        let r = (y[i + 1] - y[i]) / h1 - (y[i] - y[i - 1]) / h0
        let denominator = b - a * c[i - 1]
        c[i] = (h1 / 6) / denominator
        d[i] = (r - a * d[i - 1]) / denominator
      }
      for i in stride(from: n - 2, through: 1, by: -1) {
        second[i] = d[i] - c[i] * second[i + 1]
      }
    }
    return (0..<4096).map { k in
      let t = Double(Float(k) / 4095)
      if t <= x[0] { return Float(y[0]) }
      if t >= x[n - 1] { return Float(y[n - 1]) }
      let i = (1..<n).first(where: { t <= x[$0] })! - 1
      let h = x[i + 1] - x[i]
      let a = (x[i + 1] - t) / h
      let b = (t - x[i]) / h
      let value =
        a * y[i] + b * y[i + 1]
        + ((a * a * a - a) * second[i] + (b * b * b - b) * second[i + 1]) * h * h / 6
      return unit(Float(value))
    }
  }
}

public struct CurvesAdjustment: Codable, Equatable, Sendable {
  public typealias Channel = LevelsAdjustment.Channel
  public var rgb: CurveChannel
  public var red: CurveChannel
  public var green: CurveChannel
  public var blue: CurveChannel
  public init(
    rgb: CurveChannel = .init(), red: CurveChannel = .init(),
    green: CurveChannel = .init(), blue: CurveChannel = .init()
  ) {
    self.rgb = rgb
    self.red = red
    self.green = green
    self.blue = blue
  }
  public subscript(_ channel: Channel) -> CurveChannel {
    get {
      switch channel {
      case .rgb: rgb
      case .red: red
      case .green: green
      case .blue: blue
      }
    }
    set {
      switch channel {
      case .rgb: rgb = newValue
      case .red: red = newValue
      case .green: green = newValue
      case .blue: blue = newValue
      }
    }
  }
  public func validate() throws {
    for channel in Channel.allCases { try self[channel].validate() }
  }
}

public struct CurvesTransfer: Sendable {
  let curves: CurvesAdjustment
  let depth: PixelDepth
  let tables: [[Float]]
  public init(_ curves: CurvesAdjustment, depth: PixelDepth) {
    self.curves = curves
    self.depth = depth
    let master = curves.rgb.table()
    tables = [curves.red, curves.green, curves.blue].map { channel in
      // Upstream Curves applies the component curve BEFORE the master curve.
      channel.table().map { Self.lookup(master, $0) }
    }
  }
  static func lookup(_ table: [Float], _ value: Float) -> Float {
    let x = min(1, max(0, value)) * 4095
    let i = Int(floor(x))
    let fraction = x - Float(i)
    return table[i] * (1 - fraction) + table[min(i + 1, 4095)] * fraction
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    guard curves != CurvesAdjustment(), pixel.a > 0, pixel.isFinite else { return pixel }
    func channel(_ value: Float, _ curve: CurveChannel, _ index: Int) -> Float {
      if curves.rgb.isIdentity && curve.isIdentity { return value }
      // Float document samples are encoded sRGB in native storage. Curves uses
      // the upstream bounded 0...1 transfer in the document's linear space.
      // HDR extrapolation / Photoshop RGB/32 exactness remain unqualified.
      let input = depth == .f32 ? SRGBTransfer.linear(value) : value
      let output = Self.lookup(tables[index], input)
      return depth == .f32 ? SRGBTransfer.encoded(output) : output
    }
    return Pixel(
      channel(pixel.r, curves.red, 0), channel(pixel.g, curves.green, 1),
      channel(pixel.b, curves.blue, 2), pixel.a)
  }
}
