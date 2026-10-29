import Foundation
import PhotoCraftCore

extension AutomationCommand {
  func modeComponents(in document: CraftDocument, allowEmpty: Bool = false) throws -> Set<Int> {
    guard case .array(let values) = parameters["components"], values.count <= document.colorMode.componentCount,
      allowEmpty || !values.isEmpty else { throw AutomationFailure(status: 400, message: "Choose valid component indices.") }
    var result = Set<Int>()
    for value in values {
      guard case .number(let n) = value, n.isFinite, n.rounded() == n,
        (0..<Double(document.colorMode.componentCount)).contains(n), result.insert(Int(n)).inserted else {
        throw AutomationFailure(status: 400, message: "Component indices must be unique and valid for this color mode.")
      }
    }
    return result
  }
  func modeComponentEdit(in document: CraftDocument) throws -> Command {
    let action = try string("action"), id = try actionUUID("layerID")
    let components = try modeComponents(in: document)
    let fields: Set<String>
    let operation: ModeComponentEdit.Operation
    switch action {
    case "fill":
      fields = ["value", "opacity"]
      operation = try .fill(Float(number("value", range: 0...1)), parameters["opacity"] == nil ? 1 : Float(number("opacity", range: 0...1)))
    case "invert": fields = []; operation = .invert
    case "stroke":
      fields = ["points", "brush"]
      let brush = try BrushAPI.decode(parameters["brush"], base: Brush())
      guard let raw = parameters["points"] else { throw AutomationFailure(status: 400, message: "Stroke points required.") }
      let values = try BrushAPI.merge(raw, schema: BrushAPI.schema("points")) as! [[String: Any]]
      let points = try values.map { raw in
        var raw = raw; if raw["pressure"] == nil { raw["pressure"] = 1 }
        return try JSONDecoder().decode(StrokePoint.self, from: JSONSerialization.data(withJSONObject: raw))
      }
      try BrushPainter.validate(brush, points: points)
      operation = .stroke(points, brush)
    case "filter":
      fields = ["filter"]
      guard let raw = parameters["filter"] else { throw AutomationFailure(status: 400, message: "Filter required.") }
      let filter = try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject: raw.jsonValue))
      guard ModeComponentEdit.filters.contains(filter.kind) else { throw AutomationFailure(status: 422, message: "Unsupported component filter.") }
      operation = .filter(filter)
    default: throw AutomationFailure(status: 400, message: "Unknown component operation.")
    }
    guard Set(parameters.keys).isSubset(of: fields.union(["action", "layerID", "components"])) else {
      throw AutomationFailure(status: 400, message: "Irrelevant component operation parameters.")
    }
    return .modeComponents(.init(layerID: id, components: components, operation: operation))
  }
}
