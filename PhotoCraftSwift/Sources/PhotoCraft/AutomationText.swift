import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension TextContent {
  var apiType: [String: Any] {
    let type = typography ?? TextTypography()
    func object<T: Encodable>(_ value: T) -> Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? NSNull() }
    return ["text": text, "kind": type.kind.rawValue, "width": layoutWidth as Any? ?? NSNull(),
      "height": layoutHeight as Any? ?? NSNull(), "style": object(type.defaultStyle), "paragraph": object(type.defaultParagraph),
      "sourceFrame":type.sourceFrame.map{object($0)} ?? NSNull(),"antialiasMode":type.antialiasMode?.rawValue as Any? ?? NSNull(),"runs": object(type.runs), "antialias": type.antialias,"orientation":type.writingOrientation.rawValue,"geometry":type.geometry.map{BrushAPI.json($0)} ?? NSNull()]
  }
  static var apiTypeSchema: [String: Any] {
    func number(_ min: Double, _ max: Double) -> [String: Any] { ["type": "number", "minimum": min, "maximum": max] }
    let style: [String: Any] = ["type": "object", "additionalProperties": false, "properties": [
      "font": ["type": "string", "minLength": 1, "maxLength": 256], "size": number(0.1, 4096),
      "color": ["type": "object", "additionalProperties": false, "required": ["r", "g", "b", "a"],
        "properties": Dictionary(uniqueKeysWithValues: ["r", "g", "b", "a"].map { ($0, number(0, 1)) })],
      "tracking": number(-1000, 10000), "baseline": number(-4096, 4096), "leading": number(0, 16384),
      "horizontalScale": number(0.01, 10), "verticalScale": number(0.01, 10),
      "characterFormatting":RichTypeAPI.character,"fontOptions":FontAPI.options,"glyphOverride":FontAPI.glyphOverride,"underline": ["type": "boolean"], "strikethrough": ["type": "boolean"]]]
    let para: [String: Any] = ["type": "object", "additionalProperties": false, "properties": [
      "alignment": ["type": "string", "enum": TypeParagraph.Alignment.allCases.map(\.rawValue)],
      "direction": ["type": "string", "enum": TypeParagraph.Direction.allCases.map(\.rawValue)],
      "firstIndent": number(-16384, 16384), "startIndent": number(-16384, 16384), "endIndent": number(-16384, 16384),
      "formatting":RichTypeAPI.paragraph,"spaceBefore": number(0, 16384), "spaceAfter": number(0, 16384), "hyphenation": ["type": "boolean"]]]
    let dimension: [String: Any] = ["anyOf": [["type": "null"], ["type": "integer", "minimum": 1, "maximum": 32768]]]
    return ["type": "object", "additionalProperties": false, "required": ["text"], "properties": [
      "text": ["type": "string", "maxLength": 100_000], "kind": ["type": "string", "enum": ["point", "paragraph"]],
      "sourceFrame":RichTypeAPI.frame,"antialiasMode":RichTypeAPI.antialias,"geometry":["anyOf":[["type":"null"],TextLayoutAPI.settings]],"orientation":BrushAPI.enumeration(TextTypography.Orientation.allCases.map(\.rawValue)),"width": dimension, "height": dimension, "style": style, "paragraph": para, "antialias": ["type": "boolean"],
      "runs": ["type": "array", "maxItems": 4096, "items": ["type": "object", "additionalProperties": false,
        "required": ["length", "style"], "properties": ["length": ["type": "integer", "minimum": 1, "maximum": 100_000], "style": style, "paragraph": para]]]]]
  }
  static func decodeAPIType(_ raw: Any) throws -> TextContent {
    func fail(_ message: String) -> AutomationFailure { .init(status: 400, message: message) }
    guard let object = raw as? [String: Any], Set(object.keys).isSubset(of: ["text", "kind", "width", "height", "style", "paragraph", "runs", "antialias", "orientation", "geometry", "sourceFrame", "antialiasMode"]),
      let string = object["text"] as? String else { throw fail("Invalid text description.") }
    func merged<T: Codable>(_ raw: Any?, fallback: T) throws -> T {
      guard let raw else { return fallback }
      guard var values = raw as? [String: Any], var defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fallback)) as? [String: Any], Set(values.keys).isSubset(of: Set(defaults.keys).union(T.self == TypeStyle.self ? ["fontOptions","glyphOverride","characterFormatting"]:T.self == TypeParagraph.self ? ["formatting"]:[])) else { throw fail("Unknown type formatting field.") }
      if let rawColor = values["color"] {
        guard let color = rawColor as? [String: Any], Set(color.keys) == ["r", "g", "b", "a"], color.values.allSatisfy({ value in guard let n = value as? NSNumber else { return false }; return CFGetTypeID(n) != CFBooleanGetTypeID() && n.doubleValue.isFinite }) else { throw fail("Invalid type color.") }
      }
      for key in ["fontOptions","glyphOverride"] {if let value=values[key]{let input=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:value));values[key] = try BrushAPI.merge(input,schema:key=="fontOptions" ? FontAPI.options:FontAPI.glyphOverride,base:key=="fontOptions" ? BrushAPI.json(TypeFontOptions()):nil)}}
      for (key,schema,base) in [("characterFormatting",RichTypeAPI.character,BrushAPI.json(TypeCharacterFormatting())),("formatting",RichTypeAPI.paragraph,BrushAPI.json(TypeParagraphFormatting()))] {
        if let value=values[key]{let input=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:value));values[key]=try BrushAPI.merge(input,schema:schema,base:base)}
      }
      for (key, value) in values {
        if let expected = defaults[key] as? NSNumber, let actual = value as? NSNumber,
          (CFGetTypeID(expected) == CFBooleanGetTypeID()) != (CFGetTypeID(actual) == CFBooleanGetTypeID()) { throw fail("Invalid \(key) type.") }
        defaults[key] = value
      }
      return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: defaults))
    }
    do {
      var content = TextContent(text: string), type = TextTypography()
      if let geometry=object["geometry"],!(geometry is NSNull){type.geometry=try TextLayoutAPI.decode(JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:geometry)))}
      if let frame=object["sourceFrame"],!(frame is NSNull){let input=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:frame));let checked=try BrushAPI.merge(input,schema:RichTypeAPI.frame);type.sourceFrame=try JSONDecoder().decode(TypeSourceFrame.self,from:JSONSerialization.data(withJSONObject:checked))}
      if let mode=object["antialiasMode"],!(mode is NSNull){guard let value=mode as?String,let parsed=TypeAntialias(rawValue:value)else{throw fail("Invalid type antialias mode.")};type.antialiasMode=parsed}
      type.defaultStyle = try merged(object["style"], fallback: TypeStyle())
      type.defaultParagraph = try merged(object["paragraph"], fallback: TypeParagraph())
      if let raw=object["orientation"]{guard let name=raw as? String,let orientation=TextTypography.Orientation(rawValue:name) else{throw fail("Invalid text orientation.")};type.orientation=orientation == .horizontal ? nil:orientation}
      if let raw = object["kind"] {
        guard let string = raw as? String, let kind = TextTypography.Kind(rawValue: string) else { throw fail("Invalid type kind.") }; type.kind = kind
      }
      for key in ["width", "height"] {
        if let raw = object[key], !(raw is NSNull) {
          guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue, (1...32768).contains(n.intValue) else { throw fail("Invalid type frame dimension.") }
          if key == "width" { content.layoutWidth = n.intValue } else { content.layoutHeight = n.intValue }
        }
      }
      if let raw = object["antialias"] {
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw fail("Invalid antialias value.") }; type.antialias = n.boolValue
      }
      if let raw = object["runs"] {
        guard let runs = raw as? [[String: Any]], runs.count <= 4096 else { throw fail("Invalid type runs.") }
        type.runs = try runs.map { run in
          guard Set(run.keys).isSubset(of: ["length", "style", "paragraph"]), run["style"] != nil,
            let n = run["length"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
            n.doubleValue.rounded() == n.doubleValue, (1...100_000).contains(n.intValue) else { throw fail("Invalid type run.") }
          return TypeRun(length: n.intValue, style: try merged(run["style"], fallback: type.defaultStyle), paragraph: try merged(run["paragraph"], fallback: type.defaultParagraph))
        }
      }
      content.typography = type; content.fontName = type.defaultStyle.font; content.size = type.defaultStyle.size; content.color = type.defaultStyle.color
      try content.validate(); return content
    } catch let error as AutomationFailure { throw error }
    catch { throw fail("Invalid text formatting: \(error.localizedDescription)") }
  }
  static var apiTypeCapabilities: [String: Any] {
    ["commands": ["text.create", "text.set"], "schema": apiTypeSchema,
      "layerSourceSchema":["anyOf":[RichTypeAPI.sourceState,["type":"null"]]],"extendedTypeVersion":69,"extendedTypeActionVersion":25,
      "units": "Font size, leading, baseline and paragraph distances are points at document resolution. Frame dimensions and positions are pixels. Tracking is thousandths of an em. Run lengths count UTF-16 code units and must cover the string without splitting Unicode scalars.",
      "persistence": "Native69/Actions25 retain extended formatting/source appearance and semantic type edits. Native35 retains shaped text; Native34 retains advanced typography; Native16 retains legacy rich text. text.set replaces the complete type description; omitted formatting uses the documented defaults.",
      "fonts":FontAPI.capabilities,"layout":TextLayoutAPI.capabilities,"limitations": "Uses installed fonts, native vertical TextKit shaping, OpenType and variation descriptors. Imported missing faces retain identity and source cache, and use a native editing fallback when no unsupported variation axis is requested. Named style libraries and complete live caps/optical/caret behavior remain open. Adobe glyph/pixel/composer equality, path and warped text remain unqualified."]
  }
}
extension AutomationCommand {
  func textCommand(document: CraftDocument) throws -> Command {
    guard let raw = parameters["text"] else { throw AutomationFailure(status: 400, message: "Missing text.") }
    let content = try TextContent.decodeAPIType(raw.jsonValue)
    if name == "text.set" {
      guard let id = UUID(uuidString: try string("layerID")), let layer = document.layers.first(where: { $0.id == id }) else { throw AutomationFailure(status: 404, message: "Layer not found.") }
      guard case .text = layer.content else { throw AutomationFailure(status: 422, message: "The target is not a type layer.") }
      return try ShapedTextLayout.replacement(layer,content:content,document:document)
    }
    _ = try NativeTextLayout.metrics(content,dpi:document.pixelsPerInch)
    var layer = Layer(name: parameters["name"] == nil ? String(content.text.prefix(32)) : try string("name"), content: .text(content))
    if layer.name.isEmpty { layer.name = "Type" }
    layer.x = try integer("x", range: -1_000_000...1_000_000); layer.y = try integer("y", range: -1_000_000...1_000_000)
    let origin=try NativeTextLayout.metrics(content,dpi:document.pixelsPerInch).origin
    if origin.x != 0 || origin.y != 0{layer.affine=layer.coordinateTransform * .translation(origin.x,origin.y);layer.x=0;layer.y=0}
    return .addLayer(layer)
  }
}
