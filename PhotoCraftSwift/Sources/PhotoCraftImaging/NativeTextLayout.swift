import AppKit
import CoreText
import PhotoCraftCore

/// TextKit owns shaping, Unicode input attributes and paragraph layout. Each
/// offscreen call owns its storage/layout manager; no UI objects are shared.
private final class NativeTypeContainer:NSTextContainer {
  var verticalWriting=false
  override var layoutOrientation:NSLayoutManager.TextLayoutOrientation{verticalWriting ? .vertical:.horizontal}
}
public enum NativeTextLayout {
  private static let optionsKey=NSAttributedString.Key("PhotatoFontOptions")
  private static let glyphKey=NSAttributedString.Key("PhotatoGlyphOverride")
  private static let sourceFontKey=NSAttributedString.Key("PhotatoSourceFont")
  private static let horizontal = NSAttributedString.Key("PhotatoHorizontalScale")
  private static let vertical = NSAttributedString.Key("PhotatoVerticalScale")
  public static func attributes(_ style: TypeStyle, paragraph: TypeParagraph, dpi: Double, orientation:TextTypography.Orientation = .horizontal) throws -> [NSAttributedString.Key: Any] {
    let font = try NativeFonts.font(style,dpi:dpi)
    let p = NSMutableParagraphStyle()
    p.alignment = [.left: .left, .center: .center, .right: .right, .justified: .justified][paragraph.alignment]!
    p.baseWritingDirection = [.natural: .natural, .leftToRight: .leftToRight, .rightToLeft: .rightToLeft][paragraph.direction]!
    let unit = dpi / 72
    p.firstLineHeadIndent = (paragraph.startIndent + paragraph.firstIndent) * unit
    p.headIndent = paragraph.startIndent * unit; p.tailIndent = -paragraph.endIndent * unit
    p.paragraphSpacingBefore = paragraph.spaceBefore * unit; p.paragraphSpacing = paragraph.spaceAfter * unit
    p.hyphenationFactor = paragraph.hyphenation ? 1 : 0
    if style.leading > 0 { p.minimumLineHeight = style.leading * unit; p.maximumLineHeight = style.leading * unit }
    var result:[NSAttributedString.Key:Any] = [.font: font, .foregroundColor: NSColor(srgbRed: CGFloat(style.color.r), green: CGFloat(style.color.g), blue: CGFloat(style.color.b), alpha: CGFloat(style.color.a)),
      .kern: style.tracking * style.size * unit / 1000, .baselineOffset: style.baseline * unit,
      .underlineStyle: style.underline ? NSUnderlineStyle.single.rawValue : 0,
      .strikethroughStyle: style.strikethrough ? NSUnderlineStyle.single.rawValue : 0,
      .paragraphStyle: p, horizontal: style.horizontalScale, vertical: style.verticalScale]
    if style.tracking == 0 { result.removeValue(forKey:.kern) }
    result[sourceFontKey]=style.font;result[.verticalGlyphForm]=orientation == .vertical ? 1:0
    if let options=style.fontOptions{result[optionsKey]=try JSONEncoder().encode(options);if let language=options.language{result[NSAttributedString.Key(kCTLanguageAttributeName as String)]=language};if let liga=options.features.first(where:{$0.tag=="liga"}){result[.ligature]=liga.value==0 ? 0:1}}
    if let glyph=style.glyphOverride{result[glyphKey]=try JSONEncoder().encode(glyph);if let info=NSGlyphInfo(glyph:NSGlyph(glyph.glyph),for:font,baseString:glyph.baseString){result[.glyphInfo]=info}}
    return result
  }
  public static func glyphString(style original:TypeStyle,paragraph:TypeParagraph,font:String,glyph:NativeFonts.Glyph,dpi:Double,orientation:TextTypography.Orientation)throws->NSAttributedString {
    var style=original
    if style.font != font{style.font=font;style.fontOptions=nil}
    let base=glyph.unicode ?? "\u{FFFC}";style.glyphOverride = .init(glyph:glyph.id,baseString:base)
    return NSAttributedString(string:base,attributes:try attributes(style,paragraph:paragraph,dpi:dpi,orientation:orientation))
  }
  public static func attributed(_ content: TextContent, dpi: Double) throws -> NSAttributedString {
    try content.validate()
    let text = content.promoted(dpi: dpi), type = text.typography!
    let result = NSMutableAttributedString(string: text.text,
      attributes: try attributes(type.defaultStyle, paragraph: type.defaultParagraph, dpi: dpi, orientation:type.writingOrientation))
    var offset = 0
    for run in type.runs {
      result.setAttributes(try attributes(run.style, paragraph: run.paragraph, dpi: dpi, orientation:type.writingOrientation), range: NSRange(location: offset, length: run.length))
      offset += run.length
    }
    return result
  }
  public static func styles(_ attributes: [NSAttributedString.Key: Any], dpi: Double) -> (TypeStyle, TypeParagraph) {
    var style = TypeStyle(), para = TypeParagraph()
    let unit = 72 / dpi
    if let font = attributes[.font] as? NSFont { style.font = font.fontName; style.size = font.pointSize * unit }
    if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
      style.color = Pixel(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent))
    }
    func number(_ key: NSAttributedString.Key) -> Double { (attributes[key] as? NSNumber)?.doubleValue ?? 0 }
    style.horizontalScale = (attributes[horizontal] as? NSNumber)?.doubleValue ?? 1
    style.verticalScale = (attributes[vertical] as? NSNumber)?.doubleValue ?? 1
    style.tracking = number(.kern) * unit * 1000 / style.size
    style.baseline = number(.baselineOffset) * unit
    style.underline = number(.underlineStyle) != 0; style.strikethrough = number(.strikethroughStyle) != 0
    if let p = attributes[.paragraphStyle] as? NSParagraphStyle {
      para.alignment = [.left: .left, .center: .center, .right: .right, .justified: .justified][p.alignment] ?? .left
      para.direction = [.natural: .natural, .leftToRight: .leftToRight, .rightToLeft: .rightToLeft][p.baseWritingDirection] ?? .natural
      para.startIndent = p.headIndent * unit; para.firstIndent = max(0, p.firstLineHeadIndent * unit - para.startIndent)
      para.endIndent = max(0, -p.tailIndent * unit)
      para.spaceBefore = p.paragraphSpacingBefore * unit; para.spaceAfter = p.paragraphSpacing * unit
      para.hyphenation = p.hyphenationFactor > 0; style.leading = p.maximumLineHeight * unit
    }
    if let name=attributes[sourceFontKey] as? String{style.font=name}
    if let data=attributes[optionsKey] as? Data{style.fontOptions=try? JSONDecoder().decode(TypeFontOptions.self,from:data)}
    if let data=attributes[glyphKey] as? Data{style.glyphOverride=try? JSONDecoder().decode(TypeGlyphOverride.self,from:data)}
    return (style, para)
  }
  public static func content(_ value: NSAttributedString, template: TextContent, dpi: Double) throws -> TextContent {
    var result = template.promoted(dpi: dpi), type = result.typography!
    result.text = value.string; type.runs = []
    value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attrs, range, _ in
      var (style, paragraph) = styles(attrs, dpi: dpi)
      if let glyph=style.glyphOverride {let part=(value.string as NSString).substring(with:range),count=range.length/glyph.baseString.utf16.count
        if count>0,part==String(repeating:glyph.baseString,count:count){for _ in 0..<count{type.runs.append(TypeRun(length:glyph.baseString.utf16.count,style:style,paragraph:paragraph))};return}
        style.glyphOverride=nil
      }
      if let last = type.runs.last, last.style == style, last.paragraph == paragraph {
        type.runs[type.runs.count - 1].length += range.length
      } else { type.runs.append(TypeRun(length: range.length, style: style, paragraph: paragraph)) }
    }
    if let first = type.runs.first { type.defaultStyle = first.style; type.defaultParagraph = first.paragraph }
    result.fontName = type.defaultStyle.font; result.size = type.defaultStyle.size; result.color = type.defaultStyle.color
    result.typography = type; try result.validate(); return result
  }
  public struct Metrics {
    public var width: Int
    public var height: Int
    public var firstBaseline: Double
    public var overset: Bool
    public var origin:PathPoint = .init(0,0)
  }
  private static func layout(_ text: TextContent, dpi: Double) throws -> (NSTextStorage, NSLayoutManager, NSTextContainer, Metrics) {
    let storage = NSTextStorage(attributedString: try attributed(text, dpi: dpi))
    let manager = NSLayoutManager(); manager.usesFontLeading = true
    let paragraph = text.typography?.kind == .paragraph
    let isVertical=text.typography?.writingOrientation == .vertical
    let width = paragraph ? text.layoutWidth ?? 1 : 32768
    let height = paragraph ? text.layoutHeight ?? 1 : 32768
    let container = NativeTypeContainer(containerSize: NSSize(width: isVertical ? height:width, height: isVertical ? width:height))
    container.verticalWriting=isVertical
    container.lineFragmentPadding = 0
    manager.addTextContainer(container); storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let used = manager.usedRect(for: container)
    let range = manager.glyphRange(for: container)
    let baseline = range.length > 0 ? manager.location(forGlyphAt: range.location).y : 0
    let metrics = Metrics(width: paragraph ? width : max(1, Int(ceil(isVertical ? used.maxY:used.maxX)) + 2),
      height: paragraph ? height : max(1, Int(ceil(isVertical ? used.maxX:used.maxY)) + 2), firstBaseline: baseline,
      overset: NSMaxRange(range) < manager.numberOfGlyphs)
    guard paragraph || !metrics.overset else { throw CraftError.unsupported("Point text exceeds the native layout extent. Use a paragraph frame or a shorter text layer.") }
    guard metrics.width <= 32768, metrics.height <= 32768, metrics.width * metrics.height <= 16_777_216 else {
      throw CraftError.unsupported("This text frame exceeds the 16 megapixel type rendering limit.")
    }
    return (storage, manager, container, metrics)
  }
  public static func metrics(_ text: TextContent, dpi: Double) throws -> Metrics { if text.typography?.geometry?.isActive==true{return try ShapedTextLayout.metrics(text,dpi:dpi)};return try layout(text, dpi: dpi).3 }
  /// Reuse TextKit glyph positions for shape/type-to-frame conversion. Color-only
  /// glyphs without vector outlines remain unsupported rather than becoming boxes.
  public static func outline(_ text: TextContent, dpi: Double) throws -> CGPath {
    if text.typography?.geometry?.isActive==true{return try ShapedTextLayout.outline(text,dpi:dpi)}
    let (storage, manager, container, metrics) = try layout(text, dpi: dpi)
    guard text.typography?.writingOrientation != .vertical else{throw CraftError.unsupported("Vertical type outline conversion is not qualified yet; retain editable type or rasterize it.")}
    _ = metrics
    let range = manager.glyphRange(for: container), path = CGMutablePath()
    for index in range.location..<(range.location + range.length) {
      try Task.checkCancellation()
      let character = manager.characterIndexForGlyph(at: index)
      guard character < storage.length, let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont else { continue }
      let glyph = manager.glyph(at: index)
      guard let cgGlyph = CGGlyph(exactly: glyph), let outline = CTFontCreatePathForGlyph(font as CTFont, cgGlyph, nil) else {
        let unit = (storage.string as NSString).substring(with: NSRange(location: character, length: 1))
        if unit.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { continue }
        throw CraftError.unsupported("This text contains a glyph without a supported vector outline.")
      }
      let line = manager.lineFragmentRect(forGlyphAt: index, effectiveRange: nil)
      let position = manager.location(forGlyphAt: index)
      let baseline = (storage.attribute(.baselineOffset, at: character, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
      let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: line.minX + position.x, ty: line.minY + position.y - baseline)
      path.addPath(outline, transform: transform)
    }
    guard !path.isEmpty else { throw CraftError.unsupported("This text has no supported vector glyph outlines.") }
    return path
  }
  public static func render(_ text: TextContent, document: CraftDocument) throws -> Surface {
    if text.typography?.geometry?.isActive==true{return try ShapedTextLayout.render(text,document:document)}
    let (storage, manager, container, metrics) = try layout(text, dpi: document.pixelsPerInch)
    let floating = document.depth != .u8
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | (floating ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : 0)
    guard let context = CGContext(data: nil, width: metrics.width, height: metrics.height,
      bitsPerComponent: floating ? 32 : 8, bytesPerRow: metrics.width * (floating ? 16 : 4),
      space: try ColorManagement.space(for: document), bitmapInfo: info) else { throw CraftError.invalid("Could not allocate the type renderer.") }
    context.setShouldAntialias(text.typography?.antialias ?? true)
    context.translateBy(x: 0, y: CGFloat(metrics.height)); context.scaleBy(x: 1, y: -1)
    if text.typography?.writingOrientation == .vertical {context.translateBy(x:CGFloat(metrics.width),y:0);context.rotate(by:.pi/2)}
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    withExtendedLifetime(storage) {}
    guard let image = context.makeImage() else { throw CraftError.invalid("Could not render text.") }
    return try RasterIO.surface(image, depth: document.depth, space: ColorManagement.space(for: document),
      colorEncoding: document.depth == .f32 ? .linearRGB : .sRGB)
  }
}
