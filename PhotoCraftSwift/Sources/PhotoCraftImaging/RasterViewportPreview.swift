import Foundation
import PhotoCraftCore

/// A document-coordinate viewport. Close views keep their working crop, and
/// wide views can reduce the same source patches as they are rendered.
public struct RasterViewportPreview: Sendable {
  public static let maximumSourcePixels = 16_777_216

  private let document: CraftDocument
  private let samples: Surface?
  public let region: IntRect
  public var streamsSource: Bool { samples == nil }

  public static func supports(_ document: CraftDocument, request: RasterPreviewRequest) -> Bool {
    let region = request.region
    return region.width <= maximumSourcePixels / region.height
      && supportsRegions(document, region: region)
  }

  private static func supportsRegions(_ document: CraftDocument, region: IntRect) -> Bool {
    region == region.clipped(toWidth: document.width, height: document.height)
      && document.colorMode == .rgb && document.inkMode == nil && document.restrictedMode == nil
      && !document.isChannelOnly && document.videoTimeline == nil
      && !Renderer.requiresFullComposition(document)
      && document.layers.allSatisfy { layer in
        layer.nativeMode == nil && layer.warp == nil && layer.smartFilters == nil
          && layer.smartObject?.pdfSource == nil && layer.sourceProjection == nil
          && layer.importedSmartAppearance == nil
          && (layer.style?.supportsLayerCanvas(document) ?? true)
      }
  }

  private static func supportsPagedReduction(_ document: CraftDocument, request: RasterPreviewRequest) -> Bool {
    let region = request.region
    return document.width * document.height > Surface.maximumDensePixels
      && region.width > maximumSourcePixels / region.height
      && (request.width < region.width || request.height < region.height)
      && supportsRegions(document, region: region)
  }

  public static func useForPatternEditing(_ document: CraftDocument, request: RasterPreviewRequest) throws -> Bool {
    guard supports(document, request: request) || supportsPagedReduction(document, request: request),
      hasVisibleRegionalStyle(document) else { return false }
    return try !PagedCanvasRenderer.hasCompactComposite(document, facts: CompositionFacts(document))
  }

  private static func hasVisibleRegionalStyle(_ document: CraftDocument) -> Bool {
    let regional = LayerStyle.requiresRegionalEffects(in: document)
    return document.layers.contains { layer in
      guard layer.visible, layer.opacity > 0, let style = layer.style, style.enabled else { return false }
      return style.effects.contains {
        ($0.kind == .patternOverlay || ($0.kind == .dropShadow && regional && style.supportsRegionalDropShadow))
          && $0.enabled && $0.opacity > 0
      }
    }
  }

  public static func pagedPatternPreview(_ document: CraftDocument, request: RasterPreviewRequest) throws -> Self? {
    guard supportsPagedReduction(document, request: request), hasVisibleRegionalStyle(document) else { return nil }
    return try Self(document, request: request, allowPagedReduction: true)
  }

  package static func uniformShadowOverview(_ document: CraftDocument, request: RasterPreviewRequest,
    channels: RGBChannelView, proof: ProofSettings?) throws -> Surface? {
    guard supportsRegions(document, region: request.region),
          request.width < request.region.width || request.height < request.region.height,
          let overview = try UniformShadowPreview(document, region: request.region) else { return nil }
    return try overview.imageSamples(request, projection: RasterPreviewProjection(document, channels: channels, proof: proof))
  }

  public init(_ document: CraftDocument, request: RasterPreviewRequest, allowPagedReduction: Bool = false) throws {
    self.document = document
    region = request.region
    if Self.supports(document, request: request) {
      // Translating the document before rendering would shift linked patterns.
      samples = try Renderer.composite(document, region: region).cropped(to: region)
    } else if allowPagedReduction && Self.supportsPagedReduction(document, request: request) {
      try document.validate()
      samples = nil
    } else {
      throw CraftError.unsupported("This viewport requires supported RGB layers and at most 16,777,216 source pixels.")
    }
  }

