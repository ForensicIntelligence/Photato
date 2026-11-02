import Foundation
import PhotoCraftCore

extension SmartFilterStack {
  var apiState: [String: Any] {
    ["enabled": enabled, "filters": filters.map { item -> [String: Any] in
      let parameters = item.filter.apiState
      return ["id": item.id.uuidString, "filter": parameters, "enabled": item.enabled,
        "opacity": item.opacity, "blendMode": item.blendMode.rawValue]
    }, "hasMask": mask != nil, "mask": ["enabled": maskProperties.enabled, "linked": maskProperties.linked,
      "density": maskProperties.density, "feather": maskProperties.feather],
      "maskTransform": ["a": maskProperties.transform.a, "b": maskProperties.transform.b,
        "c": maskProperties.transform.c, "d": maskProperties.transform.d,
        "tx": maskProperties.transform.tx, "ty": maskProperties.transform.ty]]
  }
  static var apiSchema: [String: Any] {
    ["anyOf": [["type": "null"], ["type": "object", "additionalProperties": false,
      "required": ["filters", "enabled"], "properties": [
        "enabled": ["type": "boolean"], "filters": ["type": "array", "maxItems": maximumFilters,
          "items": ["type": "object", "additionalProperties": false, "required": ["id", "filter", "enabled", "opacity", "blendMode"],
            "properties": ["id": ["type": "string", "format": "uuid"], "filter": RasterFilter.apiSchema,
              "enabled": ["type": "boolean"], "opacity": ["type": "number", "minimum": 0, "maximum": 1],
              "blendMode": ["type": "string", "enum": BlendMode.allCases.map(\.rawValue)]]]],
        "mask": ["type": "object", "additionalProperties": false, "properties": [
          "operation": ["type": "string", "enum": ["keep", "reveal", "hide", "selection", "delete"]],
          "enabled": ["type": "boolean"], "linked": ["type": "boolean"],
          "density": ["type": "number", "minimum": 0, "maximum": 1],
          "feather": ["type": "number", "minimum": 0, "maximum": 100]]]]]]]
  }
  static var apiStateSchema: [String: Any] {
    let alternatives = apiSchema["anyOf"] as! [[String: Any]]
    let input = alternatives[1]["properties"] as! [String: Any]
    return ["anyOf": [["type": "null"], ["type": "object", "required": ["enabled", "filters", "hasMask", "mask", "maskTransform"],
      "properties": ["enabled": ["type": "boolean"], "filters": input["filters"]!, "mask": input["mask"]!,
        "hasMask": ["type": "boolean"], "maskTransform": ["type": "object", "required": ["a", "b", "c", "d", "tx", "ty"],
          "properties": Dictionary(uniqueKeysWithValues: ["a", "b", "c", "d", "tx", "ty"].map { ($0, ["type": "number"]) })]]]]]
  }
  static var apiCapabilities: [String: Any] {
    ["commands": ["filter.apply", "smartFilter.set", "smartFilter.maskStroke", "smartFilter.maskFill"],
      "stackSchema": apiSchema, "layerStateSchema": apiStateSchema, "maximumFilters": maximumFilters,
      "largeRGBStacks":["kinds":RasterFilterEngine.pagedFilterKinds.map(\.rawValue),
        "maximumDimension":Surface.maxDimension,"logicalMaximumPixels":Surface.maxPixels,
        "maximumOutputPatchPixels":RasterGeometry.maximumPatchPixels,
        "behavior":"Affine placement, ordered editable filters, per-filter blend/opacity/visibility, selection and pixel masks share the native engine. Source bytes and original samples remain unchanged.",
        "limits":"Other filter families, non-RGB, Warp and large feather kernels retain separate limits. Embedded source64MiB and owned-content256MiB remain independent; dense capacity, RSS, throughput and Photoshop/platform parity remain open."],
      "order": "filters is application order, bottom first. set replaces the list, permitting edit, reorder, remove and per-filter enable/blend/opacity. null clears the stack.",
      "masks": "First filter creates a white mask, or uses current selection. Mask painting uses document coordinates and respects selection. Read layers[].smartFilters for state; set accepts enabled, filters and mask settings only.",
      "persistence": "Native15 archives retain editable stacks. Supported PSD filters use filterFX/FEid. Raster exports render the result.",
      "limitations": "See filters.kinds for the current native catalogue; Photoshop pixel equality and independent Smart Filter interchange remain unqualified. Average has no qualified PSD descriptor and rejects layered export. Unsupported mask tools reject."]
  }
}

