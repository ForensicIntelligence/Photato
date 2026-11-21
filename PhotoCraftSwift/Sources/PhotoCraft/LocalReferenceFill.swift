import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LocalReferenceFill {
  typealias LeafPredictor = (Data, [UInt32], [Float], [Float]) throws -> [Surface]

  static func prepare(_ document: CraftDocument, image: ImageGenerationReference, options: ReferenceInpainting.Options,
    model: URL, bookmark: Data?, seed: UInt32, count: Int) async throws -> Command {
    let pixels = try RasterIO.surface(image.image)
    let reference = try await ReferenceInpainting.normalize(pixels, scope: options.scope)
    return try await prepare(document, reference: reference, options: options, seed: seed, count: count) {
      reference, seeds, source, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: "", seeds: seeds, image: source, mask: mask,
        exemplar: reference)
    }
  }

  static func prepare(_ document: CraftDocument, reference: Data, options: ReferenceInpainting.Options,
    seed: UInt32, count: Int, detector: any ForegroundDetecting = VisionForegroundDetector(),
    predict: LeafPredictor) async throws -> Command {
    guard (1...LocalGenerativeFill.maximumVariations).contains(count) else {
      throw CraftError.invalid("Choose one to three reference-guided variations.")
    }
    let (recipe, coverage) = try LocalGenerativeFill.capture(document)
    let context = try ReferenceInpainting.Context(recipe: recipe, reference: reference, options: options)
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    let patches = try await patches(in: document, context: context, recipe: recipe, seeds: seeds, detector: detector,
      predict: predict)
    let layers = patches.map { patch -> Layer in
      var layer = Layer(name: "Generative Fill", content: .raster(patch))
      layer.x = recipe.selection.x
      layer.y = recipe.selection.y
      layer.mask = coverage
      return layer
    }
    return .generativeFill(try GenerativeFillVariations.pack(layers, in: document, prompt: "", seeds: seeds,
      context: context.encoded(), referenceOptions: options))
  }

  static func patches(in document: CraftDocument, context: ReferenceInpainting.Context, recipe: LocalGenerativeFill.Recipe,
    seeds: [UInt32], variation: Surface? = nil, detector: any ForegroundDetecting = VisionForegroundDetector(),
    predict: LeafPredictor) async throws -> [Surface] {
    let reference: Data
    if let variation {
      let srgb = try CraftDocument(width: 1, height: 1)
      let pixels = try ColorManagement.converted(variation, from: document, to: srgb)
      reference = try await ReferenceInpainting.normalize(pixels, scope: context.options.scope)
    } else {
      reference = context.reference
    }
    let results = try recipe.patches(in: document) { image, mask in
      try predict(reference, seeds, image, mask)
    }
    guard results.count == seeds.count else { throw CraftError.invalid("Local inference returned an incomplete batch.") }
    guard context.options.intent == .place else { return results }
    var placed: [Surface] = []
    placed.reserveCapacity(results.count)
    for result in results {
      try Task.checkCancellation()
      placed.append(try await ReferenceInpainting.place(result, in: document, detector: detector))
    }
    return placed
  }
}
