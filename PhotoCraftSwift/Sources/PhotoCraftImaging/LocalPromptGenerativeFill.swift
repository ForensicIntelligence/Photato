import Foundation
import PhotoCraftCore

#if arch(arm64)
import CoreGraphics
import CoreML
import CryptoKit
import GuernikaKit
#endif

extension LocalGenerativeFill {
  package static let maximumPromptCharacters = 256
  package static let promptModelIdentifier = "runwayml/stable-diffusion-inpainting"

  package enum PromptMode: String, Codable, Sendable {
    case fill
    case similar
  }

  package static func validatePrompt(_ raw: String) throws -> String {
    let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.count <= maximumPromptCharacters,
      !prompt.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw CraftError.invalid("Enter a single-line prompt up to \(maximumPromptCharacters) characters.")
    }
    return prompt
  }

  package static func validatePromptModel(_ url: URL) throws {
    #if arch(arm64)
    if #available(macOS 26, *) {
      try withPromptModel(at: url) { _ in }
      return
    }
    #endif
    throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.")
  }

  package static func prepare(_ document: CraftDocument, model url: URL, prompt raw: String, seed: UInt32) throws -> Command {
    let prompt = try validatePrompt(raw)
    guard !prompt.isEmpty else { return try prepare(document, model: url) }
    return try prepare(document) { image, mask in
      try predictPrompt(image: image, mask: mask, model: url, prompt: prompt, seeds: [seed])[0]
    }
  }

  package static func predictPrompt(
    image: [Float], mask: [Float], model url: URL, prompt raw: String, seeds: [UInt32], mode: PromptMode = .fill
  ) throws -> [Surface] {
    try withPromptPredictor(at: url) { predict in
      try predict(image, mask, raw, seeds, mode)
    }
  }

  package typealias PromptPredictor = ([Float], [Float], String, [UInt32], PromptMode) throws -> [Surface]

  /// Keep the compiled models, tokenizer and prompt cache inside one scoped job.
  package static func withPromptPredictor<Result>(
    at url: URL, guide: LocalGenerationGuide? = nil, guideModel: URL? = nil, _ use: (PromptPredictor) throws -> Result
  ) throws -> Result {
    #if arch(arm64)
    if #available(macOS 26, *) {
      return try withPromptModel(at: url) { pipeline in
        let scoped = guideModel?.startAccessingSecurityScopedResource() == true
        defer { if scoped { guideModel?.stopAccessingSecurityScopedResource() } }
        var stylizer: LocalGenerationGuide.AesFA?
        var style: MLMultiArray?
        if let guide {
          guard let guideModel else { throw CraftError.unavailable("Choose the model for the reference image.") }
          switch guide.kind {
          case .composition:
            guard pipeline.unet.supportsControlNet else {
              throw CraftError.invalid("The prompt model cannot use a Composition reference.")
            }
            pipeline.conditioningInput = [try guide.compositionInput(model: guideModel)]
          case .style:
            let model = try LocalGenerationGuide.AesFA(modelURL: guideModel)
            style = try model.styleInput(guide)
            stylizer = model
          }
        }
        return try use { image, mask, raw, seeds, mode in
          try Task.checkCancellation()
          let prompt = try validatePrompt(raw)
          guard !prompt.isEmpty, (1...maximumVariations).contains(seeds.count),
            Set(seeds).count == seeds.count, image.count == 3 * side * side, mask.count == side * side,
            image.allSatisfy(\.isFinite), mask.allSatisfy({ $0 == 0 || $0 == 1 }) else {
            throw CraftError.invalid("The local prompt model requires a prompt, a valid image and mask, and distinct seeds.")
          }
          let encoder = pipeline.textEncoder
          let tokens = encoder.tokenizer.tokenizeWithWeights(prompt, minCount: encoder.maxInputLength)
          guard tokens.1.count <= encoder.maxInputLength else {
            throw CraftError.invalid("The prompt exceeds the model’s token limit. Try a shorter description.")
          }
          // Keep the original request-scoped behavior for sampled VAE latents.
          // The loaded model and deterministic text embeddings stay resident.
          pipeline.encoder?.clearSampleCache()
          let source = try promptImage(samples: image, mask: nil)
          let selection = try promptImage(samples: [], mask: mask)
          return try seeds.map { seed in
            try Task.checkCancellation()
            let input = SampleInput(prompt: prompt, initImage: source, inpaintMask: selection,
              strength: mode == .similar ? 0.48 : 1, seed: seed, stepCount: 25)
            let output = try pipeline.generateImages(input: input) { _ in !Task.isCancelled }
            try Task.checkCancellation()
            guard let output, output.width == side, output.height == side else {
              throw CraftError.invalid("The local prompt model did not return a 512 × 512 image.")
            }
            let pixels = try RasterIO.surface(output, depth: .f32)
            if let stylizer, let style { return try stylizer.apply(pixels, style: style) }
            return pixels
          }
        }
      }
    }
    #endif
    throw CraftError.unavailable("Local Generative Fill requires Apple Silicon and macOS 26 or later.")
  }

  #if arch(arm64)
  @available(macOS 26, *)
  private static func withPromptModel<T>(at url: URL, use: (StableDiffusionMainPipeline) throws -> T) throws -> T {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    // The tested Core ML conversion fixes the tokenizer and the shapes expected by GuernikaKit.
    try verifyPromptModelMetadata(at: url, metadata: promptModelMetadata, name: "Runway_SD1.5_Inpaint")
    let unet = try Unet(modelAt: url.appending(path: "Unet.mlmodelc"))
    let encoder = try Encoder(modelAt: url.appending(path: "VAEEncoder.mlmodelc"), configuration: unet.configuration)
    let decoder = try Decoder(modelAt: url.appending(path: "VAEDecoder.mlmodelc"), configuration: unet.configuration)
    let text = try TextEncoder(modelAt: url.appending(path: "TextEncoder.mlmodelc"), configuration: unet.configuration)
    let pipeline = StableDiffusionMainPipeline(baseUrl: url, textEncoder: text, encoder: encoder, unet: unet,
      decoder: decoder, computeUnits: .cpuAndGPU, reduceMemory: ProcessInfo.processInfo.physicalMemory < 9_000_000_000)
    defer { pipeline.unloadResources() }
    return try use(pipeline)
  }

  static func verifyPromptModelMetadata(at url: URL, metadata: [String: String], name: String) throws {
    for (relativePath, expected) in metadata {
      let file = url.appending(path: relativePath)
      guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
        let data = try? Data(contentsOf: file),
        SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else {
        throw CraftError.invalid("Choose the extracted \(name) model folder linked in the setup guide.")
      }
    }
    for relativePath in ["TextEncoder.mlmodelc/vocab.json", "TextEncoder.mlmodelc/added_vocab.json"] {
      guard !FileManager.default.fileExists(atPath: url.appending(path: relativePath).path) else {
        throw CraftError.invalid("Choose the unmodified \(name) folder.")
      }
    }
  }

  private static let promptModelMetadata = [
    "guernika.json": "519b08c10c8216bd99e4f29bb98864c0b07b65d1462f4324e0c4aae76e44379d",
    "merges.txt": "f526393189112391ce6f9795d4695f704121ce452c3aad1f5335cc41337eba85",
    "vocab.json": "5047b556ce86ccaf6aa22b3ffccfc52d391ea4accdab9c2f2407da5b742d4363",
    "TextEncoder.mlmodelc/metadata.json": "6bf8e3ead7f3edaccab4b19b73ce4a5e5c6893a393876b53ff45734e6bc6ff8f",
    "Unet.mlmodelc/metadata.json": "983ac6291aab0cca44fd2c78814af5b75e891645ce3cf52fd26c931997cee73d",
    "VAEDecoder.mlmodelc/metadata.json": "febea1dd676a7d2321c6c691f0a74960844d323e9a84e78301634aceb2f55c9e",
    "VAEEncoder.mlmodelc/metadata.json": "3f1e8d8e110e49ad8388d348816e96d656c60ac054355ef631efc59f7285b367",
  ]

  static func promptImage(samples: [Float], mask: [Float]?) throws -> CGImage {
    let count = side * side
    var bytes = [UInt8](repeating: 0, count: count * 4)
    if let mask {
      // Guernika reads mask coverage from alpha. Opaque pixels designate the edit area.
      for i in 0..<count { bytes[4 * i + 3] = mask[i] > 0 ? 255 : 0 }
    } else {
      for i in 0..<count {
        bytes[4 * i] = UInt8((unit(samples[i]) * 255).rounded())
        bytes[4 * i + 1] = UInt8((unit(samples[count + i]) * 255).rounded())
        bytes[4 * i + 2] = UInt8((unit(samples[2 * count + i]) * 255).rounded())
        bytes[4 * i + 3] = 255
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
      let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: side * 4, space: try RasterIO.colorSpace(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .relativeColorimetric) else {
      throw CraftError.invalid("Could not create the local prompt model input.")
    }
    return image
  }
  #endif
}
