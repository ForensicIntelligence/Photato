import CoreML
import Foundation
import PhotoCraftCore

package enum LocalGenerativeFill {
  package static let maximumSelectionSide = 4096
  package static let maximumSelectionPixels = 4_194_304
  package static let side = 512
  package static let maximumVariations = 3

  package static var supported: Bool {
    #if arch(arm64)
    if #available(macOS 26, *) { return true }
    #endif
    return false
  }

  static func supportsDocument(_ document: CraftDocument) -> Bool {
    document.colorMode == .rgb && document.inkMode == nil && document.restrictedMode == nil &&
      !document.isChannelOnly && document.videoTimeline == nil && document.animation == nil && document.artboards.isEmpty
  }

  package static func selection(in document: CraftDocument, bounds override: IntRect? = nil) -> IntRect? {
    guard supportsDocument(document),
      (override != nil || document.layers.count < LayerLimits.maximumLayers),
      let bounds = override ?? document.selectionMask?.bounds ?? document.selection,
      bounds == bounds.clipped(toWidth: document.width, height: document.height),
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
    try withContextModel(url) { predict in try prepare(document, predict: predict) }
  }

  package static func withContextModel<Result>(
    _ url: URL, _ operation: (([Float], [Float]) throws -> Surface) throws -> Result
  ) throws -> Result {
    #if arch(arm64)
    guard #available(macOS 26, *) else {
      throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.")
    }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    let model = try load(url)
    return try operation { image, mask in try predict(model, image: image, mask: mask) }
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
    let layers = try prepareVariations(document) { image, mask in [try predict(image, mask)] }
    return .generativeFill(layers[0])
  }

  package static func prepareVariations(
    _ document: CraftDocument, predict: ([Float], [Float]) throws -> [Surface]
  ) throws -> [Layer] {
    let (recipe, coverage) = try capture(document)
    return try recipe.patches(in: document, predict: predict).map { pixels in
      var layer = Layer(name: "Generative Fill", content: .raster(pixels))
      layer.x = recipe.selection.x
      layer.y = recipe.selection.y
      layer.mask = coverage
      return layer
    }
  }

  /// Original model inputs and edge samples. All floats are retained exactly
  /// across the supported little-endian Mac architectures.
  package struct Recipe: Codable, Sendable {
    package static let maximumBytes = 10 * 1_024 * 1_024
    let version: Int
    package let selection: IntRect
    let region: IntRect
    let image: Data
    let modelMask: Data
    let selectedPixels: Data
    let edge: GenerativeFillEdgeBlend.Context
    let expansion: GenerativeExpandBoundary?

    package func encoded() throws -> Data {
      let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
      let data = try encoder.encode(self)
      guard data.count <= Self.maximumBytes else { throw CraftError.invalid("The saved Generative Fill context is too large.") }
      return data
    }

    package static func decode(_ data: Data) throws -> Self {
      guard (1...maximumBytes).contains(data.count) else { throw CraftError.invalid("Invalid saved Generative Fill context.") }
      let recipe = try PropertyListDecoder().decode(Self.self, from: data)
      func valid(_ rect: IntRect, side: Int) -> Bool {
        (0...Surface.maxDimension).contains(rect.x) && (0...Surface.maxDimension).contains(rect.y) &&
        (1...side).contains(rect.width) && (1...side).contains(rect.height)
      }
      func containsSelection(_ box: IntRect) -> Bool {
        box.contains(recipe.selection.x, recipe.selection.y) &&
        box.contains(recipe.selection.x + recipe.selection.width - 1, recipe.selection.y + recipe.selection.height - 1)
      }
      let count = LocalGenerativeFill.side * LocalGenerativeFill.side
      guard recipe.version == 1, valid(recipe.selection, side: maximumSelectionSide),
        valid(recipe.region, side: maximumSelectionSide + 1024),
        valid(recipe.edge.bounds, side: maximumSelectionSide + 32),
        recipe.selection.width <= maximumSelectionPixels / recipe.selection.height,
        containsSelection(recipe.region), containsSelection(recipe.edge.bounds),
        recipe.selectedPixels.count == (recipe.selection.width * recipe.selection.height + 7) / 8,
        recipe.image.count == count * 3 * MemoryLayout<Float>.stride,
        recipe.modelMask.count == count * MemoryLayout<Float>.stride else {
        throw CraftError.invalid("Invalid saved Generative Fill context.")
      }
      _ = try recipe.edge.pixels()
      try recipe.expansion?.validate(in: recipe.region)
      return recipe
    }

    package func patches(
      in document: CraftDocument, conditioning: Surface? = nil, predict: ([Float], [Float]) throws -> [Surface]
    ) throws -> [Surface] {
      func samples(_ data: Data) -> [Float] {
        var result = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
        _ = result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return result
      }
      let reference = try CraftDocument(width: side, height: side, depth: .u8)
      let scale = Double(side) / Double(max(region.width, region.height))
      let left = (Double(side) - Double(region.width) * scale) / 2
      let top = (Double(side) - Double(region.height) * scale) / 2
      let mask = samples(modelMask)
      var input = samples(image)
      if let conditioning {
        guard conditioning.width == selection.width, conditioning.height == selection.height else {
          throw CraftError.invalid("The reference variation no longer matches the original selection.")
        }
        let source = try ColorManagement.converted(conditioning, from: document, to: reference)
        let count = side * side
        for y in 0..<side {
          try Task.checkCancellation()
          let patchY = (Double(y) + 0.5 - top) / scale + Double(region.y - selection.y)
          for x in 0..<side {
            let i = y * side + x
            guard mask[i] == 1 else { continue }
            let patchX = (Double(x) + 0.5 - left) / scale + Double(region.x - selection.x)
            let p = RasterGeometry.sample(source, x: patchX, y: patchY, method: .bilinear, clampEdges: true)
            input[i] += (p.r - input[i]) * p.a
            input[i + count] += (p.g - input[i + count]) * p.a
            input[i + 2 * count] += (p.b - input[i + 2 * count]) * p.a
          }
        }
      }
      let outputs = try predict(input, mask)
      guard (1...maximumVariations).contains(outputs.count) else {
        throw CraftError.invalid("The local model returned an unexpected number of variations.")
      }
      return try outputs.map { generated in
        try Task.checkCancellation()
        guard generated.width == side, generated.height == side else {
          throw CraftError.invalid("The model returned an unexpected output size.")
        }
        func sample(_ x: Double, _ y: Double) -> Pixel {
          let mx = left + (x - Double(region.x)) * scale
          let my = top + (y - Double(region.y)) * scale
          return RasterGeometry.sample(generated, x: mx, y: my, method: .bilinear, clampEdges: true)
        }
        let blend = try GenerativeFillEdgeBlend.prepare(selection: selection, context: edge, generated: sample)
        var patch = try Surface(width: selection.width, height: selection.height, depth: .f32)
        for y in 0..<selection.height {
          try Task.checkCancellation()
          for x in 0..<selection.width {
            let docX = Double(selection.x + x) + 0.5, docY = Double(selection.y + y) + 0.5
            let i = y * selection.width + x
            let pixel = sample(docX, docY)
            let selected = selectedPixels[i / 8] & (1 << (i % 8)) != 0
            patch.setPixel(x: x, y: y, selected ? blend?.adjusted(pixel, x: docX, y: docY) ?? pixel : pixel)
          }
        }
        var output = try ColorManagement.converted(patch, from: reference, to: document)
        try expansion?.join(&output, selection: selection, selectedPixels: selectedPixels)
        return output
      }
    }
  }

  package static func capture(_ document: CraftDocument, protectedCanvas: IntRect? = nil,
    samplingLayer: Layer? = nil, selectionBounds: IntRect? = nil) throws -> (Recipe, Surface) {
    guard let selected = selection(in: document, bounds: selectionBounds) else {
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
    let guide: Surface
    if let samplingLayer { guide = try Renderer.clippingCoverage(samplingLayer, in: document, region: region) }
    else { guide = try Renderer.composite(document, region: region) }
    let crop = try guide.cropped(to: region)
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
    var selectedPixels = [UInt8](repeating: 0, count: (selected.width * selected.height + 7) / 8)
    for y in 0..<selected.height {
      try Task.checkCancellation()
      for x in 0..<selected.width {
        let coverage = document.selectionCoverage(x: selected.x + x, y: selected.y + y)
        guard coverage > 0 else { continue }
        editableMask.setPixel(x: x, y: y, Pixel(coverage, coverage, coverage))
        // Preserve the support of the original quantized layer mask for edge blending.
        if editableMask.pixel(x: x, y: y).r > 0 {
          let i = y * selected.width + x
          selectedPixels[i / 8] |= 1 << (i % 8)
        }
        // Also retain thin selections that did not hit a model pixel center.
        let mx = min(side - 1, Int(left + (Double(selected.x + x - region.x) + 0.5) * modelScale))
        let my = min(side - 1, Int(top + (Double(selected.y + y - region.y) + 0.5) * modelScale))
        mask[my * side + mx] = 1
      }
    }
    guard mask.contains(1), mask.contains(0) else { throw CraftError.invalid("Include some surrounding pixels outside the selection.") }
    let edge = try GenerativeFillEdgeBlend.capture(in: document, selection: selected, gridLimit: side) { x, y in
      let localX = x - Double(region.x), localY = y - Double(region.y)
      var pixel = RasterGeometry.sample(input, x: localX, y: localY, method: .bilinear, clampEdges: true)
      if document.depth != .u8 {
        // Use original coverage before the model input was quantized to RGB8.
        pixel.a = RasterGeometry.sample(crop, x: localX, y: localY, method: .bilinear, clampEdges: true).a
      }
      return pixel
    }
    let expansion = try protectedCanvas.map { try GenerativeExpandBoundary(protected: $0, region: region, composite: crop) }
    return (Recipe(version: 1, selection: selected, region: region, image: image.withUnsafeBytes { Data($0) },
      modelMask: mask.withUnsafeBytes { Data($0) }, selectedPixels: Data(selectedPixels), edge: edge, expansion: expansion), editableMask)
  }
}
