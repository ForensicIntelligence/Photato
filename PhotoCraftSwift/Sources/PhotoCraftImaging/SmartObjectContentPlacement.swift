import Foundation
import PhotoCraftCore

/// Replaces a Smart Object's frame content with one editable nested ingredient.
/// The child canvas clips overflow while the nested layer retains the entire source.
public struct SmartObjectContentPlacement: Sendable {
  public let mode: FrameFit
  public let anchor: CanvasAnchor

  public init(mode: FrameFit, anchor: CanvasAnchor) {
    self.mode = mode
    self.anchor = anchor
  }

  public func replacement(in document: CraftDocument, layerID: UUID, data: Data, fileName: String) throws -> Command {
    try replacement(in: document, layerID: layerID, allInstances: false) { frame in
      let layer = try SmartObjectIO.placed(data: data, fileName: fileName, in: frame, fit: false)
      let types = ["image/jpeg", "image/png", "image/tiff", "image/vnd.adobe.photoshop", "application/x-photoshop"]
      guard let type = layer.smartObject?.mediaType, types.contains(type) else {
        throw CraftError.unsupported("Frame replacement takes a JPEG, PNG, TIFF, PSD or PSB source.")
      }
      return layer
    }
  }

  public func replacement(in document: CraftDocument, layerID: UUID, source: CraftDocument,
    allInstances: Bool) throws -> Command {
    try replacement(in: document, layerID: layerID, allInstances: allInstances) { frame in
      let (object, pixels) = try SmartObjectIO.embedded(document: source, in: frame)
      var layer = Layer(name: source.name, content: .raster(pixels))
      layer.smartObject = object
      return layer
    }
  }

  private func replacement(in document: CraftDocument, layerID: UUID, allInstances: Bool,
    ingredient: (CraftDocument) throws -> Layer) throws -> Command {
    try Task.checkCancellation()
    guard mode == .fit || mode == .fill else {
      throw CraftError.invalid("Choose Fit or Fill for the Smart Object frame.")
    }
    guard let layer = document.layers.first(where: { $0.id == layerID }), let object = layer.smartObject else {
      throw CraftError.invalid("Choose an embedded Smart Object as the frame.")
    }
    for instance in document.layers where instance.id == layerID
      || (allInstances && instance.smartObject?.sourceID == object.sourceID) {
      guard !document.isImageLocked(instance.id) else {
        throw CraftError.invalid("Unlock each affected Smart Object before replacing its frame content.")
      }
      try validate(instance)
    }

    var frame = try CraftDocument(width: object.width, height: object.height, depth: document.depth, name: layer.name)
    frame.resolution = object.resolution
    frame.workingICC = document.workingICC
    frame.profileIsUntagged = document.profileIsUntagged
    var nested = try ingredient(frame)
    guard let source = nested.smartObject else { throw CraftError.invalid("Missing nested Smart Object source.") }
    let placement = mode.placement(sourceWidth: source.width, sourceHeight: source.height,
      frameWidth: frame.width, frameHeight: frame.height, anchor: anchor)
    let transform = Transform2D.translation(placement.x, placement.y) * .scale(placement.scale, placement.scale)
    try transform.validated()
    nested.x = Int(floor(transform.tx))
    nested.y = Int(floor(transform.ty))
    let linear = Transform2D.translation(-Double(nested.x), -Double(nested.y)) * transform
    nested.affine = linear == .identity ? nil : linear
    frame.layers = [nested]
    frame.activeLayerID = nested.id
    // Source dimensions are identical to the old frame, so the existing outer
    // transform stays bit-for-bit intact rather than being normalized again.
    return try SmartObjectIO.replacement(in: document, layerID: layerID, source: frame,
      preserveSize: false, allInstances: allInstances)
  }

  private func validate(_ layer: Layer) throws {
    guard let object = layer.smartObject, object.linkedSource == nil else {
      throw CraftError.unsupported("Frame replacement requires an embedded Smart Object.")
    }
    guard layer.sourceProjection == nil, layer.warp == nil else {
      throw CraftError.unsupported("Frame replacement does not support perspective or warped frames.")
    }
    let transform = layer.coordinateTransform
    try transform.validated()
    let scaleX = hypot(transform.a, transform.b), scaleY = hypot(transform.c, transform.d)
    let x = SIMD2(transform.a, transform.b) / scaleX
    let y = SIMD2(transform.c, transform.d) / scaleY
    guard abs(x.x * y.x + x.y * y.y) < 1e-9 else {
      throw CraftError.unsupported("Frame replacement does not support skewed frames.")
    }
    let rotated = abs(x.y) > 1e-9 || abs(y.x) > 1e-9 || (x.x < 0 && y.y < 0)
    if rotated, layer.mask != nil {
      throw CraftError.unsupported("Frame replacement does not support rotated frames with a pixel mask.")
    }
  }
}
