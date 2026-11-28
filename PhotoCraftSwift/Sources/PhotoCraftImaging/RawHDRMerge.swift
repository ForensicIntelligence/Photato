import CoreGraphics
import Foundation
import PhotoCraftCore

package struct RawHDRMergeSettings: Codable, Equatable, Sendable {
  package enum Deghost: String, CaseIterable, Codable, Sendable {
    case off, low, medium, high

    var threshold: Double {
      switch self {
      case .off, .medium: 0.35
      case .low: 0.55
      case .high: 0.20
      }
    }

    package var title: String { rawValue.capitalized }
  }

  package var align = true
  package var autoSettings = true
  package var deghost: Deghost = .off

  package init() {}
}

package enum RawHDRMerge {
  package struct Source: Sendable {
    let bytes: EmbeddedSourceBytes
    package let fileName: String
    let settings: RawDevelopment

    package init(bytes: EmbeddedSourceBytes, fileName: String, settings: RawDevelopment) {
      self.bytes = bytes
      self.fileName = fileName
      self.settings = settings
    }
  }

  package struct Result: Sendable {
    package let merged: HDRMerge.Result
    package let settings: CameraRawSettings?
    package let preview: CGImage?
    package let overlayPreview: CGImage?

    package func write(to url: URL) throws {
      try RawLinearDNG.write(merged.document, to: url, settings: settings)
    }
  }

  package static let sourceCount = 2...16

  package static func prepareSources(_ sources: [Source]) throws -> [CraftDocument] {
    guard sourceCount.contains(sources.count) else {
      throw CraftError.invalid("Select two to sixteen RAW exposures to merge.")
    }
    let dimensions = try sources.map { source in
      try Task.checkCancellation()
      return try RawSourceIO.inspect(source.bytes.data, decoderVersion: source.settings.decoderVersion)
    }
    let width = dimensions[0].nativeWidth, height = dimensions[0].nativeHeight
    guard dimensions.allSatisfy({ $0.nativeWidth == width && $0.nativeHeight == height }) else {
      throw CraftError.invalid("The selected RAW exposures have different image dimensions.")
    }
    guard width <= HDRMerge.maximumPixels / height, width * height <= HDRMerge.maximumTotalPixels / sources.count else {
      throw CraftError.unsupported("HDR merge supports up to 16 megapixels per photo and 32 megapixels combined.")
    }
    return try sources.map { source in
      try Task.checkCancellation()
      return try RawSourceIO.open(source.bytes, fileName: source.fileName, settings: source.settings, depth: .u16)
    }
  }

  package static func prepare(_ sources: [CraftDocument], options: RawHDRMergeSettings,
    name: String, makePreview: Bool = true) throws -> Result {
    var settings = HDRMergeSettings()
    settings.align = options.align
    settings.removeGhosts = options.deghost != .off
    let result = try HDRMerge.prepare(sources, settings: settings, name: name,
      ghostThreshold: options.deghost.threshold, retainGhostMask: makePreview)
    let pixels = try Renderer.composite(result.document)
    let adjustments = options.autoSettings ? automaticExposure(pixels) : nil
    guard makePreview else { return Result(merged: result, settings: adjustments, preview: nil, overlayPreview: nil) }
    let request = try RasterPreviewRequest.overview(width: pixels.width, height: pixels.height, maximumSide: 900)
    let overview = try request.reducing(pixels)
    let adjusted = try adjustments.map { try CameraRawEngine.develop(overview, settings: $0) } ?? overview
    let preview = try ColorManagement.displayImage(adjusted, in: result.document)
    let overlay: CGImage?
    if let mask = result.ghostMask {
      var marked = adjusted
      for y in 0..<marked.height {
        try Task.checkCancellation()
        let sourceY = y * pixels.height / marked.height
        for x in 0..<marked.width {
          let amount = mask[sourceY * pixels.width + x * pixels.width / marked.width] * 0.55
          if amount > 0 {
            let sample = marked.linearPixel(x: x, y: y)
            marked.setLinearPixel(x: x, y: y, Pixel(sample.r * (1 - amount) + amount,
              sample.g * (1 - amount), sample.b * (1 - amount), sample.a))
          }
        }
      }
      overlay = try ColorManagement.displayImage(marked, in: result.document)
    } else { overlay = nil }
    return Result(merged: result, settings: adjustments, preview: preview, overlayPreview: overlay)
  }

  private static func automaticExposure(_ surface: Surface) -> CameraRawSettings {
    let step = max(1, Int(sqrt(Double(surface.width * surface.height) / 8_192)))
    var luminance: [Float] = []
    for y in stride(from: 0, to: surface.height, by: step) {
      for x in stride(from: 0, to: surface.width, by: step) {
        let p = surface.linearPixel(x: x, y: y)
        luminance.append(0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
      }
    }
    luminance.sort()
    let midpoint = max(0.0001, luminance[luminance.count / 2])
    let high = max(0.0001, luminance[luminance.count * 95 / 100])
    var settings = CameraRawSettings()
    settings.exposure = min(3, max(-3, min(log2(0.18 / midpoint), log2(0.95 / high))))
    return settings
  }
}
