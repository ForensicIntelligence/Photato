import Foundation

/// Portable settings, shared by interactive conversion and recorded Actions.
public struct DocumentModeRequest: Codable, Equatable, Sendable {
  public var conversion: DocumentModeConversion
  public var mergeVisible: Bool
  public var clipHDR: Bool
  public init(_ conversion: DocumentModeConversion, mergeVisible: Bool = false, clipHDR: Bool = false) {
    self.conversion = conversion; self.mergeVisible = mergeVisible; self.clipHDR = clipHDR
  }
}

public struct RestrictedModeRequest: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case indexed, bitmap, colorTable }
  public var kind: Kind
  public var indexed = IndexedColorSettings()
  public var bitmap = BitmapConversionSettings()
  public var mergeVisible = false
  public var colors: [PaletteColor] = []
  public var transparentIndex: Int?
  public var previousPalette: [PaletteColor]?
  public init(_ kind: Kind) { self.kind = kind }
  public var title: String { switch kind { case .indexed: "Indexed Color"; case .bitmap: "Bitmap"; case .colorTable: "Color Table" } }
  public var usesMasterPalette: Bool {
    kind == .indexed && [.masterPerceptual, .masterSelective, .masterAdaptive].contains(indexed.palette)
  }
  public func validate() throws {
    switch kind {
    case .indexed:
      try indexed.validate()
      if let previousPalette, !(1...256).contains(previousPalette.count) { throw CraftError.invalid("Previous palette requires1–256 colors.") }
      if indexed.palette == .previous, previousPalette == nil { throw CraftError.invalid("Previous palette is missing from the recorded conversion.") }
    case .bitmap: try bitmap.validate()
    case .colorTable:
      guard (1...256).contains(colors.count), transparentIndex == nil || colors.indices.contains(transparentIndex!) else { throw CraftError.invalid("Invalid recorded color table.") }
    }
  }
}

/// The full playback result commits only to the immutable source it was prepared from.
public struct PreparedActionEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let title: String
  public init(source: CraftDocument, result: CraftDocument, title: String) {
    self.source = source; self.result = result; self.title = title
  }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id else { throw CraftError.invalid("The document changed during Actions playback.") }
    try result.validate(); return result
  }
}
