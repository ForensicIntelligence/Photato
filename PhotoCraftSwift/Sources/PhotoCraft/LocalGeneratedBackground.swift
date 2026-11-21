import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LocalGeneratedBackground {
  static let defaultPrompt = "a natural background matching the subject’s lighting and perspective"

  /// Samples and mask from the original cutout, in the model's square input space.
  struct Context: Codable {
    let width: Int
    let height: Int
    let image: Data
    let mask: Data

    private static let count = LocalGenerativeFill.side * LocalGenerativeFill.side
    private static let border = 1
    private static let artworkSide = LocalGenerativeFill.side - 2 * border
    private var x: Int { (LocalGenerativeFill.side - width) / 2 }
    private var y: Int { (LocalGenerativeFill.side - height) / 2 }
    private var storedWidth: Int { width + 2 * Self.border }
    private var storedHeight: Int { height + 2 * Self.border }
    private var outputBounds: IntRect {
      IntRect(x: x - Self.border, y: y - Self.border, width: storedWidth, height: storedHeight)
    }

    init(in document: CraftDocument, subject: Layer) throws {
      let side = LocalGenerativeFill.side
      let request = try GeneratedBackground.referenceRequest(width: document.width, height: document.height, maximumSide: Self.artworkSide)
      width = request.width
      height = request.height
      var referenceLayer = subject
      referenceLayer.style = nil
      let coverage = try Renderer.clippingCoveragePreview(referenceLayer, in: document, request: request)
      let reference = try ColorManagement.converted(coverage, from: document, to: CraftDocument(width: 1, height: 1))
      let left = (side - width) / 2, top = (side - height) / 2
      var samples = [Float](repeating: 0, count: 3 * Self.count)
      var selection = [Float](repeating: 1, count: Self.count)
      var hasSubject = false, hasBackground = false
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          let pixel = reference.pixel(x: x, y: y)
          let index = (top + y) * side + left + x
          if pixel.a >= 0.5 {
            selection[index] = 0
            hasSubject = true
          } else {
            hasBackground = true
          }
          samples[index] = pixel.r * pixel.a
          samples[index + Self.count] = pixel.g * pixel.a
          samples[index + 2 * Self.count] = pixel.b * pixel.a
        }
      }
      guard hasSubject && hasBackground else {
        throw CraftError.invalid("Adjust the layer mask so it includes both a visible subject and an open background.")
      }
      image = samples.withUnsafeBytes { Data($0) }
      mask = selection.withUnsafeBytes { Data($0) }
    }

    func encoded() throws -> Data {
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      return try encoder.encode(self)
    }

    static func decode(_ data: Data, matching source: CraftDocument) throws -> Self {
      guard (1...4_200_000).contains(data.count) else { throw invalid }
      let context = try PropertyListDecoder().decode(Self.self, from: data)
      guard (1...artworkSide).contains(context.width), (1...artworkSide).contains(context.height),
        context.storedWidth == source.width, context.storedHeight == source.height,
        context.image.count == 3 * count * MemoryLayout<Float>.stride,
        context.mask.count == count * MemoryLayout<Float>.stride else { throw invalid }
      return context
    }

    func patches(in document: CraftDocument, reference: Surface? = nil,
      predict: ([Float], [Float]) throws -> [Surface]) throws -> [Surface] {
      let working = try CraftDocument(width: 1, height: 1)
      var pixels = Self.samples(image)
      let mask = Self.samples(mask)
      if let reference {
        guard reference.width == storedWidth, reference.height == storedHeight else { throw Self.invalid }
        let source = try ColorManagement.converted(reference, from: document, to: working)
        for row in 0..<height {
          try Task.checkCancellation()
          for col in 0..<width {
            let i = (y + row) * LocalGenerativeFill.side + x + col
            guard mask[i] == 1 else { continue }
            let p = source.pixel(x: col + Self.border, y: row + Self.border)
            pixels[i] += (p.r - pixels[i]) * p.a
            pixels[i + Self.count] += (p.g - pixels[i + Self.count]) * p.a
            pixels[i + 2 * Self.count] += (p.b - pixels[i + 2 * Self.count]) * p.a
          }
        }
      }
      return try predict(pixels, mask).map { output in
        let side = LocalGenerativeFill.side
        guard output.width == side, output.height == side else { throw Self.invalid }
        return try ColorManagement.converted(output.cropped(to: outputBounds), from: working, to: document)
      }
    }

    func placement(in document: CraftDocument) -> Transform2D {
      // Preserve a modeled pixel beyond each canvas edge for bilinear sampling.
      .scale(Double(document.width) / Double(width), Double(document.height) / Double(height)) *
        .translation(Double(-Self.border), Double(-Self.border))
    }

    private static func samples(_ data: Data) -> [Float] {
      var output = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
      _ = output.withUnsafeMutableBytes { data.copyBytes(to: $0) }
      return output
    }

    private static let invalid = CraftError.invalid("The saved Generative Background context is invalid.")
  }

  static func prepare(_ document: CraftDocument, model: URL, bookmark: Data?, prompt: String,
    seed: UInt32, count: Int) throws -> Command {
    try prepare(document, prompt: prompt, seed: seed, count: count) { prompt, seeds, image, mask in
      try GenerativeFillWorker.run(model: model, bookmark: bookmark, prompt: prompt, seeds: seeds, image: image, mask: mask)
    }
  }

  static func prepare(_ document: CraftDocument, prompt: String, seed: UInt32, count: Int,
    predict: (String, [UInt32], [Float], [Float]) throws -> [Surface]) throws -> Command {
    try Task.checkCancellation()
    guard GeneratedBackground.foreground(in: document) != nil,
      let target = document.layers.firstIndex(where: { $0.id == document.activeLayerID }),
      (1...LocalGenerativeFill.maximumVariations).contains(count) else {
      throw CraftError.invalid("Select a visible pixel layer with an enabled subject mask. Use Remove Background first.")
    }
    let prompt = try LocalGenerativeFill.validatePrompt(prompt)
    let effectivePrompt = prompt.isEmpty ? defaultPrompt : prompt
    let context = try Context(in: document, subject: document.layers[target])
    let seeds = (0..<count).map { seed &+ UInt32($0) }
    let results = try context.patches(in: document) { image, mask in
      try predict(effectivePrompt, seeds, image, mask)
    }
    guard results.count == count else { throw CraftError.invalid("The local model returned an incomplete background batch.") }
    let choices = results.map { Layer(name: "Generated Background", content: .raster($0)) }
    var layer = try GenerativeFillVariations.pack(choices, in: document, prompt: effectivePrompt, seeds: seeds,
      context: context.encoded(), forBackground: true)
    layer.affine = context.placement(in: document)
    var edited = document
    edited.layers.insert(layer, at: target)
    edited.activeLayerID = layer.id
    try edited.validate()
    return .regionRetouch(.init(source: document, result: edited, label: "Generate Background"))
  }
}
