import Foundation
import CoreGraphics
import PhotoCraftCore

public struct ImageStackSettings: Codable, Equatable, Sendable {
  public var align = false
  public var createSmartObject = false
  public var mode: ImageStackMode?
  public init() {}
  public func validate() throws {
    guard mode == nil || createSmartObject else { throw CraftError.invalid("A statistical stack requires a Smart Object.") }
  }
}
public enum ImageStack {
  /// Legacy direct-kernel threshold, independent of logical document extent.
  public static let maximumTotalPixels = 16_777_216
  public static let maximumSources = LayerLimits.maximumLayers
  public static let maximumDocumentPixels = Surface.maxPixels
  public struct Result: Sendable { public let document: CraftDocument; public let sourceCount: Int; public let aligned: Bool }
  /// Display reduction belongs after statistical evaluation, never on input photos.
  public static func preview(_ document:CraftDocument)throws->CGImage {
    let large=document.width>maximumTotalPixels/document.height
    let composite=try large ? Renderer.compositePaged(document):Renderer.composite(document)
    let pixels=try large ? RasterPreviewRequest.overview(width:document.width,height:document.height).reducing(composite):composite
    return try ColorManagement.displayImage(pixels,in:document)
  }
  /// Each visible root (or child of a single outer group) is one sample. Its subtree,
  /// masks, transform and filters render normally; its outer blend/clipping is neutral.
  public static func render(_ source: CraftDocument, mode: ImageStackMode, in parent: CraftDocument) throws -> Surface {
    try SmartObjectIO.check(source)
    var roots = source.layers.filter { $0.parentID == nil }
    let outer = roots.count == 1 && roots[0].isGroup ? roots[0] : nil
    if let outer { roots = source.layers.filter { $0.parentID == outer.id } }
    roots = roots.filter { $0.visible && (outer?.visible ?? true) }
    guard roots.count <= maximumSources else { throw CraftError.unsupported("Image statistics exceeds the document layer limit.") }
    let paged=roots.count>16 || source.width*source.height*max(1,roots.count)>maximumTotalPixels
    var frames: [Surface] = []
    for root in roots {
      try Task.checkCancellation()
      if case .adjustment = root.content { throw CraftError.unsupported("Place adjustments inside a source group before computing image statistics.") }
      var isolated = source
      let ids = Set(source.subtreeIDs(root.id)).union(outer.map { [$0.id] } ?? [])
      isolated.layers = source.layers.filter { ids.contains($0.id) };LayerLinks.prune(in:&isolated)
      isolated.activeLayerID = root.id
      isolated.selection = nil; isolated.selectionMask = nil; isolated.quickMask = nil
      for i in isolated.layers.indices where isolated.layers[i].id == root.id || isolated.layers[i].id == outer?.id {
        isolated.layers[i].blendMode = .normal; isolated.layers[i].clipped = false
      }
      frames.append(try paged ? PagedImageStatistics.backed(SmartObjectIO.sourceComposite(isolated)):Renderer.composite(isolated))
    }
    if paged {
      let output=try PagedImageStatistics.surface(frames,width:source.width,height:source.height,depth:source.depth,mode:mode)
      return try ColorManagement.converted(output,from:source,to:parent)
    }
    var output = try Surface(width:source.width,height:source.height,depth:source.depth,colorEncoding:source.depth == .f32 ? .linearRGB:.sRGB)
    var r = [Float](),g = r,b = r
    for y in 0..<source.height {
      try Task.checkCancellation()
      for x in 0..<source.width {
        r.removeAll(keepingCapacity:true);g.removeAll(keepingCapacity:true);b.removeAll(keepingCapacity:true)
        var alpha: Float = 0
        for frame in frames {
          let p = source.depth == .f32 ? frame.linearPixel(x:x,y:y):frame.pixel(x:x,y:y)
          if p.a > 0 { r.append(p.r);g.append(p.g);b.append(p.b);alpha = max(alpha,p.a) }
        }
        let pixel = Pixel(mode.statistic(r),mode.statistic(g),mode.statistic(b),alpha)
        if source.depth == .f32 { output.setLinearPixel(x:x,y:y,pixel) } else { output.setPixel(x:x,y:y,pixel) }
      }
    }
    return try ColorManagement.converted(output,from:source,to:parent)
  }
  public static func command(in document: CraftDocument,layerID: UUID,mode: ImageStackMode?) throws -> Command {
    guard let object = document.layers.first(where:{$0.id == layerID})?.smartObject,!document.isImageLocked(layerID),object.rawDevelopment == nil else { throw CraftError.invalid("Select an unlocked layered Smart Object.") }
    let source = try SmartObjectLayerCompIO.presentation(SmartObjectIO.sourceDocument(object), compID: object.layerComps?.selectedID)
    let pixels = try mode.map { try render(source,mode:$0,in:document) } ?? ColorManagement.converted(SmartObjectIO.sourceComposite(source),from:source,to:document)
    return .smartObjectStack(layerID,mode,pixels)
  }
  public static func prepare(_ sources: [CraftDocument],settings: ImageStackSettings,name: String = "Untitled Stack") throws -> Result {
    try settings.validate();try Task.checkCancellation()
    guard (2...maximumSources).contains(sources.count) else { throw CraftError.invalid("Choose two to \(maximumSources) source images within the document layer limit.") }
    guard !settings.align || sources.count<=PhotoAlign.maximumLayers else{throw CraftError.unsupported("Automatic alignment supports up to \(PhotoAlign.maximumLayers) sources; disable alignment for a larger stack.")}
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 256 else { throw CraftError.invalid("Choose a document name with 1–256 characters.") }
    for source in sources { try source.validate() }
    let width = sources.map(\.width).max()!,height = sources.map(\.height).max()!
    let paged=sources.count>16 || width*height*sources.count>maximumTotalPixels
    let first = sources[0]
    var output = try CraftDocument(width:width,height:height,depth:first.depth)
    output.layers = [];output.name = name;output.workingICC = first.workingICC;output.resolution = first.resolution
    for source in sources {
      try Task.checkCancellation()
      let composite=try SmartObjectIO.sourceComposite(source)
      let converted = try ColorManagement.converted(paged ? PagedImageStatistics.backed(composite):composite,from:source,to:output)
      let pixels=try paged ? PagedImageStatistics.backed(converted):converted
      output.layers.append(Layer(name:source.name,content:.raster(pixels)))
    }
    output.activeLayerID = output.layers.last?.id
    if settings.align {
      var align = PhotoAlignSettings();align.projection = .auto
      output = try PhotoAlign.prepare(output,layerIDs:Set(output.layers.map(\.id)),settings:align).result
    }
    if settings.createSmartObject {
      // Preserve the source canvas and every source photo, including transparent borders.
      let (source,pixels) = try SmartObjectIO.embedded(document:output,in:output)
      var layer = Layer(name:name,content:.raster(pixels));layer.smartObject = source
      let contents = output
      output.layers = [layer];output.activeLayerID = layer.id
      if let mode = settings.mode {
        output.layers[0].smartObject?.stackMode = mode
        output.layers[0].content = .raster(try render(contents,mode:mode,in:output))
      }
    }
    try output.validate();return Result(document:output,sourceCount:sources.count,aligned:settings.align)
  }
}
