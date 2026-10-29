import Foundation

public enum BitmapConversionMethod: String, Codable, CaseIterable, Sendable {
  case threshold, pattern, diffusion, halftone, customPattern
}
public enum BitmapHalftoneShape: String, Codable, CaseIterable, Sendable {
  case round, ellipse, line, square, diamond, cross
}

/// A bounded repeating grayscale threshold tile. This is an explicit native
/// extension; Adobe custom-pattern phase/resampling is not independently verified.
public struct BitmapThresholdPattern: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var samples: Data
  public init(width: Int, height: Int, samples: Data) throws {
    self.width = width; self.height = height; self.samples = Data(samples); try validate()
  }
  public func validate() throws {
    guard width > 0, height > 0, width <= 1024, height <= 1024, samples.count == width * height else {
      throw CraftError.invalid("Custom bitmap patterns require 1 through 1024 pixels per dimension and one gray byte per pixel.")
    }
  }
}

public struct BitmapConversionSettings: Codable, Equatable, Sendable {
  public var method: BitmapConversionMethod = .diffusion
  public var outputResolution: Double = 300
  public var frequency: Double = 53
  public var angle: Double = 45
  public var shape: BitmapHalftoneShape = .round
  public var pattern: BitmapThresholdPattern?
  public init() {}
  public func validate() throws {
    guard outputResolution.isFinite, (1...9600).contains(outputResolution), frequency.isFinite,
      (1...999.999).contains(frequency), angle.isFinite, (-180...180).contains(angle) else {
      throw CraftError.invalid("Invalid Bitmap resolution, halftone frequency or angle.")
    }
    if let pattern { try pattern.validate() }
    if method == .customPattern, pattern == nil { throw CraftError.invalid("Choose a custom bitmap pattern first.") }
  }
}

