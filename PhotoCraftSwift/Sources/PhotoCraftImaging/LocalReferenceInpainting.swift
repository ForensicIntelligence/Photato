import Foundation
import PhotoCraftCore

#if arch(arm64)
import GuernikaKit
#endif

extension LocalGenerativeFill {
  package static let referenceModelIdentifier = "Fantasy-Studio/Paint-by-Example"
  package static let exemplarSide = 224
  package static let exemplarByteCount = exemplarSide * exemplarSide * 4

  package static func validateReferenceModel(_ url: URL) throws {
    #if arch(arm64)
    if #available(macOS 26, *) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do { _ = try PaintByExamplePipeline(resources: url) }
      catch { throw CraftError.invalid("Choose the PaintByExampleCoreML folder from the setup guide.") }
      return
    }
    #endif
    throw CraftError.unavailable("Reference-guided Fill requires Apple Silicon and macOS 26 or later.")
  }

  package static func withReferencePredictor<Result>(at url: URL, reference: Data,
    _ use: (PromptPredictor) throws -> Result) throws -> Result {
    #if arch(arm64)
    if #available(macOS 26, *) {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try Task.checkCancellation()
      guard reference.count == exemplarByteCount else { throw CraftError.invalid("Invalid saved reference image.") }
      let pipeline = try PaintByExamplePipeline(resources: url,
        reduceMemory: ProcessInfo.processInfo.physicalMemory < 10_000_000_000)
      defer { pipeline.unloadResources() }
      let area = exemplarSide * exemplarSide
      let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
      let std: [Float] = [0.26862954, 0.26130258, 0.27577711]
      let normalized: [Float] = reference.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        (0..<(area * 3)).map { index in
          let channel = index / area
          return (Float(bytes[index % area * 4 + channel]) / 255 - mean[channel]) / std[channel]
        }
      }
      let embedding = try pipeline.referenceEmbedding(normalized)
      return try use { source, mask, prompt, seeds, _ in
        guard prompt.isEmpty, (1...maximumVariations).contains(seeds.count), Set(seeds).count == seeds.count else {
          throw CraftError.invalid("Reference-guided Fill requires an image and distinct variation seeds.")
        }
        return try seeds.map { seed in
          let image = try pipeline.generate(image: source, mask: mask, embedding: embedding, seed: seed)
          guard image.width == side, image.height == side else {
            throw CraftError.invalid("The reference model returned invalid image dimensions.")
          }
          return try RasterIO.surface(image, depth: .f32)
        }
      }
    }
    #endif
    throw CraftError.unavailable("Reference-guided Fill requires Apple Silicon and macOS 26 or later.")
  }
}