  public func pixel(x: Int, y: Int) throws -> Pixel? {
    guard region.contains(x, y) else { return nil }
    if let samples { return samples.pixel(x: x - region.x, y: y - region.y) }
    return try Renderer.composite(document, region: IntRect(x: x, y: y, width: 1, height: 1)).pixel(x: x, y: y)
  }

  public func imageSamples(_ request: RasterPreviewRequest, channels: RGBChannelView = .init(),
    proof: ProofSettings? = nil) throws -> Surface {
    guard request.region == region else { throw CraftError.invalid("The viewport region changed.") }
    let projection = try RasterPreviewProjection(document, channels: channels, proof: proof)
    guard let samples else {
      let (prepared, _) = try Renderer.preparedSources(document)
      return try PagedCanvasRenderer.reducedPatternPreview(prepared, request: request, projection: projection)
    }
    let pixels = try projection.apply(samples)
    return try pixels.reducedPreview(in: IntRect(x: 0, y: 0, width: region.width, height: region.height),
      width: request.width, height: request.height)
  }
}

struct RasterPreviewProjection {
  private let depth: PixelDepth
  private let usesLargeCanvas: Bool
  private let channels: RGBChannelView
  private let proof: ProofSettings?
  private let proofProfile: Data?

  init(_ document: CraftDocument, channels: RGBChannelView, proof: ProofSettings?) throws {
    depth = document.depth
    usesLargeCanvas = document.width * document.height > Surface.maximumDensePixels
    self.channels = channels
    self.proof = proof
    if let proof {
      try SoftProof.validate(proof, in: document)
      proofProfile = try ColorManagement.space(for: document).copyICCData() as Data?
        ?? NativeModeProfile.standard(.rgb, depth: document.depth)
    } else {
      proofProfile = nil
    }
  }

  func apply(_ samples: Surface) throws -> Surface {
    if let proof {
      return try PagedSoftProof.project(samples, depth: depth, rgbProfile: proofProfile, settings: proof)
    }
    if usesLargeCanvas { return try channels.applyingToLargePreview(samples) }
    return try channels.applying(to: samples)
  }
}

/// A constant raster rectangle can only vary around its own boundaries, the
/// shifted shadow edges, and edited source tiles. Other spans reuse one sample
/// along their constant axis when computing a reduced view.
struct UniformShadowPreview {
  private struct AxisSpan {
    let range: Range<Int>
    let repeats: Bool
    var sampleCount: Int { repeats ? 1 : range.count }
  }

  private static let maximumCorrectionTiles = 2048
  private let document: CraftDocument
  private let baseline: CraftDocument
  private let region: IntRect
  private let horizontal: [AxisSpan], vertical: [AxisSpan]
  private let changedTiles: Set<Int>