extension AutomationCommand {
  func smartFilterCommand(document: CraftDocument) throws -> Command {
    guard let id = UUID(uuidString: try string("layerID")), let layer = document.layers.first(where: { $0.id == id }) else {
      throw AutomationFailure(status: 404, message: "Layer not found.")
    }
    guard layer.smartObject != nil else { throw AutomationFailure(status: 422, message: "Smart Filters require a Smart Object.") }
    func fail(_ text: String) -> AutomationFailure { .init(status: 400, message: text) }
    func number(_ fields: [String: Any], _ key: String, _ range: ClosedRange<Double>) throws -> Double {
      guard let n = fields[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
        range.contains(n.doubleValue) else { throw fail("Invalid \(key).") }
      return n.doubleValue
    }
    func flag(_ fields: [String: Any], _ key: String) throws -> Bool {
      guard let n = fields[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw fail("Invalid \(key).") }
      return n.boolValue
    }
    if name == "smartFilter.maskFill" {
      return .smartFilterMask(id, .maskFill(id, Float(try self.number("value", range: 0...1))))
    }
    if name == "smartFilter.maskStroke" {
      guard case .array(let values) = parameters["points"], (1...4096).contains(values.count) else { throw fail("Provide one to4096 stroke points.") }
      let points = try values.map { value -> StrokePoint in
        guard let point = value.jsonValue as? [String: Any], Set(point.keys).isSubset(of: ["x", "y", "pressure"]) else { throw fail("Invalid stroke point.") }
        return try StrokePoint(x: number(point, "x", -1_000_000...1_000_000), y: number(point, "y", -1_000_000...1_000_000),
          pressure: point["pressure"] == nil ? 1 : Float(number(point, "pressure", 0...1)))
      }
      var brush = Brush()
      brush.size = try self.number("size", range: 0.5...2048)
      brush.hardness = Float(try self.number("hardness", range: 0...1))
      brush.opacity = Float(try self.number("opacity", range: 0...1))
      let v = Float(try self.number("value", range: 0...1)); brush.color = Pixel(v, v, v, 1)
      return .smartFilterMask(id, .maskStroke(id, points, brush))
    }
    guard let input = parameters["stack"] else { throw fail("Missing stack.") }
    if case .null = input { return .smartFilters(id, nil) }
    guard let fields = input.jsonValue as? [String: Any], Set(fields.keys).isSubset(of: ["filters", "enabled", "mask"]),
      let filters = fields["filters"] as? [[String: Any]], filters.count <= SmartFilterStack.maximumFilters else { throw fail("Invalid filter stack.") }
    var stack = layer.smartFilters ?? SmartFilterStack()
    stack.enabled = try flag(fields, "enabled")
    stack.filters = try filters.map { fields in
      guard Set(fields.keys) == ["id", "filter", "enabled", "opacity", "blendMode"],
        let text = fields["id"] as? String, let uuid = UUID(uuidString: text),
        let filter = fields["filter"] as? [String: Any], let mode = fields["blendMode"] as? String,
        let blend = BlendMode(rawValue: mode) else { throw fail("Invalid Smart Filter.") }
      return try SmartFilter(id: uuid, filter: RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject: filter)),
        enabled: flag(fields, "enabled"), opacity: Float(number(fields, "opacity", 0...1)), blendMode: blend)
    }
    if layer.smartFilters == nil && !stack.filters.isEmpty { try stack.createMask(in: document, selection: document.selection != nil) }
    if let inputMask = fields["mask"] {
      guard let mask = inputMask as? [String: Any], Set(mask.keys).isSubset(of: ["operation", "enabled", "linked", "density", "feather"]) else { throw fail("Invalid filter mask.") }
      let operation = mask["operation"] as? String ?? "keep"
      if mask["operation"] != nil && !(mask["operation"] is String) { throw fail("Invalid mask operation.") }
      switch operation {
      case "keep": break
      case "delete": stack.mask = nil
      case "reveal", "hide", "selection": try stack.createMask(in: document, selection: operation == "selection", value: operation == "hide" ? 0 : 1)
      default: throw fail("Unknown mask operation.")
      }
      if mask["enabled"] != nil { stack.maskProperties.enabled = try flag(mask, "enabled") }
      if mask["linked"] != nil { stack.maskProperties.linked = try flag(mask, "linked") }
      if mask["density"] != nil { stack.maskProperties.density = Float(try number(mask, "density", 0...1)) }
      if mask["feather"] != nil { stack.maskProperties.feather = try number(mask, "feather", 0...100) }
    }
    do { try stack.validate() } catch { throw fail(error.localizedDescription) }
    // Imported originals may retain an empty stack and its enable/mask state.
    // Resubmitting that exact state must not discard the original appearance.
    if stack == layer.smartFilters {return .smartFilters(id,stack)}
    return .smartFilters(id, stack.filters.isEmpty ? nil : stack)
  }
}
