import Foundation

public struct RasterPattern: Equatable, Sendable, Codable, Identifiable {
  public let id: String
  public var name: String
  public let surface: Surface
  public static let maxPixels = 16_000_000
  public var displayName: String {
    let text = name.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    return text.hasPrefix("$$$/")
      ? String(text.split(separator: "=", maxSplits: 1).last ?? Substring(text)) : text
  }
  public init(name: String, surface: Surface, id: String? = nil) throws {
    guard name.utf16.count <= 65_535 else { throw CraftError.invalid("Pattern name is too long.") }
    self.name = name
    self.surface = surface
    self.id = try id ?? Self.contentID(name: name, surface: surface)
    try validate()
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535, !id.isEmpty, id.utf8.count <= 255,
      surface.width <= 30_000, surface.height <= 30_000,
      surface.width * surface.height <= Self.maxPixels
    else {
      throw CraftError.invalid("Invalid pattern name, identifier or dimensions (maximum 16 MP).")
    }
    try surface.validated()
  }
  // PhotoCraft's deterministic FNV-1a identifier; opaque RGB drops its alpha channel.
  static func contentID(name: String, surface: Surface) throws -> String {
    guard surface.width * surface.height <= maxPixels else {
      throw CraftError.invalid("Patterns are limited to 16 megapixels.")
    }
    try surface.validated()
    var alpha = false
    for y in 0..<surface.height {
      try Task.checkCancellation()
      for x in 0..<surface.width where surface.pixel(x: x, y: y).a < 1 { alpha = true }
    }
    func fnv(_ initial: UInt64, _ bytes: some Sequence<UInt8>) -> UInt64 {
      bytes.reduce(initial) { ($0 ^ UInt64($1)) &* 0x0100_0000_01b3 }
    }
    func bytes(_ value: UInt32) -> [UInt8] {
      (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    var h1 = fnv(0xcbf2_9ce4_8422_2325, name.utf8)
    h1 = fnv(h1, bytes(UInt32(surface.width)))
    h1 = fnv(h1, bytes(UInt32(surface.height)))
    for y in 0..<surface.height {
      try Task.checkCancellation()
      for x in 0..<surface.width {
        let p = surface.pixel(x: x, y: y)
        for value in alpha ? [p.r, p.g, p.b, p.a] : [p.r, p.g, p.b] {
          h1 = fnv(h1, bytes(value.bitPattern))
        }
      }
    }
    let sample = surface.depth == .u8 ? "U8" : surface.depth == .u16 ? "U16" : "F32"
    let format = "PixelFormat { mode: Rgb, sample: \(sample), alpha: \(alpha) }"
    let h2 = fnv(h1 ^ 0x9e37_79b9_7f4a_7c15, format.utf8)
    return String(
      format: "%08x-%04x-%04x-%04x-%012llx", UInt32(h1 >> 32),
      UInt16(truncatingIfNeeded: h1 >> 16), UInt16(truncatingIfNeeded: h1),
      UInt16(h2 >> 48), h2 & 0xffff_ffff_ffff)
  }
}

public struct PatternPlacement: Codable, Equatable, Sendable {
  public var scale: Float = 100
  public var angle: Float = 0
  public var phaseX: Float = 0
  public var phaseY: Float = 0
  public init() {}
  public func validate() throws {
    guard scale.isFinite, (1...1000).contains(scale), angle.isFinite, abs(angle) <= 360_000,
      phaseX.isFinite, phaseY.isFinite, abs(phaseX) <= 1_000_000, abs(phaseY) <= 1_000_000
    else {
      throw CraftError.invalid("Invalid pattern placement.")
    }
  }
}

/// Premultiplied bilinear wrapping, ported from PhotoCraft compose/pattern.rs.
/// Pattern samples retain the pattern's native encoded RGB domain until painting.
public struct PatternSampler: Sendable {
  let surface: Surface
  /// Cap extra preparation at 4 MiB per sampler. Larger patterns retain the
  /// original sparse-surface path rather than duplicating up to 256 MiB.
  static let preparedPixelLimit = 262_144
  let prepared: [SIMD4<Float>]
  let cosine: Double
  let sine: Double
  let inverseScale: Double
  let origin: PathPoint
  public init(_ pattern: RasterPattern, placement: PatternPlacement = PatternPlacement()) throws {
    try self.init(pattern, placement: placement, preparePixels: true)
  }
  init(_ pattern: RasterPattern, placement: PatternPlacement, preparePixels: Bool) throws {
    try pattern.validate()
    try placement.validate()
    surface = pattern.surface
    if preparePixels, surface.width * surface.height <= Self.preparedPixelLimit {
      var samples: [SIMD4<Float>] = []
      samples.reserveCapacity(surface.width * surface.height)
      for y in 0..<surface.height {
        try Task.checkCancellation()
        for x in 0..<surface.width {
          let p = surface.pixel(x: x, y: y)
          samples.append(SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
        }
      }
      prepared = samples
    } else {
      prepared = []
    }
    let radians = Double(placement.angle) * (.pi / 180)
    cosine = cos(radians)
    sine = sin(radians)
    inverseScale = 1 / Double(placement.scale / 100)
    origin = .init(Double(placement.phaseX), Double(placement.phaseY))
  }
  public func sample(x: Double, y: Double) -> Pixel {
    guard x.isFinite, y.isFinite, abs(x) <= 1e9, abs(y) <= 1e9 else { return .clear }
    let dx = x - origin.x
    let dy = y - origin.y
    return tile(
      u: (dx * cosine - dy * sine) * inverseScale,
      v: (dx * sine + dy * cosine) * inverseScale)
  }
  public func tile(u: Double, v: Double) -> Pixel {
    guard u.isFinite, v.isFinite, abs(u) <= 1e12, abs(v) <= 1e12 else { return .clear }
    let u = u - 0.5
    let v = v - 0.5
    let floorX = floor(u)
    let floorY = floor(v)
    let fx = Float(u - floorX)
    let fy = Float(v - floorY)
    let x0 = Int(floorX)
    let y0 = Int(floorY)
    var acc = SIMD4<Float>.zero
    for (dy, wy) in [(0, 1 - fy), (1, fy)] where wy != 0 {
      for (dx, wx) in [(0, 1 - fx), (1, fx)] where wx != 0 {
        let x = ((x0 + dx) % surface.width + surface.width) % surface.width
        let y = ((y0 + dy) % surface.height + surface.height) % surface.height
        let p: SIMD4<Float>
        if prepared.isEmpty {
          let sample = surface.pixel(x: x, y: y)
          p = SIMD4(sample.r * sample.a, sample.g * sample.a, sample.b * sample.a, sample.a)
        } else {
          p = prepared[y * surface.width + x]
        }
        let k = wx * wy
        acc += p * k
      }
    }
    guard acc.w > 0 else { return .clear }
    return Pixel(acc.x / acc.w, acc.y / acc.w, acc.z / acc.w, min(1, acc.w))
  }
}

public enum PatternArchive {
  public static let maxCount = 1024
  public static let maxTotalPixels = 64_000_000
  public static let maxBytes = 512 * 1024 * 1024
  struct Envelope: Codable {
    let version: Int
    let patterns: [RasterPattern]
    let selectedID: String?
  }
  public static func validate(_ patterns: [RasterPattern]) throws {
    guard patterns.count <= maxCount, Set(patterns.map(\.id)).count == patterns.count else {
      throw CraftError.invalid("Pattern library is too large or contains duplicate identifiers.")
    }
    var pixels = 0
    var storage = 0
    for pattern in patterns {
      try Task.checkCancellation()
      try pattern.validate()
      pixels += pattern.surface.width * pattern.surface.height
      storage += ((pattern.surface.width + 63) / 64) * ((pattern.surface.height + 63) / 64) * 65_536
      guard pixels <= maxTotalPixels else {
        throw CraftError.invalid("Pattern library exceeds its 64 MP budget.")
      }
      guard storage <= 1024 * 1024 * 1024 else {
        throw CraftError.invalid("Pattern library exceeds its tiled storage budget.")
      }
    }
  }
  public static func encode(_ patterns: [RasterPattern], selectedID: String? = nil) throws -> Data {
    try validate(patterns)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(Envelope(version: 1, patterns: patterns, selectedID: selectedID))
    guard data.count <= maxBytes else {
      throw CraftError.invalid("Pattern library file is too large.")
    }
    return data
  }
  public static func decode(_ data: Data) throws -> [RasterPattern] {
    try decodeState(data).patterns
  }
  public static func decodeState(_ data: Data) throws -> (
    patterns: [RasterPattern], selectedID: String?
  ) {
    if try libraryVersion(data) == PatternLibraryState.version {
      let state = try decodeLibraryState(data)
      return (state.patterns, state.selectedID)
    }
    guard data.count <= maxBytes else {
      throw CraftError.invalid("Pattern library file is too large.")
    }
    let decoder = PropertyListDecoder()
    decoder.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: 1024 * 1024 * 1024)
    let envelope = try decoder.decode(Envelope.self, from: data)
    guard envelope.version == 1 else {
      throw CraftError.unsupported("Unknown pattern library version.")
    }
    try validate(envelope.patterns)
    return (envelope.patterns, envelope.selectedID)
  }
}
