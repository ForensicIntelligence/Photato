import Foundation
import PhotoCraftCore

enum InkChannelAPI {
  static let commands = ["ink.channel.read", "ink.channel.write", "ink.channel.edit", "ink.channel.manage", "ink.channel.select", "ink.channel.visibility"]
  static let edits = ["ink.channel.write", "ink.channel.edit", "ink.channel.manage"]
  static var target: [String: Any] { ["type": "string", "minLength": 7, "maxLength": 36, "description": "duotone or a Multichannel plate UUID"] }
  static var targets: [String: Any] { ["type": "array", "minItems": 0, "maxItems": 56, "uniqueItems": true, "items": target] }
  static func schema(_ key: String, command: String) -> [String: Any] {
    switch key {
    case "target": return target
    case "targets": var value = targets; if command != "ink.channel.select" { value["minItems"] = 1 }; return value
    case "action": return BrushAPI.enumeration(command == "ink.channel.manage" ? ["create", "delete", "duplicate", "move", "options"] : ["fill", "stroke", "invert", "filter", "selection"])
    case "offset": return BrushAPI.number(0, Double(InkPlane.maximumPixels - 1), integer: true)
    case "count": return BrushAPI.number(1, 4096, integer: true)
    case "index": return BrushAPI.number(0, 55, integer: true)
    case "values": return ["type": "array", "minItems": 1, "maxItems": 4096, "items": BrushAPI.number()]
    case "value", "opacity", "solidity", "density": return BrushAPI.number()
    case "plateID", "newID": return InkModeAPI.identity
    case "name": return ["type": "string", "minLength": 1, "maxLength": 1024]
    case "color": return BrushAPI.color
    case "brush": return BrushAPI.brush
    case "points": return BrushAPI.schema("points")
    case "filter": return RasterFilter.apiSchema
    case "mode": return BrushAPI.enumeration(SelectionMode.allCases.map(\.rawValue))
    case "invert": return BrushAPI.flag
    default: return [:]
    }
  }
  static var capabilities: [String: Any] { [
    "commands": commands, "targets": target,
    "storage": ["sampleBlockSize": ComponentPlane.blockSamples, "copyOnWriteLevels": 4, "rawSampleBits": true, "implicitUniformFill": true, "maximumPixels": InkPlane.maximumPixels, "limits": "Ink editing, rendering, native encoding and PSD/PSB routes retain the existing8,388,608pixel limit. The internal paged numeric-plane foundation does not lift application document limits."],
    "readResultSchema": BrushAPI.object([
      "target": target, "offset": schema("offset", command: ""), "values": schema("values", command: ""),
      "width": BrushAPI.number(1, Double(InkPlane.maximumPixels), integer: true), "height": BrushAPI.number(1, Double(InkPlane.maximumPixels), integer: true),
      "depth": ["type": "integer", "enum": [8, 16]], "revision": ["type": "string"]], required: ["target", "offset", "values", "width", "height", "depth", "revision"]),
    "samples": "Read/write use retained normalized gray for Duotone and density for Multichannel (zero means no ink). At most4096 samples per page. Writes ignore selection and replace the requested numeric range. Fill/stroke/filter/invert use channel-view gray (zero is black/full ink), respect selection and preserve unedited plane bytes. Selection loading accepts exactly one target.",
    "targeting": "Explicit editing targets are independent of desktop selection. Empty select means all ink channels; visibility requires at least one. View changes do not add history. One visible Multichannel plate displays gray; multiple plates display their retained ink colors. No RGB layer is synthesized.",
    "management": "Create/delete/duplicate/move/options require Multichannel. Keep at least one plate and at most56 total ink/alpha channels. Create defaults to zero density, black and zero solidity. Optional newID makes create/duplicate identities deterministic. Options require name/color/solidity. Solidity affects preview only.",
    "filters": InkChannelCommand.filters.map(\.rawValue).sorted(),
    "limits": "Desktop supports Brush/Eraser and the listed channel filters. Other Multichannel paint tools, complete semantic ink-channel Actions, full Adobe ink descriptors, separation printing, Duotone PSD and ink TIFF interchange remain open. Multichannel PSD/PSB preserves ink and alpha planes through the shared file routes. No Adobe endpoint is invented. Busy/stale/revoked requests cannot commit."] }
}

