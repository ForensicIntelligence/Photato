import Foundation

public struct InkCurvePoint: Codable, Equatable, Sendable {
  public var input: Float
  public var output: Float
  public init(_ input: Float, _ output: Float) { self.input = input; self.output = output }
}
public struct DuotoneInk: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var color: Pixel
  public var curve: [InkCurvePoint]
  public init(id: UUID = UUID(), name: String, color: Pixel, curve: [InkCurvePoint] = [.init(0, 0), .init(1, 1)]) {
    self.id = id; self.name = name; self.color = color; self.curve = curve
  }
  public func validate() throws {
    try InkPlate.validateColor(name: name, color: color)
    guard (2...256).contains(curve.count), curve.first?.input == 0, curve.last?.input == 1,
      curve.allSatisfy({ $0.input.isFinite && $0.output.isFinite && (0...1).contains($0.input) && (0...1).contains($0.output) }),
      zip(curve, curve.dropFirst()).allSatisfy({ $0.0.input < $0.1.input }) else {
      throw CraftError.invalid("An ink curve needs ordered, distinct points between zero and one, including both input endpoints.")
    }
  }
  /// Licensed PhotoCraft density transfer; exact Photoshop interpolation is separately qualified.
  func density(_ value: Float) -> Float {
    let x = unit(value)
    for pair in zip(curve, curve.dropFirst()) where x <= pair.1.input {
      return unit(pair.0.output + (pair.1.output - pair.0.output) * (x - pair.0.input) / (pair.1.input - pair.0.input))
    }
    return curve.last?.output ?? x
  }
}
public struct InkOverprint: Codable, Equatable, Sendable {
  /// Bit i identifies ink i. Only combinations of at least two inks can override display.
  public var mask: Int
  public var color: Pixel
  public init(mask: Int, color: Pixel) { self.mask = mask; self.color = color }
}
public struct DuotoneSettings: Codable, Equatable, Sendable {
  public var inks: [DuotoneInk]
  public var overprints: [InkOverprint]
  public init(inks: [DuotoneInk] = [.init(name: "Black", color: .black)], overprints: [InkOverprint] = []) {
    self.inks = inks; self.overprints = overprints
  }
  public var title: String { switch inks.count { case 1: "Monotone"; case 2: "Duotone"; case 3: "Tritone"; default: "Quadtone" } }
  public func validate() throws {
    guard (1...4).contains(inks.count), Set(inks.map(\.id)).count == inks.count,
      overprints.count <= 11, Set(overprints.map(\.mask)).count == overprints.count else {
      throw CraftError.invalid("Duotone requires one to four distinct inks and unique overprint combinations.")
    }
    for ink in inks { try ink.validate() }
    for entry in overprints {
      guard entry.mask > 0, entry.mask < 1 << inks.count, entry.mask.nonzeroBitCount >= 2 else {
        throw CraftError.invalid("Overprint combinations must refer to two or more existing inks.")
      }
      try InkPlate.validateColor(name: "Overprint", color: entry.color)
    }
  }
  func lookup() throws -> [Pixel] {
    try validate()
    // Override colors describe full-coverage ink combinations. Interpolate their
    // display by coverage; these colors never alter the grayscale source or plates.
    var table = [Pixel](repeating: .white, count: 1 << inks.count)
    for mask in table.indices {
      var p = Pixel.white
      for i in inks.indices where mask & (1 << i) != 0 {
        p.r *= inks[i].color.r; p.g *= inks[i].color.g; p.b *= inks[i].color.b
      }
      table[mask] = p
    }
    for entry in overprints { table[entry.mask] = entry.color }
    return (0...255).map { value in
      let gray = Float(value) / 255, densities = inks.map { $0.density(1 - gray) }
      if overprints.isEmpty {
        var p = Pixel.white
        for (ink, density) in zip(inks, densities) {
          p.r *= 1 - density * (1 - ink.color.r)
          p.g *= 1 - density * (1 - ink.color.g)
          p.b *= 1 - density * (1 - ink.color.b)
        }
        return p
      }
      var p = Pixel(0, 0, 0)
      for mask in table.indices {
        var weight: Float = 1
        for i in inks.indices { weight *= mask & (1 << i) != 0 ? densities[i] : 1 - densities[i] }
        p.r += weight * table[mask].r; p.g += weight * table[mask].g; p.b += weight * table[mask].b
      }
      return p
    }
  }
}
public struct DuotoneRaster: Codable, Equatable, Sendable {
  public var gray: InkPlane
  public private(set) var settings: DuotoneSettings
  /// Original format metadata is retained only while its corresponding settings stay unchanged.
  public private(set) var sourceModeData: Data?
  public init(gray: InkPlane, settings: DuotoneSettings, sourceModeData: Data? = nil) throws {
    self.gray = gray; self.settings = settings; self.sourceModeData = sourceModeData; try validate()
  }
  public func validate() throws {
    try gray.validate(); try settings.validate()
    guard gray.depth == .u8, (sourceModeData?.count ?? 0) <= 1_048_576 else {
      throw CraftError.invalid("Duotone requires one 8-bit grayscale plane and bounded mode metadata.")
    }
  }
  public func replacing(settings: DuotoneSettings) throws -> Self {
    try settings.validate(); var result = self
    if self.settings != settings { result.settings = settings; result.sourceModeData = nil }
    return result
  }
  public func separations() throws -> MultichannelRaster {
    try validate()
    let plates = try settings.inks.map { ink in
      var samples = [UInt8](); samples.reserveCapacity(gray.count)
      for i in 0..<gray.count {
        if i % 4096 == 0 { try Task.checkCancellation() }
        samples.append(UInt8((ink.density(1 - gray.value(at: i)) * 255).rounded()))
      }
      return InkPlate(id: ink.id, name: ink.name, color: ink.color,
        samples: try InkPlane(width: gray.width, height: gray.height, bytes: Data(samples)))
    }
    return try MultichannelRaster(plates: plates)
  }
}
public struct InkPlate: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var color: Pixel
  /// Zero simulates a transparent printing ink; one covers underlying ink at full density.
  public var solidity: Float
  /// Zero means no ink, one means full ink coverage.
  public var samples: InkPlane
  public init(id: UUID = UUID(), name: String, color: Pixel, solidity: Float = 0, samples: InkPlane) {
    self.id = id; self.name = name; self.color = color; self.solidity = solidity; self.samples = samples
  }
  static func validateColor(name: String, color: Pixel) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 1024,
      color.isFinite, color.a == 1, [color.r, color.g, color.b].allSatisfy({ (0...1).contains($0) }) else {
      throw CraftError.invalid("Ink names and opaque display colors must be valid.")
    }
  }
  public func validate() throws {
    try Self.validateColor(name: name, color: color); try samples.validate()
    guard solidity.isFinite, (0...1).contains(solidity) else { throw CraftError.invalid("Ink solidity must be between zero and one.") }
  }
}
public struct MultichannelRaster: Codable, Equatable, Sendable {
  public static let maximumChannels = 56
  public var plates: [InkPlate]
  public var width: Int { plates.first?.samples.width ?? 0 }
  public var height: Int { plates.first?.samples.height ?? 0 }
  public var depth: PixelDepth { plates.first?.samples.depth ?? .u8 }
  public init(plates: [InkPlate]) throws { self.plates = plates; try validate() }
  public func validate() throws {
    guard (1...Self.maximumChannels).contains(plates.count), Set(plates.map(\.id)).count == plates.count else {
      throw CraftError.invalid("Multichannel requires one to 56 uniquely identified ink plates.")
    }
    for plate in plates {
      try plate.validate()
      guard plate.samples.width == width, plate.samples.height == height, plate.samples.depth == depth else {
        throw CraftError.invalid("Ink plates must share dimensions and bit depth.")
      }
    }
    guard plates.reduce(0, { $0 + $1.samples.estimatedBytes }) <= 1_073_741_824 else {
      throw CraftError.invalid("Ink plates exceed the document raster budget.")
    }
  }
}
public enum InkModeRaster: Codable, Equatable, Sendable {
  case duotone(DuotoneRaster), multichannel(MultichannelRaster)
  public var mode: DocumentColorMode { switch self { case .duotone: .duotone; case .multichannel: .multichannel } }
  public var width: Int { switch self { case .duotone(let r): r.gray.width; case .multichannel(let r): r.width } }
  public var height: Int { switch self { case .duotone(let r): r.gray.height; case .multichannel(let r): r.height } }
  public var depth: PixelDepth { switch self { case .duotone: .u8; case .multichannel(let r): r.depth } }
  public var estimatedBytes: Int {
    switch self {
    case .duotone(let r): r.gray.estimatedBytes + (r.sourceModeData?.count ?? 0) + r.settings.inks.reduce(0) { $0 + $1.name.utf8.count + $1.curve.count * 8 + 128 } + r.settings.overprints.count * 32
    case .multichannel(let r): r.plates.reduce(0) { $0 + $1.samples.estimatedBytes + $1.name.utf8.count + 128 }
    }
  }
  public func validate() throws { switch self { case .duotone(let r): try r.validate(); case .multichannel(let r): try r.validate() } }
  public func surface(region: IntRect? = nil) throws -> Surface {
    try validate(); try Task.checkCancellation()
    let region = (region ?? .init(x: 0, y: 0, width: width, height: height)).clipped(toWidth: width, height: height)
    var result = try Surface(width: width, height: height, depth: .f32, colorEncoding: .sRGB)
    switch self {
    case .duotone(let raster):
      let lookup = try raster.settings.lookup()
      for y in region.y..<(region.y + region.height) { try Task.checkCancellation(); for x in region.x..<(region.x + region.width) {
        result.setPixel(x: x, y: y, lookup[Int(raster.gray.rawWord(at: y * width + x))])
      } }
    case .multichannel(let raster):
      for y in region.y..<(region.y + region.height) { try Task.checkCancellation(); for x in region.x..<(region.x + region.width) {
        var p = Pixel.white
        for plate in raster.plates {
          let density = plate.samples.value(at: y * width + x), cover = plate.solidity * density, keep = 1 - cover
          p.r = keep * p.r * (1 - density + density * plate.color.r) + cover * plate.color.r
          p.g = keep * p.g * (1 - density + density * plate.color.g) + cover * plate.color.g
          p.b = keep * p.b * (1 - density + density * plate.color.b) + cover * plate.color.b
        }
        result.setPixel(x: x, y: y, p)
      } }
    }
    return result
  }
}
