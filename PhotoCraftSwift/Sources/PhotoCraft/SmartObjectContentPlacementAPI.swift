import PhotoCraftCore
import PhotoCraftImaging

enum SmartObjectContentPlacementAPI {
  private static let horizontal: [String: Double] = ["left": 0, "center": 0.5, "right": 1]
  private static let vertical: [String: Double] = ["top": 0, "center": 0.5, "bottom": 1]

  static var schema: [String: Any] {
    BrushAPI.object([
      "mode": ["type": "string", "enum": ["fit", "fill"]],
      "horizontalAlign": ["type": "string", "enum": ["left", "center", "right"], "default": "left"],
      "verticalAlign": ["type": "string", "enum": ["top", "center", "bottom"], "default": "top"],
    ], required: ["mode"])
  }

  static var capabilities: [String: Any] {
    [
      "photatoCommand": "smartObject.replace", "photatoField": "parameters.contentPlacement",
      "adobeRoute": "POST /v2/create-composite", "adobeField": "edits.layers[].smartObject.contentPlacement",
      "schema": schema,
      "scope": "Fit or fill an embedded frame, retaining the complete ingredient as a nested Smart Object.",
      "unsupportedFrames": ["linked", "skewed", "perspective", "warped", "rotated with a pixel mask"],
    ]
  }

  static func parse(_ raw: Any, path: String) throws -> SmartObjectContentPlacement {
    let object = try AdobeActionsRequest.Object(raw, at: path, allowed: ["mode", "horizontalAlign", "verticalAlign"])
    let mode = try object.string("mode")
    guard let fit = FrameFit(rawValue: mode), fit != .original else {
      throw AdobeAPIError.invalid("\(path).mode must be fit or fill.")
    }
    let h = try object.fields["horizontalAlign"].map { _ in try object.string("horizontalAlign") } ?? "left"
    let v = try object.fields["verticalAlign"].map { _ in try object.string("verticalAlign") } ?? "top"
    guard let x = horizontal[h], let y = vertical[v], let anchor = CanvasAnchor.allCases.first(where: { $0.fractions == (x, y) }) else {
      throw AdobeAPIError.invalid("\(path) contains an unknown alignment.")
    }
    return .init(mode: fit, anchor: anchor)
  }
}
