import Foundation

/// Native translation of the licensed PhotoCraft channel-command arithmetic.
/// Source agreement is separate from Photoshop kernel/profile qualification.
public struct ChannelArithmeticOptions: Codable, Equatable, Sendable {
  public var blending = "multiply"
  public var opacity: Float = 1
  public var scale: Float = 1
  public var offset: Float = 0
  public var preserveTransparency = false
  public init() {}
  public static var modes: [String] {
    ["normal","darken","multiply","colorBurn","linearBurn","lighten","screen",
     "colorDodge","linearDodge","overlay","softLight","hardLight","vividLight",
     "linearLight","pinLight","hardMix","difference","exclusion","divide","add","subtract"]
  }
  public static func title(_ key: String) -> String {
    if key == "add" { return "Add" }; if key == "subtract" { return "Subtract" }
    return BlendMode.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "").lowercased() == key.lowercased() }?.rawValue ?? key
  }
  public func validate() throws {
    guard Self.modes.contains(blending), opacity.isFinite, (0...1).contains(opacity),
      scale.isFinite, (1...2).contains(scale), offset.isFinite, (-255...255).contains(offset)
    else { throw CraftError.invalid("Invalid channel blending, opacity, scale or offset.") }
  }
  public func blend(_ base: Float, _ source: Float, extended: Bool = false) -> Float {
    let value: Float
    if blending == "add" { value = (base + source) / scale + offset / 255 }
    else if blending == "subtract" { value = (base - source) / scale + offset / 255 }
    else if extended && blending == "linearDodge" { value = base + source }
    else {
      let mode = BlendMode.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "").lowercased() == blending.lowercased() } ?? .multiply
      value = mode.channel(base, source)
    }
    return extended ? value : unit(value)
  }
}

public enum ChannelArithmeticChannel: Codable, Equatable, Hashable, Sendable {
  case composite, gray, component(Int), alpha(UUID), quickMask, selection
  case transparency, layerMask, vectorMask, ink(InkChannelTarget)
}
public struct ChannelArithmeticSource: Codable, Equatable, Sendable {
  /// Nil means the destination document. APIs resolve explicitly shared documents first.
  public var documentID: UUID?
  public var layerID: UUID?
  public var channel: ChannelArithmeticChannel = .composite
  public var invert = false
  public init(documentID: UUID? = nil, layerID: UUID? = nil,
    channel: ChannelArithmeticChannel = .composite, invert: Bool = false) {
    self.documentID = documentID; self.layerID = layerID; self.channel = channel; self.invert = invert
  }
}
/// Numeric components, without alpha weighting or an implicit color conversion.
/// A fourth component uses `a` as an ink value. Single planes repeat their value in RGB.
public struct ChannelArithmeticInput: Sendable {
  public var samples: Surface
  public var components: Int
  public var mode: DocumentColorMode
  public init(samples: Surface, components: Int = 1, mode: DocumentColorMode = .grayscale) {
    self.samples = samples; self.components = components; self.mode = mode
  }
  public func validate(width: Int, height: Int) throws {
    guard samples.width == width, samples.height == height,
      samples.colorEncoding == .sRGB, [1,3,4].contains(components)
    else { throw CraftError.invalid("Channel source dimensions or numerical layout differ.") }
    try samples.validated()
  }
  public func plane(_ index: Int = 0, mean: Bool = false) throws -> Surface {
    guard (0..<components).contains(index) else { throw CraftError.invalid("Source component not found.") }
    return try samples.mappedStoredSamples(encoding: .sRGB) { p in
      let v: Float
      if mean { v = components==4 ? (p.r+p.g+p.b+p.a)/4 : components==3 ? (p.r+p.g+p.b)/3:p.r }
      else { switch index {case 0:v=p.r;case 1:v=p.g;case 2:v=p.b;default:v=p.a} }
      return Pixel(v,v,v)
    }
  }
}
public enum ChannelArithmeticTarget: Codable, Equatable, Sendable {
  /// Empty components means composite editing; a nonempty set preserves stored alpha.
  case pixels(UUID, [Int]), layerMask(UUID), alpha(UUID), quickMask, ink(InkChannelTarget)
}
public enum ChannelCalculationResult: String, Codable, CaseIterable, Sendable {
  case newChannel, selection, newDocument
  public var title: String {
    switch self { case .newChannel: "New Channel"; case .selection: "Selection"; case .newDocument: "New Document" }
  }
}
public struct ChannelArithmeticRequest: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case applyImage, calculations }
  public var kind: Kind
  public var source1 = ChannelArithmeticSource()
  public var source2 = ChannelArithmeticSource(channel: .component(0))
  public var mask: ChannelArithmeticSource?
  public var options = ChannelArithmeticOptions()
  public var result: ChannelCalculationResult = .newChannel
  public var name: String?
  public init(_ kind: Kind) {
    self.kind = kind
    if kind == .calculations { source1.channel = .component(0) }
  }
  public var title: String { kind == .applyImage ? "Apply Image" : "Calculations" }
  public func validate() throws {
    try options.validate()
    if let name { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf8.count <= 1024 else { throw CraftError.invalid("Invalid result name.") } }
  }
}

/// Same immutable transaction is committed by native dialogs and automation.
public struct ChannelArithmeticEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let title: String
  public init(source: CraftDocument, result: CraftDocument, title: String) {
    self.source = source; self.result = result; self.title = title
  }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id else {
      throw CraftError.invalid("The destination changed during channel blending.")
    }
    try result.validate(); return result
  }
}
