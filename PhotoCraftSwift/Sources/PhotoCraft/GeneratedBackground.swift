import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging

enum ImageGenerationIntent: String, CaseIterable, Sendable {
  case image, background
  var title: String { self == .image ? "New image layer" : "Background below subject" }
}

/// Placement metadata is descriptive, never executable or provider attestation.
struct GeneratedBackgroundRecord: Codable, Equatable, Sendable {
  let version: Int
  let foregroundLayerID: UUID
  let width: Int
  let height: Int
  init(foregroundLayerID: UUID, width: Int, height: Int) {
    version = 1; self.foregroundLayerID = foregroundLayerID
    self.width = width; self.height = height
  }
  func validate() throws {
    guard version == 1, GeneratedBackground.supportsCanvas(width: width, height: height) else {
      throw CraftError.invalid("Invalid generated-background placement record.")
    }
  }
}

enum GeneratedBackground {
  static let contextKey = "PtGB"
  static func supportsCanvas(width: Int, height: Int) -> Bool {
    width > 0 && height > 0 && width <= Surface.maxDimension && height <= Surface.maxDimension
      && width <= Surface.maxPixels / height
  }
  static func referenceRequest(width: Int, height: Int) throws -> RasterPreviewRequest {
    guard supportsCanvas(width: width, height: height) else {
      throw CraftError.invalid("Invalid background-reference canvas.")
    }
    let longest = max(width, height)
    let limit = min(2048, longest)
    // Fix the dominant side exactly instead of flooring a nearly integral
    // floating-point product (8001 * (2048 / 8001) can become2047).
    let w = width == longest ? limit : max(1, Int(Double(width) * Double(limit) / Double(longest)))
    let h = height == longest ? limit : max(1, Int(Double(height) * Double(limit) / Double(longest)))
    return try RasterPreviewRequest(region: .init(x: 0, y: 0, width: width, height: height), width: w, height: h)
  }
  static func foreground(in source: CraftDocument) -> Layer? {
    guard source.colorMode == .rgb, source.restrictedMode == nil, source.inkMode == nil,
      !source.isChannelOnly, source.animation == nil, source.videoTimeline == nil,
      supportsCanvas(width: source.width, height: source.height),
      source.layers.count < LayerLimits.maximumLayers,
      let id = source.activeLayerID, let layer = source.layers.first(where: { $0.id == id }),
      case .raster = layer.content, layer.mask != nil, layer.effectiveMaskProperties.enabled,
      layer.parentID == nil, !layer.isClipped, !layer.isBackground, layer.visible,
      layer.smartObject == nil, layer.sourceProjection == nil else { return nil }
    return layer
  }

  /// Only the visual reference is rendered. Original source pixels and mask
  /// transforms/density/feather remain unchanged in the eventual document.
  static func reference(_ source: CraftDocument) throws -> CGImage {
    try source.validate(); try Task.checkCancellation()
    guard var layer = foreground(in: source) else {
      throw CraftError.invalid("Select a visible, masked pixel layer outside a group. Remove its background first.")
    }
    layer.style = nil
    if (try? ForegroundSelection.checkSize(source.width, source.height)) == nil {
      // Document geometry is independent of the model reference budget. Keep
      // the old admitted path below unchanged, including its resampling order.
      let request = try referenceRequest(width: source.width, height: source.height)
      let reduced = try Renderer.clippingCoveragePreview(layer, in: source, request: request)
      let display = try ColorManagement.converted(reduced, from: source, to: CraftDocument(width: 1, height: 1))
      try Task.checkCancellation()
      return try RasterIO.displayImage(display)
    }
    var pixels = try Renderer.clippingCoverage(layer, in: source)
    let proxyDocument = try CraftDocument(width: 1, height: 1)
    pixels = try ColorManagement.converted(pixels, from: source, to: proxyDocument)
    // Bounded reference, not a promise of the system model's output resolution.
    if max(pixels.width, pixels.height) > 2048 {
      let scale = 2048 / Double(max(pixels.width, pixels.height))
      pixels = try Renderer.resize(pixels, width: max(1, Int(Double(pixels.width) * scale)),
        height: max(1, Int(Double(pixels.height) * scale)))
    }
    try Task.checkCancellation()
    return try RasterIO.displayImage(pixels)
  }

  static func record(_ layer: Layer) throws -> GeneratedBackgroundRecord? {
    guard let data = try layer.sourceTags?[contextKey] ?? GeneratedVariations.metadata(layer,key:contextKey) else { return nil }
    guard data.count <= 4096 else { throw CraftError.invalid("Generated-background metadata exceeds its limit.") }
    let record = try JSONDecoder().decode(GeneratedBackgroundRecord.self, from: data)
    try record.validate(); return record
  }

  static func prepareLayer(_ bytes: Data, source: CraftDocument, requestID: UUID,
    sourceRevision: UUID, initialPrompt: String, startedAt: Date, acceptedAt: Date,
    processing: PhotoCraftAI.GenerationRecord.Processing, resultStyle: String?) throws -> Layer {
    guard let foreground = foreground(in: source) else {
      throw CraftError.invalid("The masked foreground is no longer available.")
    }
    var layer = try GeneratedImageStorage.preparedLayer(bytes, source: source, requestID: requestID,
      sourceRevision: sourceRevision, initialPrompt: initialPrompt, startedAt: startedAt,
      acceptedAt: acceptedAt, processing: processing, resultStyle: resultStyle, coverCanvas: true)
    layer.name = "Generated Background"
    let record = GeneratedBackgroundRecord(foregroundLayerID: foreground.id,
      width: source.width, height: source.height)
    try record.validate()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    layer.sourceTags?[contextKey] = try encoder.encode(record)
    return layer
  }

  static func command(_ layer: Layer, source: CraftDocument, foregroundID: UUID) throws -> Command {
    try Task.checkCancellation()
    guard let subject = foreground(in: source), subject.id == foregroundID,
      let index = source.layers.firstIndex(where: { $0.id == foregroundID }),
      case .raster(let pixels) = layer.content,
      pixels.width == source.width, pixels.height == source.height, pixels.depth == source.depth,
      layer.x == 0, layer.y == 0, layer.mask == nil, layer.parentID == nil,
      let context = try record(layer), context.foregroundLayerID == foregroundID,
      context.width == source.width, context.height == source.height,
      !source.layers.contains(where: { $0.id == layer.id }) else {
      throw CraftError.invalid("The generated background or its foreground target is invalid.")
    }
    _ = try GeneratedImageStorage.original(layer)
    var result = source
    result.layers.insert(layer, at: index)
    result.activeLayerID = layer.id
    try result.validate(); try Task.checkCancellation()
    // Shared immutable prepared-document transaction, not a second editing algorithm.
    return .regionRetouch(.init(source: source, result: result, label: "Generate Background"))
  }
}
