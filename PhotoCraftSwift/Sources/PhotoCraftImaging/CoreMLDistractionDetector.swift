import CoreML
import Foundation
import PhotoCraftCore

public struct DistractionProposal: Sendable {
  /// A nil category denotes a person or pet to protect from automatic marking.
  public let category: RemoveDistractionCategory?
  public let bounds: IntRect
  public let confidence: Float
}

/// The vision graph includes frozen OWLv2 text embeddings for a fixed set of
/// distraction labels. Pixels and inference stay on this Mac.
public actor CoreMLDistractionDetector {
  public static let modelName = "DistractionDetectorV1"
  public static let publisherRevision = "cfd3195ba4ea9592eec887ded089f4c08eff231d"
  private static let side = 960
  private static let boxes = 3600
  private static let minimumConfidence: Float = 0.25

  private let model: MLModel
  private let categories: [RemoveDistractionCategory?]

  public init(url: URL) throws {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndGPU
    let model = try MLModel(contentsOf: url, configuration: configuration)
    let description = model.modelDescription
    let metadata = description.metadata[.creatorDefinedKey] as? [String: String]
    guard metadata?["source_revision"] == Self.publisherRevision,
      let queryData = metadata?["query_set"]?.data(using: .utf8),
      let queries = try? JSONDecoder().decode([[String]].self, from: queryData),
      queries.count == 24 && queries.allSatisfy({ row in
        row.count == 2 && (row[0] == "subject" || RemoveDistractionCategory(rawValue: row[0]) != nil)
      }),
      description.inputDescriptionsByName["pixels"]?.multiArrayConstraint?.shape.map(\.intValue) == [1, 3, Self.side, Self.side],
      description.outputDescriptionsByName["boxes"]?.multiArrayConstraint?.shape.map(\.intValue) == [1, Self.boxes, 4],
      description.outputDescriptionsByName["logits"]?.multiArrayConstraint?.shape.map(\.intValue) == [1, Self.boxes, queries.count] else {
      throw CraftError.invalid("Choose the compiled Photato DistractionDetectorV1 model.")
    }
    self.model = model
    categories = queries.map { RemoveDistractionCategory(rawValue: $0[0]) }
  }

  public func proposals(in image: Surface) throws -> [DistractionProposal] {
    try Task.checkCancellation()
    let pixels = try Self.input(image)
    let predictor = try MLDictionaryFeatureProvider(dictionary: ["pixels": pixels])
    let observation = try model.prediction(from: predictor)
    try Task.checkCancellation()
    guard let boxes = observation.featureValue(for: "boxes")?.multiArrayValue,
      let logits = observation.featureValue(for: "logits")?.multiArrayValue,
      boxes.shape.map(\.intValue) == [1, Self.boxes, 4], logits.shape.map(\.intValue) == [1, Self.boxes, categories.count],
      boxes.dataType == .float32, logits.dataType == .float32 else {
      throw CraftError.invalid("The distraction model returned invalid box or score tensors.")
    }
    let boxStrides = boxes.strides.map(\.intValue)
    let logitStrides = logits.strides.map(\.intValue)
    let boxData = boxes.dataPointer.assumingMemoryBound(to: Float.self)
    let logitData = logits.dataPointer.assumingMemoryBound(to: Float.self)
    let extent = Float(max(image.width, image.height))
    let cutoff = log(Self.minimumConfidence / (1 - Self.minimumConfidence))
    var candidates: [(index: Int, proposal: DistractionProposal)] = []
    for row in 0..<Self.boxes {
      if row.isMultiple(of: 256) { try Task.checkCancellation() }
      var best = cutoff, label: Int?
      for query in categories.indices {
        let score = logitData[row * logitStrides[1] + query * logitStrides[2]]
        if score.isFinite, score > best { best = score; label = query }
      }
      guard let label else { continue }
      let coord = (0..<4).map { boxData[row * boxStrides[1] + $0 * boxStrides[2]] }
      guard coord.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { continue }
      let x0 = max(0, Int(floor((coord[0] - coord[2] / 2) * extent)))
      let y0 = max(0, Int(floor((coord[1] - coord[3] / 2) * extent)))
      let x1 = min(image.width, Int(ceil((coord[0] + coord[2] / 2) * extent)))
      let y1 = min(image.height, Int(ceil((coord[1] + coord[3] / 2) * extent)))
      guard x1 - x0 >= 5, y1 - y0 >= 5 else { continue }
      let region = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
      candidates.append((row, .init(category: categories[label], bounds: region, confidence: 1 / (1 + exp(-best)))))
    }
    var kept: [DistractionProposal] = []
    for (_, proposal) in candidates.sorted(by: { a, b in
      a.proposal.confidence == b.proposal.confidence ? a.index < b.index : a.proposal.confidence > b.proposal.confidence
    }) {
      if kept.contains(where: { Self.duplicates($0, proposal) }) { continue }
      kept.append(proposal)
      if kept.count == 24 { break }
    }
    return kept
  }

  static func duplicates(_ first: DistractionProposal, _ second: DistractionProposal) -> Bool {
    // Boxes for distinct categories can overlap when objects touch. Retain both
    // so the local segmentation can separate them before category review.
    guard first.category == second.category else { return false }
    let a = first.bounds, b = second.bounds
    if overlap(a, b) > 0.44 { return true }
    let shared = intersection(a, b)
    let smaller = min(a.width * a.height, b.width * b.height)
    let larger = max(a.width * a.height, b.width * b.height)
    return smaller > 0 && Double(smaller) >= Double(larger) * 0.28
      && Double(shared.width * shared.height) >= Double(smaller) * 0.85
  }

  private static func input(_ image: Surface) throws -> MLMultiArray {
    let pixels = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
    let exposed = pixels.dataPointer.assumingMemoryBound(to: Float.self)
    let plane = side * side
    let mean = SIMD3<Float>(0.48145466, 0.4578275, 0.40821073)
    let sigma = SIMD3<Float>(0.26862954, 0.26130258, 0.27577711)
    let extent = max(image.width, image.height)
    let step = Double(extent) / Double(side)
    // The publisher pads to a square at the bottom and right before normalizing.
    // Sample in that same square so predicted boxes stay in document coordinates.
    let grey = Pixel(0.5, 0.5, 0.5)
    let flat = try image.rgbaData(depth: .u8)
    try flat.withUnsafeBytes { raw in
      let bytes = raw.bindMemory(to: UInt8.self)
      func sample(_ x: Int, _ y: Int) -> SIMD3<Float> {
        let sx = max(0, x), sy = max(0, y)
        guard sx < image.width, sy < image.height else { return grey.rgb }
        let i = (sy * image.width + sx) * 4
        let alpha = Float(bytes[i + 3]) / 255
        let rgb = SIMD3(Float(bytes[i]), Float(bytes[i + 1]), Float(bytes[i + 2])) / 255
        return rgb * alpha + grey.rgb * (1 - alpha)
      }
      for y in 0..<side {
        try Task.checkCancellation()
        let py = (Double(y) + 0.5) * step - 0.5
        let sy = Int(floor(py)), fy = Float(py - Double(sy))
        for x in 0..<side {
          let px = (Double(x) + 0.5) * step - 0.5
          let sx = Int(floor(px)), fx = Float(px - Double(sx))
          let rowA = sample(sx, sy) * (1 - fx) + sample(sx + 1, sy) * fx
          let rowB = sample(sx, sy + 1) * (1 - fx) + sample(sx + 1, sy + 1) * fx
          let normalized = ((rowA * (1 - fy) + rowB * fy) - mean) / sigma
          let position = y * side + x
          exposed[position] = normalized.x
          exposed[plane + position] = normalized.y
          exposed[2 * plane + position] = normalized.z
        }
      }
    }
    return pixels
  }

  static func overlap(_ first: IntRect, _ second: IntRect) -> Double {
    let shared = intersection(first, second)
    let area = shared.width * shared.height
    let union = first.width * first.height + second.width * second.height - area
    return union == 0 ? 0 : Double(area) / Double(union)
  }

  static func intersection(_ a: IntRect, _ b: IntRect) -> IntRect {
    let x = max(a.x, b.x), y = max(a.y, b.y)
    return .init(x: x, y: y, width: max(0, min(a.x + a.width, b.x + b.width) - x),
      height: max(0, min(a.y + a.height, b.y + b.height) - y))
  }
}
