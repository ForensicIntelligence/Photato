import Foundation
import PhotoCraftCore

public struct ContentAwareInput: Sendable {
  public let original: CraftDocument
  public let layerID: UUID
  public let layerGuide: Surface
  public let composite: Surface
  public let selection: SelectionMask
  public static let maximumCanvasPixels = 16_777_216
  public static func prepare(_ document: CraftDocument,layerID: UUID) throws -> Self {
    guard document.width <= maximumCanvasPixels/document.height, let mask = try document.coverageSelection(), mask.bounds != nil,
      var layer = document.layers.first(where: { $0.id == layerID }), case .raster(let pixels) = layer.content,
      layer.smartObject == nil, pixels.width <= maximumCanvasPixels/pixels.height else { throw CraftError.invalid("Content-Aware Fill requires a selection and an ordinary raster layer in a canvas of at most16 megapixels.") }
    layer.mask = nil; layer.maskProperties = nil; layer.vectorMask = nil; layer.visible = true; layer.style = nil; layer.opacity = 1
    return try Self(original:document,layerID:layerID,layerGuide:Renderer.clippingCoverage(layer,in:document),composite:Renderer.composite(document),selection:mask)
  }
  public func masks(settings: ContentAwareSettings,strokes: [ContentAwareStroke] = [],sampling: SelectionMask? = nil) throws -> (selection:SelectionMask,sampling:SelectionMask) {
    try settings.validate()
    guard strokes.count <= 256, strokes.reduce(0,{ $0+$1.points.count }) <= 16384 else { throw CraftError.invalid("Content-Aware Fill brush limit exceeded.") }
    if let sampling { guard sampling.width == original.width, sampling.height == original.height else { throw CraftError.invalid("Sampling channel dimensions differ.") } }
    var selected = selection
    for stroke in strokes where stroke.target == .selection { selected = try stroke.applying(to:selected) }
    guard let box = selected.bounds else { throw CraftError.invalid("The fill selection is empty.") }
    let margin = settings.sampling == .auto ? max(32,max(box.width,box.height)*3/4):settings.margin
    let rect = IntRect(x:box.x-margin,y:box.y-margin,width:box.width+2*margin,height:box.height+2*margin).clipped(toWidth:original.width,height:original.height)
    var source: SelectionMask
    if settings.sampling == .custom {
      source = try sampling ?? SelectionMask(width:original.width,height:original.height,bytes:Array(repeating:0,count:original.width*original.height))
    } else { source = try SelectionMask.make(.rectangle(rect),width:original.width,height:original.height,antiAlias:false) }
    for stroke in strokes where stroke.target == .sampling { source = try stroke.applying(to:source) }
    var bytes = try source.bytes
    for y in 0..<original.height { try Task.checkCancellation(); for x in 0..<original.width where selected.byte(at:y*original.width+x) > 0 { bytes[y*original.width+x] = 0 } }
    return (selected,try SelectionMask(width:original.width,height:original.height,bytes:bytes))
  }
  public func edit(settings: ContentAwareSettings,output: ContentAwareOutput = .new,strokes: [ContentAwareStroke] = [],sampling: SelectionMask? = nil) throws -> ContentAwareEdit {
    let masks = try masks(settings:settings,strokes:strokes,sampling:sampling)
    guard let selected = masks.selection.bounds,let source = masks.sampling.bounds else { throw CraftError.invalid("Add a sampling area outside the selection.") }
    let x = min(selected.x,source.x),y = min(selected.y,source.y)
    let window = IntRect(x:x,y:y,width:max(selected.x+selected.width,source.x+source.width)-x,height:max(selected.y+selected.height,source.y+source.height)-y)
    guard window.width <= ContentAwareSynthesis.maximumPixels/window.height else { throw CraftError.invalid("Sampling region exceeds 4 megapixels. Choose a smaller sampling area.") }
    let guide = settings.sampleAllLayers ? composite:layerGuide, count = window.width*window.height
    var image = [Float](repeating:0,count:count*4),hole = [Bool](repeating:false,count:count),allowed = hole
    for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
      let dx = x+window.x,dy = y+window.y,i = y*window.width+x,j = dy*original.width+dx
      let p = original.depth == .f32 ? guide.linearPixel(x:dx,y:dy):guide.pixel(x:dx,y:dy)
      image[i*4] = p.r; image[i*4+1] = p.g; image[i*4+2] = p.b; image[i*4+3] = p.a
      hole[i] = masks.selection.byte(at:j) > 0; allowed[i] = masks.sampling.byte(at:j) > 127
    } }
    let filled = try ContentAwareSynthesis.fill(width:window.width,height:window.height,image:image,hole:hole,source:allowed,settings:settings,hdr:original.depth == .f32)
    var pixels = try Surface(width:window.width,height:window.height,depth:original.depth,colorEncoding:original.depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
      let i = (y*window.width+x)*4,p = Pixel(filled[i],filled[i+1],filled[i+2],unit(filled[i+3]))
      if original.depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) }
    } }
    return ContentAwareEdit(layerID:layerID,output:output,window:window,pixels:pixels,selection:masks.selection)
  }
}
