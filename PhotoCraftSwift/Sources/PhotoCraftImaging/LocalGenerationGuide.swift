import Foundation
import PhotoCraftCore

#if arch(arm64)
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import CryptoKit
import GuernikaKit
#endif

package struct LocalGenerationGuide: Codable, Sendable {
  package enum Kind: String, Codable, Sendable, CaseIterable {
    case style, composition

    package var title: String { self == .style ? "Style" : "Composition" }
    package var modelName: String { self == .style ? "AesFA" : "ControlNet_Canny" }
  }

  package let kind: Kind
  package let rgba: Data
  private static let side = LocalGenerativeFill.side
  package static let byteCount = side * side * 4

  package init(kind: Kind, rgba: Data) throws {
    self.kind = kind
    self.rgba = rgba
    try validate()
  }

  package func validate() throws {
    guard rgba.count == Self.byteCount else { throw CraftError.invalid("The reference image samples have an invalid size.") }
  }

  package func surface() throws -> Surface {
    try validate()
    let side = Self.side
    var surface = try Surface(width: side, height: side)
    try rgba.withUnsafeBytes { (samples: UnsafeRawBufferPointer) in
      for y in 0..<side {
        try Task.checkCancellation()
        for x in 0..<side {
          let i = (y * side + x) * 4
          surface.setPixel(x: x, y: y, Pixel(Float(samples[i]) / 255, Float(samples[i + 1]) / 255,
            Float(samples[i + 2]) / 255, Float(samples[i + 3]) / 255))
        }
      }
    }
    return surface
  }

  package static func validateModel(_ url: URL, kind: Kind) throws {
    #if arch(arm64)
    if #available(macOS 26, *) {
      switch kind {
      case .composition: _ = try makeControlNet(url)
      case .style: _ = try AesFA(modelURL: url)
      }
      return
    }
    #endif
    throw CraftError.unavailable("Local image references require Apple Silicon and macOS 26 or later.")
  }
}

#if arch(arm64)
extension LocalGenerationGuide {
  static func makeControlNet(_ url: URL) throws -> ControlNet {
    let metadata = url.appending(path: "metadata.json")
    guard let length = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize, (1...16_384).contains(length),
      let bytes = try? Data(contentsOf: metadata),
      SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined()
        == "c7e04690f365a53f1ef04285b89dd4d2df8257b51f9c632936a67363779cd597" else {
      throw CraftError.invalid("Choose the extracted ORIGINAL ControlNet_Canny.mlmodelc package from the setup guide.")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndGPU
    return try ControlNet(modelAt: url, configuration: config)
  }

  func compositionInput(model: URL) throws -> ConditioningInput {
    let image = try RasterIO.displayImage(surface())
    let input = CIImage(cgImage: image)
    let edge = CIFilter.cannyEdgeDetector()
    edge.inputImage = input.clampedToExtent()
    edge.gaussianSigma = 1
    edge.perceptual = true
    edge.thresholdLow = 0.10
    edge.thresholdHigh = 0.22
    edge.hysteresisPasses = 2
    let space = try RasterIO.colorSpace()
    let context = CIContext(options: [.useSoftwareRenderer: true])
    guard let output = edge.outputImage, let map = context.createCGImage(output, from: input.extent,
      format: .RGBA8, colorSpace: space) else {
      throw CraftError.invalid("Could not read composition edges from this reference.")
    }
    let conditioning = ConditioningInput(module: try Self.makeControlNet(model))
    conditioning.image = map
    return conditioning
  }

  struct AesFA {
    private static let modelSide = 224
    private static let mean: [Float] = [0.485, 0.456, 0.406]
    private static let std: [Float] = [0.229, 0.224, 0.225]
    private static var shape: [NSNumber] { [1, 3, NSNumber(value: modelSide), NSNumber(value: modelSide)] }
    private let model: MLModel

    init(modelURL: URL) throws {
      let config = MLModelConfiguration()
      config.computeUnits = .cpuOnly
      let model = try MLModel(contentsOf: modelURL, configuration: config)
      let inputs = model.modelDescription.inputDescriptionsByName
      let outputs = model.modelDescription.outputDescriptionsByName
      guard Set(inputs.keys) == ["content_image", "style_image"], Set(outputs.keys) == ["stylized"],
        (Array(inputs.values) + Array(outputs.values)).allSatisfy({
          $0.multiArrayConstraint?.shape == Self.shape && $0.multiArrayConstraint?.dataType == .float32
        }) else {
        throw CraftError.invalid("Choose the compiled AesFA.mlmodelc package from the setup guide.")
      }
      self.model = model
    }

    func styleInput(_ reference: LocalGenerationGuide) throws -> MLMultiArray {
      try Self.samples(reference.surface())
    }

    func apply(_ generated: Surface, style: MLMultiArray) throws -> Surface {
      try Task.checkCancellation()
      let inputs = try MLDictionaryFeatureProvider(dictionary: [
        "content_image": Self.samples(generated), "style_image": style
      ])
      let values = try model.prediction(from: inputs)
      guard let output = values.featureValue(for: "stylized")?.multiArrayValue, output.shape == Self.shape else {
        throw CraftError.invalid("The Style model returned invalid image dimensions.")
      }
      let size = Self.modelSide
      var styled = try Surface(width: size, height: size, depth: .f32)
      let planes = output.strides.map(\.intValue)
      try output.withUnsafeBufferPointer(ofType: Float.self) { samples in
        for y in 0..<size {
          for x in 0..<size {
            let i = y * planes[2] + x * planes[3]
            let r = samples[i] * Self.std[0] + Self.mean[0]
            let g = samples[i + planes[1]] * Self.std[1] + Self.mean[1]
            let b = samples[i + 2 * planes[1]] * Self.std[2] + Self.mean[2]
            guard r.isFinite, g.isFinite, b.isFinite else {
              throw CraftError.invalid("The Style model returned invalid pixel values.")
            }
            styled.setPixel(x: x, y: y, Pixel(min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)), 1))
          }
        }
      }
      try Task.checkCancellation()
      return try Self.resampled(styled, side: LocalGenerationGuide.side)
    }

    private static func samples(_ source: Surface) throws -> MLMultiArray {
      let size = modelSide
      let surface = try resampled(source, side: size)
      let values = try MLMultiArray(shape: shape, dataType: .float32)
      let area = size * size
      try values.withUnsafeMutableBufferPointer(ofType: Float.self) { samples, _ in
        for y in 0..<size {
          try Task.checkCancellation()
          for x in 0..<size {
            let i = y * size + x
            let pixel = surface.pixel(x: x, y: y)
            samples[i] = (pixel.r - mean[0]) / std[0]
            samples[i + area] = (pixel.g - mean[1]) / std[1]
            samples[i + 2 * area] = (pixel.b - mean[2]) / std[2]
          }
        }
      }
      return values
    }

    private static func resampled(_ surface: Surface, side: Int) throws -> Surface {
      let image = try RasterIO.cgImage(surface)
      let space = try RasterIO.colorSpace()
      guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 32,
        bytesPerRow: side * 16, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue) else {
        throw CraftError.invalid("Could not resize the model image.")
      }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      guard let output = context.makeImage() else { throw CraftError.invalid("Could not resize the model image.") }
      return try RasterIO.surface(output, depth: .f32)
    }
  }
}
#endif
