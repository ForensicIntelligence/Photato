import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LocalPromptEdit {
  private static let side = LocalGenerativeFill.side
  typealias Prediction = LocalGeneratedImage.Prediction

  static func target(in document: CraftDocument) -> Layer? {
    guard LocalGeneratedImage.supports(document), let active = document.activeLayerID,
      let position = document.layers.firstIndex(where: { $0.id == active }) else { return nil }
    let layer = document.layers[position]
    guard layer.parentID == nil, layer.visible, layer.opacity > 0, !layer.isClipped, layer.style == nil,
      case .raster(let pixels) = layer.content, pixels.tileCount > 0 || pixels.defaultPixel.a > 0 else { return nil }
    if let next = document.layers.dropFirst(position + 1).first(where: { $0.parentID == nil }), next.isClipped {
      return nil
    }
    let generated = layer.sourceTags?[PSDCodec.fillVariationTag] != nil || layer.sourceTags?[GeneratedVariations.key] != nil
      || layer.sourceTags?[GeneratedImageStorage.recordKey] != nil
    guard layer.smartObject == nil || generated else { return nil }
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    if let mask = document.selectionMask {
      guard mask.bounds == canvas, (try? mask.isFullCoverage) == true else { return nil }
    } else if document.selection != nil || generated {
      guard document.selection == canvas else { return nil }
    }
    return layer
  }

  static func prepare(_ document: CraftDocument, targetID: UUID, model: URL, bookmark: Data?, prompt: String,
    seed: UInt32, count: Int) throws -> Command {
    try prepare(document, targetID: targetID, prompt: prompt, seed: seed, count: count) { prompt, seeds, image, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt, seeds: seeds, image: image, mask: mask,
        instructions: true)
    }
  }

  static func prepare(_ document: CraftDocument, targetID: UUID, prompt raw: String, seed: UInt32, count: Int,
    predict: Prediction) throws -> Command {
    let prompt = try LocalGenerativeFill.validatePrompt(raw)
    guard let target = target(in: document), target.id == targetID, !prompt.isEmpty,
      let index = document.layers.firstIndex(where: { $0.id == targetID }),
      (1...LocalGenerativeFill.maximumVariations).contains(count) else {
      throw CraftError.invalid("Select a visible pixel layer and enter an instruction for the whole image.")
    }
    let context = try Context(in: document, layer: target)
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    let patches = try context.pixels(in: document, reference: nil, prompt: prompt, seeds: seeds, predict: predict)
    let choices = patches.map { Layer(name: "Prompt Edit", content: .raster($0)) }
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    var layer = try GenerativeFillVariations.packModelImages(choices, in: document, prompt: prompt, seeds: seeds,
      instructionContext: encoder.encode(context))
    layer.affine = .scale(Double(document.width) / Double(context.width), Double(document.height) / Double(context.height))
      * .translation(-1, -1)
    layer.opacity = target.opacity
    layer.blendMode = target.blendMode
    var result = document
    result.layers[index].visible = false
    result.layers.insert(layer, at: index + 1)
    result.activeLayerID = layer.id
    try result.validate()
    return .regionRetouch(.init(source: document, result: result, label: "Prompt to Edit"))
  }

  /// A bounded, unmodified visual source for retries. Its stored opacity also
  /// keeps generated RGB from filling transparent portions of the source layer.
  struct Context: Codable {
    private static let invalid = CraftError.invalid("The saved Prompt to Edit reference is invalid.")
    let width: Int
    let height: Int
    let rgba: Data
    private var insetX: Int { (side - width) / 2 }
    private var insetY: Int { (side - height) / 2 }

    init(in document: CraftDocument, layer: Layer) throws {
      let request = try GeneratedBackground.referenceRequest(width: document.width, height: document.height, maximumSide: side - 2)
      let coverage = try Renderer.clippingCoveragePreview(layer, in: document, request: request)
      let working = try CraftDocument(width: 1, height: 1)
      let reference = try ColorManagement.converted(coverage, from: document, to: working)
      width = request.width
      height = request.height
      rgba = try reference.rgbaData(depth: .u8)
      guard stride(from: 3, to: rgba.count, by: 4).contains(where: { rgba[$0] > 0 }) else {
        throw CraftError.invalid("The selected layer has no visible pixels to edit in this canvas.")
      }
    }

    static func decode(_ bytes: Data, matching inner: CraftDocument) throws -> Self {
      guard bytes.count <= side * side * 4 + 1024 else { throw invalid }
      let context = try PropertyListDecoder().decode(Self.self, from: bytes)
      guard (1...side - 2).contains(context.width), (1...side - 2).contains(context.height),
        context.width + 2 == inner.width, context.height + 2 == inner.height,
        context.rgba.count == context.width * context.height * 4 else { throw invalid }
      return context
    }

    func pixels(in document: CraftDocument, reference: Surface?, prompt: String, seeds: [UInt32],
      predict: Prediction) throws -> [Surface] {
      let working = try CraftDocument(width: 1, height: 1)
      let previous: Surface?
      if let reference {
        guard reference.width == width + 2, reference.height == height + 2 else { throw Self.invalid }
        previous = try ColorManagement.converted(reference, from: document, to: working)
      } else {
        previous = nil
      }
      let area = side * side
      var image = [Float](repeating: 0, count: 3 * area)
      let original = [UInt8](rgba)
      for y in 0..<side {
        try Task.checkCancellation()
        let vy = min(height - 1, max(0, y - insetY))
        for x in 0..<side {
          let vx = min(width - 1, max(0, x - insetX))
          let source = (vy * width + vx) * 4
          let alpha = Float(original[source + 3]) / 255
          let pixel = previous?.pixel(x: vx + 1, y: vy + 1)
            ?? Pixel(Float(original[source]) / 255, Float(original[source + 1]) / 255, Float(original[source + 2]) / 255)
          let offset = y * side + x
          image[offset] = 0.5 + (pixel.r - 0.5) * alpha
          image[offset + area] = 0.5 + (pixel.g - 0.5) * alpha
          image[offset + 2 * area] = 0.5 + (pixel.b - 0.5) * alpha
        }
      }
      let output = try predict(prompt, seeds, image, [Float](repeating: 1, count: area))
      try Task.checkCancellation()
      guard output.count == seeds.count, output.allSatisfy({ $0.width == side && $0.height == side }) else {
        throw CraftError.invalid("The local editing model returned an incomplete batch.")
      }
      let areaWithBorder = IntRect(x: insetX - 1, y: insetY - 1, width: width + 2, height: height + 2)
      return try output.map { surface in
        var patch = try surface.cropped(to: areaWithBorder)
        patch.mapPixels { x, y, pixel in
          let vx = min(width - 1, max(0, x - 1)), vy = min(height - 1, max(0, y - 1))
          return Pixel(pixel.r, pixel.g, pixel.b, Float(original[(vy * width + vx) * 4 + 3]) / 255)
        }
        try Task.checkCancellation()
        return try ColorManagement.converted(patch, from: working, to: document)
      }
    }
  }
}
