import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LocalGeneratedImage {
  private static let side = LocalGenerativeFill.side
  typealias Prediction = (String, [UInt32], [Float], [Float]) throws -> [Surface]

  static func supports(_ document: CraftDocument) -> Bool {
    document.colorMode == .rgb && document.inkMode == nil && document.restrictedMode == nil
      && !document.isChannelOnly && document.videoTimeline == nil && document.animation == nil
      && document.artboards.isEmpty && document.layers.count < LayerLimits.maximumLayers
  }

  static func prepare(_ document: CraftDocument, model: URL, bookmark: Data?, prompt: String,
    seed: UInt32, count: Int) throws -> Command {
    try prepare(document, prompt: prompt, seed: seed, count: count) { prompt, seeds, image, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt, seeds: seeds, image: image, mask: mask)
    }
  }

  static func prepare(_ document: CraftDocument, prompt raw: String, seed: UInt32, count: Int,
    predict: Prediction) throws -> Command {
    try Task.checkCancellation()
    let prompt = try LocalGenerativeFill.validatePrompt(raw)
    guard supports(document), !prompt.isEmpty, (1...LocalGenerativeFill.maximumVariations).contains(count) else {
      throw CraftError.invalid("Enter an image prompt in a still RGB document with room for a new layer.")
    }
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    let images = try pixels(in: document, reference: nil, prompt: prompt, seeds: seeds, predict: predict)
    let choices = images.map { Layer(name: "Generated Image", content: .raster($0)) }
    var layer = try GenerativeFillVariations.packGeneratedImage(choices, in: document, prompt: prompt, seeds: seeds)
    let scale = Double(max(document.width, document.height)) / Double(side)
    layer.affine = .translation((Double(document.width) - Double(side) * scale) / 2,
      (Double(document.height) - Double(side) * scale) / 2) * .scale(scale, scale)
    var result = document
    result.layers.append(layer)
    result.activeLayerID = layer.id
    try result.validate()
    return .regionRetouch(.init(source: document, result: result, label: "Generate Image"))
  }

  /// Condition on an empty, fully editable model input. Only Generate Similar
  /// supplies pixels, and those come from the chosen variation, never the canvas.
  static func pixels(in document: CraftDocument, reference: Surface?, prompt: String,
    seeds: [UInt32], predict: Prediction) throws -> [Surface] {
    let working = try CraftDocument(width: 1, height: 1)
    let area = side * side
    var image = [Float](repeating: 0, count: 3 * area)
    if let reference {
      guard reference.width == side, reference.height == side else {
        throw CraftError.invalid("The saved generated image has an invalid size.")
      }
      let converted = try ColorManagement.converted(reference, from: document, to: working)
      for y in 0..<side {
        try Task.checkCancellation()
        for x in 0..<side {
          let index = y * side + x
          let pixel = converted.pixel(x: x, y: y)
          image[index] = pixel.r * pixel.a
          image[index + area] = pixel.g * pixel.a
          image[index + 2 * area] = pixel.b * pixel.a
        }
      }
    }
    let results = try predict(prompt, seeds, image, [Float](repeating: 1, count: area))
    try Task.checkCancellation()
    guard results.count == seeds.count, results.allSatisfy({ $0.width == side && $0.height == side }) else {
      throw CraftError.invalid("The local model returned an incomplete image batch.")
    }
    return try results.map { try ColorManagement.converted($0, from: working, to: document) }
  }
}