  init?(_ document: CraftDocument, region: IntRect) throws {
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    guard document.colorMode == .rgb, document.inkMode == nil, document.restrictedMode == nil,
          document.videoTimeline == nil, !document.isChannelOnly,
          region == region.clipped(toWidth: canvas.width, height: canvas.height),
          region.width > 0, region.height > 0 else { return nil }
    let side = Surface.tileSide, columns = (document.width + side - 1) / side
    var baseline = document, changed = Set<Int>()
    var columnsWithEdges = [Range<Int>](), rowsWithEdges = [Range<Int>]()
    var hasUniformShadowSource = false

    func addEdge(x: Double, y: Double, halo: Int) {
      columnsWithEdges.append((Int(floor(x)) - halo)..<(Int(ceil(x)) + halo + 1))
      rowsWithEdges.append((Int(floor(y)) - halo)..<(Int(ceil(y)) + halo + 1))
    }

    func addCorrection(_ bounds: IntRect) throws -> Bool {
      let left = max(region.x, bounds.x), top = max(region.y, bounds.y)
      let right = min(region.x + region.width, bounds.x + bounds.width)
      let bottom = min(region.y + region.height, bounds.y + bounds.height)
      guard left < right, top < bottom else { return true }
      for row in top / side...(bottom - 1) / side {
        try Task.checkCancellation()
        for column in left / side...(right - 1) / side {
          changed.insert(row * columns + column)
          if changed.count > Self.maximumCorrectionTiles { return false }
        }
      }
      return true
    }

    func addStored(_ surface: Surface, x: Int, y: Int, shadows: [LayerStyleRenderer.DropShadowGeometry]) throws -> Bool {
      let columns = (surface.width + side - 1) / side
      for key in surface.storedTileKeys {
        try Task.checkCancellation()
        let left = key % columns * side, top = key / columns * side
        let bounds = IntRect(x: x + left, y: y + top,
          width: min(side, surface.width - left), height: min(side, surface.height - top))
          .clipped(toWidth: canvas.width, height: canvas.height)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        if try !addCorrection(bounds) { return false }
        for shadow in shadows {
          if try !addCorrection(shadow.footprint(of: bounds, in: document)) { return false }
        }
      }
      return true
    }

    for (index, layer) in document.layers.enumerated() {
      try Task.checkCancellation()
      guard layer.parentID == nil, !layer.isGroup, !layer.isClipped else { return nil }
      if !layer.visible || layer.opacity == 0 { continue }
      guard layer.affine == nil, layer.warp == nil, layer.smartObject == nil, layer.smartFilters == nil,
            layer.sourceProjection == nil, layer.nativeMode == nil, layer.vectorMask?.enabled != true,
            layer.blendMode != .dissolve else { return nil }
      var shadows = [LayerStyleRenderer.DropShadowGeometry]()
      if let style = layer.style {
        guard style.sourcePSDData == nil, style.effects.allSatisfy({ $0.kind == .dropShadow }) else { return nil }
        if style.enabled {
          for effect in style.effects where effect.enabled && effect.opacity > 0 {
            // Dither and dissolve vary with position even in a uniform input region.
            guard effect.blendMode != .dissolve, (effect.advanced?.noise ?? 0) == 0 else { return nil }
            shadows.append(.init(effect, style: style, in: document))
          }
        }
      }
      let rect: IntRect
      let alpha: Float
      switch layer.content {
      case .fill(let pixel):
        rect = canvas
        alpha = pixel.a
      case .raster(let surface):
        rect = IntRect(x: layer.x, y: layer.y, width: surface.width, height: surface.height)
          .clipped(toWidth: canvas.width, height: canvas.height)
        alpha = surface.defaultPixel.a
        if try !addStored(surface, x: layer.x, y: layer.y, shadows: shadows) { return nil }
        if surface.tileCount > 0 { baseline.layers[index].content = .raster(try surface.implicitSampleSurface()) }
      default:
        return nil
      }
      if let mask = layer.mask, layer.effectiveMaskProperties.enabled {
        guard layer.effectiveMaskProperties.feather == 0, layer.maskCoordinateTransform == .identity,
              mask.width == canvas.width, mask.height == canvas.height else { return nil }
        if try !addStored(mask, x: 0, y: 0, shadows: shadows) { return nil }
        if mask.tileCount > 0 { baseline.layers[index].mask = try mask.implicitSampleSurface() }
      }
      guard rect.width > 0, rect.height > 0, alpha > 0 else { continue }
      addEdge(x: Double(rect.x), y: Double(rect.y), halo: 0)
      addEdge(x: Double(rect.x + rect.width), y: Double(rect.y + rect.height), halo: 0)
      for shadow in shadows {
        hasUniformShadowSource = true
        addEdge(x: Double(rect.x) + shadow.dx, y: Double(rect.y) + shadow.dy, halo: shadow.halo)
        addEdge(x: Double(rect.x + rect.width) + shadow.dx,
          y: Double(rect.y + rect.height) + shadow.dy, halo: shadow.halo)
        // Both renderers use a bounded map at the physical canvas edge.
        addEdge(x: 0, y: 0, halo: shadow.halo)
        addEdge(x: Double(canvas.width), y: Double(canvas.height), halo: shadow.halo)
      }
    }
    guard hasUniformShadowSource else { return nil }
    let x = Self.spans(columnsWithEdges, in: region.x..<(region.x + region.width))
    let y = Self.spans(rowsWithEdges, in: region.y..<(region.y + region.height))
    let samples = x.reduce(0) { $0 + $1.sampleCount } * y.reduce(0) { $0 + $1.sampleCount }
    let work = samples + 2 * changed.count * side * side
    guard work < region.width * region.height, work <= RasterViewportPreview.maximumSourcePixels else { return nil }
    self.document = document
    self.baseline = baseline
    self.region = region
    horizontal = x
    vertical = y
    changedTiles = changed
  }

