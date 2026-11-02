import Foundation
import CoreGraphics
import PhotoCraftCore

// Native port of the unwarped TySh/EngineData subset of photocraft
// crates/text/src/psd.rs (MIT OR Apache-2.0). Adobe glyph fidelity is unqualified.
enum PSDText {
  typealias E = PSDTextValue
  static let featureKeys=["Ligatures":"liga","DLigatures":"dlig","ContextualLigatures":"calt","Swash":"swsh","OldStyle":"onum","StylisticAlternates":"salt","Titling":"titl","Ornaments":"ornm","Ordinals":"ordn","Fractions":"frac"]
  static func checkColorSpace(_ document: CraftDocument) throws {
    let space = try ColorManagement.space(for: document)
    guard space == (try RasterIO.colorSpace()) || (document.depth == .f32 && space == CGColorSpace(name: CGColorSpace.linearSRGB)) else { throw CraftError.unsupported("Editable PSD type currently requires an sRGB working profile.") }
  }
  static func descriptor(_ data: Data) throws -> (Transform2D, PSDDescriptor) {
    var r = PSDReader(data: data)
    guard try r.u16() == 1 else { throw CraftError.unsupported("Unsupported TySh version.") }
    let values = try (0..<6).map { _ in Double(bitPattern: try r.number(8)) }
    let transform = Transform2D(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    try transform.validated()
    guard try r.u16() == 50 else { throw CraftError.unsupported("Unsupported text descriptor version.") }
    let (text, used) = try PSDDescriptor.readPrefix(data.subdata(in: r.offset..<data.count)); _ = try r.view(used)
    guard try r.u16() == 1 else { throw CraftError.unsupported("Unsupported text warp version.") }
    let (warp, size) = try PSDDescriptor.readPrefix(data.subdata(in: r.offset..<data.count)); _ = try r.view(size)
    if case .enumerated(_, let value) = warp["warpStyle"], value.text != "warpNone" { throw CraftError.unsupported("Warped type is not supported yet.") }
    if case .enumerated(_, let value) = text["Ornt"], !["Hrzn","Vrtc"].contains(value.text) { throw CraftError.unsupported("Unknown type orientation.") }
    _ = try (0..<4).map { _ in try r.i32() }
    guard r.remaining <= 3, try r.consumePadding(0) else { throw CraftError.invalid("Invalid type block tail.") }
    return (transform, text)
  }
  static func restore(_ layer: inout Layer, in document: CraftDocument) throws {
    guard let data = layer.sourceTags?["TySh"] else { return }
    try checkColorSpace(document)
    let (transform, desc) = try descriptor(data)
    guard case .raw(let engine) = desc["EngineData"], case .text(let units) = desc["Txt "] else { throw CraftError.unsupported("Type requires text and EngineData.") }
    let root = try E.parse(engine), dict = root["EngineDict"], resources = root["ResourceDict"]
    let text = String(decoding: units.last == 0 ? units.dropLast() : units[...], as: UTF16.self).replacingOccurrences(of: "\r", with: "\n")
    guard text.utf16.count <= 100_000 else { throw CraftError.invalid("PSD text is too long.") }
    if let actual = dict?["Editor"]?["Text"]?.string, actual.replacingOccurrences(of: "\r", with: "\n") != text + "\n" { throw CraftError.unsupported("Conflicting PSD text sources.") }
    let fonts = resources?["FontSet"]?.array?.compactMap { $0["Name"]?.string } ?? []
    let base = resources?["StyleSheetSet"]?.array?.first?["StyleSheetData"]?.fields ?? [:]
    let basePara = resources?["ParagraphSheetSet"]?.array?.first?["Properties"]?.fields ?? [:]
    let k = 72 / document.pixelsPerInch
    func style(_ entry: E) throws -> TypeStyle {
      let d = base.merging(entry.fields) { _, new in new }
      func n(_ key: String, _ fallback: Double = 0) -> Double { d[key]?.number ?? fallback }
      guard ["FauxBold", "FauxItalic"].allSatisfy({ d[$0]?.flag != true }),
        [0,1].contains(n("FontCaps")), n("Kerning") == 0 else { throw CraftError.unsupported("This PSD uses advanced character formatting not ported yet.") }
      var s = TypeStyle()
      let fi = n("Font"); guard fi >= 0, fi < Double(fonts.count), fi.rounded() == fi else { throw CraftError.invalid("Invalid text font index.") }
      s.font = fonts[Int(fi)]; s.size = n("FontSize", 36) * k
      s.leading = d["AutoLeading"]?.flag == false ? n("Leading") * k : 0
      s.tracking = n("Tracking"); s.baseline = n("BaselineShift") * k
      s.horizontalScale = n("HorizontalScale", 1); s.verticalScale = n("VerticalScale", 1)
      s.underline = d["Underline"]?.flag == true; s.strikethrough = d["Strikethrough"]?.flag == true
      if let fill = d["FillColor"] {
        let values = fill["Values"]?.array?.compactMap(\.number) ?? []
        guard fill["Type"]?.number == 1, values.count == 4 else { throw CraftError.unsupported("Only RGB type colors are implemented.") }
        s.color = Pixel(Float(values[1]), Float(values[2]), Float(values[3]), Float(values[0]))
      }
      var options=TypeFontOptions()
      for (key,tag) in featureKeys {if let value=d[key]?.flag,tag != "liga" || !value{options.features.append(.init(tag,value ? 1:0))}}
      if n("FontCaps")==1{options.features.append(.init("smcp",1))};options.features.sort{$0.tag<$1.tag}
      if !options.isEmpty{s.fontOptions=options}
      try s.validate(); return s
    }
    func paragraph(_ entry: E) throws -> TypeParagraph {
      let d = basePara.merging(entry.fields) { _, new in new }
      func n(_ key: String) -> Double { d[key]?.number ?? 0 }
      var p = TypeParagraph()
      switch n("Justification") { case 0: p.alignment = .left; case 1: p.alignment = .right; case 2: p.alignment = .center; case 3: p.alignment = .justified
      default: throw CraftError.unsupported("This paragraph justification is not ported yet.") }
      p.firstIndent = n("FirstLineIndent") * k; p.startIndent = n("StartIndent") * k; p.endIndent = n("EndIndent") * k
      p.spaceBefore = n("SpaceBefore") * k; p.spaceAfter = n("SpaceAfter") * k; p.hyphenation = d["AutoHyphenate"]?.flag == true
      try p.validate(); return p
    }
    func runs(_ name: String) throws -> [(Int, E)] {
      guard let array = dict?[name]?["RunArray"]?.array, let lengths = dict?[name]?["RunLengthArray"]?.array, array.count == lengths.count, !array.isEmpty, array.count <= 4096 else { throw CraftError.invalid("Invalid PSD text runs.") }
      var offset = 0, result: [(Int, E)] = []
      for (item, raw) in zip(array, lengths) {
        guard let length = raw.number, length.rounded() == length, length > 0, length <= Double(text.utf16.count + 1 - offset) else { throw CraftError.invalid("Invalid PSD type run length.") }
        offset += Int(length); result.append((min(offset, text.utf16.count), item))
      }
      guard offset == text.utf16.count + 1 else { throw CraftError.invalid("PSD runs do not cover the type string.") }
      return result
    }
    let chars = try runs("StyleRun"), paras = try runs("ParagraphRun")
    let styles = try chars.map { try style($0.1["StyleSheet"]?["StyleSheetData"] ?? .dictionary([:])) }
    let paragraphs = try paras.map { try paragraph($0.1["ParagraphSheet"]?["Properties"] ?? .dictionary([:])) }
    var type = TextTypography();if case .enumerated(_,let value)=desc["Ornt"],value.text=="Vrtc"{type.orientation = .vertical};type.defaultStyle = styles[0]; type.defaultParagraph = paragraphs[0]
    type.antialias = dict?["AntiAlias"]?.number != 0
    var at = 0, ci = 0, pi = 0
    while at < text.utf16.count {
      let end = min(chars[ci].0, paras[pi].0)
      guard end > at else { throw CraftError.invalid("Empty PSD type run.") }
      type.runs.append(TypeRun(length: end - at, style: styles[ci], paragraph: paragraphs[pi])); at = end
      if chars[ci].0 == at { ci += 1 }; if paras[pi].0 == at { pi += 1 }
    }
    var content = TextContent(text: text, fontName: type.defaultStyle.font, size: type.defaultStyle.size, color: type.defaultStyle.color)
    var origin = Transform2D.identity
    if let shape = dict?["Rendered"]?["Shapes"]?["Children"]?.array?.first, shape["ShapeType"]?.number == 1 {
      let bounds = shape["Cookie"]?["Photoshop"]?["BoxBounds"]?.array?.compactMap(\.number) ?? []
      guard bounds.count == 4, bounds.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }), (1...32768).contains(bounds[2] - bounds[0]), (1...32768).contains(bounds[3] - bounds[1]), bounds.allSatisfy({ $0.rounded() == $0 }) else { throw CraftError.unsupported("Invalid or fractional paragraph text frame.") }
      type.kind = .paragraph; content.layoutWidth = Int(bounds[2] - bounds[0]); content.layoutHeight = Int(bounds[3] - bounds[1]); origin = .translation(bounds[0], bounds[1])
    }
    content.typography = type; try content.validate()
    let metrics = try NativeTextLayout.metrics(content, dpi: document.pixelsPerInch)
    if type.kind == .point {origin=type.writingOrientation == .vertical ? .translation(-Double(metrics.width)+metrics.firstBaseline,0):.translation(0,-metrics.firstBaseline)}
    let mask = layer.maskCoordinateTransform
    layer.content = .text(content); layer.x = 0; layer.y = 0; layer.affine = transform * origin
    if layer.mask != nil { var properties = layer.effectiveMaskProperties; properties.transform = try layer.coordinateTransform.inverted() * mask; layer.maskProperties = properties }
  }
  static func write(_ layer: Layer, in document: CraftDocument) throws -> Data {
    guard case .text(let original) = layer.content else { throw CraftError.invalid("Expected type layer.") }
    guard !original.requiresRichTypeArchive else{throw CraftError.unsupported("Extended type formatting and original source appearance require native saving until their editable PSD mappings are qualified.")}
    try checkColorSpace(document)
    let text = original.promoted(dpi: document.pixelsPerInch), type = text.typography!
    try text.validate()
    guard type.geometry==nil else{throw CraftError.unsupported("Editable shaped text requires native saving until PSD path/warp mappings are qualified.")}
    let runs = type.runs.isEmpty ? [TypeRun(length: text.text.utf16.count, style: type.defaultStyle, paragraph: type.defaultParagraph)] : type.runs
    guard runs.allSatisfy({$0.style.glyphOverride==nil && ($0.style.fontOptions?.variations.isEmpty ?? true) && $0.style.fontOptions?.language==nil && ($0.style.fontOptions?.features.allSatisfy{(featureKeys.values.contains($0.tag) || $0.tag=="smcp") && (0...1).contains($0.value)} ?? true)}) else{throw CraftError.unsupported("This typography requires native saving: variable axes, language tags, glyph overrides or unsupported OpenType features cannot be preserved in editable PSD yet.")}
    guard runs.allSatisfy({ $0.paragraph.direction != .rightToLeft }) else { throw CraftError.unsupported("RTL text remains native-only until its PSD writing-direction mapping is qualified.") }
    let metrics = try NativeTextLayout.metrics(text, dpi: document.pixelsPerInch), unit = document.pixelsPerInch / 72
    var fonts: [String] = [], sr: [E] = [], pr: [E] = [], lengths: [E] = [], paragraphLengths: [E] = []
    var previousParagraph: TypeParagraph?
    for (i, run) in runs.enumerated() {
      if !fonts.contains(run.style.font) { fonts.append(run.style.font) }
      let s = run.style, p = run.paragraph
      var styleFields:[String:E] = ["Font": .number(Double(fonts.firstIndex(of: s.font)!)), "FontSize": .number(s.size * unit),
        "AutoLeading": .bool(s.leading == 0), "Leading": .number(s.leading * unit), "Tracking": .number(s.tracking),
        "BaselineShift": .number(s.baseline * unit), "HorizontalScale": .number(s.horizontalScale), "VerticalScale": .number(s.verticalScale),
        "FontCaps": .number(s.fontOptions?.features.first{$0.tag=="smcp"}?.value == 1 ? 1:0),
        "Underline": .bool(s.underline), "Strikethrough": .bool(s.strikethrough), "Ligatures": .bool(s.fontOptions?.features.first{$0.tag=="liga"}?.value != 0), "AutoKerning": .bool(true),
        "FillColor": .dictionary(["Type": .number(1), "Values": .array([s.color.a, s.color.r, s.color.g, s.color.b].map { .number(Double($0)) })])]
      for feature in s.fontOptions?.features ?? [] {if let key=featureKeys.first(where:{$0.value==feature.tag})?.key{styleFields[key] = .bool(feature.value != 0)}}
      let style:E = .dictionary(styleFields)
      let paragraph: E = .dictionary(["Justification": .number([.left: 0, .right: 1, .center: 2, .justified: 3][p.alignment]!),
        "FirstLineIndent": .number(p.firstIndent * unit), "StartIndent": .number(p.startIndent * unit), "EndIndent": .number(p.endIndent * unit),
        "SpaceBefore": .number(p.spaceBefore * unit), "SpaceAfter": .number(p.spaceAfter * unit), "AutoHyphenate": .bool(p.hyphenation), "AutoLeading": .number(1.2), "LeadingType": .number(0)])
      sr.append(.dictionary(["StyleSheet": .dictionary(["StyleSheetData": style])]))
      let length = Double(run.length + (i == runs.count - 1 ? 1 : 0))
      if previousParagraph == p, let last = paragraphLengths.last?.number {
        paragraphLengths[paragraphLengths.count - 1] = .number(last + length)
      } else {
        pr.append(.dictionary(["ParagraphSheet": .dictionary(["DefaultStyleSheet": .number(0), "Properties": paragraph])]))
        paragraphLengths.append(.number(length)); previousParagraph = p
      }
      lengths.append(.number(length))
    }
    let box = type.kind == .paragraph
    var photoshop: [String: E] = ["ShapeType": .number(box ? 1 : 0), "Base": .dictionary(["ShapeType": .number(box ? 1 : 0), "TransformPoint0": .array([.number(1), .number(0)]), "TransformPoint1": .array([.number(0), .number(1)]), "TransformPoint2": .array([.number(0), .number(0)])])]
    photoshop[box ? "BoxBounds" : "PointBase"] = .array(box ? [0, 0, Double(text.layoutWidth!), Double(text.layoutHeight!)].map(E.number) : [.number(0), .number(0)])
    let resource: E = .dictionary(["FontSet": .array(fonts.map { .dictionary(["Name": .string($0), "Script": .number(0), "FontType": .number(1), "Synthetic": .number(0)]) }),
      "StyleSheetSet": .array([.dictionary(["Name": .string("Normal RGB"), "StyleSheetData": sr[0]["StyleSheet"]!["StyleSheetData"]!])]),
      "ParagraphSheetSet": .array([.dictionary(["Name": .string("Normal RGB"), "DefaultStyleSheet": .number(0), "Properties": pr[0]["ParagraphSheet"]!["Properties"]!])]), "TheNormalStyleSheet": .number(0), "TheNormalParagraphSheet": .number(0)])
    let engine: E = .dictionary(["ResourceDict": resource, "DocumentResources": resource, "EngineDict": .dictionary([
      "Editor": .dictionary(["Text": .string(text.text.replacingOccurrences(of: "\n", with: "\r") + "\r")]),
      "StyleRun": .dictionary(["RunArray": .array(sr), "RunLengthArray": .array(lengths), "IsJoinable": .number(2)]),
      "ParagraphRun": .dictionary(["RunArray": .array(pr), "RunLengthArray": .array(paragraphLengths), "IsJoinable": .number(1)]),
      "AntiAlias": .number(type.antialias ? 4 : 0), "UseFractionalGlyphWidths": .bool(true),
      "Rendered": .dictionary(["Version": .number(1), "Shapes": .dictionary(["WritingDirection": .number(type.writingOrientation == .vertical ? 2:0), "Children": .array([
        .dictionary(["ShapeType": .number(box ? 1 : 0), "Procession": .number(type.writingOrientation == .vertical ? 1:0), "Lines": .dictionary(["WritingDirection": .number(type.writingOrientation == .vertical ? 2:0), "Children": .array([])]), "Cookie": .dictionary(["Photoshop": .dictionary(photoshop)])])])])])])])
    let anchorX = !box && type.writingOrientation == .vertical ? Double(metrics.width)-metrics.firstBaseline:0
    let anchorY = !box && type.writingOrientation != .vertical ? metrics.firstBaseline:0
    let top = -anchorY
    func rect(_ name: String) -> PSDValue { .object(PSDDescriptor(name, items: [
      .init("Left", .unit(Data("#Pnt".utf8), (-anchorX).bitPattern)), .init("Top ", .unit(Data("#Pnt".utf8), top.bitPattern)),
      .init("Rght", .unit(Data("#Pnt".utf8), (Double(metrics.width)-anchorX).bitPattern)), .init("Btom", .unit(Data("#Pnt".utf8), (Double(metrics.height) + top).bitPattern))])) }
    let desc = PSDDescriptor("TxLr", items: [.init("Txt ", .text(Array(text.text.replacingOccurrences(of: "\n", with: "\r").utf16) + [0])),
      .init("textGridding", .enumerated(.init("textGridding"), .init("None"))), .init("Ornt", .enumerated(.init("Ornt"), .init(type.writingOrientation == .vertical ? "Vrtc":"Hrzn"))),
      .init("AntA", .enumerated(.init("Annt"), .init(type.antialias ? "AnSm" : "Anno"))), .init("TextIndex", .integer(0)), .init("bounds", rect("bounds")), .init("boundingBox", rect("boundingBox")), .init("EngineData", .raw(engine.encoded()))])
    let warp = PSDDescriptor("warp", items: [.init("warpStyle", .enumerated(.init("warpStyle"), .init("warpNone"))), .init("warpValue", .number(0)), .init("warpPerspective", .number(0)), .init("warpPerspectiveOther", .number(0)), .init("warpRotate", .enumerated(.init("Ornt"), .init("Hrzn")))])
    let matrix = layer.coordinateTransform * (box ? .identity : .translation(anchorX, anchorY))
    var writer = PSDWriter(); writer.n(1, 2)
    for value in [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty] { writer.n(Int(truncatingIfNeeded: value.bitPattern), 8) }
    writer.n(50, 2); writer.data.append(try desc.encoded()); writer.n(1, 2); writer.data.append(try warp.encoded())
    for value in [0, Int(floor(top)), metrics.width, Int(ceil(Double(metrics.height) + top))] { writer.n(value, 4) }
    return writer.data
  }
  static func preview(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    let tag = try write(layer, in: document)
    var copy = layer; copy.content = .raster(try Renderer.layerSurface(layer, in: document))
    copy = try DocumentGeometry.transformLayer(copy, by: .identity, in: document)
    if copy.sourceTags == nil { copy.sourceTags = [:] }; copy.sourceTags?["TySh"] = tag
    return copy
  }
}
