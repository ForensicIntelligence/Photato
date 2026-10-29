import Foundation
import PhotoCraftCore

public struct PhotomergeSettings: Codable, Equatable, Sendable {
  public var projection: PhotoAlignSettings.Projection = .auto
  public var blendImages = true
  public var fillTransparentAreas = false
  public var focalLengthPixels: Double?
  public init() {}
  public func validate() throws { var align = PhotoAlignSettings();align.focalLengthPixels = focalLengthPixels;try align.validate() }
}
/// Native multi-document panorama construction. Input documents are immutable snapshots;
/// individual photographs are flattened and converted into the first source's working space.
public enum Photomerge {
  public struct Result: Sendable {
    public let document: CraftDocument
    public let projection: PhotoAlignSettings.Projection
    public let matchedPoints: Int
    public let rmsPixels: Double
  }
  public static func prepare(_ sources: [CraftDocument],settings: PhotomergeSettings,name: String = "Untitled Panorama") throws -> Result {
    try Task.checkCancellation();try settings.validate()
    guard (2...PhotoAlign.maximumLayers).contains(sources.count) else { throw CraftError.invalid("Photomerge needs two to sixteen source images.") }
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count <= 256 else { throw CraftError.invalid("Choose a panorama name with 1–256 characters.") }
    var total = 0
    for source in sources { try source.validate();guard source.width*source.height <= PhotoAlign.maximumPixels else { throw CraftError.unsupported("A Photomerge source exceeds the 16 megapixel working limit.") };total += source.width*source.height }
    guard total <= PhotoAlign.maximumTotalPixels else { throw CraftError.unsupported("Photomerge sources exceed the combined 32 megapixel working limit.") }
    let first = sources[0]
    var input = try CraftDocument(width:first.width,height:first.height,depth:first.depth)
    input.layers = [];input.name = name;input.workingICC = first.workingICC;input.resolution = first.resolution
    for source in sources {
      try Task.checkCancellation()
      let surface = try ColorManagement.converted(Renderer.composite(source),from:source,to:input)
      input.layers.append(Layer(name:source.name,content:.raster(surface)))
    }
    input.activeLayerID = input.layers.last!.id
    var align = PhotoAlignSettings();align.projection = settings.projection;align.focalLengthPixels = settings.focalLengthPixels
    let aligned = try PhotoAlign.prepare(input,layerIDs:Set(input.layers.map(\.id)),settings:align)
    var output = aligned.result
    let bounds = try output.layers.map { layer -> IntRect in
      guard case .raster(let s) = layer.content else { throw CraftError.invalid("Missing panorama source pixels.") };return try layer.coordinateTransform.bounds(width:s.width,height:s.height)
    }
    let x0 = bounds.map(\.x).min()!,y0 = bounds.map(\.y).min()!,x1 = bounds.map{$0.x+$0.width}.max()!,y1 = bounds.map{$0.y+$0.height}.max()!
    let w = x1-x0,h = y1-y0
    guard w > 0,h > 0,w <= Surface.maxDimension,h <= Surface.maxDimension,w <= PhotoAlign.maximumPixels/h else { throw CraftError.unsupported("The panorama exceeds the 16 megapixel canvas limit. Try a different projection or smaller sources.") }
    output.width = w;output.height = h
    for i in output.layers.indices { output.layers[i].x -= x0;output.layers[i].y -= y0 }
    try output.validate()
    if settings.blendImages {
      var blend = PhotoBlendSettings();blend.seamlessTones = true;blend.fillTransparentAreas = settings.fillTransparentAreas
      output = try PhotoBlend.prepare(output,layerIDs:Set(output.layers.map(\.id)),settings:blend).result
      if let last = output.layers.indices.last { output.layers[last].name = "Panorama" }
    } else if settings.fillTransparentAreas {
      // Preserve the unblended photo layers and add only newly synthesized hole pixels.
      guard w <= PhotoBlend.maximumPixels/h else { throw CraftError.unsupported("Transparent-area fill supports panoramas up to 4 megapixels.") }
      let composite = try Renderer.composite(output),count = w*h
      var rgba = [Float](repeating:0,count:count*4),holes = [Bool](repeating:false,count:count),sample = holes
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let p = output.depth == .f32 ? composite.linearPixel(x:x,y:y):composite.pixel(x:x,y:y),i = y*w+x
        rgba[i*4] = p.r;rgba[i*4+1] = p.g;rgba[i*4+2] = p.b;rgba[i*4+3] = p.a;holes[i] = p.a <= 0;sample[i] = p.a > 0.99
      } }
      if holes.contains(true) {
        var options = ContentAwareSettings();options.colorAdaptation = .none;options.seed = 1
        let filled = try ContentAwareSynthesis.fill(width:w,height:h,image:rgba,hole:holes,source:sample,settings:options,hdr:output.depth == .f32)
        var surface = try Surface(width:w,height:h,depth:output.depth,colorEncoding:output.depth == .f32 ? .linearRGB:.sRGB)
        for y in 0..<h { try Task.checkCancellation();for x in 0..<w where holes[y*w+x] {
          let i = (y*w+x)*4,p = Pixel(filled[i],filled[i+1],filled[i+2],1)
          if output.depth == .f32 { surface.setLinearPixel(x:x,y:y,p) } else { surface.setPixel(x:x,y:y,p) }
        } }
        let layer = Layer(name:"Content-Aware Fill",content:.raster(surface));output.layers.append(layer);output.activeLayerID = layer.id
      }
    }
    try output.validate();return Result(document:output,projection:aligned.projection,matchedPoints:aligned.matchedPoints,rmsPixels:aligned.rmsPixels)
  }
}
