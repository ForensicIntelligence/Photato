import CoreGraphics
import Foundation
import PhotoCraftCore

package struct RawPanoramaSettings: Codable, Equatable, Sendable {
  package enum Projection: String, CaseIterable, Codable, Sendable {
    case spherical, cylindrical, perspective
    package var title: String { rawValue.capitalized }
    var alignment: PhotoAlignSettings.Projection {
      switch self {
      case .spherical: .spherical
      case .cylindrical: .cylindrical
      case .perspective: .perspective
      }
    }
  }

  package var projection: Projection = .spherical
  package var boundaryWarp: Double = 0
  package var fillEdges = false
  package var autoCrop = true
  package var autoSettings = true

  package init() {}

  package func validate() throws {
    guard boundaryWarp.isFinite, (0...100).contains(boundaryWarp) else {
      throw CraftError.invalid("Boundary Warp must be between 0 and 100.")
    }
  }
}

package enum RawPanorama {
  package struct Result: Sendable {
    package let document: CraftDocument
    let rawDocument: CraftDocument
    package let crop: RawCropBounds?
    package let adjustments: CameraRawSettings?
    package let matchedPoints: Int
    package let rmsPixels: Double
    package let preview: CGImage?

    package func write(to url: URL) throws {
      try RawLinearDNG.write(rawDocument, to: url, settings: adjustments, preserveTransparency: true, crop: crop)
    }
  }

  package static let sourceCount = 2...PhotoAlign.maximumLayers
  package static let hdrSourceCount = 4...(PhotoAlign.maximumLayers * RawHDRMerge.sourceCount.upperBound)

  package struct HDRSources: Sendable {
    package let photos: [CraftDocument]
    package let bracketSize: Int
  }

  package static func bracketRanges(exposureFactors: [Double], bracketSize explicit: Int? = nil) throws -> [Range<Int>] {
    guard hdrSourceCount.contains(exposureFactors.count), exposureFactors.allSatisfy({ $0.isFinite && $0 > 0 }) else {
      throw CraftError.invalid("HDR Panorama needs at least two complete sets with valid exposure metadata.")
    }
    let exposures = exposureFactors.map(log2)
    // Mechanical shutter rounding can make matching camera increments differ slightly.
    let offsetTolerance = 0.2
    let minimumSeparation = 0.08
    let sizes = explicit.map { [$0] } ?? Array(RawHDRMerge.sourceCount)
    for size in sizes where RawHDRMerge.sourceCount.contains(size) && exposures.count % size == 0
      && sourceCount.contains(exposures.count / size) {
      let ranges = stride(from: 0, to: exposures.count, by: size).map { $0..<(($0 + size)) }
      let baseline = exposures[ranges[0]].map { $0 - exposures[0] }
      let matches = ranges.allSatisfy { range in
        let set = exposures[range], ordered = set.sorted()
        return zip(ordered, ordered.dropFirst()).allSatisfy { $1 - $0 >= minimumSeparation }
          && zip(set, baseline).allSatisfy { abs($0 - exposures[range.lowerBound] - $1) <= offsetTolerance }
      }
      if matches { return ranges }
    }
    throw CraftError.invalid("Could not find matching HDR exposure sets. Select complete brackets in capture order, with the same offset pattern at every position.")
  }

  package static func prepareHDRSources(_ sources: [RawHDRMerge.Source], bracketSize: Int? = nil) throws -> HDRSources {
    guard hdrSourceCount.contains(sources.count) else {
      throw CraftError.invalid("Select at least two exposure brackets in capture order.")
    }
    let measured = try sources.map(RawHDRMerge.measure)
    let ranges = try bracketRanges(exposureFactors: measured.map(\.exposure), bracketSize: bracketSize)
    var total = 0
    for range in ranges {
      let group = Array(measured[range])
      try RawHDRMerge.validateBracketDimensions(group)
      let info = group[0].info
      total += info.nativeWidth * info.nativeHeight
    }
    guard total <= PhotoAlign.maximumTotalPixels else {
      throw CraftError.unsupported("The fused panorama positions exceed the combined 32 megapixel working limit.")
    }
    let reference = RawHDRMerge.reference(Array(measured[ranges[0]]))
    let whiteBalance = RawHDRMerge.whiteBalance(reference)
    var hdr = RawHDRMergeSettings()
    hdr.autoSettings = false
    let photos = try ranges.map { range in
      let bracket = try RawHDRMerge.developBracket(Array(measured[range]), whiteBalance: whiteBalance)
      let result = try RawHDRSceneFusion.merge(bracket.map(\.bracket), options: hdr, referenceExposure: reference.exposure)
      return try rasterDocument(result.pixels, name: measured[range.lowerBound].source.fileName)
    }
    return HDRSources(photos: photos, bracketSize: ranges[0].count)
  }


  package static func prepareSources(_ sources: [RawHDRMerge.Source]) throws -> [CraftDocument] {
    guard sourceCount.contains(sources.count) else {
      throw CraftError.invalid("Select two to sixteen overlapping RAW photos.")
    }
    let info = try sources.map { source in
      try Task.checkCancellation()
      return try RawSourceIO.inspect(source.bytes.data, decoderVersion: source.settings.decoderVersion)
    }
    var total = 0
    for photo in info {
      guard photo.nativeWidth <= PhotoAlign.maximumPixels / photo.nativeHeight else {
        throw CraftError.unsupported("A Camera Raw panorama source exceeds 16 megapixels.")
      }
      total += photo.nativeWidth * photo.nativeHeight
    }
    guard total <= PhotoAlign.maximumTotalPixels else {
      throw CraftError.unsupported("The RAW panorama sources exceed the combined 32 megapixel working limit.")
    }
    let reference = sources[0].settings
    let temperature = reference.temperature ?? info[0].temperature
    let tint = reference.tint ?? info[0].tint
    return try sources.map { source in
      try Task.checkCancellation()
      var settings = source.settings
      settings.temperature = (2_000...50_000).contains(temperature) ? temperature : nil
      settings.tint = (-150...150).contains(tint) ? tint : nil
      settings.exposure = 0
      settings.boost = 0
      settings.shadowBoost = 0
      settings.extendedRange = 0
      settings.highlightRecovery = false
      settings.adjustments = .init()
      let pixels = try RawSourceIO.renderSceneExposure(source.bytes.data, settings: settings)
      return try rasterDocument(pixels, name: source.fileName)
    }
  }

  package static func prepare(_ sources: [CraftDocument], options: RawPanoramaSettings,
    name: String, makePreview: Bool = true) throws -> Result {
    try options.validate()
    let prepared = try register(sources, projection: options.projection, name: name)
    return try finish(prepared, options: options, makePreview: makePreview)
  }

  package struct Registration: Sendable {
    let name: String
    let projection: RawPanoramaSettings.Projection
    let pixels: Surface
    let matchedPoints: Int
    let rmsPixels: Double
  }

  package static func register(_ sources: [CraftDocument], projection: RawPanoramaSettings.Projection,
    name: String) throws -> Registration {
    var settings = PhotomergeSettings()
    settings.projection = projection.alignment
    settings.blendImages = false
    let aligned = try Photomerge.prepare(sources, settings: settings, name: name)
    return Registration(name: name, projection: projection, pixels: try stitch(aligned.document),
      matchedPoints: aligned.matchedPoints, rmsPixels: aligned.rmsPixels)
  }

  package static func finish(_ registered: Registration, options: RawPanoramaSettings,
    makePreview: Bool = true) throws -> Result {
    try options.validate()
    guard options.projection == registered.projection else { throw CraftError.invalid("The panorama projection changed.") }
    var pixels = registered.pixels
    if options.boundaryWarp > 0 {
      pixels = try warpBoundary(pixels, amount: options.boundaryWarp / 100)
    }
    if options.fillEdges { pixels = try fillEdges(pixels) }
    let rawDocument = try rasterDocument(pixels, name: registered.name)
    let bounds = try options.autoCrop ? coverageBounds(pixels) : nil
    let crop: RawCropBounds?
    let cropped: Surface
    if let bounds, bounds.width < pixels.width || bounds.height < pixels.height {
      crop = try RawCropBounds(left: Float(bounds.x) / Float(pixels.width),
        top: Float(bounds.y) / Float(pixels.height), right: Float(bounds.x + bounds.width) / Float(pixels.width),
        bottom: Float(bounds.y + bounds.height) / Float(pixels.height))
      cropped = try pixels.cropped(to: bounds)
    } else {
      crop = nil
      cropped = pixels
    }
    let document = crop == nil ? rawDocument : try rasterDocument(cropped, name: registered.name)
    let adjustments = options.autoSettings ? try RawHDRMerge.automaticTone(cropped) : nil
    let preview: CGImage?
    if makePreview {
      let request = try RasterPreviewRequest.overview(width: cropped.width, height: cropped.height, maximumSide: 900)
      let overview = try request.reducing(cropped)
      let developed = try adjustments.map { try CameraRawEngine.develop(overview, settings: $0) } ?? overview
      preview = try ColorManagement.displayImage(developed, in: document)
    } else { preview = nil }
    return Result(document: document, rawDocument: rawDocument, crop: crop, adjustments: adjustments, matchedPoints: registered.matchedPoints,
      rmsPixels: registered.rmsPixels, preview: preview)
  }

  private static func rasterDocument(_ pixels: Surface, name: String) throws -> CraftDocument {
    var document = try CraftDocument(width: pixels.width, height: pixels.height, depth: .f32, name: name)
    let layer = Layer(name: name, content: .raster(pixels))
    document.layers = [layer]
    document.activeLayerID = layer.id
    return document
  }

  // Work in linear light and visit only the source pixels touching each scanline.
  // Feather overlaps at their actual coverage boundaries, including curved edges.
  private static func stitch(_ document: CraftDocument) throws -> Surface {
    let width = document.width, height = document.height
    let layers = try document.layers.map { layer in
      guard case .raster(let surface) = layer.content else { throw CraftError.invalid("Missing panorama pixels.") }
      return (surface: surface, x: layer.x, y: layer.y)
    }
    var output = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<height {
      try Task.checkCancellation()
      var rgb = [SIMD3<Float>](repeating: .zero, count: width)
      var sum = [Float](repeating: 0, count: width), coverage = sum
      for layer in layers {
        let row = y - layer.y, surface = layer.surface
        guard (0..<surface.height).contains(row), let range = coverageRange(surface, line: row, horizontal: true) else { continue }
        let vertical = min(row + 1, surface.height - row)
        for x in range {
          let p = surface.linearPixel(x: x, y: row)
          guard p.a > 0 else { continue }
          let distance = min(x - range.lowerBound + 1, range.upperBound - x, vertical)
          let amount = Float(min(64, distance)) * p.a
          let i = layer.x + x
          rgb[i] += p.rgb * amount
          sum[i] += amount
          coverage[i] = max(coverage[i], p.a)
        }
      }
      for x in sum.indices where sum[x] > 0 {
        let color = rgb[x] / sum[x]
        output.setLinearPixel(x: x, y: y, Pixel(max(0, color.x), max(0, color.y), max(0, color.z), coverage[x]))
      }
    }
    return output
  }

  private static func coverageRange(_ surface: Surface, line: Int, horizontal: Bool) -> Range<Int>? {
    let length = horizontal ? surface.width : surface.height
    func visible(_ i: Int) -> Bool {
      (horizontal ? surface.linearPixel(x: i, y: line) : surface.linearPixel(x: line, y: i)).a > 0.001
    }
    guard let first = (0..<length).first(where: visible) else { return nil }
    let last = (first..<length).reversed().first(where: visible) ?? first
    return first..<(last + 1)
  }

  private static func warpBoundary(_ source: Surface, amount: Double) throws -> Surface {
    func warp(_ input: Surface, horizontally: Bool) throws -> Surface {
      let width = input.width, height = input.height
      let lines = horizontally ? height : width, length = horizontally ? width : height
      var result = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
      for line in 0..<lines {
        try Task.checkCancellation()
        guard let visible = coverageRange(input, line: line, horizontal: horizontally) else { continue }
        let start = amount * Double(visible.lowerBound)
        let span = Double(length) + amount * Double(visible.count - length)
        for i in 0..<length {
          let position = start + (Double(i) + 0.5) * (span / Double(length))
          let fixed = Double(line) + 0.5
          let value = horizontally ? CropGeometry.sample(input, x: position, y: fixed)
            : CropGeometry.sample(input, x: fixed, y: position)
          result.setLinearPixel(x: horizontally ? i : line, y: horizontally ? line : i, value)
        }
      }
      return result
    }
    return try warp(warp(source, horizontally: false), horizontally: true)
  }

  private static func fillEdges(_ source: Surface) throws -> Surface {
    let width = source.width, height = source.height
    guard width <= PhotoBlend.maximumPixels / height else {
      throw CraftError.unsupported("Fill Edges supports panoramas up to 4 megapixels. Auto Crop and Boundary Warp support larger results.")
    }
    var rgba = [Float](), holes = [Bool](), samples = [Bool]()
    rgba.reserveCapacity(width * height * 4)
    holes.reserveCapacity(width * height)
    samples.reserveCapacity(width * height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let pixel = source.linearPixel(x: x, y: y)
        rgba.append(pixel.r)
        rgba.append(pixel.g)
        rgba.append(pixel.b)
        rgba.append(pixel.a)
        holes.append(pixel.a < 0.999)
        samples.append(pixel.a >= 0.999)
      }
    }
    guard holes.contains(true) else { return source }
    var settings = ContentAwareSettings()
    settings.colorAdaptation = .none
    settings.seed = 1
    let synthesized = try ContentAwareSynthesis.fill(width: width, height: height, image: rgba,
      hole: holes, source: samples, settings: settings, hdr: true)
    var result = source
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width where holes[y * width + x] {
        let index = 4 * (y * width + x), a = rgba[index + 3]
        let pixel = SIMD3(rgba[index], rgba[index + 1], rgba[index + 2]) * a
        let replacement = SIMD3(synthesized[index], synthesized[index + 1], synthesized[index + 2]) * (1 - a)
        let color = pixel + replacement
        result.setLinearPixel(x: x, y: y, Pixel(max(0, color.x), max(0, color.y), max(0, color.z), 1))
      }
    }
    return result
  }

  private static func coverageBounds(_ source: Surface) throws -> IntRect {
    let width = source.width, height = source.height
    var heights = [Int](repeating: 0, count: width), stack = [Int]()
    var best = IntRect(x: 0, y: 0, width: 0, height: 0)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        heights[x] = source.linearPixel(x: x, y: y).a >= 0.999 ? heights[x] + 1 : 0
      }
      stack.removeAll(keepingCapacity: true)
      for x in 0...width {
        let next = x < width ? heights[x] : 0
        while let previous = stack.last, heights[previous] > next {
          stack.removeLast()
          let left = (stack.last ?? -1) + 1, rows = heights[previous]
          if rows * (x - left) > best.width * best.height {
            best = IntRect(x: left, y: y + 1 - rows, width: x - left, height: rows)
          }
        }
        stack.append(x)
      }
    }
    guard best.width > 0 else { throw CraftError.invalid("The panorama has no fully covered crop. Try Boundary Warp or Fill Edges.") }
    return best
  }
}
