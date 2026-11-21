import Foundation
import PhotoCraftCore

/// The unfiltered working samples for a single visible document rectangle.
/// Screen resampling, RGB isolation and soft proof use this same working crop.
public struct RasterViewportPreview: Sendable {
  public static let maximumSourcePixels = 16_777_216

  private let document: CraftDocument
  private let samples: Surface
  public let region: IntRect

  public static func supports(_ document: CraftDocument, request: RasterPreviewRequest) -> Bool {
    let region = request.region
    return region.width <= maximumSourcePixels / region.height
      && region == region.clipped(toWidth: document.width, height: document.height)
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

  public static func useForPatternEditing(_ document: CraftDocument, request: RasterPreviewRequest) throws -> Bool {
    guard supports(document, request: request),
      document.layers.contains(where: { layer in
      layer.visible && layer.style?.effects.contains { $0.kind == .patternOverlay } == true
      }) else { return false }
    return try !PagedCanvasRenderer.hasCompactComposite(document, facts: CompositionFacts(document))
  }

  public init(_ document: CraftDocument, request: RasterPreviewRequest) throws {
    guard Self.supports(document, request: request) else {
      throw CraftError.unsupported("This viewport requires supported RGB layers and at most 16,777,216 source pixels.")
    }
    self.document = document
    region = request.region
    // The ordinary renderer sees the original document and region throughout.
    // Translating the document before rendering would shift linked patterns.
    samples = try Renderer.composite(document, region: request.region).cropped(to: request.region)
  }

  public func pixel(x: Int, y: Int) -> Pixel? {
    guard region.contains(x, y) else { return nil }
    return samples.pixel(x: x - region.x, y: y - region.y)
  }

  public func imageSamples(_ request: RasterPreviewRequest, channels: RGBChannelView = .init(),
    proof: ProofSettings? = nil) throws -> Surface {
    guard request.region == region else { throw CraftError.invalid("The viewport region changed.") }
    let projection = try RasterPreviewProjection(document, channels: channels, proof: proof)
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
