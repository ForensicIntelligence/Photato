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
      hasVisibleOverlay(document) else { return false }
    return try !PagedCanvasRenderer.hasCompactComposite(document, facts: CompositionFacts(document))
  }

  private static func hasVisibleOverlay(_ document: CraftDocument) -> Bool {
    document.layers.contains { layer in
      layer.visible && layer.opacity > 0 && layer.style?.enabled == true
        && layer.style?.effects.contains { $0.kind == .patternOverlay && $0.enabled && $0.opacity > 0 } == true
    }
  }

  public static func pagedPatternPreview(_ document: CraftDocument, request: RasterPreviewRequest) throws -> Self? {
    guard supportsPagedReduction(document, request: request), hasVisibleOverlay(document) else { return nil }
    return try Self(document, request: request, allowPagedReduction: true)
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
