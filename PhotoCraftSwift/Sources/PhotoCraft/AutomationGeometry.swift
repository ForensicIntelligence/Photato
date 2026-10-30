import Foundation
import PhotoCraftCore

enum GeometryAPI {
  static let commands = ["document.resize", "document.canvasSize", "document.rotate", "document.resolution"]
  static let methods: [String: Resampling] = ["nearest": .nearest, "bilinear": .bilinear, "bicubic": .bicubic]
  static let turns: [String: CanvasTurn] = ["clockwise": .clockwise, "counterclockwise": .counterclockwise, "half": .half, "horizontal": .horizontal, "vertical": .vertical]
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "width", "height": return ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension]
    case "resolution": return ["type": "number", "minimum": 1, "maximum": 100000]
    case "method": return ["type": "string", "enum": methods.keys.sorted(), "description": "Defaults to nearest for Indexed/Bitmap; bicubic for component modes."]
    case "anchor": return ["type": "string", "enum": CanvasAnchor.allCases.map(\.rawValue), "default": "center"]
    case "turn": return ["type": "string", "enum": turns.keys.sorted()]
    case "fill": return ["type": "array", "minItems": 4, "maxItems": 4, "items": ["type": "number", "minimum": 0, "maximum": 1], "description": "RGBA; omitted uses transparency where supported, otherwise white quantized to the current palette."]
    default: return [:]
    }
  }
  static var capabilities: [String: Any] { [
    "commands": commands, "restrictedMaximumPixels": PaletteQuantization.maximumPixels, "inkMaximumPixels": InkPlane.maximumPixels,
    "inkModes": "Duotone geometry transforms its gray source; Multichannel transforms each numeric ink plate. Grid transforms preserve exact8/16-bit samples. Saved alpha masks and selections transform with the canvas. Duotone extension uses gray background/paper; Multichannel extension requires paper (omitted or white fill). Off-canvas ink samples are discarded; Undo restores them.",
    "behavior": "Whole-document geometry uses the desktop commands and one prepared Undo transaction. Width/height are pixels; resolution is pixels/inch. Resolution-only changes never resample. Native color mode, palette and bit storage are retained.",
    "restricted": "Nearest sampling and integer crop/canvas/quarter-turn transforms preserve exact indices, including duplicate colors. Bilinear/bicubic results map back to the current palette or black/white. Bitmap extension is white; Indexed extension is transparent when available, otherwise white mapped to the table. Canvas shrinking discards outside samples; Undo restores them.",
    "limits": "8,388,608 output pixels in Indexed/Bitmap/Duotone/Multichannel. Exact Photoshop resampling and corresponding Adobe action descriptors remain unqualified. No Adobe route is added."] }
}

extension AutomationCommand {
  func geometryCommand(in document: CraftDocument) throws -> Command {
    switch name {
    case "document.resize":
      let method: Resampling
      if parameters["method"] != nil {
        guard let parsed = GeometryAPI.methods[try string("method")] else { throw AutomationFailure(status: 400, message: "Unknown resampling method.") }
        method = parsed
      } else { method = document.colorMode.isRestricted ? .nearest : .bicubic }
      return .imageSize(try integer("width", range: 1...Double(Surface.maxDimension)), try integer("height", range: 1...Double(Surface.maxDimension)), try parameters["resolution"].map { _ in try number("resolution", range: 1...100000) } ?? document.pixelsPerInch, method)
    case "document.canvasSize":
      let anchor: CanvasAnchor
      if parameters["anchor"] != nil {
        guard let parsed = CanvasAnchor(rawValue: try string("anchor")) else { throw AutomationFailure(status: 400, message: "Unknown canvas anchor.") }
        anchor = parsed
      } else { anchor = .center }
      var fill: Pixel?
      if let raw = parameters["fill"] {
        guard case .array(let values) = raw, values.count == 4 else { throw AutomationFailure(status: 400, message: "Canvas fill requires four RGBA values.") }
        let rgba = try values.map { value -> Float in
          guard case .number(let n) = value, n.isFinite, (0...1).contains(n) else { throw AutomationFailure(status: 400, message: "Invalid canvas fill.") }
          return Float(n)
        }
        fill = Pixel(rgba[0], rgba[1], rgba[2], rgba[3])
      }
      return .canvasSize(try integer("width", range: 1...Double(Surface.maxDimension)), try integer("height", range: 1...Double(Surface.maxDimension)), anchor, fill)
    case "document.rotate":
      guard let turn = GeometryAPI.turns[try string("turn")] else { throw AutomationFailure(status: 400, message: "Unknown canvas turn.") }
      return .rotateCanvas(turn)
    case "document.resolution": return .resolution(try number("resolution", range: 1...100000))
    default: throw AutomationFailure(status: 400, message: "Unknown document geometry command.")
    }
  }
}
