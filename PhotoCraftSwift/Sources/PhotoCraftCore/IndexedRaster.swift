import Foundation

public struct IndexedColorSettings: Codable, Equatable, Sendable {
  public var palette: IndexedPaletteKind = .localSelective
  public var colors: Int = 256
  public var forced: IndexedForcedColors = .blackWhite
  public var forcedColors: [PaletteColor] = []
  public var customPalette: [PaletteColor] = []
  public var transparency: Bool = true
  /// nil is no matte: low-alpha pixels become transparent, remaining RGB is retained.
  public var matte: PaletteColor?
  public var dither: IndexedDither = .diffusion
  public var amount: Float = 0.75
  public var preserveExact: Bool = false
  public init() {}
  public func validate() throws {
    guard (2...256).contains(colors), amount.isFinite, (0...1).contains(amount),
      forcedColors.count <= 256, Set(forcedColors).count == forcedColors.count,
      customPalette.count <= 256 else { throw CraftError.invalid("Invalid Indexed Color count, dither amount or palette.") }
    if forced == .custom, forcedColors.isEmpty { throw CraftError.invalid("Choose custom forced colors first.") }
    if palette == .custom, customPalette.isEmpty { throw CraftError.invalid("Choose a custom palette first.") }
  }
}

/// The indices, rather than their RGB expansion, are authoritative. This retains
/// duplicate palette entries across Color Table edits, file I/O and history.
public struct IndexedRaster: Codable, Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var palette: [PaletteColor]
  public private(set) var indices: Data
  public private(set) var transparentIndex: Int?
  public let profile: Data
  public var estimatedBytes: Int { indices.count + palette.count * 3 + profile.count }

  public init(width: Int, height: Int, palette: [PaletteColor], indices: Data,
    transparentIndex: Int? = nil, profile: Data? = nil) throws {
    self.width = width; self.height = height; self.palette = palette; self.indices = Data(indices)
    self.transparentIndex = transparentIndex
    self.profile = try profile.map { Data($0) } ?? NativeModeProfile.standard(.rgb, depth: .u8)
    try validate()
  }
  static func validateDimensions(_ width: Int, _ height: Int) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= PaletteQuantization.maximumPixels / height else {
      throw CraftError.invalid("Restricted color modes support 1 through 8,388,608 pixels and dimensions up to 32,768.")
    }
  }
  public func validate() throws {
    try Self.validateDimensions(width, height)
    guard (1...256).contains(palette.count), indices.count == width * height,
      transparentIndex == nil || palette.indices.contains(transparentIndex!) else {
      throw CraftError.invalid("Indexed color dimensions, palette or transparency entry differ.")
    }
    for (i, index) in indices.enumerated() {
      if i % 4096 == 0 { try Task.checkCancellation() }
      guard Int(index) < palette.count else { throw CraftError.invalid("A pixel refers to a missing palette entry.") }
    }
    try NativeModeProfile.validate(profile, mode: .rgb, depth: .u8)
  }
  public func surface() throws -> Surface {
    try validate(); var result = try Surface(width: width, height: height)
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let i = Int(indices[y * width + x])
      result.setPixel(x: x, y: y, i == transparentIndex ? .clear : palette[i].pixel)
    } }; return result
  }
  public func replacingPalette(_ colors: [PaletteColor], transparentIndex: Int?) throws -> Self {
    try Self(width: width, height: height, palette: colors, indices: indices, transparentIndex: transparentIndex, profile: profile)
  }
  public func replacingIndices(_ data: Data) throws -> Self {
    try Self(width: width, height: height, palette: palette, indices: data, transparentIndex: transparentIndex, profile: profile)
  }
  public func cropped(to rect: IntRect) throws -> Self {
    try validate()
    guard rect.width > 0, rect.height > 0, rect == rect.clipped(toWidth: width, height: height) else {
      throw CraftError.invalid("Indexed crop is outside the image.")
    }
    var data = Data(); data.reserveCapacity(rect.width * rect.height)
    for y in rect.y..<rect.y + rect.height { try Task.checkCancellation(); let start = y * width + rect.x; data.append(indices[start..<start + rect.width]) }
    return try Self(width: rect.width, height: rect.height, palette: palette, indices: data, transparentIndex: transparentIndex, profile: profile)
  }
  public func reconciled(with edited: Surface, previous: Surface) throws -> Self {
    try validate()
    guard edited.width == width, edited.height == height, previous.width == width, previous.height == height,
      edited.depth == .u8, previous.depth == .u8 else { throw CraftError.invalid("Reconcile indexed geometry before pixel edits.") }
    var result = self
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let p = edited.pixel(x: x, y: y)
      if p.hasSameBits(as: previous.pixel(x: x, y: y)) { continue }
      let i = y * width + x
      if p.a < 0.5, let transparentIndex { result.indices[i] = UInt8(transparentIndex) }
      else {
        guard palette.count > 1 || transparentIndex == nil else { throw CraftError.invalid("The color table has no opaque entry.") }
        let rgb = transparentIndex == nil ? SIMD3(p.r * p.a + 1 - p.a, p.g * p.a + 1 - p.a, p.b * p.a + 1 - p.a) : SIMD3(p.r, p.g, p.b)
        result.indices[i] = UInt8(PaletteQuantization.nearest(palette, rgb, excluding: transparentIndex))
      }
    } }; return result
  }
  /// Input must already be RGB8 in the supplied working profile. Master sources
  /// must be converted into the same working coordinates by the document adapter.
  public static func converting(_ source: Surface, settings: IndexedColorSettings,
    profile: Data? = nil, masterSources: [Surface] = [], previousPalette: [PaletteColor]? = nil) throws -> Self {
    try settings.validate(); try validateDimensions(source.width, source.height)
    guard source.depth == .u8 else { throw CraftError.invalid("Convert to RGB 8-bit before Indexed Color.") }
    let resolvedProfile = try profile ?? NativeModeProfile.standard(.rgb, depth: .u8)
    try NativeModeProfile.validate(resolvedProfile, mode: .rgb, depth: .u8)
    func samples(_ surface: Surface) throws -> [PaletteQuantization.Sample] {
      guard surface.depth == .u8 else { throw CraftError.invalid("Master palette inputs must share RGB8 coordinates.") }
      try validateDimensions(surface.width, surface.height)
      var result = [PaletteQuantization.Sample](); result.reserveCapacity(surface.width * surface.height)
      for y in 0..<surface.height { try Task.checkCancellation(); for x in 0..<surface.width {
        let p = surface.pixel(x: x, y: y)
        let clear = settings.transparency && p.a < 0.5
        let matte = settings.matte ?? (settings.transparency ? nil : PaletteColor(255, 255, 255))
        var c = SIMD3(p.r, p.g, p.b)
        if let matte, !clear { c = c * p.a + matte.vector / 255 * (1 - p.a) }
        result.append(SIMD4(c.x, c.y, c.z, clear ? 0 : 1))
      } }; return result
    }
    let pixels = try samples(source), hasClear = settings.transparency && pixels.contains { $0.w == 0 }
    var pool = pixels
    if settings.palette.isMaster {
      guard !masterSources.isEmpty else { throw CraftError.invalid("Master palettes require explicit additional image sources.") }
      for input in masterSources {
        guard input.width <= (PaletteQuantization.maximumPixels - pool.count) / input.height else {
          throw CraftError.unsupported("Master palette inputs exceed 8,388,608 combined pixels.")
        }
        pool += try samples(input)
      }
    } else if !masterSources.isEmpty { throw CraftError.invalid("Additional image sources apply only to Master palettes.") }
    let forced = settings.forced.colors(settings.forcedColors)
    let generated = [.uniform, .localAdaptive, .localPerceptual, .localSelective].contains(settings.palette.local)
    if generated, forced.count > settings.colors - (hasClear ? 1 : 0) {
      throw CraftError.invalid("Forced colors and transparency exceed the requested palette size.")
    }
    var colors: [PaletteColor]
    if settings.palette == .custom { colors = settings.customPalette }
    else if settings.palette == .previous {
      guard let previousPalette, !previousPalette.isEmpty, previousPalette.count <= 256 else { throw CraftError.invalid("No previous indexed palette is available.") }
      colors = previousPalette
    } else {
      colors = try PaletteQuantization.palette(pool, kind: settings.palette.local,
        colors: max(1, settings.colors - (hasClear ? 1 : 0)), forced: forced, sourceProfile: resolvedProfile)
    }
    var transparent: Int?
    if hasClear {
      if colors.count == 256 {
        // Fixed system palettes reserve their final slot for transparency; Exact,
        // Custom and Previous must never silently lose an explicitly supplied color.
        guard [.systemMac, .systemWindows, .web, .uniform, .localAdaptive, .localPerceptual, .localSelective].contains(settings.palette.local),
          !forced.contains(colors[255]) else { throw CraftError.invalid("Transparency needs one free palette entry.") }
        colors.removeLast()
      }
      transparent = colors.count; colors.append(.init(255, 255, 255))
    }
    let indices = try PaletteQuantization.indices(pixels, width: source.width, palette: colors,
      dither: settings.dither, amount: settings.amount, transparentIndex: transparent, preserveExact: settings.preserveExact)
    return try Self(width: source.width, height: source.height, palette: colors, indices: indices,
      transparentIndex: transparent, profile: resolvedProfile)
  }
}
