import Foundation
import PhotoCraftCore

#if arch(arm64)
import GuernikaKit
#endif

extension LocalGenerativeFill {
  package static let instructionModelIdentifier = "timbrooks/instruct-pix2pix"

  package static func validateInstructionModel(_ url: URL) throws {
    try withInstructionPredictor(at: url) { _ in }
  }

  package static func withInstructionPredictor<Result>(at url: URL, _ use: (PromptPredictor) throws -> Result) throws -> Result {
    #if arch(arm64)
    if #available(macOS 26, *) {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      try Task.checkCancellation()
      try verifyPromptModelMetadata(at: url, metadata: instructionMetadata, name: "TimBrooks_InstructPix2Pix")
      let unet = try Unet(modelAt: url.appending(path: "Unet.mlmodelc"))
      guard unet.function == .instructions else { throw CraftError.invalid("Choose the InstructPix2Pix model.") }
      let text = try TextEncoder(modelAt: url.appending(path: "TextEncoder.mlmodelc"), configuration: unet.configuration)
      let encoder = try Encoder(modelAt: url.appending(path: "VAEEncoder.mlmodelc"), configuration: unet.configuration)
      let decoder = try Decoder(modelAt: url.appending(path: "VAEDecoder.mlmodelc"), configuration: unet.configuration)
      let pipeline = StableDiffusionPix2PixPipeline(baseUrl: url, textEncoder: text, encoder: encoder, unet: unet,
        decoder: decoder, computeUnits: .cpuAndGPU, reduceMemory: ProcessInfo.processInfo.physicalMemory < 9_000_000_000)
      defer { pipeline.unloadResources() }
      return try use { image, mask, raw, seeds, _ in
        try Task.checkCancellation()
        let prompt = try validatePrompt(raw)
        guard !prompt.isEmpty, (1...maximumVariations).contains(seeds.count), Set(seeds).count == seeds.count,
          image.count == 3 * side * side, image.allSatisfy(\.isFinite), mask.count == side * side,
          mask.allSatisfy({ $0 == 1 }) else {
          throw CraftError.invalid("Prompt to Edit requires a valid whole image, an instruction and distinct seeds.")
        }
        let tokens = text.tokenizer.tokenizeWithWeights(prompt, minCount: text.maxInputLength)
        guard tokens.1.count <= text.maxInputLength else {
          throw CraftError.invalid("The instruction exceeds the model’s token limit. Try a shorter instruction.")
        }
        let source = try promptImage(samples: image, mask: nil)
        return try seeds.map { seed in
          try Task.checkCancellation()
          // The sampled VAE reference depends on this alternative's seed.
          encoder.clearSampleCache()
          let input = SampleInput(prompt: prompt, initImage: source, seed: seed, stepCount: 20, imageGuidanceScale: 1.5)
          let output = try pipeline.generateImages(input: input) { _ in !Task.isCancelled }
          try Task.checkCancellation()
          guard let output, output.width == side, output.height == side else {
            throw CraftError.invalid("The instruction model did not return a 512 × 512 image.")
          }
          return try RasterIO.surface(output, depth: .f32)
        }
      }
    }
    #endif
    throw CraftError.unavailable("Prompt to Edit requires Apple Silicon and macOS 26 or later.")
  }

  #if arch(arm64)
  private static let instructionMetadata = [
    "guernika.json": "72741f58775ff3c7fed60d480c2919bed4cab4673929e5a4caf069c9823d763d",
    "merges.txt": "f526393189112391ce6f9795d4695f704121ce452c3aad1f5335cc41337eba85",
    "vocab.json": "5047b556ce86ccaf6aa22b3ffccfc52d391ea4accdab9c2f2407da5b742d4363",
    "Unet.mlmodelc/metadata.json": "16728c8f1e74530c0da41d29c89795fed2e7c643244b07d6018e930dbfcecb2a",
    "TextEncoder.mlmodelc/metadata.json": "a221a240e1eeb2342f4582f83aecaa8b01f55ab64c16a83a8354d5fe8120bdc7",
    "VAEEncoder.mlmodelc/metadata.json": "0720486c8bb170a694edf629296629c58cde5aa64428ee050dcb37b9ae112050",
    "VAEDecoder.mlmodelc/metadata.json": "b4f12268b7107618856c5aebab8bf28e28f1d082a667f35e093644b9913a616c",
  ]
  #endif
}
