import Foundation

public struct TextContent: Codable, Equatable, Sendable {
  public var text: String
  public var fontName: String
  public var size: Double
  public var color: Pixel
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
    if case .colorBalance(let settings) = self {
      let transfer = ColorBalanceTransfer(settings, depth: depth)
      return { transfer.apply($0) }
    }
    return { self.apply($0) }
  }
  /// Document-space coordinates keep ordered dither stable across tiles and cropped layers.
  public func spatialEvaluator(depth: PixelDepth) throws -> @Sendable (Pixel, Int, Int) -> Pixel {
    if case .gradientMap(let settings) = self {
      let transfer = try GradientMapTransfer(settings, depth: depth)
      return { transfer.apply($0, x: $1, y: $2) }
    }
    let evaluate = evaluator(depth: depth)
    return { pixel, _, _ in evaluate(pixel) }
  }
  public var usesDocumentToneSpace: Bool {
    switch self {
    case .levels, .curves, .hueSaturation, .colorBalance, .tonalSteps, .gradientMap: true
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
  case shape(ShapeContent)
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
  public var visible = true
  public var locked = false
  public var opacity: Float = 1
  public var blendMode: BlendMode = .normal
  public var x = 0
  public var y = 0
  public var mask: Surface?
  public var maskProperties: MaskProperties?
  public var vectorMask: VectorMask?
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
  public var sourceMetadata: [String: Data]?
  public var resolution: Double?
  public var pixelsPerInch: Double { resolution ?? 72 }
  // Bottom to top, with each group's descendants immediately before its folder.
  // Child geometry is in document coordinates; moving a group moves its entire subtree.
  public var layers: [Layer]
  public var activeLayerID: UUID?
  public var selection: IntRect?
  public var selectionMask: SelectionMask?
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
      return total + raster + (layer.mask?.allocatedBytes ?? 0)
        + (layer.vectorMask?.path.knotCount ?? 0) * 64
        + (layer.sourceTags?.values.reduce(0) { $0 + $1.count } ?? 0)
    } + (paths?.reduce(0) { $0 + $1.path.knotCount * 64 } ?? 0) + (selectionMask?.bytes.count ?? 0)
      + (patterns?.reduce(0) { $0 + $1.surface.allocatedBytes } ?? 0)
      + (sourceICC?.count ?? 0)
      + (sourceMetadata?.values.reduce(0) { $0 + $1.count } ?? 0)
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
    try validateHierarchy()
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
      + layers.reduce(0) { $0 + ($1.vectorMask?.path.knotCount ?? 0) }
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
    var bytes =
      (selectionMask?.bytes.count ?? 0) + knots * 64
      + (patterns?.reduce(0) { $0 + $1.surface.allocatedBytes } ?? 0)
    guard bytes <= 1_073_741_824 else {
      throw CraftError.invalid("This document exceeds the current 1 GiB raster budget.")
    }
    for l in layers {
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
        guard t.size.isFinite, (1...4096).contains(t.size), t.text.count <= 100_000,
          t.color.isFinite
        else { throw CraftError.invalid("Invalid text layer.") }
        if let w = t.layoutWidth, !(1...Surface.maxDimension).contains(w) {
          throw CraftError.invalid("Invalid text layout width.")
        }
        if let h = t.layoutHeight, !(1...Surface.maxDimension).contains(h) {
          throw CraftError.invalid("Invalid text layout height.")
        }
      case .shape(let s):
        guard s.width > 0, s.height > 0, s.width <= 32768, s.height <= 32768, s.color.isFinite
        else { throw CraftError.invalid("Invalid shape.") }
      case .adjustment(let a): try a.validate()
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
    var version = 9
    var document: CraftDocument
  }
  public static func encode(_ document: CraftDocument) throws -> Data {
    try document.validate()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(Envelope(document: document))
    guard data.count <= 512 * 1024 * 1024 else {
      throw CraftError.invalid("Archive exceeds the 512 MiB file limit.")
    }
    return data
  }
  public static func decode(_ data: Data) throws -> CraftDocument {
    try decode(data, rasterByteLimit: 1_073_741_824)
  }
  public static func decode(_ data: Data, rasterByteLimit: Int) throws -> CraftDocument {
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
    guard header.magic == "PhotoCraftSwift", (1...9).contains(header.version) else {
      throw CraftError.unsupported("Unsupported Photato document version.")
    }
    decoder.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: rasterByteLimit)
    let envelope = try decoder.decode(Envelope.self, from: data)
    try envelope.document.validate()
    return envelope.document
  }
}
