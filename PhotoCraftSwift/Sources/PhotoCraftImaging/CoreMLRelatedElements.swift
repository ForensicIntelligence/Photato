import CoreML
import Foundation
import PhotoCraftCore

/// Fixed CLIPSeg prompts and model tensors match the offline converter.
public actor CoreMLRelatedElements: RemoveRelatedElementDetecting {
  public static let modelName = "RelatedElementsV1"
  private static let revision = "999e0328d9e10b484360c477313983f9afdd7050"
  private static let prompts = ["shadow on the ground", "cast shadow", "a reflection in water",
    "a reflected object", "reversed mirror image"]
  private static let side = RemoveRelatedElements.side
  private let model: MLModel

  public init(url: URL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndGPU
    let model = try MLModel(contentsOf: url, configuration: configuration)
    let desc = model.modelDescription
    let metadata = desc.metadata[.creatorDefinedKey] as? [String: String]
    let queries = try metadata?["queries"]?.data(using: .utf8).map { try JSONDecoder().decode([String].self, from: $0) }
    let input = desc.inputDescriptionsByName["pixels"]?.multiArrayConstraint
    let output = desc.outputDescriptionsByName["logits"]?.multiArrayConstraint
    guard metadata?["revision"] == Self.revision, queries == Self.prompts,
      input?.dataType == .float32, input?.shape.map(\.intValue) == [1, 3, Self.side, Self.side],
      output?.dataType == .float32, output?.shape.map(\.intValue) == [Self.prompts.count, Self.side, Self.side] else {
      throw CraftError.invalid("Choose the compiled Photato RelatedElementsV1 model.")
    }
    self.model = model
  }

  public func scores(in image: Surface, for element: RemoveRelatedElement) throws -> [Float] {
    try Task.checkCancellation()
    let pixels = try Self.imageTensor(image)
    let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": pixels]))
    try Task.checkCancellation()
    guard let logits = result.featureValue(for: "logits")?.multiArrayValue,
      logits.dataType == .float32, logits.shape.map(\.intValue) == [Self.prompts.count, Self.side, Self.side] else {
      throw CraftError.invalid("The related elements model returned an unexpected output shape.")
    }
    let strides = logits.strides.map(\.intValue), data = logits.dataPointer.assumingMemoryBound(to: Float.self)
    var scores = [Float](repeating: 0, count: Self.side * Self.side)
    func probability(_ channel: Int, _ offset: Int) throws -> Float {
      let value = data[channel * strides[0] + offset]
      guard value.isFinite else { throw CraftError.invalid("The model returned a nonfinite related element sample.") }
      return 1 / (1 + exp(-value))
    }
    for y in 0..<Self.side {
      try Task.checkCancellation()
      for x in 0..<Self.side {
        let offset = y * strides[1] + x * strides[2]
        let score: Float
        switch element {
        case .shadow:
          score = try max(probability(0, offset), probability(1, offset) - 0.07)
        case .reflection:
          score = try max(probability(3, offset), probability(4, offset) + 0.06)
        }
        scores[y * Self.side + x] = unit(score)
      }
    }
    return scores
  }

  private static func imageTensor(_ image: Surface) throws -> MLMultiArray {
    let tensor = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
    let data = tensor.dataPointer.assumingMemoryBound(to: Float.self), stride = tensor.strides.map(\.intValue)
    let mean = SIMD3<Float>(0.485, 0.456, 0.406), scale = SIMD3<Float>(0.229, 0.224, 0.225)
    let xScale = Double(image.width) / Double(side), yScale = Double(image.height) / Double(side)
    for y in 0..<side {
      try Task.checkCancellation()
      let py = (Double(y) + 0.5) * yScale
      for x in 0..<side {
        let px = (Double(x) + 0.5) * xScale
        let sample = RasterGeometry.sample(image, x: px, y: py, method: .bilinear, clampEdges: true)
        let color = (sample.rgb * sample.a + SIMD3<Float>(repeating: 0.5) * (1 - sample.a) - mean) / scale
        let index = y * stride[2] + x * stride[3]
        data[index] = color.x; data[stride[1] + index] = color.y; data[2 * stride[1] + index] = color.z
      }
    }
    return tensor
  }
}
