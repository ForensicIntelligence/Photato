import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum AutomationValue: Decodable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: Self])
  case null
  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let b = try? value.decode(Bool.self) {
      self = .bool(b)
    } else if let s = try? value.decode(String.self) {
      self = .string(s)
    } else if let n = try? value.decode(Double.self) {
      self = .number(n)
    } else {
      self = .object(try value.decode([String: Self].self))
    }
  }
}

struct AutomationCommand {
  struct Definition {
    let name: String
    let parameters: [String: String]
    let description: String
    var schema: [String: Any] {
      var properties: [String: Any] = [:]
      for key in parameters.keys {
        switch key {
        case "layerID": properties[key] = ["type": "string", "format": "uuid"]
        case "name": properties[key] = ["type": "string", "minLength": 1, "maxLength": 256]
        case "visible", "replace": properties[key] = ["type": "boolean"]
        case "format":
          properties[key] = ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)]
        case "channel":
          properties[key] = ["type": "string", "enum": RGBChannelPreview.allCases.map(\.title)]
        case "x", "y":
          properties[key] = [
            "type": "integer", "minimum": name == "layer.move" ? -1_000_000 : 0,
            "maximum": 1_000_000,
          ]
        case "width", "height":
          properties[key] = ["type": "integer", "minimum": 1, "maximum": 1_000_000]
        default: properties[key] = ["type": "number", "minimum": 0, "maximum": 1]
        }
      }
      return [
        "type": "object", "additionalProperties": false,
        "required": ["command", "revision", "parameters"],
        "properties": [
          "command": ["const": name], "revision": ["type": "string", "minLength": 1],
          "parameters": [
            "type": "object", "additionalProperties": false, "properties": properties,
            "required": parameters.keys.sorted(),
          ],
        ],
      ]
    }
  }
  static let definitions: [Definition] = [
    .init(
      name: "document.save", parameters: [:],
      description:
        "Save the shared document to its associated file through the native save path. Requires separate local-saving permission; no path is accepted."
    ),
    .init(
      name: "document.saveAs",
      parameters: [
        "name": "filename, no path components", "format": "photato, psd, png, jpeg or tiff",
        "replace": "boolean",
      ],
      description:
        "Save to a filename inside the native-approved Save As folder, adopting that file association. Requires separate local-saving permission and a selected folder."
    ),
    .init(
      name: "document.revert", parameters: [:],
      description:
        "Reload this shared document's associated file as one undoable edit. Requires native document-transfer enablement; no file path is accepted. A successful Revert clears the modified flag."
    ),
    .init(
      name: "channel.target", parameters: ["channel": "RGB, Red, Green or Blue"],
      description:
        "Select the native editing target and its preview. Component editing requires RGB8. Target selection does not change document history."
    ),
    .init(
      name: "channel.fill", parameters: ["value": "number, 0–1", "opacity": "number, 0–1"],
      description:
        "Normal neutral Fill of the active RGB8 component on the active pixel layer. Preserves other components and alpha, respects selection and shares desktop undo."
    ),
    .init(
      name: "view.channelPreview", parameters: ["channel": "RGB, Red, Green or Blue"],
      description:
        "Choose a channel preview. This changes view state, not the channel editing target or document history."
    ),
    .init(
      name: "view.channelVisibility",
      parameters: ["channel": "RGB, Red, Green or Blue", "visible": "boolean"],
      description:
        "Show or hide color components without changing the preview selection. Hiding the last visible component is a no-op. Mask views must be exited first."
    ),
    .init(
      name: "layer.rename", parameters: ["layerID": "uuid", "name": "string, 1–256 characters"],
      description: "Rename one layer."),
    .init(
      name: "layer.opacity", parameters: ["layerID": "uuid", "opacity": "number, 0–1"],
      description: "Set one layer's opacity."),
    .init(
      name: "layer.visibility", parameters: ["layerID": "uuid", "visible": "boolean"],
      description: "Set one layer's visibility."),
    .init(
      name: "layer.move",
      parameters: ["layerID": "uuid", "x": "integer, ±1000000", "y": "integer, ±1000000"],
      description: "Set absolute layer position in document pixels."),
    .init(
      name: "layer.new", parameters: ["name": "string, 1–256 characters"],
      description: "Create a transparent pixel layer above the active layer."),
    .init(
      name: "layer.fill",
      parameters: [
        "layerID": "uuid", "r": "number, 0–1", "g": "number, 0–1", "b": "number, 0–1",
        "a": "number, 0–1",
      ],
      description:
        "Fill a pixel layer with native RGBA values, respecting the document selection. Does not target a mask."
    ),
    .init(
      name: "selection.rectangle",
      parameters: [
        "x": "integer, >=0", "y": "integer, >=0", "width": "integer, >=1", "height": "integer, >=1",
      ], description: "Replace selection with a rectangle contained in the canvas."),
    .init(name: "selection.clear", parameters: [:], description: "Deselect."),
    .init(
      name: "history.undo", parameters: [:],
      description: "Undo the latest shared desktop/API document edit."),
    .init(
      name: "history.redo", parameters: [:], description: "Redo the latest undone document edit."),
  ]
  let name: String
  let revision: String
  let parameters: [String: AutomationValue]
  init(data: Data) throws {
    let object: [String: AutomationValue]
    do { object = try JSONDecoder().decode([String: AutomationValue].self, from: data) } catch {
      throw AutomationFailure(status: 400, message: "Expected a JSON command object.")
    }
    guard Set(object.keys) == ["command", "revision", "parameters"],
      case .string(let name) = object["command"], case .string(let revision) = object["revision"],
      case .object(let parameters) = object["parameters"]
    else {
      throw AutomationFailure(
        status: 400, message: "Required fields: command, revision, parameters.")
    }
    guard let definition = Self.definitions.first(where: { $0.name == name }) else {
      throw AutomationFailure(
        status: 422, message: "Command is not implemented by this API version.")
    }
    guard Set(parameters.keys) == Set(definition.parameters.keys) else {
      throw AutomationFailure(status: 400, message: "Missing or unknown command parameters.")
    }
    self.name = name
    self.revision = revision
    self.parameters = parameters
  }
  func string(_ key: String) throws -> String {
    guard case .string(let value) = parameters[key],
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.count <= 256,
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw AutomationFailure(status: 400, message: "Invalid \(key).") }
    return value
  }
  func number(_ key: String, range: ClosedRange<Double>) throws -> Double {
    guard case .number(let value) = parameters[key], value.isFinite, range.contains(value) else {
      throw AutomationFailure(status: 400, message: "Invalid \(key).")
    }
    return value
  }
  func integer(_ key: String, range: ClosedRange<Double>) throws -> Int {
    let value = try number(key, range: range)
    guard value.rounded() == value else {
      throw AutomationFailure(status: 400, message: "\(key) must be an integer.")
    }
    return Int(value)
  }
  func nativeCommand(document: CraftDocument) throws -> Command? {
    func id() throws -> UUID {
      guard let id = UUID(uuidString: try string("layerID")),
        document.layers.contains(where: { $0.id == id })
      else {
        throw AutomationFailure(status: 404, message: "Layer not found.")
      }
      return id
    }
    switch name {
    case "layer.rename": return .renameLayer(try id(), try string("name"))
    case "layer.opacity": return .opacity(try id(), Float(try number("opacity", range: 0...1)))
    case "layer.visibility":
      guard case .bool(let value) = parameters["visible"] else {
        throw AutomationFailure(status: 400, message: "visible must be boolean.")
      }
      return .visibility(try id(), value)
    case "layer.move":
      return .move(
        try id(), try integer("x", range: -1_000_000...1_000_000),
        try integer("y", range: -1_000_000...1_000_000))
    case "layer.new": return .newPixelLayer(NewPixelLayerOptions(name: try string("name")))
    case "layer.fill":
      let target = try id()
      guard case .raster = document.layers.first(where: { $0.id == target })?.content else {
        throw AutomationFailure(status: 422, message: "Fill requires a pixel layer.")
      }
      return .fill(
        target,
        Pixel(
          Float(try number("r", range: 0...1)), Float(try number("g", range: 0...1)),
          Float(try number("b", range: 0...1)), Float(try number("a", range: 0...1))))
    case "selection.rectangle":
      let x = try integer("x", range: 0...Double(document.width - 1))
      let y = try integer("y", range: 0...Double(document.height - 1))
      let width = try integer("width", range: 1...Double(document.width - x))
      let height = try integer("height", range: 1...Double(document.height - y))
      return .selection(IntRect(x: x, y: y, width: width, height: height))
    case "selection.clear": return .selection(nil)
    case "history.undo", "history.redo": return nil
    default: throw AutomationFailure(status: 422, message: "Unsupported command.")
    }
  }

  @MainActor func applyViewCommand(to store: EditorStore) throws -> Bool {
    if name == "channel.fill" {
      let command = try store.componentFillCommand(
        value: Float(number("value", range: 0...1)),
        opacity: Float(number("opacity", range: 0...1)))
      try store.executeEditorCommand(command)
      return true
    }
    guard ["channel.target", "view.channelPreview", "view.channelVisibility"].contains(name) else {
      return false
    }
    let title = try string("channel")
    guard let channel = RGBChannelPreview.allCases.first(where: { $0.title == title }) else {
      throw AutomationFailure(status: 400, message: "channel must be RGB, Red, Green or Blue.")
    }
    if name == "channel.target" {
      try store.selectEditingChannel(channel)
    } else if name == "view.channelPreview" {
      store.previewChannel(channel)
    } else {
      guard case .bool(let visible) = parameters["visible"] else {
        throw AutomationFailure(status: 400, message: "visible must be boolean.")
      }
      guard store.setChannelVisibility(channel, visible: visible) else {
        throw AutomationFailure(
          status: 422, message: "Exit mask viewing/editing before changing channel visibility.")
      }
    }
    return true
  }
}
