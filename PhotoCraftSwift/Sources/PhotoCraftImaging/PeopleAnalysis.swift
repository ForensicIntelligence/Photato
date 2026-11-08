import Foundation
import PhotoCraftCore

/// Large-document inference has a bounded analysis grid, not a smaller editing canvas.
public enum PeopleAnalysis {
  public static let maximumAnalysisSide = 1024
  public static let maximumPeople = 64
  public static let maximumAnalysisMaskBytes = 64 * 1024 * 1024
  public static let maximumExportedMaskPixels = 16_777_216

  public static func checkSize(_ width: Int, _ height: Int) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height else { throw CraftError.invalid("Invalid person-selection canvas.") }
  }
  public static func dimensions(width: Int, height: Int) throws -> (width: Int, height: Int) {
    try checkSize(width, height)
    if (try? ForegroundSelection.checkSize(width, height)) != nil { return (width, height) }
    let scale = min(1, Double(maximumAnalysisSide) / Double(max(width, height)))
    return (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
  }
  static func checkInputBudget(width: Int, height: Int, count: Int) throws {
    try ForegroundSelection.checkSize(width, height)
    guard (0...maximumPeople).contains(count) else { throw CraftError.unsupported("Select People supports at most64 detected people.") }
    guard count > 0 else { return }
    if width <= maximumAnalysisSide, height <= maximumAnalysisSide {
      guard width <= maximumAnalysisMaskBytes / height / max(1, count) else {
        throw CraftError.unsupported("Person analysis exceeds its64MiB raw mask budget.")
      }
    } else {
      // The old native-size path retains its established resource admission.
      try MaskAllObjectsEdit.checkBudget(width: width, height: height, count: count)
    }
  }
  static func input(_ document: CraftDocument, layerID: UUID?, allLayers: Bool) throws -> Surface {
    let size = try dimensions(width: document.width, height: document.height)
    if size.width == document.width, size.height == document.height {
      return try SelectionToolPreparation.input(document, layerID: layerID, allLayers: allLayers)
    }
    try document.validate(); try Task.checkCancellation()
    guard SelectionToolPreparation.canSample(document, layerID: layerID, allLayers: allLayers) else {
      throw CraftError.unsupported("Choose a source layer or enable Sample All Layers.")
    }
    let rendered: Surface
    if allLayers { rendered = try Renderer.composite(document) }
    else {
      guard let id = layerID ?? document.activeLayerID,
        var layer = document.layers.first(where: { $0.id == id }) else {
        throw CraftError.invalid("Selection source layer no longer exists.")
      }
      layer.visible = true; layer.style = nil; layer.opacity = 1; layer.blendMode = .normal
      layer.parentID = nil; layer.clipped = false
      var isolated = document; isolated.layers = [layer]; isolated.activeLayerID = layer.id
      // The original document was validated above. Comps and other unrelated
      // document records aren't rewritten merely to render this one source.
      rendered = try Renderer.compositeValidated(isolated, preferPaged: true)
    }
    let request = try RasterPreviewRequest(region: .init(x: 0, y: 0, width: document.width, height: document.height),
      width: size.width, height: size.height)
    let reduced = try request.reducing(rendered)
    return try ColorManagement.converted(reduced, from: document, to: CraftDocument(width: 1, height: 1))
  }
  static func bounds(_ bounds: IntRect, analysisWidth: Int, analysisHeight: Int, width: Int, height: Int) -> IntRect {
    let sx = Double(width) / Double(analysisWidth), sy = Double(height) / Double(analysisHeight)
    // Conservative support includes interpolation into neighboring grid cells.
    let x0 = max(0, Int(floor(Double(bounds.x - 1) * sx)))
    let y0 = max(0, Int(floor(Double(bounds.y - 1) * sy)))
    let x1 = min(width, Int(ceil(Double(bounds.x + bounds.width + 1) * sx)))
    let y1 = min(height, Int(ceil(Double(bounds.y + bounds.height + 1) * sy)))
    return .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  private struct Axis {
    let low: Int, high: Int
    let fraction: Float
    init(_ value: Int, count: Int, canvas: Int) {
      let sample = max(0, min(Double(count - 1), (Double(value) + 0.5) * Double(count) / Double(canvas) - 0.5))
      low = Int(sample); high = min(count - 1, low + 1); fraction = Float(sample - Double(low))
    }
  }
  private static func sample(_ mask: SelectionMask, x: Axis, y: Axis) -> UInt8 {
    let top = Float(mask.byte(at: y.low * mask.width + x.low)) * (1 - x.fraction)
      + Float(mask.byte(at: y.low * mask.width + x.high)) * x.fraction
    let bottom = Float(mask.byte(at: y.high * mask.width + x.low)) * (1 - x.fraction)
      + Float(mask.byte(at: y.high * mask.width + x.high)) * x.fraction
    return UInt8(min(255, max(0, (top * (1 - y.fraction) + bottom * y.fraction).rounded())))
  }
  private static func probability(_ map: PeopleFeatureMap, x: Axis, y: Axis, channels: [Int]) -> Float {
    var value: Float = 0
    for c in channels {
      let top = map.probabilities[(y.low * map.width + x.low) * 6 + c] * (1 - x.fraction)
        + map.probabilities[(y.low * map.width + x.high) * 6 + c] * x.fraction
      let bottom = map.probabilities[(y.high * map.width + x.low) * 6 + c] * (1 - x.fraction)
        + map.probabilities[(y.high * map.width + x.high) * 6 + c] * x.fraction
      value += top * (1 - y.fraction) + bottom * y.fraction
    }
    return min(1, max(0, value))
  }
  static func coverage(_ masks: [SelectionMask], width: Int, height: Int,
    featureMap: PeopleFeatureMap?, features: [PeopleFeature], hardEdge: Bool) throws -> SelectionMask {
    try checkSize(width, height); try Task.checkCancellation()
    guard let first = masks.first, masks.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
      throw CraftError.invalid("Invalid person analysis masks.")
    }
    let whole = features.contains(.wholePerson), channels = features.map(\.channel)
    // A full uniform result is represented implicitly even at300000². This is
    // an exact union identity, not a substitute for a nonuniform learned mask.
    if whole {
      for mask in masks {
        try Task.checkCancellation()
        if try mask.bytes.allSatisfy({ $0 == 255 }) {
          return try SelectionMask(coverage: Surface(width: width, height: height, depth: .u8, fill: .white))
        }
      }
    }
    let regions = masks.compactMap(\.bounds).map {
      bounds($0, analysisWidth: first.width, analysisHeight: first.height, width: width, height: height)
    }
    return try SelectionMask.sampledCoverage(width: width, height: height, regions: regions) { x, y in
      let sx = Axis(x, count: first.width, canvas: width), sy = Axis(y, count: first.height, canvas: height)
      var byte: UInt8 = 0
      for mask in masks { byte = max(byte, sample(mask, x: sx, y: sy)) }
      if byte > 0, !whole, let map = featureMap {
        byte = UInt8((Float(byte) * probability(map, x: Axis(x, count: map.width, canvas: width),
          y: Axis(y, count: map.height, canvas: height), channels: channels)).rounded())
      }
      return hardEdge ? (byte >= 128 ? 255 : 0) : byte
    }
  }
}
