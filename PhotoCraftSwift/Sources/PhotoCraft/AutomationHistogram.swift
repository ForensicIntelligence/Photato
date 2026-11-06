import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum HistogramAPI {
  static let name = "tone.histogram"
  static func schema(_ key: String) -> [String: Any] {
    key == "layerID" ? ["type": "string", "format": "uuid"] : BrushAPI.flag
  }
  static var histogramSchema: [String: Any] {
    let count: [String: Any] = ["type": "integer", "minimum": 0, "maximum": Surface.maxPixels]
    let triple: [String: Any] = ["type": "array", "minItems": 3, "maxItems": 3, "items": count]
    return BrushAPI.object([
      "channels": ["type": "array", "minItems": 3, "maxItems": 3, "items": ["type": "array", "minItems": 256, "maxItems": 256, "items": count]],
      "samples": count, "transparent": count, "invalid": count,
      "underflow": triple, "overflow": triple, "shadows": triple, "highlights": triple
    ], required: ["channels", "samples", "transparent", "invalid", "underflow", "overflow", "shadows", "highlights"])
  }
  static var capabilities: [String: Any] {
    ["command": name, "histogramSchema": histogramSchema,
     "resultSchema": BrushAPI.object(["histogram": histogramSchema, "revision": ["type": "string"],
       "sourceDepth": BrushAPI.enumeration(PixelDepth.allCases.map(\.rawValue)),
       "layerID": ["type": "string", "format": "uuid"], "luminance": BrushAPI.flag],
       required: ["histogram", "revision", "sourceDepth", "layerID", "luminance"]), "layerIDRequired": true,
     "useSelectionDefault": true, "luminanceDefault": false, "readOnly": true,
     "source": "Raster cells for pixel layers; input backdrop before own adjustment parameters/mask/opacity for adjustment layers. Same request as native Levels/Curves.",
     "sampleDomain": "Encoded RGB at8/16; linear RGB at32, through the existing transfer path. Luminance8 uses round-to-even. Positive alpha/selection count once, without coverage weighting.",
     "pagedRasterMaximumDimension": Surface.maxDimension, "pagedRasterMaximumPixels": Surface.maxPixels,
     "limits": "Paged for ordinary integral-translation raster and same-grid surfaces. Other affine layer statistics retain original per-cell sampling. Adjustment composition, ICC/Photoshop fidelity, dense performance and all-operation capacity remain unqualified. No Adobe histogram route is invented."]
  }
  static func json(_ h: RGBHistogram) -> [String: Any] {
    ["channels": h.channels, "samples": h.samples, "transparent": h.transparent, "invalid": h.invalid,
     "underflow": h.underflow, "overflow": h.overflow, "shadows": h.shadows, "highlights": h.highlights]
  }
}
extension AutomationCommand {
  func histogramRequest(in document: CraftDocument) throws -> LevelsAnalysisRequest {
    let id = try actionUUID("layerID")
    guard let layer = document.layers.first(where: { $0.id == id }) else {
      throw AutomationFailure(status: 404, message: "Histogram source layer not found.")
    }
    let pixel: Bool
    switch layer.content {
    case .raster: pixel = true
    case .adjustment: pixel = false
    default: throw AutomationFailure(status: 422, message: "Select a pixel or adjustment layer for its histogram.")
    }
    let selected = try pathFlag("useSelection", true), luminance = try pathFlag("luminance", false)
    if !pixel, parameters["useSelection"] != nil {
      throw AutomationFailure(status: 400, message: "useSelection is a pixel-layer option; adjustment input matches the native inspector.")
    }
    var snapshot = document
    if !selected { snapshot.selection = nil; snapshot.selectionMask = nil }
    return .init(document: snapshot, layerID: id, pixelLayer: pixel, luminance: luminance)
  }
}
