import CoreGraphics
import Foundation
import PhotoCraftCore

public enum RemoveRelatedElement: String, CaseIterable, Sendable {
  case shadow, reflection

  public var title: String {
    switch self { case .shadow: "Shadows"; case .reflection: "Reflections" }
  }

  fileprivate var tint: Pixel {
    switch self { case .shadow: Pixel(0.36, 0.79, 1); case .reflection: Pixel(0.36, 0.94, 0.63) }
  }
}

public protocol RemoveRelatedElementDetecting: Sendable {
  func scores(in image: Surface, for element: RemoveRelatedElement) async throws -> [Float]
}

public struct RemoveRelatedElementGroup: Sendable {
  public let element: RemoveRelatedElement
  public let coverage: SelectionMask
  public let overlay: CGImage
}

package struct RemoveRelatedAnalysis: Sendable {
  package let object: SelectionMask
  package let objectOverlay: CGImage
  package let groups: [RemoveRelatedElementGroup]
}

public enum RemoveRelatedElements {
  public static let side = 352
  public static let maximumAnalysisPixels = 16_777_216

  package static func analyze(_ request: RemoveRequest, source: CraftDocument,
    detector: any RemoveRelatedElementDetecting) async throws -> RemoveRelatedAnalysis {
    try source.validate(); try Task.checkCancellation()
    guard RemovePreparation.supportsLocalProcessing(source),
      let target = source.layers.first(where: { $0.id == request.layerID }), case .raster = target.content,
      target.smartObject == nil, target.sourceProjection == nil,
      !source.ancestors(of: target.id).contains(where: { $0.protection.fullyLocks }) else {
      throw CraftError.invalid("Choose an ordinary raster layer in a still RGB image.")
    }
    let marks = try RemovePreparation.markCoverage(request, in: source)
    guard let object = marks.bounds else { throw CraftError.invalid("Mark the object before reviewing its related elements.") }
    let overview = try RasterPreviewRequest.overview(width: source.width, height: source.height, maximumSide: 960)
    // Include uncertain edges in the review. Thin gaps can otherwise leave enough
    // of the offending object in the model input to re-create its silhouette.
    let radius = Int(sqrt(Double(object.width) * Double(object.height)) / 13)
    let expand = SelectionModification(.expand, amount: min(18, max(2, radius)))
    var groups: [RemoveRelatedElementGroup] = []
    for element in RemoveRelatedElement.allCases {
      try Task.checkCancellation()
      let region = context(around: object, element: element, width: source.width, height: source.height)
      guard region.width <= maximumAnalysisPixels / region.height else {
        throw CraftError.unsupported("Mark one object with a neighbourhood of up to 16 megapixels for related element analysis.")
      }
      let input: Surface
      if request.settings.sampleAllLayers { input = try Renderer.composite(source, region: region) }
      else { input = try Renderer.clippingCoverage(ContentAwareInput.samplingLayer(target), in: source, region: region) }
      let crop = try ColorManagement.converted(input.cropped(to: region), from: source, to: CraftDocument(width: 1, height: 1))
      let confidence = try await detector.scores(in: crop, for: element)
      let selected = try associate(confidence, element: element, crop: crop, region: region, marks: marks, object: object)
      guard selected.contains(255) else { continue }
      let coverage = try SelectionMask.sampledCoverage(width: source.width, height: source.height, regions: [region]) { x, y in
        guard region.contains(x, y), marks.coverage(x: x, y: y) < 0.5 else { return 0 }
        let gx = min(side - 1, (x - region.x) * side / region.width)
        let gy = min(side - 1, (y - region.y) * side / region.height)
        return selected[gy * side + gx]
      }
      guard coverage.bounds != nil else { continue }
      let padded = try expand.applied(to: coverage)
      if let overlay = try SelectionToolPreparation.overlay(padded, color: element.tint, request: overview) {
        groups.append(.init(element: element, coverage: padded, overlay: overlay))
      }
    }
    let markedObject = try expand.applied(to: marks)
    guard let overlay = try SelectionToolPreparation.overlay(markedObject, color: Pixel(1, 0.20, 0.40), request: overview) else {
      throw CraftError.invalid("Could not preview the marked object.")
    }
    return .init(object: markedObject, objectOverlay: overlay, groups: groups)
  }

  private static func context(around box: IntRect, element: RemoveRelatedElement, width: Int, height: Int) -> IntRect {
    let padX = max(24, Int(0.8 * Double(min(box.width, box.height))))
    let above = max(20, box.height / 5)
    let below = switch element {
    case .shadow: max(17, box.height / 5)
    case .reflection: max(above, box.height, Int(Double(box.width) * 0.29))
    }
    return IntRect(x: box.x - padX, y: box.y - above, width: box.width + 2 * padX,
      height: box.height + above + below).clipped(toWidth: width, height: height)
  }

  private static func associate(_ confidence: [Float], element: RemoveRelatedElement, crop: Surface,
    region: IntRect, marks: SelectionMask, object: IntRect) throws -> [UInt8] {
    guard confidence.count == side * side, confidence.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw CraftError.invalid("The related elements model returned invalid mask scores.")
    }
    let threshold: Float = element == .shadow ? 0.40 : 0.26
    var candidates = [Bool](repeating: false, count: confidence.count)
    var distance = [Int](repeating: Int.max, count: confidence.count)
    var nearest: [Int] = []
    for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side {
        let i = y * side + x
        let localX = min(region.width - 1, (2 * x + 1) * region.width / (2 * side))
        let localY = min(region.height - 1, (2 * y + 1) * region.height / (2 * side))
        let dx = localX + region.x, dy = localY + region.y
        if marks.coverage(x: dx, y: dy) >= 0.5 {
          nearest.append(i); distance[i] = 0; continue
        }
        guard confidence[i] >= threshold, crop.pixel(x: localX, y: localY).a > 0.5 else { continue }
        if element == .reflection {
          let border = max(4, object.width / 16)
          guard dx >= object.x - border, dx < object.x + object.width + border,
            dy >= object.y + object.height - max(3, object.height / 18) else { continue }
        }
        candidates[i] = true
      }
    }
    let reach = element == .shadow ? 18 : 46
    var cursor = 0
    while cursor < nearest.count {
      if cursor.isMultiple(of: side) { try Task.checkCancellation() }
      let i = nearest[cursor]; cursor += 1
      let next = distance[i] + 1
      guard next <= reach else { continue }
      for j in neighbours(of: i) where distance[j] > next {
        distance[j] = next; nearest.append(j)
      }
    }
    var result = [UInt8](repeating: 0, count: candidates.count)
    for i in candidates.indices where candidates[i] {
      try Task.checkCancellation()
      var component = [i], next = 0, contact = 0
      candidates[i] = false
      while next < component.count {
        if next.isMultiple(of: side) { try Task.checkCancellation() }
        let px = component[next]; next += 1
        if distance[px] <= reach { contact += 1 }
        for py in neighbours(of: px) where candidates[py] {
          candidates[py] = false; component.append(py)
        }
      }
      guard component.count >= 24, contact >= max(4, component.count / 60) else { continue }
      for index in component { result[index] = 255 }
    }
    return result
  }

  private static func neighbours(of index: Int) -> [Int] {
    let x = index % side, y = index / side
    return [x > 0 ? index - 1 : nil, x + 1 < side ? index + 1 : nil,
      y > 0 ? index - side : nil, y + 1 < side ? index + side : nil].compactMap { $0 }
  }
}