  private static func spans(_ edges: [Range<Int>], in bounds: Range<Int>) -> [AxisSpan] {
    var result = [AxisSpan](), start = bounds.lowerBound
    for edge in edges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      let lower = max(start, edge.lowerBound), upper = min(bounds.upperBound, edge.upperBound)
      guard lower < upper else { continue }
      if start < lower { result.append(.init(range: start..<lower, repeats: true)) }
      for x in stride(from: lower, to: upper, by: 128) {
        result.append(.init(range: x..<min(x + 128, upper), repeats: false))
      }
      start = upper
    }
    if start < bounds.upperBound { result.append(.init(range: start..<bounds.upperBound, repeats: true)) }
    return result
  }

  func imageSamples(_ request: RasterPreviewRequest, projection: RasterPreviewProjection) throws -> Surface {
    let baselineFacts = CompositionFacts(baseline)
    let documentFacts = CompositionFacts(document, vectorViewport: region)
    func samples(_ d: CraftDocument, _ rect: IntRect, facts: CompositionFacts) throws -> Surface {
      try projection.apply(Renderer.compositePrepared(d, region: rect, facts: facts).cropped(to: rect))
    }
    let x0 = horizontal.max { $0.range.count < $1.range.count }!.range.lowerBound
    let y0 = vertical.max { $0.range.count < $1.range.count }!.range.lowerBound
    let probe = try samples(baseline, IntRect(x: x0, y: y0, width: 1, height: 1), facts: baselineFacts)
    let linear = probe.colorEncoding == .linearRGB
    let implicit = linear ? probe.linearPixel(x: 0, y: 0) : probe.pixel(x: 0, y: 0)
    var reduction = Surface.PreviewReduction(region: region, width: request.width,
      height: request.height, encoding: probe.colorEncoding, implicit: implicit)
    for y in vertical {
      for x in horizontal {
        try Task.checkCancellation()
        let rect = IntRect(x: x.range.lowerBound, y: y.range.lowerBound, width: x.range.count, height: y.range.count)
        let patch = try samples(baseline, IntRect(x: rect.x, y: rect.y,
          width: x.sampleCount, height: y.sampleCount), facts: baselineFacts)
        try reduction.appendRepeating(patch, in: rect)
      }
    }
    let side = Surface.tileSide, columns = (document.width + side - 1) / side
    for key in changedTiles.sorted() {
      try Task.checkCancellation()
      let x = key % columns * side, y = key / columns * side
      let left = max(x, region.x), top = max(y, region.y)
      let rect = IntRect(x: left, y: top,
        width: min(x + side, region.x + region.width) - left,
        height: min(y + side, region.y + region.height) - top)
      try reduction.replace(samples(baseline, rect, facts: baselineFacts),
        with: samples(document, rect, facts: documentFacts), x: left, y: top)
    }
    return try reduction.finish()
  }
}
