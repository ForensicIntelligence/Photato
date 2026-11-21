import CoreML
import Foundation
import PhotoCraftCore

package enum LocalGenerativeFill {
  package static let maximumSelectionSide = 4096
  package static let maximumSelectionPixels = 4_194_304
  static let side = 512

  package static var supported: Bool {
    #if arch(arm64)
    if #available(macOS 26, *) { return true }
    #endif
    return false
  }

  package static func selection(in document: CraftDocument) -> IntRect? {
    guard document.colorMode == .rgb, document.inkMode == nil, document.restrictedMode == nil,
      !document.isChannelOnly, document.videoTimeline == nil, document.animation == nil,
      document.artboards.isEmpty, document.layers.count < LayerLimits.maximumLayers,
      let bounds = document.selectionMask?.bounds ?? document.selection,
      bounds.width > 0, bounds.height > 0,
      max(bounds.width, bounds.height) <= maximumSelectionSide,
      bounds.width <= maximumSelectionPixels / bounds.height else { return nil }
    return bounds
  }

  package static func validateModel(_ url: URL) throws {
    guard supported else { throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.") }
    _ = try load(url)
  }

  package static func prepare(_ document: CraftDocument, model url: URL) throws -> Command {
    #if arch(arm64)
    guard #available(macOS 26, *) else {
      throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.")
    }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    let model = try load(url)
    return try prepare(document) { image, mask in try predict(model, image: image, mask: mask) }
    #else
    throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.")
    #endif
  }

  private static func load(_ url: URL) throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndGPU
    let model = try MLModel(contentsOf: url, configuration: configuration)
    let inputs = model.modelDescription.inputDescriptionsByName
    let outputs = model.modelDescription.outputDescriptionsByName
    guard inputs.count == 2, outputs.count == 1,
      tensor(inputs["image"], channels: 3, type: .float32), tensor(inputs["mask"], channels: 1, type: .float32),
      tensor(outputs["result"], channels: 3, type: .float16) else {
      throw CraftError.invalid("Choose a compiled LaMa512 model with image, mask and result tensors.")
    }
    return model
  }

  private static func tensor(_ feature: MLFeatureDescription?, channels: Int, type: MLMultiArrayDataType) -> Bool {
    guard let constraint = feature?.multiArrayConstraint else { return false }
    return constraint.dataType == type && constraint.shape.map(\.intValue) == [1, channels, side, side]
  }

  #if arch(arm64)
  @available(macOS 26, *)
  private static func predict(_ model: MLModel, image: [Float], mask: [Float]) throws -> Surface {
    let imageArray = try makeTensor(image, channels: 3)
    let maskArray = try makeTensor(mask, channels: 1)
    let input = try MLDictionaryFeatureProvider(dictionary: ["image": imageArray, "mask": maskArray])
    try Task.checkCancellation()
    let features = try model.prediction(from: input)
    try Task.checkCancellation()
    guard let output = features.featureValue(for: "result")?.multiArrayValue,
      output.dataType == .float16, output.shape.map(\.intValue) == [1, 3, side, side] else {
      throw CraftError.invalid("The model returned an invalid inpainted image.")
    }
    var result = try Surface(width: side, height: side, depth: .f32)
    let strides = output.strides.map(\.intValue)
    try output.withUnsafeBufferPointer(ofType: Float16.self) { values in
      for y in 0..<side {
        try Task.checkCancellation()
        for x in 0..<side {
          let i = y * strides[2] + x * strides[3]
          let r = Float(values[i]), g = Float(values[i + strides[1]]), b = Float(values[i + 2 * strides[1]])
          guard r.isFinite, g.isFinite, b.isFinite else { throw CraftError.invalid("The model returned non-finite color.") }
          result.setPixel(x: x, y: y, Pixel(unit(r), unit(g), unit(b)))
        }
      }
    }
    return result
  }

  private static func makeTensor(_ samples: [Float], channels: Int) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, NSNumber(value: channels), NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
    array.withUnsafeMutableBufferPointer(ofType: Float.self) { values, strides in
      for c in 0..<channels { for y in 0..<side { for x in 0..<side {
        values[c * strides[1] + y * strides[2] + x * strides[3]] = samples[(c * side + y) * side + x]
      } } }
    }
    return array
  }
  #endif

  static func prepare(_ document: CraftDocument, predict: ([Float], [Float]) throws -> Surface) throws -> Command {
    guard let selected = selection(in: document) else {
      throw CraftError.invalid("Select an area of up to 4 megapixels in a still RGB image.")
    }
    if selected.width == document.width, selected.height == document.height,
      try document.coverageSelection()?.isFullCoverage == true {
      throw CraftError.invalid("Include some surrounding pixels outside the selection.")
    }
    let margin = min(512, max(32, max(selected.width, selected.height) / 4))
    let region = IntRect(x: selected.x - margin, y: selected.y - margin,
      width: selected.width + 2 * margin, height: selected.height + 2 * margin)
      .clipped(toWidth: document.width, height: document.height)
    let reference = try CraftDocument(width: side, height: side, depth: .u8)
    let crop = try Renderer.composite(document, region: region).cropped(to: region)
    let input = try ColorManagement.converted(crop, from: document, to: reference)
    let modelScale = Double(side) / Double(max(region.width, region.height))
    let left = (Double(side) - Double(region.width) * modelScale) / 2
    let top = (Double(side) - Double(region.height) * modelScale) / 2
    let count = side * side
    var image = [Float](repeating: 0, count: 3 * count)
    var mask = [Float](repeating: 0, count: count)
    for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side {
        let px = (Double(x) + 0.5 - left) / modelScale
        let py = (Double(y) + 0.5 - top) / modelScale
        let p = RasterGeometry.sample(input, x: px, y: py, method: .bilinear, clampEdges: true)
        let i = y * side + x
        image[i] = p.r * p.a
        image[i + count] = p.g * p.a
        image[i + 2 * count] = p.b * p.a
        if px >= 0, py >= 0, px < Double(region.width), py < Double(region.height),
          document.selectionCoverage(x: region.x + Int(px), y: region.y + Int(py)) > 0 { mask[i] = 1 }
      }
    }
    var editableMask = try Surface(width: selected.width, height: selected.height, fill: .black)
    for y in 0..<selected.height {
      try Task.checkCancellation()
      for x in 0..<selected.width {
        let coverage = document.selectionCoverage(x: selected.x + x, y: selected.y + y)
        guard coverage > 0 else { continue }
        editableMask.setPixel(x: x, y: y, Pixel(coverage, coverage, coverage))
        // Also retain thin selections that did not hit a model pixel center.
        let mx = min(side - 1, Int(left + (Double(selected.x + x - region.x) + 0.5) * modelScale))
        let my = min(side - 1, Int(top + (Double(selected.y + y - region.y) + 0.5) * modelScale))
        mask[my * side + mx] = 1
      }
    }
    guard mask.contains(1), mask.contains(0) else { throw CraftError.invalid("Include some surrounding pixels outside the selection.") }
    let generated = try predict(image, mask)
    try Task.checkCancellation()
    guard generated.width == side, generated.height == side else {
      throw CraftError.invalid("The model returned an unexpected output size.")
    }
    var patch = try Surface(width: selected.width, height: selected.height, depth: .f32)
    for y in 0..<selected.height {
      try Task.checkCancellation()
      for x in 0..<selected.width {
        let mx = left + (Double(selected.x + x - region.x) + 0.5) * modelScale
        let my = top + (Double(selected.y + y - region.y) + 0.5) * modelScale
        patch.setPixel(x: x, y: y, RasterGeometry.sample(generated, x: mx, y: my, method: .bilinear, clampEdges: true))
      }
    }
    var layer = Layer(name: "Generative Fill", content: .raster(try ColorManagement.converted(patch, from: reference, to: document)))
    layer.x = selected.x
    layer.y = selected.y
    layer.mask = editableMask
    return .generativeFill(layer)
  }
}