extension AutomationCommand {
  func inkTarget(_ text: String, in document: CraftDocument) throws -> InkChannelTarget {
    let target: InkChannelTarget
    if text == "duotone" { target = .duotone }
    else if let id = UUID(uuidString: text) { target = .plate(id) }
    else { throw AutomationFailure(status: 400, message: "Use duotone or an ink plate UUID.") }
    guard document.inkChannelTargets.contains(target) else { throw AutomationFailure(status: 422, message: "Ink channel does not exist in this document.") }
    return target
  }
  func inkTargets(in document: CraftDocument, allowEmpty: Bool = false) throws -> [InkChannelTarget] {
    guard document.inkMode != nil else { throw AutomationFailure(status: 422, message: "Ink channels require Duotone or Multichannel.") }
    guard case .array(let values) = parameters["targets"], values.count <= 56, allowEmpty || !values.isEmpty else { throw AutomationFailure(status: 400, message: "Choose valid ink targets.") }
    let targets = try values.map { value -> InkChannelTarget in
      guard case .string(let value) = value else { throw AutomationFailure(status: 400, message: "Ink targets must be strings.") }
      return try inkTarget(value, in: document)
    }
    guard Set(targets).count == targets.count else { throw AutomationFailure(status: 400, message: "Ink targets must be unique.") }
    return document.inkChannelTargets.filter { targets.contains($0) }
  }
  func inkChannelPage(in document: CraftDocument) throws -> (InkChannelTarget, InkPlane, Int) {
    let target = try inkTarget(string("target"), in: document), plane = try document.inkChannel(target)
    let offset = try parameters["offset"].map { _ in try integer("offset", range: 0...Double(plane.count - 1)) } ?? 0
    return (target, plane, offset)
  }
  func inkChannelNameParameter() throws -> String {
    guard case .string(let value) = parameters["name"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 1024 else { throw AutomationFailure(status: 400, message: "Ink name must contain at most1024 UTF-8 bytes.") }
    return value
  }
  func inkChannelCommand(in document: CraftDocument) throws -> Command {
    if name == "ink.channel.write" {
      let (target, plane, offset) = try inkChannelPage(in: document)
      guard let raw = parameters["values"], let values = try BrushAPI.merge(raw, schema: InkChannelAPI.schema("values", command: name)) as? [Double], values.count <= plane.count - offset else { throw AutomationFailure(status: 400, message: "Ink sample write exceeds the channel.") }
      return .inkChannel(.write(target, offset, values.map(Float.init)))
    }
    let action = try string("action"), fields: Set<String>, command: InkChannelCommand
    if name == "ink.channel.manage" {
      guard document.colorMode == .multichannel else { throw AutomationFailure(status: 422, message: "Plate management requires Multichannel mode.") }
      switch action {
      case "create", "options":
        fields = action == "create" ? ["newID", "name", "color", "solidity", "density"] : ["plateID", "name", "color", "solidity"]
        let name = try inkChannelNameParameter()
        let color: Pixel
        if let raw = parameters["color"] {
          color = try JSONDecoder().decode(Pixel.self, from: JSONSerialization.data(withJSONObject: BrushAPI.merge(raw, schema: BrushAPI.color)))
        } else if action == "create" { color = .black }
        else { throw AutomationFailure(status: 400, message: "Channel options require color.") }
        let solidity = try parameters["solidity"].map { _ in Float(try number("solidity", range: 0...1)) } ?? (action == "create" ? 0 : -1)
        guard solidity >= 0 else { throw AutomationFailure(status: 400, message: "Channel options require solidity.") }
        if action == "create" {
          let id = try parameters["newID"].map { _ in try actionUUID("newID") } ?? UUID()
          let density = try parameters["density"].map { _ in Float(try number("density", range: 0...1)) } ?? 0
          command = .create(.init(id: id, name: name, color: color, solidity: solidity, samples: try InkPlane(width: document.width, height: document.height, depth: document.depth, value: density)))
        } else { command = try .options(actionUUID("plateID"), name, color, solidity) }
      case "delete": fields = ["plateID"]; command = try .delete(actionUUID("plateID"))
      case "duplicate": fields = ["plateID", "newID", "name"]; command = try .duplicate(actionUUID("plateID"), parameters["newID"].map { _ in try actionUUID("newID") } ?? UUID(), parameters["name"].map { _ in try inkChannelNameParameter() })
      case "move": fields = ["plateID", "index"]; command = try .move(actionUUID("plateID"), integer("index", range: 0...Double(document.inkChannelTargets.count - 1)))
      default: throw AutomationFailure(status: 400, message: "Unknown ink management operation.")
      }
    } else {
      let targets = try inkTargets(in: document)
      switch action {
      case "fill": fields = ["targets", "value", "opacity"]; command = try .edit(targets, .fill(Float(number("value", range: 0...1)), parameters["opacity"].map { _ in Float(try number("opacity", range: 0...1)) } ?? 1))
      case "invert": fields = ["targets"]; command = .edit(targets, .invert)
      case "stroke":
        fields = ["targets", "points", "brush"]
        let brush = try BrushAPI.decode(parameters["brush"], base: Brush())
        guard let raw = parameters["points"] else { throw AutomationFailure(status: 400, message: "Stroke points required.") }
        let values = try BrushAPI.merge(raw, schema: BrushAPI.schema("points")) as! [[String: Any]]
        let points = try values.map { value in
          var value = value; if value["pressure"] == nil { value["pressure"] = 1 }
          return try JSONDecoder().decode(StrokePoint.self, from: JSONSerialization.data(withJSONObject: value))
        }
        try BrushPainter.validate(brush, points: points); command = .edit(targets, .stroke(points, brush))
      case "filter":
        fields = ["targets", "filter"]
        guard let raw = parameters["filter"] else { throw AutomationFailure(status: 400, message: "Filter required.") }
        let filter = try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject: raw.jsonValue))
        guard InkChannelCommand.filters.contains(filter.kind) else { throw AutomationFailure(status: 422, message: "Unsupported ink channel filter.") }
        command = .edit(targets, .filter(filter))
      case "selection":
        fields = ["targets", "mode", "invert"]
        guard targets.count == 1, let mode = SelectionMode(rawValue: try parameters["mode"].map { _ in try string("mode") } ?? SelectionMode.replace.rawValue) else { throw AutomationFailure(status: 400, message: "Selection loading requires one ink channel and a valid mode.") }
        command = try .loadSelection(targets[0], mode, pathFlag("invert", false))
      default: throw AutomationFailure(status: 400, message: "Unknown ink edit operation.")
      }
    }
    guard Set(parameters.keys).isSubset(of: fields.union(["action"])) else { throw AutomationFailure(status: 400, message: "Irrelevant ink operation parameters.") }
    return .inkChannel(command)
  }
}
