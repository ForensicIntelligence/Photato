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
    package let document: CraftDocument
    package let exposureEV: [Double]
    package let offsets: [SIMD2<Int>]
    package let settings: CameraRawSettings?
    package let preview: CGImage?
    package let overlayPreview: CGImage?

    package func write(to url: URL) throws {
      try RawLinearDNG.write(document, to: url, settings: settings)
    }
  }

  package static let sourceCount = 2...16
  package static let maximumPixels = 96_000_000
  package static let maximumTotalPixels = 384_000_000

  package struct Exposure: Sendable {
    let bracket: RawHDRSceneFusion.Bracket
  }

  struct MeasuredSource: Sendable {
    let source: Source
    let info: RawSourceIO.Info
    let exposure: Double
  }

  struct WhiteBalance: Sendable {
    let temperature: Float
    let tint: Float
  }

  static func measure(_ source: Source) throws -> MeasuredSource {
    try Task.checkCancellation()
    let bytes = source.bytes.data
    let info = try RawSourceIO.inspect(bytes, decoderVersion: source.settings.decoderVersion)
    guard let exposure = RawSourceIO.hdrExposureFactor(bytes, sourceType: info.type) else {
      throw CraftError.invalid("The RAW exposure “\(source.fileName)” needs recorded shutter time, aperture and ISO.")
    }
    return MeasuredSource(source: source, info: info, exposure: exposure)
  }

  static func reference(_ measured: [MeasuredSource]) -> MeasuredSource {
    measured.sorted { $0.exposure < $1.exposure }[measured.count / 2]
  }

  static func whiteBalance(_ measured: MeasuredSource) -> WhiteBalance {
    WhiteBalance(temperature: measured.source.settings.temperature ?? measured.info.temperature,
      tint: measured.source.settings.tint ?? measured.info.tint)
  }

  package static func prepareSources(_ sources: [Source]) throws -> [Exposure] {
    guard sourceCount.contains(sources.count) else {
      throw CraftError.invalid("Select two to sixteen RAW exposures to merge.")
    }
    let measured = try sources.map(measure)
    return try developBracket(measured, whiteBalance: whiteBalance(reference(measured)))
  }

  static func validateBracketDimensions(_ sources: [MeasuredSource]) throws {
    guard let first = sources.first, sourceCount.contains(sources.count) else {
      throw CraftError.invalid("Select two to sixteen RAW exposures to merge.")
    }
    let width = first.info.nativeWidth, height = first.info.nativeHeight
    guard sources.allSatisfy({ $0.info.nativeWidth == width && $0.info.nativeHeight == height }) else {
      throw CraftError.invalid("The selected RAW exposures have different image dimensions.")
    }
    guard width <= maximumPixels / height, width * height <= maximumTotalPixels / sources.count else {
      throw CraftError.unsupported("Camera Raw HDR merge supports up to 96 megapixels per photo and 384 megapixels combined.")
    }
  }

  static func developBracket(_ sources: [MeasuredSource], whiteBalance: WhiteBalance) throws -> [Exposure] {
    try validateBracketDimensions(sources)
    let preferPaged = sources.reduce(0) { $0 + $1.info.nativeWidth * $1.info.nativeHeight } > Surface.maximumDensePixels
    return try sources.map { measured in
      try Task.checkCancellation()
      let source = measured.source
      var settings = source.settings
      settings.temperature = (2_000...50_000).contains(whiteBalance.temperature) ? whiteBalance.temperature : nil
      settings.tint = (-150...150).contains(whiteBalance.tint) ? whiteBalance.tint : nil
      settings.exposure = 0
      settings.boost = 0
      settings.shadowBoost = 0
      settings.extendedRange = 0
      settings.highlightRecovery = false
      settings.adjustments = .init()
      let pixels = try RawSourceIO.renderSceneExposure(source.bytes.data, settings: settings, preferPaged: preferPaged)
      return Exposure(bracket: .init(pixels: pixels, exposure: measured.exposure))
    }
  }

  package static func prepare(_ sources: [Exposure], options: RawHDRMergeSettings,
    name: String, makePreview: Bool = true) throws -> Result {
    let result = try RawHDRSceneFusion.merge(sources.map(\.bracket), options: options)
    let pixels = result.pixels
    var document = try CraftDocument(width: pixels.width, height: pixels.height, depth: .f32, name: name)
    let layer = Layer(name: "HDR Merge", content: .raster(pixels))
    document.layers = [layer]
    document.activeLayerID = layer.id
    let adjustments = options.autoSettings ? try automaticTone(pixels) : nil
    guard makePreview else {
      return Result(document: document, exposureEV: result.exposureEV, offsets: result.offsets, settings: adjustments,
        preview: nil, overlayPreview: nil)
    }
    let request = try RasterPreviewRequest.overview(width: pixels.width, height: pixels.height, maximumSide: 900)
    let overview = try request.reducing(pixels)
    let adjusted = try adjustments.map { try CameraRawEngine.develop(overview, settings: $0) } ?? overview
    let preview = try ColorManagement.displayImage(adjusted, in: document)
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
      overlay = try ColorManagement.displayImage(marked, in: document)
    } else { overlay = nil }
    return Result(document: document, exposureEV: result.exposureEV, offsets: result.offsets, settings: adjustments,
      preview: preview, overlayPreview: overlay)
  }

  // Sample evenly spaced cell centers so a narrow photo or an isolated hot pixel
  // cannot dominate the exposure. Keep the analysis bounded independently of merge size.
  package static func automaticTone(_ surface: Surface) throws -> CameraRawSettings {
    let budget = 8_192
    let width = surface.width, height = surface.height
    let columns = min(width, budget, max(1, Int(sqrt(Double(budget * width) / Double(height)))))
    let rows = min(height, budget / columns)
    var luminance = [Float](), peaks = [Float](), chroma = [Float]()
    luminance.reserveCapacity(columns * rows)
    peaks.reserveCapacity(columns * rows)
    chroma.reserveCapacity(columns * rows)
    for row in 0..<rows {
      try Task.checkCancellation()
      let y = (2 * row + 1) * height / (2 * rows)
      for column in 0..<columns {
        let x = (2 * column + 1) * width / (2 * columns)
        let p = surface.linearPixel(x: x, y: y)
        guard p.isFinite, p.a > 0 else { continue }
        let low = max(0, min(p.r, p.g, p.b)), high = max(p.r, p.g, p.b, 0)
        let light = max(0, 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
        luminance.append(light)
        peaks.append(high)
        // Near-black read noise and specular whites are poor color samples.
        if (0.025...0.8).contains(light), high > 0 { chroma.append((high - low) / high) }
      }
    }
    luminance.sort()
    peaks.sort()
    chroma.sort()
    func percentile(_ sorted: [Float], _ fraction: Float) -> Float {
      guard !sorted.isEmpty else { return 0 }
      let position = Float(sorted.count - 1) * fraction
      let lower = Int(position), upper = min(lower + 1, sorted.count - 1)
      return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Float(lower))
    }
    func smooth(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
      let t = min(1, max(0, (value - lower) / (upper - lower)))
      return t * t * (3 - 2 * t)
    }

    var settings = CameraRawSettings()
    let shoulder = percentile(luminance, 0.985)
    guard shoulder > 0.0001 else { return settings }
    let median = percentile(luminance, 0.50)
    let highKey = smooth(0.25, 0.7, median)
    let target = 0.34 - 0.065 * highKey
    let midtoneGain = min(target / max(0.0001, median), 1.75 / shoulder)
    let upperPercentile = percentile(luminance, 0.90)
    // Dark foregrounds can coexist with a large, bright part of the scene.
    // Protect that part more strongly than scattered specular highlights.
    let brightArea = smooth(0.55, 0.85, upperPercentile)
    let highlightSeparation = smooth(0.10, 0.50, upperPercentile - percentile(luminance, 0.75))
    let broadHighlightGain = (0.80 - 0.35 * highlightSeparation) / max(0.0001, upperPercentile)
    let gain = midtoneGain + brightArea * (min(midtoneGain, broadHighlightGain) - midtoneGain)
    settings.exposure = (100 * min(3, max(-3, log2(gain)))).rounded() / 100
    let appliedGain = pow(2, settings.exposure)
    let lowerTone = percentile(luminance, 0.10) * appliedGain
    let upperTone = upperPercentile * appliedGain
    let midtoneSpread = SRGBTransfer.encoded(percentile(luminance, 0.75) * appliedGain)
      - SRGBTransfer.encoded(percentile(luminance, 0.25) * appliedGain)
    settings.contrast = max(0, 10 - 20 * midtoneSpread).rounded()

    // Keep a bright shoulder and a visible toe without baking display clipping
    // into the DNG. Match black anchoring to the amount of shadow recovery.
    let shoulderPressure = max(smooth(0.72, 1.55, shoulder * appliedGain),
      smooth(0.48, 0.85, percentile(luminance, 0.85)))
    settings.highlights = (-95 * shoulderPressure).rounded()
    let shadowCompensation = 60 * (1 - smooth(0.025, 0.25, lowerTone)) + 48 * max(0, -settings.exposure)
    let shadowLift = shadowCompensation * (1 - 0.55 * brightArea * highlightSeparation)
    settings.shadows = (min(85, shadowLift) * smooth(0.005, 0.075, median * appliedGain)).rounded()
    settings.blacks = (-settings.shadows * (0.23 + 0.43 * (1 - smooth(0.06, 0.28, lowerTone)))).rounded()

    let colorAmount = percentile(chroma, 0.50)
    let chromaticWhite = smooth(0.9, 1.85, percentile(peaks, 0.95) * appliedGain)
    let narrowShoulder = smooth(1.4, 3, shoulder * appliedGain / max(0.001, upperTone))
    settings.whites = (0.53 * -settings.highlights
      - chromaticWhite * (18 + 42 * colorAmount) - 26 * narrowShoulder).rounded()
    let hasColor = smooth(0.01, 0.1, colorAmount)
    settings.vibrance = (20 * hasColor * (1 - 0.18 * colorAmount)).rounded()
    settings.saturation = (hasColor * (8 - 14 * smooth(0.22, 0.82, colorAmount))).rounded()
    return settings
  }
}