/// Authoritative MSB-first, row-aligned one-bit data: one is black, zero is white.
/// Unused low bits in the last byte of each row are zero for canonical persistence.
public struct BitmapRaster: Codable, Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var bits: Data
  public var rowStride: Int { width / 8 + (width % 8 == 0 ? 0 : 1) }
  public var estimatedBytes: Int { bits.count }
  public init(width: Int, height: Int, bits: Data) throws {
    self.width = width; self.height = height; self.bits = Data(bits); try validate()
  }
  public func validate() throws {
    try IndexedRaster.validateDimensions(width, height)
    guard bits.count == rowStride * height else { throw CraftError.invalid("Bitmap packed row dimensions differ.") }
    if width % 8 != 0 {
      let padding = UInt8((1 << (8 - width % 8)) - 1)
      for y in 0..<height {
        if y % 256 == 0 { try Task.checkCancellation() }
        guard bits[(y + 1) * rowStride - 1] & padding == 0 else { throw CraftError.invalid("Bitmap row padding must be zero.") }
      }
    }
  }
  public func isBlack(x: Int, y: Int) -> Bool {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      x >= 0, y >= 0, x < width, y < height, y * rowStride + x / 8 < bits.count else { return false }
    return bits[y * rowStride + x / 8] & (0x80 >> (x % 8)) != 0
  }
  private mutating func setBlack(_ black: Bool, x: Int, y: Int) {
    let i = y * rowStride + x / 8, mask = UInt8(0x80 >> (x % 8))
    if black { bits[i] |= mask } else { bits[i] &= ~mask }
  }
  public func surface() throws -> Surface {
    try validate(); var result = try Surface(width: width, height: height)
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let v: Float = isBlack(x: x, y: y) ? 0 : 1; result.setPixel(x: x, y: y, Pixel(v, v, v))
    } }; return result
  }
  public func cropped(to rect: IntRect) throws -> Self {
    try validate()
    guard rect.width > 0, rect.height > 0, rect == rect.clipped(toWidth: width, height: height) else { throw CraftError.invalid("Bitmap crop is outside the image.") }
    var result = try Self(width: rect.width, height: rect.height, bits: Data(count: ((rect.width + 7) / 8) * rect.height))
    for y in 0..<rect.height { try Task.checkCancellation(); for x in 0..<rect.width { result.setBlack(isBlack(x: rect.x + x, y: rect.y + y), x: x, y: y) } }
    return result
  }
  public func reconciled(with edited: Surface, previous: Surface) throws -> Self {
    try validate()
    guard edited.width == width, edited.height == height, previous.width == width, previous.height == height,
      edited.depth == .u8, previous.depth == .u8 else { throw CraftError.invalid("Reconcile bitmap geometry before pixel edits.") }
    var result = self
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let p = edited.pixel(x: x, y: y)
      if p.hasSameBits(as: previous.pixel(x: x, y: y)) { continue }
      let gray = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * p.a + 1 - p.a
      result.setBlack(gray < 0.5, x: x, y: y)
    } }; return result
  }
  private static func spot(_ shape: BitmapHalftoneShape, _ u: Float, _ v: Float) -> Float {
    let value: Float
    switch shape {
    case .round: value = 1 - (u * u + v * v) / 2
    case .ellipse: value = 1 - (u * u + 0.6 * v * v) / 1.6
    case .line: value = 1 - abs(v)
    case .square: value = 1 - max(abs(u), abs(v))
    case .diamond: value = 1 - (abs(u) + abs(v)) / 2
    case .cross: value = 1 - min(abs(u), abs(v))
    }; return unit(value)
  }
  /// Grayscale samples are already resampled to the output resolution by the
  /// document adapter. Original PhotoCraft supplies the four classic algorithms.
  public static func converting(_ gray: [Float], width: Int, settings: BitmapConversionSettings) throws -> Self {
    try settings.validate()
    guard width > 0, gray.count % width == 0 else { throw CraftError.invalid("Invalid bitmap input rows.") }
    let height = gray.count / width; try IndexedRaster.validateDimensions(width, height)
    for (i, v) in gray.enumerated() {
      if i % 4096 == 0 { try Task.checkCancellation() }
      guard v.isFinite, (0...1).contains(v) else { throw CraftError.invalid("Bitmap requires finite gray values between zero and one.") }
    }
    var result = try Self(width: width, height: height, bits: Data(count: ((width + 7) / 8) * height))
    var diffusion = settings.method == .diffusion ? gray : []
    let angle = Float(settings.angle) * (Float.pi / 180), sine = sin(angle), cosine = cos(angle)
    let cell = max(2, Float(settings.outputResolution / settings.frequency))
    let table: [Float] = settings.method == .halftone ? (0..<1024).map {
      spot(settings.shape, (Float($0 % 32) + 0.5) / 16 - 1, (Float($0 / 32) + 0.5) / 16 - 1)
    }.sorted() : []
    func rank(_ value: Float) -> Float {
      var lo = 0, hi = table.count
      while lo < hi { let m = (lo + hi) / 2; if table[m] < value { lo = m + 1 } else { hi = m } }
      return Float(lo) / Float(table.count)
    }
    func remainder(_ value: Float) -> Float { let r = value.truncatingRemainder(dividingBy: 1); return r < 0 ? r + 1 : r }
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let i = y * width + x, v = gray[i]; let black: Bool
      switch settings.method {
      case .threshold: black = v < 0.5
      case .pattern: black = v <= PaletteQuantization.bayer(x, y) + 0.5
      case .diffusion:
        let old = diffusion[i], new: Float = old >= 0.5 ? 1 : 0, e = old - new; black = new == 0
        if x + 1 < width { diffusion[i + 1] += e * 7 / 16 }
        if y + 1 < height {
          if x > 0 { diffusion[i + width - 1] += e * 3 / 16 }
          diffusion[i + width] += e * 5 / 16
          if x + 1 < width { diffusion[i + width + 1] += e / 16 }
        }
      case .halftone:
        let px = Float(x) + 0.5, py = Float(y) + 0.5
        let u = remainder((px * cosine + py * sine) / cell) * 2 - 1
        let t = remainder((-px * sine + py * cosine) / cell) * 2 - 1
        black = rank(spot(settings.shape, u, t)) >= v
      case .customPattern:
        guard let pattern = settings.pattern else { throw CraftError.invalid("Missing custom bitmap pattern.") }
        let threshold = (Float(pattern.samples[pattern.samples.startIndex + (y % pattern.height) * pattern.width + x % pattern.width]) + 0.5) / 256
        black = v <= threshold
      }
      result.setBlack(black, x: x, y: y)
    } }; return result
  }
}
