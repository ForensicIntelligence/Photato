import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum GenerativeExpand {
  static func supports(_ document: CraftDocument) -> Bool {
    document.colorMode == .rgb && document.inkMode == nil && document.restrictedMode == nil &&
      !document.isChannelOnly && document.videoTimeline == nil && document.animation == nil &&
      document.artboards.isEmpty && document.layers.count < LayerLimits.maximumLayers
  }

  static func protectedCanvas(for request: CropRequest, in document: CraftDocument) throws -> IntRect {
    try request.validate()
    guard supports(document) else {
      throw CraftError.unsupported("Generative Expand requires a still RGB document with room for another layer.")
    }
    guard request.angle == 0, request.x <= 0, request.y <= 0,
      request.x + request.width >= document.width, request.y + request.height >= document.height,
      request.width != document.width || request.height != document.height else {
      throw CraftError.invalid("Drag the crop handles outward to extend the canvas without cutting or rotating it.")
    }
    return IntRect(x: -request.x, y: -request.y, width: document.width, height: document.height)
  }

  static func prepare(
    _ request: CropRequest, in original: CraftDocument, model: URL, bookmark: Data?,
    prompt raw: String, seed: UInt32, count: Int
  ) throws -> Command {
    let prompt = try LocalGenerativeFill.validatePrompt(raw)
    if prompt.isEmpty {
      return try LocalGenerativeFill.withContextModel(model) { predict in
        try prepare(request, in: original, prompt: prompt, seed: seed, count: count) { image, mask in
          [try predict(image, mask)]
        }
      }
    }
    return try prepare(request, in: original, prompt: prompt, seed: seed, count: count, predictWindow: { variation, image, mask in
      let result = try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt,
        seeds: [seed &+ UInt32(variation)], image: image, mask: mask)
      guard let patch = result.first else { throw CraftError.invalid("The model returned no Generative Expand window.") }
      return patch
    }) { image, mask in
      let seeds = (0..<count).map { seed &+ UInt32($0) }
      return try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt,
        seeds: seeds, image: image, mask: mask)
    }
  }

  static func prepare(
    _ request: CropRequest, in original: CraftDocument, prompt: String, seed: UInt32, count: Int,
    predict: ([Float], [Float]) throws -> [Surface]
  ) throws -> Command {
    try prepare(request, in: original, prompt: prompt, seed: seed, count: count, predictWindow: { variation, image, mask in
      let results = try predict(image, mask)
      guard results.count == count else { throw CraftError.invalid("The model returned the wrong number of variations.") }
      return results[variation]
    }, predict: predict)
  }

  private static func prepare(
    _ request: CropRequest, in original: CraftDocument, prompt: String, seed: UInt32, count: Int,
    predictWindow: (Int, [Float], [Float]) throws -> Surface,
    predict: ([Float], [Float]) throws -> [Surface]
  ) throws -> Command {
    guard (1...LocalGenerativeFill.maximumVariations).contains(count), !prompt.isEmpty || count == 1 else {
      throw CraftError.invalid("Multiple variations require a text prompt.")
    }
    let kept = try protectedCanvas(for: request, in: original)
    let right = kept.x + kept.width, bottom = kept.y + kept.height
    let frame = IntRect(x: request.x, y: request.y, width: request.width, height: request.height)
    let strips = [
      IntRect(x: 0, y: 0, width: frame.width, height: kept.y),
      IntRect(x: 0, y: kept.y, width: kept.x, height: kept.height),
      IntRect(x: right, y: kept.y, width: frame.width - right, height: kept.height),
      IntRect(x: 0, y: bottom, width: frame.width, height: frame.height - bottom),
    ].filter { $0.width > 0 && $0.height > 0 }
    guard let minX = strips.map(\.x).min(), let minY = strips.map(\.y).min(),
      let maxX = strips.map({ $0.x + $0.width }).max(), let maxY = strips.map({ $0.y + $0.height }).max() else {
      throw CraftError.invalid("Generative Expand needs room outside the original canvas.")
    }
    let width = maxX - minX, height = maxY - minY
    var framed = try CanvasFrameGeometry.reframed(original, bounds: frame)
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    if max(width, height) > LocalGenerativeFill.maximumSelectionSide ||
      width > LocalGenerativeFill.maximumSelectionPixels / height {
      let border = IntRect(x: minX, y: minY, width: width, height: height)
      let windows = GenerativeExpandWindows(frame: frame, protected: kept, border: border, strips: strips, depth: original.depth)
      let layers = try windows.render(original: original, count: count, predict: predictWindow)
      let layer = count == 1 ? layers[0]
        : try GenerativeFillVariations.pack(layers, in: framed, prompt: prompt, seeds: seeds, fileBacked: true)
      return try finish(layer, original: original, framed: &framed)
    }
    let selection = try SelectionMask.sampledCoverage(width: frame.width, height: frame.height, regions: strips) { x, y in
      kept.contains(x, y) ? 0 : 255
    }
    framed.setCoverageSelection(selection)
    let (recipe, coverage) = try LocalGenerativeFill.capture(framed, protectedCanvas: kept)
    let patches = try recipe.patches(in: framed, predict: predict)
    guard patches.count == count else { throw CraftError.invalid("The local model returned the wrong number of variations.") }
    let layers = patches.map { pixels in
      var layer = Layer(name: "Generative Expand", content: .raster(pixels))
      layer.x = recipe.selection.x
      layer.y = recipe.selection.y
      layer.mask = coverage
      return layer
    }
    let layer: Layer
    if prompt.isEmpty {
      layer = layers[0]
    } else {
      layer = try GenerativeFillVariations.pack(layers, in: framed, prompt: prompt, seeds: seeds, context: recipe.encoded())
    }
    return try finish(layer, original: original, framed: &framed)
  }

  private static func finish(_ layer: Layer, original: CraftDocument, framed: inout CraftDocument) throws -> Command {
    try Command.generativeFill(layer).apply(to: &framed)
    framed.setCoverageSelection(nil)
    return .cropDocument(CropEdit(source: original, result: framed, kind: .generativeExpand))
  }
}
