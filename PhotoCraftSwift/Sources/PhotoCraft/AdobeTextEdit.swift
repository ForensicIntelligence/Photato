import AppKit
import PhotoCraftCore
import PhotoCraftImaging

/// Published create-composite text_layer add/edit subset; unknown semantics
/// fail explicitly. All shaping and document commands use the native engine.
struct AdobeTextEdit: Sendable {
  let raw: Data
  init(_ value: Any, path: String) throws {
    let root = try AdobeActionsRequest.Object(value, at: path, allowed: ["operation", "type", "name", "id", "text", "transformMode", "isVisible", "isClipped"])
    guard try root.string("type") == "text_layer" else { throw AdobeAPIError.invalid("Expected text_layer.") }
    _ = try root.object("text", allowed: ["content", "frame", "characterStyles", "paragraphStyles", "antiAliasing", "textOrientation"])
    raw = try JSONSerialization.data(withJSONObject: value)
  }
  func apply(to session: inout EditorSession, fontOptions: AdobeTypeFontOptions) throws {
    typealias Object = AdobeActionsRequest.Object
    let root = try Object(JSONSerialization.jsonObject(with: raw), at: "text layer", allowed: ["operation", "type", "name", "id", "text", "transformMode", "isVisible", "isClipped"])
    let op = try root.object("operation", allowed: ["type", "placement"]), adding = try op.string("type") == "add"
    guard ["add", "edit"].contains(try op.string("type")) else { throw AdobeAPIError.unsupported("Only text add/edit operations are supported.") }
    var layer: Layer
    let dpi = session.document.pixelsPerInch
    if adding {
      let placement = try op.object("placement", allowed: ["type"])
      guard try placement.string("type") == "top", root.fields["id"] == nil else { throw AdobeAPIError.unsupported("Text creation supports top placement and generated IDs.") }
      var content = TextContent(text: ""), type = TextTypography()
      type.defaultStyle.font = fontOptions.defaultFont; type.defaultStyle.size = 30 * 72 / dpi; type.defaultStyle.leading = 36 * 72 / dpi
      content.typography = type
      layer = Layer(name: root.fields["name"] == nil ? "Type" : try root.string("name"), content: .text(content))
    } else {
      guard op.fields["placement"] == nil, (root.fields["name"] == nil) != (root.fields["id"] == nil) else { throw AdobeAPIError.invalid("An edit requires one layer reference and no placement.") }
      let name = try root.fields["name"].map { _ in try root.string("name") }
      let id = try root.fields["id"].map { _ in Int32(try root.integer("id", range: Int(Int32.min)...Int(Int32.max))) }
      let matches = session.document.layers.filter { candidate in
        if let name { return candidate.name == name }
        guard let bytes = candidate.sourceTags?["lyid"], bytes.count == 4 else { return false }
        return Int32(bitPattern: bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) == id
      }
      guard matches.count == 1, let existing = matches.first, case .text = existing.content else { throw AdobeAPIError.invalid("Reference must identify exactly one text layer.") }
      layer = existing
    }
    guard case .text(let previous) = layer.content else { throw AdobeAPIError.invalid("Expected text layer.") }
    var content = previous.promoted(dpi: dpi)
    let input = try root.object("text", allowed: ["content", "frame", "characterStyles", "paragraphStyles", "antiAliasing", "textOrientation"])
    if input.fields["textOrientation"] != nil {guard let orientation=TextTypography.Orientation(rawValue:try input.string("textOrientation")) else{throw AdobeAPIError.invalid("Unknown text orientation.")};content.typography?.orientation=orientation == .horizontal ? nil:orientation}
    if input.fields["antiAliasing"] != nil {
      let aa = try input.string("antiAliasing")
      guard ["none","sharp","crisp","strong","smooth"].contains(aa),let mode=TypeAntialias(rawValue:aa) else { throw AdobeAPIError.unsupported("Unknown published text antialiasing value.") }
      content.typography?.antialias = aa != "none"
      if !["none","smooth"].contains(aa) || content.typography?.antialiasMode != nil{content.typography?.antialiasMode=mode}
    }
    if input.fields["content"] != nil {
      content.text = try input.string("content"); content.typography?.runs = []
    }
    guard content.text.utf16.count <= 100_000 else { throw AdobeAPIError.invalid("Text is too long.") }
    if root.fields["transformMode"] != nil, try root.string("transformMode") != "none" { throw AdobeAPIError.unsupported("Text supports transformMode none; custom/fit/fill are not implemented.") }
    var frameOrigin: CGPoint?
    if input.fields["frame"] != nil {
      let frame = try input.object("frame", allowed: ["type", "origin", "bounds"])
      content.typography?.sourceFrame=nil
      switch try frame.string("type") {
      case "point":
        guard frame.fields["bounds"] == nil else { throw AdobeAPIError.invalid("Point frames cannot have bounds.") }
        content.typography?.kind = .point; content.layoutWidth = nil; content.layoutHeight = nil
        if frame.fields["origin"] != nil {
          let origin = try frame.object("origin", allowed: ["x", "y"])
          frameOrigin = try CGPoint(x: origin.integer("x", range: -1_000_000...1_000_000), y: origin.integer("y", range: -1_000_000...1_000_000))
        }
      case "area":
        guard frame.fields["origin"] == nil else { throw AdobeAPIError.invalid("Area frames cannot have an origin.") }
        let bounds = try frame.object("bounds", allowed: ["left", "top", "right", "bottom"])
        let left = try bounds.integer("left", range: -1_000_000...1_000_000), top = try bounds.integer("top", range: -1_000_000...1_000_000)
        let right = try bounds.integer("right", range: -1_000_000...1_000_000), bottom = try bounds.integer("bottom", range: -1_000_000...1_000_000)
        content.typography?.kind = .paragraph; content.layoutWidth = right - left; content.layoutHeight = bottom - top; frameOrigin = CGPoint(x: left, y: top)
      default: throw AdobeAPIError.invalid("Unknown text frame type.")
      }
    }
    // Font resolution is local and deterministic; no Adobe Fonts identity claim.
    func resolve(_ name: String) throws -> String {
      if NSFont(name: name, size: 12) != nil { return name }
      if fontOptions.useDefault, NSFont(name: fontOptions.defaultFont, size: 12) != nil { return fontOptions.defaultFont }
      throw AdobeAPIError.unsupported("Font ‘\(name)’ is not installed.")
    }
    var resolved = content.typography!
    resolved.defaultStyle.font = try resolve(resolved.defaultStyle.font)
    for i in resolved.runs.indices { let font = try resolve(resolved.runs[i].style.font); resolved.runs[i].style.font = font }
    content.typography = resolved
    let attributed = NSMutableAttributedString(attributedString: try NativeTextLayout.attributed(content, dpi: dpi))
    func inclusive(_ object: Object, count: Int) throws -> NSRange {
      if object.fields["apply"] == nil { return NSRange(location: 0, length: count) }
      let range = try object.object("apply", allowed: ["from", "to"])
      let from = try range.integer("from", range: 0...max(0, count - 1)), to = try range.integer("to", range: 0...max(0, count - 1))
      guard count > 0, to >= from else { throw AdobeAPIError.invalid("Invalid inclusive style range.") }
      return NSRange(location: from, length: to - from + 1)
    }
    func apply(_ range: NSRange, _ change: (inout TypeStyle, inout TypeParagraph) throws -> Void) throws {
      guard TextTypography.isBoundary(range.location, in: content.text), TextTypography.isBoundary(NSMaxRange(range), in: content.text) else { throw AdobeAPIError.invalid("Style range splits a Unicode scalar.") }
      if range.length == 0 {
        var style = content.typography!.defaultStyle, paragraph = content.typography!.defaultParagraph
        try change(&style, &paragraph); content.typography?.defaultStyle = style; content.typography?.defaultParagraph = paragraph; return
      }
      var edits: [(NSRange, [NSAttributedString.Key: Any])] = [], failure: Error?
      attributed.enumerateAttributes(in: range) { attrs, local, stop in
        do { var (s, p) = NativeTextLayout.styles(attrs, dpi: dpi); try change(&s, &p); try s.validate(); try p.validate(); edits.append((local, try NativeTextLayout.attributes(s, paragraph: p, dpi: dpi,orientation:content.typography!.writingOrientation))) }
        catch { failure = error; stop.pointee = true }
      }
      if let failure { throw failure }; for (range, attrs) in edits { attributed.setAttributes(attrs, range: range) }
    }
    func number(_ object: Object, _ key: String) throws -> Double {
      guard let n = object.fields[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw AdobeAPIError.invalid("Invalid \(key).") }; return n.doubleValue
    }
    for raw in try input.fields["characterStyles"].map({ _ in try input.array("characterStyles", count: 0...4096) }) ?? [] {
      let item = try Object(raw, at: "character style", allowed: ["apply", "characterStyle"])
      let style = try item.object("characterStyle", allowed: ["font", "fontSize", "fontAlpha", "letterSpacing", "lineHeight", "autoLeading", "underline", "syntheticBold", "syntheticItalic", "capsOption"])
      let bold=try style.optionalBool("syntheticBold"),italic=try style.optionalBool("syntheticItalic")
      if style.fields["capsOption"] != nil, !["normal_caps","small_caps","all_caps"].contains(try style.string("capsOption")) { throw AdobeAPIError.unsupported("All-small-caps and unknown caps values are not implemented.") }
      try apply(inclusive(item, count: attributed.length)) { s, _ in
        if bold != nil || italic != nil {
          if s.characterFormatting != nil || bold == true || italic == true {
            var formatting=s.characterFormatting ?? .init();if let bold{formatting.fauxBold=bold};if let italic{formatting.fauxItalic=italic};s.characterFormatting=formatting
          }
        }
        if style.fields["capsOption"] != nil {
          let caps=try style.string("capsOption");var options=s.fontOptions ?? .init();options.features.removeAll{$0.tag=="smcp"};if caps=="small_caps"{options.features.append(.init("smcp",1))};s.fontOptions=options.isEmpty ? nil:options
          if s.characterFormatting != nil || caps=="all_caps" {var formatting=s.characterFormatting ?? .init();formatting.caps=caps=="all_caps" ? .allCaps:caps=="small_caps" ? .smallCaps:.normal;s.characterFormatting=formatting}
        }
        if style.fields["font"] != nil { s.font = try resolve(style.object("font", allowed: ["postScriptName"]).string("postScriptName")) }
        if style.fields["fontSize"] != nil { s.size = try number(style, "fontSize") * 72 / dpi }
        if style.fields["fontAlpha"] != nil { s.color.a = Float(try number(style, "fontAlpha")) }
        if style.fields["letterSpacing"] != nil { s.tracking = try number(style, "letterSpacing") * 72 / dpi * 1000 / s.size }
        if style.fields["lineHeight"] != nil { s.leading = try number(style, "lineHeight") * 72 / dpi }
        if try style.optionalBool("autoLeading") == true { s.leading = 0 }
        if let underline = try style.optionalBool("underline") { s.underline = underline }
      }
    }
    let ns = content.text as NSString
    var paragraphs: [NSRange] = [], at = 0
    while at < ns.length { let range = ns.paragraphRange(for: NSRange(location: at, length: 0)); paragraphs.append(range); at = NSMaxRange(range) }
    if ns.length == 0 || content.text.hasSuffix("\n") || content.text.hasSuffix("\r") { paragraphs.append(NSRange(location: ns.length, length: 0)) }
    for raw in try input.fields["paragraphStyles"].map({ _ in try input.array("paragraphStyles", count: 0...4096) }) ?? [] {
      let item = try Object(raw, at: "paragraph style", allowed: ["apply", "paragraphStyle"])
      let style = try item.object("paragraphStyle", allowed: ["alignment", "writingDirection", "firstLineIndent", "startIndent", "endIndent", "spaceBefore", "spaceAfter"])
      let range = try inclusive(item, count: paragraphs.count)
      let first = paragraphs[range.location], last = paragraphs[NSMaxRange(range) - 1]
      try apply(NSRange(location: first.location, length: NSMaxRange(last) - first.location)) { _, p in
        if style.fields["alignment"] != nil {
          let alignment=try style.string("alignment")
          guard let value = ["left": TypeParagraph.Alignment.left,"center":.center,"right":.right,"justify_left":.justified,"justify_center":.justified,"justify_right":.justified,"justify":.justified][alignment] else { throw AdobeAPIError.unsupported("Unknown published paragraph alignment.") };p.alignment=value
          if value == .justified,alignment != "justify_left" || p.formatting != nil {
            var formatting=p.formatting ?? .init();formatting.lastLine=alignment=="justify_center" ? .center:alignment=="justify_right" ? .right:alignment=="justify" ? .justified:.left;p.formatting=formatting
          }
        }
        if style.fields["writingDirection"] != nil {
          guard let value = ["left_to_right": TypeParagraph.Direction.leftToRight, "right_to_left": .rightToLeft][try style.string("writingDirection")] else { throw AdobeAPIError.invalid("Invalid writing direction.") }; p.direction = value
        }
        for (key, path) in [("firstLineIndent", \TypeParagraph.firstIndent), ("startIndent", \.startIndent), ("endIndent", \.endIndent), ("spaceBefore", \.spaceBefore), ("spaceAfter", \.spaceAfter)] where style.fields[key] != nil { p[keyPath: path] = try number(style, key) * 72 / dpi }
      }
    }
    content = try NativeTextLayout.content(attributed, template: content, dpi: dpi)
    let metrics = try NativeTextLayout.metrics(content, dpi: dpi)
    if let origin = frameOrigin {
      layer.x = 0; layer.y = 0; layer.affine = .translation(origin.x - (content.typography?.kind == .point && content.typography?.writingOrientation == .vertical ? Double(metrics.width)-metrics.firstBaseline:0), origin.y - (content.typography?.kind == .point && content.typography?.writingOrientation != .vertical ? metrics.firstBaseline : 0))
    }
    layer.content = .text(content)
    if let visible = try root.optionalBool("isVisible") { layer.visible = visible }
    if let clipped = try root.optionalBool("isClipped") { layer.clipped = clipped }
    if adding { try session.execute(.addLayer(layer)) }
    else {
      try session.execute(ShapedTextLayout.replacement(session.document.layers.first{$0.id==layer.id}!,content:content,document:session.document))
      if let original = session.document.layers.first(where: { $0.id == layer.id }), frameOrigin != nil {
        try session.execute(.transform(layer.id, layer.coordinateTransform * original.coordinateTransform.inverted(), .bicubic))
      }
      try session.execute(.visibility(layer.id, layer.visible))
      if let original = session.document.layers.first(where: { $0.id == layer.id }), original.clipped != layer.clipped { try session.execute(.clipping(layer.id, layer.isClipped)) }
    }
  }
}
struct AdobeTypeFontOptions: Sendable {
  var defaultFont = "HelveticaNeue"
  var useDefault = false
  init(_ raw: Any? = nil) throws {
    guard let raw else { return }
    let object = try AdobeActionsRequest.Object(raw, at: "fontOptions", allowed: ["defaultFontPostScriptName", "missingFontStrategy"])
    if object.fields["defaultFontPostScriptName"] != nil { defaultFont = try object.string("defaultFontPostScriptName") }
    if object.fields["missingFontStrategy"] != nil {
      let strategy = try object.string("missingFontStrategy")
      guard ["fail", "use_default"].contains(strategy) else { throw AdobeAPIError.invalid("Invalid missing font strategy.") }; useDefault = strategy == "use_default"
    }
  }
}
