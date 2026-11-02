import Foundation

/// Native type uses point sizes and UTF-16 ranges, matching AppKit. Legacy plain
/// text retains its original pixel-sized renderer until explicitly edited.
public struct TypeStyle: Codable, Equatable, Sendable {
  public var font = "HelveticaNeue"
  public var size: Double = 36
  public var color = Pixel.black
  public var tracking: Double = 0 // thousandths of an em
  public var baseline: Double = 0
  public var leading: Double = 0 // zero = automatic
  public var horizontalScale: Double = 1
  public var verticalScale: Double = 1
  public var underline = false
  public var strikethrough = false
  public var fontOptions: TypeFontOptions?
  public var glyphOverride: TypeGlyphOverride?
  public var characterFormatting: TypeCharacterFormatting?
  public init() {}
  public func validate() throws {
    try fontOptions?.validate();try glyphOverride?.validate();try characterFormatting?.validate()
    guard !font.isEmpty, font.utf8.count <= 256, size.isFinite, (0.1...4096).contains(size),
      color.isFinite, [color.r, color.g, color.b, color.a].allSatisfy({ (0...1).contains($0) }),
      tracking.isFinite, (-1000...10000).contains(tracking), baseline.isFinite,
      abs(baseline) <= 4096, leading.isFinite, (0...16384).contains(leading),
      horizontalScale.isFinite, verticalScale.isFinite,
      (0.01...10).contains(horizontalScale), (0.01...10).contains(verticalScale)
    else { throw CraftError.invalid("Invalid character formatting.") }
  }
}
public struct TypeParagraph: Codable, Equatable, Sendable {
  public enum Alignment: String, Codable, CaseIterable, Sendable { case left, center, right, justified }
  public enum Direction: String, Codable, CaseIterable, Sendable { case natural, leftToRight, rightToLeft }
  public var alignment: Alignment = .left
  public var direction: Direction = .natural
  public var firstIndent: Double = 0
  public var startIndent: Double = 0
  public var endIndent: Double = 0
  public var spaceBefore: Double = 0
  public var spaceAfter: Double = 0
  public var hyphenation = false
  public var formatting: TypeParagraphFormatting?
  public init() {}
  public func validate() throws {
    try formatting?.validate()
    guard [firstIndent,startIndent,endIndent].allSatisfy({$0.isFinite && (-16384...16384).contains($0)}),[spaceBefore,spaceAfter].allSatisfy({$0.isFinite && (0...16384).contains($0)})
    else { throw CraftError.invalid("Invalid paragraph formatting.") }
  }
}
public struct TypeRun: Codable, Equatable, Sendable {
  public var length: Int
  public var style: TypeStyle
  public var paragraph: TypeParagraph
  public init(length: Int, style: TypeStyle, paragraph: TypeParagraph = .init()) {
    self.length = length; self.style = style; self.paragraph = paragraph
  }
}
public struct TextTypography: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable { case point, paragraph }
  public var kind: Kind = .point
  public var defaultStyle = TypeStyle()
  public var defaultParagraph = TypeParagraph()
  public var runs: [TypeRun] = []
  public var antialias = true
  public var orientation: Orientation?
  public var geometry: TextGeometry?
  public var sourceFrame: TypeSourceFrame?
  public var antialiasMode: TypeAntialias?
  public init() {}
  public func validate(text: String) throws {
    try geometry?.validate();try sourceFrame?.validate()
    try defaultStyle.validate(); try defaultParagraph.validate()
    let utf16=Array(text.utf16),count = utf16.count
    guard count <= 100_000, runs.count <= 4096 else { throw CraftError.invalid("Text exceeds the native type limit.") }
    if runs.isEmpty,let glyph=defaultStyle.glyphOverride,text != glyph.baseString{throw CraftError.invalid("Glyph metadata does not match the text.")}
    var position = 0
    for run in runs {
      try run.style.validate(); try run.paragraph.validate()
      guard run.length > 0, run.length <= count - position else { throw CraftError.invalid("Invalid type run length.") }
      if let glyph=run.style.glyphOverride {let part=String(decoding:utf16[position..<(position+run.length)],as:UTF16.self);guard part==glyph.baseString else{throw CraftError.invalid("Glyph metadata does not match its text run.")}}
      position += run.length
      guard Self.isBoundary(position, in: text) else { throw CraftError.invalid("A type run splits a Unicode scalar.") }
    }
    guard runs.isEmpty || position == count else { throw CraftError.invalid("Type runs must cover the whole string.") }
  }
  public static func isBoundary(_ offset: Int, in text: String) -> Bool {
    guard offset >= 0, offset <= text.utf16.count else { return false }
    let index = text.utf16.index(text.utf16.startIndex, offsetBy: offset)
    return String.Index(index, within: text.unicodeScalars) != nil
  }
}
extension TextContent {
  public func promoted(dpi: Double) -> TextContent {
    guard typography == nil else { return self }
    var result = self, type = TextTypography()
    type.defaultStyle.font = fontName; type.defaultStyle.size = size * 72 / dpi
    type.defaultStyle.color = color
    type.kind = layoutWidth == nil ? .point : .paragraph
    result.typography = type
    return result
  }
  public func validate() throws {
    try importedAppearance?.validate()
    guard size.isFinite, (0.1...4096).contains(size), text.utf16.count <= 100_000, color.isFinite else {
      throw CraftError.invalid("Invalid text layer.")
    }
    for dimension in [layoutWidth, layoutHeight].compactMap({ $0 }) {
      guard (1...Surface.maxDimension).contains(dimension) else { throw CraftError.invalid("Invalid text frame.") }
    }
    if let typography {
      try typography.validate(text: text)
      if typography.kind == .paragraph, layoutWidth == nil || layoutHeight == nil {
        throw CraftError.invalid("Paragraph text requires a width and height.")
      }
    }
  }
}
