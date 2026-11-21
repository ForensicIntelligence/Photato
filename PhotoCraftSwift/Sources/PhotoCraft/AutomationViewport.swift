import CoreFoundation
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum AutomationViewport {
  static let header = "X-Photato-Viewport"
  private static let required = ["x", "y", "width", "height"]
  private static let output = ["outputWidth", "outputHeight"]

  static var capabilities: [String: Any] {
    let maximum = Double(Surface.maxDimension)
    var fields = Dictionary(uniqueKeysWithValues: (required + output).map {
      ($0, BrushAPI.number($0 == "x" || $0 == "y" ? 0 : 1, maximum, integer: true))
    })
    for key in output { fields[key]?["description"] = "Supply both output dimensions to reduce the source rectangle." }
    return [
      "header": header,
      "routes": ["preview.png", "channel-preview.png", "proof-preview.png"],
      "sourcePixels": RasterViewportPreview.maximumSourcePixels,
      "outputPixels": RasterPreviewRequest.maximumPixels,
      "schema": BrushAPI.object(fields, required: required),
      "scope": "Committed RGB compositing in top-left document coordinates. Omit both output dimensions for one sample per source pixel. Requested dimensions may reduce the rectangle. Neighborhood and whole-source preparation stay on their existing full-render paths.",
    ]
  }

  static func parse(_ raw: String?, document: CraftDocument) throws -> RasterPreviewRequest? {
    guard let raw else { return nil }
    let invalid = AutomationFailure(status: 400,
      message: "Supply x, y, width and height as integers in the viewport header, with both output dimensions if resizing.")
    guard let fields = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
      Set(required).isSubset(of: fields.keys),
      Set(fields.keys).isSubset(of: required + output),
      (fields[output[0]] == nil) == (fields[output[1]] == nil) else { throw invalid }
    func coordinate(_ key: String) throws -> Int {
      guard let number = fields[key] as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        let integer = Int(exactly: number.doubleValue),
        (0...Surface.maxDimension).contains(integer) else { throw invalid }
      return integer
    }
    let region = try IntRect(x: coordinate("x"), y: coordinate("y"),
      width: coordinate("width"), height: coordinate("height"))
    guard region.width > 0, region.height > 0,
      region == region.clipped(toWidth: document.width, height: document.height) else {
      throw AutomationFailure(status: 400, message: "The viewport must be a positive rectangle inside the document.")
    }
    guard region.width <= RasterViewportPreview.maximumSourcePixels / region.height else {
      throw AutomationFailure(status: 413, message: "The viewport exceeds 16,777,216 source pixels.")
    }
    let width = try fields[output[0]] == nil ? region.width : coordinate(output[0])
    let height = try fields[output[1]] == nil ? region.height : coordinate(output[1])
    guard width > 0, height > 0, width <= region.width, height <= region.height else {
      throw AutomationFailure(status: 400, message: "Viewport output dimensions must fit the source rectangle.")
    }
    guard width <= RasterPreviewRequest.maximumPixels / height else {
      throw AutomationFailure(status: 413, message: "The viewport exceeds 4,194,304 output pixels.")
    }
    return try RasterPreviewRequest(region: region, width: width, height: height)
  }
}