package enum ReferenceInpainting {
  package struct Options: Codable, Equatable, Sendable {
    package enum Scope: String, Codable, Sendable, CaseIterable {
      case object, wholeImage
      package var title: String { self == .object ? "Object" : "Whole Image" }
    }

    package enum Intent: String, Codable, Sendable, CaseIterable {
      case swap, place
      package var title: String { self == .swap ? "Swap" : "Place" }
    }

    package var scope: Scope = .object
    package var intent: Intent = .swap
    package init(scope: Scope = .object, intent: Intent = .swap) {
      self.scope = scope
      self.intent = intent
    }
  }

  package struct Context: Codable, Sendable {
    package static let maximumBytes = LocalGenerativeFill.Recipe.maximumBytes + LocalGenerativeFill.exemplarByteCount + 1024
    let version: Int
    let recipe: Data
    package let reference: Data
    package let options: Options

    package init(recipe: LocalGenerativeFill.Recipe, reference: Data, options: Options) throws {
      guard reference.count == LocalGenerativeFill.exemplarByteCount else {
        throw CraftError.invalid("The reference image was not prepared for inpainting.")
      }
      version = 1
      self.recipe = try recipe.encoded()
      self.reference = reference
      self.options = options
    }

    package func encoded() throws -> Data {
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      let bytes = try encoder.encode(self)
      guard bytes.count <= Self.maximumBytes else { throw CraftError.invalid("The saved reference fill context is too large.") }
      return bytes
    }

    package static func decode(_ bytes: Data, options: Options, source: CraftDocument) throws -> (Self, LocalGenerativeFill.Recipe) {
      guard (1...maximumBytes).contains(bytes.count) else { throw CraftError.invalid("Invalid saved reference fill context.") }
      let context = try PropertyListDecoder().decode(Self.self, from: bytes)
      let recipe = try LocalGenerativeFill.Recipe.decode(context.recipe)
      guard context.version == 1, context.options == options, context.reference.count == LocalGenerativeFill.exemplarByteCount,
        recipe.selection.width == source.width, recipe.selection.height == source.height else {
        throw CraftError.invalid("The reference no longer matches the saved fill layer.")
      }
      return (context, recipe)
    }
  }

  package static func normalize(_ input: Surface, scope: Options.Scope,
    detector: VisionForegroundDetector = .init()) async throws -> Data {
    let proxy = try bounded(input, maximumSide: LocalGenerativeFill.side)
    let frame = IntRect(x: 0, y: 0, width: proxy.width, height: proxy.height)
    var pixels = proxy
    var bounds = frame
    if scope == .object {
      let rgba = try proxy.rgbaData(depth: .u8)
      let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
      let subject: SelectionMask
      if alpha.contains(where: { $0 < 255 }) {
        subject = try SelectionMask(width: proxy.width, height: proxy.height, bytes: alpha)
      } else {
        let candidates = try await detector.masks(for: proxy)
        guard let candidate = candidates.max(by: { first, second in
          let a = first.mask.bounds, b = second.mask.bounds
          return (a.map { $0.width * $0.height } ?? 0) < (b.map { $0.width * $0.height } ?? 0)
        }) else { throw CraftError.invalid("Choose a reference with a distinct foreground object.") }
        subject = candidate.mask
        for y in 0..<proxy.height {
          try Task.checkCancellation()
          for x in 0..<proxy.width {
            var p = proxy.pixel(x: x, y: y)
            p.a = subject.coverage(x: x, y: y)
            pixels.setPixel(x: x, y: y, p)
          }
        }
      }
      guard let subjectBounds = subject.bounds else {
        throw CraftError.invalid("Choose a reference with a visible foreground object.")
      }
      let margin = max(4, max(subjectBounds.width, subjectBounds.height) / 10)
      bounds = IntRect(x: subjectBounds.x - margin, y: subjectBounds.y - margin,
        width: subjectBounds.width + 2 * margin, height: subjectBounds.height + 2 * margin).clipped(toWidth: frame.width, height: frame.height)
    }
    let side = LocalGenerativeFill.exemplarSide
    let scale = Double(side) / Double(max(bounds.width, bounds.height))
    let left = (Double(side) - Double(bounds.width) * scale) / 2
    let top = (Double(side) - Double(bounds.height) * scale) / 2
    var square = try Surface(width: side, height: side, fill: Pixel(0.5, 0.5, 0.5, 1))
    let cropped = try pixels.cropped(to: bounds)
    for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side {
        let sourceX = (Double(x) + 0.5 - left) / scale
        let sourceY = (Double(y) + 0.5 - top) / scale
        guard sourceX >= 0, sourceY >= 0, sourceX < Double(bounds.width), sourceY < Double(bounds.height) else { continue }
        let p = RasterGeometry.sample(cropped, x: sourceX, y: sourceY, method: .bicubic, clampEdges: true)
        square.setPixel(x: x, y: y, Pixel(0.5 + (p.r - 0.5) * p.a, 0.5 + (p.g - 0.5) * p.a,
          0.5 + (p.b - 0.5) * p.a, 1))
      }
    }
    return try square.rgbaData(depth: .u8)
  }

  /// Place colours only the generated subject. The original editable selection
  /// mask still applies above the individual result's intrinsic transparency.
  package static func place(_ patch: Surface, in document: CraftDocument,
    detector: any ForegroundDetecting = VisionForegroundDetector()) async throws -> Surface {
    let srgb = try CraftDocument(width: 1, height: 1)
    let preview = try bounded(ColorManagement.converted(patch, from: document, to: srgb),
      maximumSide: LocalGenerativeFill.side)
    let subject = try await detector.mask(for: preview)
    guard subject.width == preview.width, subject.height == preview.height, subject.bounds != nil,
      try !subject.isFullCoverage else {
      throw CraftError.invalid("No distinct object could be placed. Try a more isolated reference or use Swap.")
    }
    let alpha = try subject.coverageSurface()
    var result = patch
    for y in 0..<patch.height {
      try Task.checkCancellation()
      for x in 0..<patch.width {
        let px = (Double(x) + 0.5) * Double(alpha.width) / Double(patch.width)
        let py = (Double(y) + 0.5) * Double(alpha.height) / Double(patch.height)
        let coverage = RasterGeometry.sample(alpha, x: px, y: py, method: .bilinear, clampEdges: true).r
        var color = patch.pixel(x: x, y: y)
        color.a *= coverage
        result.setPixel(x: x, y: y, color.a == 0 ? .clear : color)
      }
    }
    return result
  }

  private static func bounded(_ input: Surface, maximumSide: Int) throws -> Surface {
    let largest = max(input.width, input.height)
    guard largest > maximumSide else { return input }
    let scale = Double(maximumSide) / Double(largest)
    let width = max(1, Int((Double(input.width) * scale).rounded()))
    let height = max(1, Int((Double(input.height) * scale).rounded()))
    var result = try Surface(width: width, height: height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        result.setPixel(x: x, y: y, RasterGeometry.sample(input, x: (Double(x) + 0.5) / scale,
          y: (Double(y) + 0.5) / scale, method: .bilinear, clampEdges: true))
      }
    }
    return result
  }
}
