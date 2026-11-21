import CoreGraphics
import Foundation
import PhotoCraftCore

public enum RemoveDistractionCategory: String, CaseIterable, Sendable {
  case identifiedObjects, poles, spotsAndDust, unrecognizedObjects, vegetation, visualClutter

  public var title: String {
    switch self {
    case .identifiedObjects: "Identified objects"
    case .poles: "Poles"
    case .spotsAndDust: "Spots and dust"
    case .unrecognizedObjects: "Unrecognized objects"
    case .vegetation: "Vegetation"
    case .visualClutter: "Visual clutter"
    }
  }

  public var color: Pixel {
    switch self {
    case .identifiedObjects: Pixel(0.24, 0.62, 1)
    case .poles: Pixel(1, 0.75, 0.20)
    case .spotsAndDust: Pixel(0.31, 0.90, 1)
    case .unrecognizedObjects: Pixel(1, 0.45, 0.20)
    case .vegetation: Pixel(0.76, 0.45, 1)
    case .visualClutter: Pixel(0.22, 0.89, 0.60)
    }
  }
}

public struct RemoveDistractionMark: Sendable {
  public let category: RemoveDistractionCategory
  public let mask: SelectionMask
  public let count: Int

  public init(category: RemoveDistractionCategory, mask: SelectionMask, count: Int = 1) {
    self.category = category; self.mask = mask; self.count = count
  }
}

public protocol RemoveDistractionDetecting: Sendable {
  func detectDistractions(in input: Surface) async throws -> [RemoveDistractionMark]
}

public struct RemoveDistractionGroup: Sendable {
  public let category: RemoveDistractionCategory
  public let count: Int
  public let coverage: SelectionMask
  public let overlay: CGImage
}

public enum RemoveDistractionPreparation {
  public static func detect(_ document: CraftDocument, layerID: UUID, settings: RemoveToolSettings,
    detector: any RemoveDistractionDetecting) async throws -> [RemoveDistractionGroup] {
    try settings.validate(); try document.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb, document.width <= RemovePreparation.maximumCanvasPixels / document.height,
      let layer = document.layers.first(where: { $0.id == layerID }), case .raster = layer.content,
      layer.smartObject == nil, layer.sourceProjection == nil,
      !document.ancestors(of: layerID).contains(where: { $0.protection.fullyLocks }),
      settings.createNewLayer || !document.isImageLocked(layerID) else {
      throw CraftError.unsupported("General distractions requires an available RGB raster target within the current Remove canvas limit.")
    }
    let source = try RemoveDistractionInput.prepare(document, layer: layer, sampleAllLayers: settings.sampleAllLayers)
    let marks = try await detector.detectDistractions(in: source)
    guard marks.count <= 128, marks.allSatisfy({ $0.mask.width == source.width && $0.mask.height == source.height && (1...128).contains($0.count) }) else {
      throw CraftError.invalid("The distraction detector returned invalid analysis masks.")
    }
    // Groups share one analysis grid and one document geometry. Save the screen overlay
    // separately so changing enabled groups does not rescan the source or its pixels.
    return try RemoveDistractionCategory.allCases.compactMap { category in
      try Task.checkCancellation()
      let members = marks.filter { $0.category == category && $0.mask.bounds != nil }
      guard !members.isEmpty else { return nil }
      let mask = try PeopleAnalysis.coverage(members.map(\.mask), width: document.width, height: document.height,
        featureMap: nil, features: [.wholePerson], hardEdge: true)
      let overlay = try RasterPreviewRequest.overview(width: document.width, height: document.height, maximumSide: 960)
      guard mask.bounds != nil, let image = try SelectionToolPreparation.overlay(mask, color: category.color, request: overlay) else { return nil }
      return RemoveDistractionGroup(category: category, count: members.reduce(0) { $0 + $1.count }, coverage: mask, overlay: image)
    }
  }
}

enum RemoveDistractionInput {
  static func prepare(_ document: CraftDocument, layer: Layer, sampleAllLayers: Bool) throws -> Surface {
    let preview = try RasterPreviewRequest.overview(width: document.width, height: document.height, maximumSide: 960)
    var visibleLayer = layer
    visibleLayer.visible = true; visibleLayer.style = nil; visibleLayer.opacity = 1
    let guide = try sampleAllLayers ? Renderer.compositePaged(document) : Renderer.clippingCoverage(visibleLayer, in: document)
    return try ColorManagement.converted(preview.reducing(guide), from: document, to: CraftDocument(width: 1, height: 1))
  }
}
