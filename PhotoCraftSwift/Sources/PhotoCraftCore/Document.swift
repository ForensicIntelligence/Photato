import Foundation

public struct TextContent: Codable, Equatable, Sendable {
  public var text: String
  public var fontName: String
  public var size: Double
  public var color: Pixel
  public var typography: TextTypography?
  public var layoutWidth: Int?
  public var layoutHeight: Int?
  public init(
    text: String, fontName: String = "Helvetica Neue", size: Double = 64, color: Pixel = .white
  ) {
    self.text = text
    self.fontName = fontName
    self.size = size
    self.color = color
  }
}
public struct ShapeContent: Codable, Equatable, Sendable {
  public var definition: ShapeDefinition?
  public enum Kind: String, Codable, CaseIterable, Sendable { case rectangle, ellipse }
  public var kind: Kind
  public var width: Int
  public var height: Int
  public var color: Pixel
  public init(kind: Kind, width: Int, height: Int, color: Pixel) {
    self.kind = kind
    self.width = width
    self.height = height
    self.color = color
  }
}
public enum Adjustment: Codable, Equatable, Sendable {
  case levels(LevelsAdjustment)
  case curves(CurvesAdjustment)
  case hueSaturation(HueSaturationAdjustment)
  case colorBalance(ColorBalanceAdjustment)
  case classic(ClassicAdjustment)
  case modern(ModernAdjustment)
  case colorLookup(ColorLookupAdjustment)
  case tonalSteps(TonalStepsAdjustment)
  case gradientMap(GradientMapAdjustment)
  case exposure(Float)
  case brightnessContrast(Float, Float)
  case saturation(Float)
  case invert, grayscale
  public func apply(_ p: Pixel) -> Pixel {
    switch self {
    case .levels(let levels): return LevelsTransfer(levels, depth: .f32).apply(p)
    case .curves(let curves): return CurvesTransfer(curves, depth: .f32).apply(p)
    case .hueSaturation(let settings): return HueSaturationTransfer(settings, depth: .f32).apply(p)
    case .colorLookup(let settings): return (try? ColorLookupTransfer(settings, depth: .f32))?.apply(p) ?? p
    case .classic(let settings): return ClassicAdjustmentTransfer(settings, depth: .f32).apply(p)
    case .modern(let settings): return ModernAdjustmentTransfer(settings).apply(p,x:0,y:0)
    case .colorBalance(let settings): return ColorBalanceTransfer(settings, depth: .f32).apply(p)
    case .tonalSteps(let settings): return TonalStepsTransfer(settings, depth: .f32).apply(p)
    case .gradientMap(let settings):
      return (try? GradientMapTransfer(settings, depth: .f32))?.apply(p) ?? p
    case .exposure(let e):
      let f = pow(2, e)
      return Pixel(p.r * f, p.g * f, p.b * f, p.a)
    case .brightnessContrast(let b, let c):
      return Pixel(
        (p.r - 0.5) * c + 0.5 + b, (p.g - 0.5) * c + 0.5 + b, (p.b - 0.5) * c + 0.5 + b, p.a)
    case .saturation(let s):
      let l = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
      return Pixel(l + (p.r - l) * s, l + (p.g - l) * s, l + (p.b - l) * s, p.a)
    case .invert: return Pixel(1 - p.r, 1 - p.g, 1 - p.b, p.a)
    case .grayscale:
      let l = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
      return Pixel(l, l, l, p.a)
    }
  }
  public func evaluator(depth: PixelDepth) -> @Sendable (Pixel) -> Pixel {
    if case .gradientMap(let settings) = self {
      let transfer = try? GradientMapTransfer(settings, depth: depth)
      return { transfer?.apply($0) ?? $0 }
    }
    if case .tonalSteps(let settings) = self {
      let transfer = TonalStepsTransfer(settings, depth: depth)
      return { transfer.apply($0) }
    }
    if case .levels(let levels) = self {
      let transfer = LevelsTransfer(levels, depth: depth)
      return { transfer.apply($0) }
    }
    if case .curves(let curves) = self {
      let transfer = CurvesTransfer(curves, depth: depth)
      return { transfer.apply($0) }
    }
    if case .hueSaturation(let settings) = self {
      let transfer = HueSaturationTransfer(settings, depth: depth)
      return { transfer.apply($0) }
    }
    if case .colorLookup(let settings) = self {
      let transfer = try? ColorLookupTransfer(settings, depth: depth)
      return { transfer?.apply($0) ?? $0 }
    }
    if case .classic(let settings) = self {
      let transfer = ClassicAdjustmentTransfer(settings, depth: depth)
      return { transfer.apply($0) }
    }
    if case .colorBalance(let settings) = self {
      let transfer = ColorBalanceTransfer(settings, depth: depth)
      return { transfer.apply($0) }
    }
    return { self.apply($0) }
  }
  /// Document-space coordinates keep ordered dither stable across tiles and cropped layers.
  public func spatialEvaluator(depth: PixelDepth) throws -> @Sendable (Pixel, Int, Int) -> Pixel {
    if case .modern(let settings) = self {
      guard !settings.needsNeighborhood else {throw CraftError.unsupported("This adjustment needs its complete layer input.")}
      let transfer=ModernAdjustmentTransfer(settings)
      return {transfer.apply($0,x:$1,y:$2)}
    }
    if case .colorLookup(let settings) = self {
      let transfer = try ColorLookupTransfer(settings, depth: depth)
      return { transfer.apply($0, x: $1, y: $2) }
    }
    if case .gradientMap(let settings) = self {
      let transfer = try GradientMapTransfer(settings, depth: depth)
      return { transfer.apply($0, x: $1, y: $2) }
    }
    let evaluate = evaluator(depth: depth)
    return { pixel, _, _ in evaluate(pixel) }
  }
  public var usesDocumentToneSpace: Bool {
    switch self {
    case .levels, .curves, .hueSaturation, .colorBalance, .classic, .modern, .colorLookup, .tonalSteps, .gradientMap: true
    default: false
    }
  }
  public func validate() throws {
    let valid: Bool
    switch self {
    case .levels(let levels):
      try levels.validate()
      valid = true
    case .curves(let curves):
      try curves.validate()
      valid = true
    case .hueSaturation(let settings):
      try settings.validate()
      valid = true
    case .colorLookup(let settings):
      try settings.validate()
      valid = true
    case .classic(let settings):
      try settings.validate()
      valid = true
    case .modern(let settings):
      try settings.validate()
      valid = true
    case .colorBalance(let settings):
      try settings.validate()
      valid = true
    case .gradientMap(let settings):
      try settings.validate()
      valid = true
    case .tonalSteps(let settings):
      try settings.validate()
      valid = true
    case .exposure(let e): valid = e.isFinite && (-20...20).contains(e)
    case .brightnessContrast(let b, let c):
      valid = b.isFinite && c.isFinite && (-1...1).contains(b) && (0...10).contains(c)
    case .saturation(let s): valid = s.isFinite && (0...10).contains(s)
    default: valid = true
    }
    if !valid { throw CraftError.invalid("Adjustment values are out of range.") }
  }
}
public struct GroupContent: Codable, Equatable, Sendable {
  public var videoStartTime: Double?
  public var artboard: Artboard?
  public var frame: FrameDefinition?
  public var passThrough: Bool
  public var expanded: Bool
  public init(passThrough: Bool = true, expanded: Bool = true) {
    self.passThrough = passThrough
    self.expanded = expanded
  }
}
public enum LayerContent: Codable, Equatable, Sendable {
  case raster(Surface)
  case fill(Pixel)
  case patternFill(PatternFill)
  case gradientFill(GradientFill)
  case text(TextContent)
  indirect case shape(ShapeContent)
  case adjustment(Adjustment)
  case group(GroupContent)
  public var label: String {
    switch self {
    case .raster: "Pixel layer"
    case .fill: "Color fill"
    case .patternFill: "Pattern fill"
    case .gradientFill: "Gradient fill"
    case .text: "Type layer"
    case .shape: "Shape layer"
    case .adjustment(.levels): "Levels"
    case .adjustment(.curves): "Curves"
    case .adjustment(.hueSaturation): "Hue/Saturation"
    case .adjustment(.colorLookup): "Color Lookup"
    case .adjustment(.classic(let value)): value.kind.title
    case .adjustment(.modern(let value)): value.kind.title
    case .adjustment(.colorBalance): "Color Balance"
    case .adjustment(.gradientMap): "Gradient Map"
    case .adjustment(.tonalSteps(let settings)): settings.kind.rawValue
    case .adjustment: "Adjustment"
    case .group: "Group"
    }
  }
}
public struct Layer: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var content: LayerContent
  public var nativeMode: NativeModeRaster?
  public var visible = true
  public var locked = false
  // Nil preserves historical archives and their full-lock Bool. Explicit partial
  // bits are authoritative; sourceTags contain provenance, not current settings.
  var protectionFlags: LayerProtection?
  public var opacity: Float = 1
  public var blendMode: BlendMode = .normal
  public var x = 0
  public var y = 0
  public var mask: Surface?
  public var maskProperties: MaskProperties?
  public var vectorMask: VectorMask?
  public var style: LayerStyle?
  public var videoTiming: VideoLayerTiming?
  public var video: VideoClip?
  public var videoKeyframes: [VideoKeyframe]?
  public var smartObject: SmartObject?
  public var smartFilters: SmartFilterStack?
  public var warp: WarpDefinition?
  public var sourceTags: [String: Data]?
  public var affine: Transform2D?
  // Optional fields keep archives from before hierarchy support readable.
  public var parentID: UUID?
  public var clipped: Bool?
  public var blendClippedAsGroup: Bool?
  public init(name: String, content: LayerContent) {
    id = UUID()
    self.name = name
    self.content = content
  }
}
public struct CraftDocument: Codable, Equatable, Sendable {
  public var id = UUID()
  public var name: String
  public var width: Int
  public var height: Int
  public var depth: PixelDepth
  public var colorSpace: String = "sRGB"
  public var sourceICC: Data?
  /// Profile of stored colour coordinates; nil means the historical sRGB working space.
  /// RGB32 stores linear coordinates. Never infer this from sourceICC in old archives.
  public var workingICC: Data?
  /// Explicitly omit the profile on output; retained ICC remains the numerical interpretation.
  /// Nil preserves historical tagged-document behavior.
  public var profileIsUntagged: Bool?
  public var modeDescriptor: DocumentModeDescriptor?
  public var restrictedMode: RestrictedModeRaster?
  public var inkMode: InkModeRaster?
  public var sourceMetadata: [String: Data]?
  public var artboardOrigin: ArtboardOrigin?
  public var vanishingPoint: VanishingSettings?
  public var videoTimeline: VideoTimeline?
  public var animation: FrameAnimation?
  public var variables: DataDrivenGraphics?
  public var resolution: Double?
  public var pixelsPerInch: Double { resolution ?? 72 }
  // Bottom to top, with each group's descendants immediately before its folder.
  // Child geometry is in document coordinates; moving a group moves its entire subtree.
  public var layers: [Layer]
  public var activeLayerID: UUID?
  public var selection: IntRect?
  public var selectionMask: SelectionMask?
  public var alphaChannels: [AlphaChannel]?
  public var quickMask: AlphaChannel?
  public var paths: [NamedPath]?
  public var patterns: [RasterPattern]?
  public init(
    width: Int = 1200, height: Int = 800, depth: PixelDepth = .u8, name: String = "Untitled"
  ) throws {
    _ = try Surface(width: width, height: height, depth: depth)
    self.width = width
    self.height = height
    self.depth = depth
    self.name = name
    let layer = Layer(
      name: "Background",
      content: .raster(try Surface(width: width, height: height, depth: depth, fill: .white)))
    layers = [layer]
    activeLayerID = layer.id
  }
  public var estimatedBytes: Int {
    layers.reduce(0) { total, layer in
      let raster: Int
      if case .raster(let surface) = layer.content {
        raster = surface.allocatedBytes
      } else {
        raster = 0
      }
      let lookup: Int
      if case .adjustment(.colorLookup(let a)) = layer.content { lookup = a.lut?.estimatedBytes ?? 0 } else { lookup = 0 }
      return total + (layer.video?.estimatedBytes ?? 0) + layer.keyframeBytes + lookup + raster + (layer.nativeMode?.estimatedBytes ?? 0) + (layer.mask?.allocatedBytes ?? 0)
        + (layer.smartObject?.data.count ?? 0)
        + (layer.smartFilters?.mask?.allocatedBytes ?? 0) + (layer.smartFilters?.programBytes ?? 0)
        + (layer.style?.estimatedBytes ?? 0) + (layer.shape?.definition?.estimatedBytes ?? 0)
        + ((layer.vectorMask?.path.knotCount ?? 0) + (layer.frame?.customPath?.knotCount ?? 0)) * 64
        + (layer.sourceTags?.values.reduce(0) { $0 + $1.count } ?? 0)
    } + (paths?.reduce(0) { $0 + $1.path.knotCount * 64 } ?? 0) + (selectionMask?.allocatedBytes ?? 0)
      + (patterns?.reduce(0) { $0 + $1.surface.allocatedBytes } ?? 0)
      + (alphaChannels?.reduce(0) { $0 + $1.pixels.allocatedBytes + $1.name.utf8.count + 128 } ?? 0)
      + (quickMask?.pixels.allocatedBytes ?? 0)
      + (vanishingPoint?.estimatedBytes ?? 0) + (animation?.estimatedBytes ?? 0) + timelineAudioBytes + retainedFrameSourceBytes + sampledTransitionBytes
      + (sourceICC?.count ?? 0) + (workingICC?.count ?? 0) + (modeDescriptor?.profile.count ?? 0) + (restrictedMode?.estimatedBytes ?? 0) + (inkMode?.estimatedBytes ?? 0)
      + (sourceMetadata?.values.reduce(0) { $0 + $1.count } ?? 0)
      + (variables?.estimatedBytes ?? 0)
  }
  /// Tile payloads share native Array storage across snapshots; count each live
  /// allocation once. Other document payloads remain conservatively estimated.
  func accountHistoryMemory(_ seen: inout Set<UInt>, includeMetadata: Bool) -> Int {
    var unique = 0
    var logical = 0
    func account(_ surface: Surface) {
      logical += surface.allocatedBytes
      unique += surface.accountHistoryTiles(&seen)
    }
    for layer in layers {
      if case .raster(let pixels) = layer.content { account(pixels) }
      for frame in layer.video?.frames ?? [] { account(frame) }
      if let mask = layer.mask { account(mask) }
      if let mask = layer.smartFilters?.mask { account(mask) }
    }
    for image in variables?.images ?? [] { account(image.pixels) }
    for pattern in patterns ?? [] { account(pattern.surface) }
    for channel in alphaChannels ?? [] { account(channel.pixels) }
    if let quickMask { account(quickMask.pixels) }
    return unique + (includeMetadata ? max(0, estimatedBytes - logical) + 1024 : 0)
  }
  public var activeIndex: Int? { layers.firstIndex { $0.id == activeLayerID } }
  public func validate() throws {
    _ = try Surface(width: width, height: height, depth: depth)
    guard pixelsPerInch.isFinite, (1...100_000).contains(pixelsPerInch) else {
      throw CraftError.invalid("Resolution must be between 1 and 100,000 pixels per inch.")
    }
    guard colorSpace == "sRGB", layers.count <= 512, Set(layers.map(\.id)).count == layers.count,
      activeLayerID == nil || layers.contains(where: { $0.id == activeLayerID })
    else { throw CraftError.invalid("Invalid document metadata or unsupported color space.") }
    if let workingICC { try ICCProfile.validate(workingICC, linear: depth == .f32) }
    try validateModeStorage()
    try animation?.validate(in: self)
    try validateVideo()
    try variables?.validate(in: self)
    try vanishingPoint?.validate()
    if let vanishingPoint { _ = try VanishingScene(vanishingPoint,width:width,height:height) }
    try validateHierarchy()
    try validateArtboards()
    try validateFrames()
    if let patterns { try PatternArchive.validate(patterns) }
    if let paths {
      guard paths.count <= 128, Set(paths.map(\.id)).count == paths.count,
        paths.filter(\.isWorkPath).count <= 1,
        paths.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 1024 })
      else { throw CraftError.invalid("Invalid saved paths.") }
      for path in paths { try path.path.validate() }
    }
    let knots =
      (paths?.reduce(0) { $0 + $1.path.knotCount } ?? 0)
      + layers.reduce(0) { $0 + ($1.vectorMask?.path.knotCount ?? 0) + ($1.frame?.customPath?.knotCount ?? 0) }
    guard knots <= 65_536 else { throw CraftError.invalid("Document path anchor limit reached.") }
    if let s = selection {
      guard s.x >= 0, s.y >= 0, s.width > 0, s.height > 0, s.x <= width - s.width,
        s.y <= height - s.height
      else { throw CraftError.invalid("Selection is outside the canvas.") }
    }
    if let mask = selectionMask {
      guard mask.width == width, mask.height == height, mask.bounds == selection, selection != nil
      else {
        throw CraftError.invalid("Invalid selection mask or bounds.")
      }
    }
    let channels = (alphaChannels ?? []) + (quickMask.map { [$0] } ?? [])
    guard (alphaChannels?.count ?? 0) <= Self.maximumAlphaChannels, Set(channels.map(\.id)).count == channels.count else { throw CraftError.invalid("Channel limit or duplicate identifier.") }
    for channel in channels { try channel.validate(width:width,height:height,depth:depth) }
    var bytes = timelineAudioBytes + retainedFrameSourceBytes + sampledTransitionBytes + (animation?.estimatedBytes ?? 0) + channels.reduce(0) { $0 + $1.pixels.allocatedBytes } + (restrictedMode?.estimatedBytes ?? 0) + (inkMode?.estimatedBytes ?? 0)
      + (selectionMask?.allocatedBytes ?? 0) + knots * 64
      + (patterns?.reduce(0) { $0 + $1.surface.allocatedBytes } ?? 0)
    guard bytes <= 1_073_741_824 else {
      throw CraftError.invalid("This document exceeds the current 1 GiB raster budget.")
    }
    var smartSources: [UUID: SmartObject] = [:]
    for l in layers {
      bytes += (l.video?.estimatedBytes ?? 0) + l.keyframeBytes
      bytes += l.nativeMode?.estimatedBytes ?? 0
      if let smart = l.smartObject {
        try smart.validate()
        if let existing = smartSources[smart.sourceID], !existing.sharesSource(with: smart) {
          throw CraftError.invalid("Shared Smart Object instances must contain the same source.")
        }
        smartSources[smart.sourceID] = smart
        guard case .raster(let cache) = l.content, cache.width == smart.width, cache.height == smart.height,
          cache.depth == depth else { throw CraftError.invalid("Smart Object source/cache dimensions or depth differ.") }
        bytes += smart.data.count
      }
      if let warp = l.warp {
        guard l.smartObject != nil, l.vectorMask == nil else { throw CraftError.invalid("Editable Warp requires a Smart Object without a vector mask.") }
        try warp.validate(); bytes += (warp.mesh?.points.count ?? 0)*16
      }
      if let stack = l.smartFilters {
        guard l.smartObject != nil else { throw CraftError.invalid("Smart Filters require an embedded source.") }
        try stack.validate(); _ = try SmartFilterEngine.renderBounds(l, in: self)
        for item in stack.filters { try item.filter.lensBlur?.validateSources(layer:l,document:self) }
        bytes += (stack.mask?.allocatedBytes ?? 0) + stack.programBytes
      }
      try l.style?.validate(in: self)
      try l.protection.validate()
      guard l.protectionFlags?.contains(.all) != true else {
        throw CraftError.invalid("Full layer protection must use the legacy lock field.")
      }
      try l.vectorMask?.validate()
      try l.coordinateTransform.validated()
      guard l.opacity.isFinite, (0...1).contains(l.opacity), abs(Double(l.x)) <= 1_000_000,
        abs(Double(l.y)) <= 1_000_000
      else { throw CraftError.invalid("Invalid layer properties.") }
      if let properties = l.maskProperties {
        guard l.mask != nil else { throw CraftError.invalid("Mask properties without a mask.") }
        try properties.validate()
        try l.maskCoordinateTransform.validated()
      }
      if let tags = l.sourceTags {
        guard tags.count <= 512, tags.keys.allSatisfy({ $0.utf8.count == 4 }) else {
          throw CraftError.invalid("Invalid source layer metadata.")
        }
        bytes += tags.values.reduce(0) { $0 + $1.count }
      }
      if let m = l.mask {
        try m.validated()
        bytes += m.allocatedBytes
      }
      switch l.content {
      case .raster(let s):
        try s.validated()
        bytes += s.allocatedBytes
      case .fill(let p): guard p.isFinite else { throw CraftError.invalid("Invalid fill color.") }
      case .patternFill(let fill):
        try fill.validate()
        guard pattern(fill.patternID) != nil else {
          throw CraftError.invalid("Missing embedded pattern.")
        }
      case .gradientFill(let fill): try fill.validate()
      case .text(let t):
        try t.validate()
      case .shape(let s):
        try s.validate(in: self)
      case .adjustment(let a):
        try a.validate()
        if case .modern(let value)=a {try value.validate(in:self)}
        if case .colorLookup(let lookup) = a { bytes += lookup.lut?.estimatedBytes ?? 0 }
      case .group: break
      }
      guard bytes <= 1_073_741_824 else {
        throw CraftError.invalid("This document exceeds the current 1 GiB raster budget.")
      }
    }
  }
}
public enum NativeArchive {
  private struct Envelope: Codable {
    var magic = "PhotoCraftSwift"
    var version = 10
    var document: CraftDocument
  }
  public static func encode(_ document: CraftDocument) throws -> Data {
    if document.minimumArchiveVersion>=64 {return try encodeChunked(document,minimumVersion:64)}
    try document.validate()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(Envelope(version: document.minimumArchiveVersion, document: document))
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Archive exceeds the 512 MiB file limit.")
    }
    return data
  }
  public static func decode(_ data: Data) throws -> CraftDocument {
    try decode(data, rasterByteLimit: 1_073_741_824)
  }
  public static func decode(_ data: Data, rasterByteLimit: Int) throws -> CraftDocument {
    if data.starts(with: NativeChunkedArchive.magic) {
      return try NativeChunkedArchive.decode(count: data.count, rasterByteLimit: rasterByteLimit) {
        offset, count in
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
          throw CraftError.invalid("Invalid native archive range.")
        }
        let start = data.startIndex + offset
        return data.subdata(in: start..<start + count)
      }
    }
    guard (0...1_073_741_824).contains(rasterByteLimit) else {
      throw CraftError.invalid("Invalid archive raster byte limit.")
    }
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Archive exceeds the 512 MiB input limit.")
    }
    struct Header: Decodable {
      var magic: String
      var version: Int
    }
    let decoder = PropertyListDecoder()
    let header = try decoder.decode(Header.self, from: data)
    guard header.magic == "PhotoCraftSwift", ((1...10).contains(header.version) || [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62].contains(header.version)) else {
      throw CraftError.unsupported("Unsupported Photato document version.")
    }
    decoder.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: rasterByteLimit)
    var envelope = try decoder.decode(Envelope.self, from: data)
    if header.version < 10 { envelope.document.workingICC = nil }
    try envelope.document.restoreModeCaches()
    try envelope.document.validate()
    guard envelope.document.minimumArchiveVersion <= max(10, header.version) else { throw CraftError.invalid("Archive version cannot represent its document features.") }
    return envelope.document
  }
}
