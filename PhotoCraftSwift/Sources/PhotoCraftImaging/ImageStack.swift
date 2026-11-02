import Foundation
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
  public static let maximumTotalPixels = 16_777_216
  public struct Result: Sendable { public let document: CraftDocument; public let sourceCount: Int; public let aligned: Bool }
  /// Each visible root (or child of a single outer group) is one sample. Its subtree,
  /// masks, transform and filters render normally; its outer blend/clipping is neutral.
  public static func render(_ source: CraftDocument, mode: ImageStackMode, in parent: CraftDocument) throws -> Surface {
    try SmartObjectIO.check(source)
    var roots = source.layers.filter { $0.parentID == nil }
    let outer = roots.count == 1 && roots[0].isGroup ? roots[0] : nil
    if let outer { roots = source.layers.filter { $0.parentID == outer.id } }
    roots = roots.filter { $0.visible && (outer?.visible ?? true) }
    guard roots.count <= 16, source.width*source.height*max(1,roots.count) <= maximumTotalPixels else { throw CraftError.unsupported("Image statistics supports sixteen frames and a combined 16 megapixel sample grid.") }
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
      frames.append(try Renderer.composite(isolated))
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
    let pixels = try mode.map { try render(source,mode:$0,in:document) } ?? ColorManagement.converted(Renderer.composite(source),from:source,to:document)
    return .smartObjectStack(layerID,mode,pixels)
  }
  public static func prepare(_ sources: [CraftDocument],settings: ImageStackSettings,name: String = "Untitled Stack") throws -> Result {
    try settings.validate();try Task.checkCancellation()
    guard (2...16).contains(sources.count) else { throw CraftError.invalid("Choose two to sixteen source images.") }
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 256 else { throw CraftError.invalid("Choose a document name with 1–256 characters.") }
    for source in sources { try SmartObjectIO.check(source) }
    let width = sources.map(\.width).max()!,height = sources.map(\.height).max()!
    guard width*height*sources.count <= maximumTotalPixels else { throw CraftError.unsupported("Image stacks support a combined 16 megapixel sample grid.") }
    let first = sources[0]
    var output = try CraftDocument(width:width,height:height,depth:first.depth)
    output.layers = [];output.name = name;output.workingICC = first.workingICC;output.resolution = first.resolution
    for source in sources {
      try Task.checkCancellation()
      let pixels = try ColorManagement.converted(Renderer.composite(source),from:source,to:output)
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
