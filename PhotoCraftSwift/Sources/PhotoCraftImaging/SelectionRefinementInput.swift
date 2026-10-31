import Foundation
import PhotoCraftCore

public struct SelectionRefinementInput: Sendable {
  public let original: CraftDocument
  public let layerID: UUID
  public let guide: Surface
  public let mask: SelectionMask
  public static func prepare(_ document: CraftDocument,layerID: UUID,fromLayerMask: Bool = false,sampleAllLayers: Bool = false) throws -> Self {
    try SelectionMatting.checkSize(document.width,document.height)
    guard let layer = document.layers.first(where: { $0.id == layerID }), case .raster(let pixels) = layer.content,
      layer.smartObject == nil else { throw CraftError.invalid("Select and Mask requires an ordinary pixel layer. Rasterize a copy of the Smart Object first.") }
    try SelectionMatting.checkSize(pixels.width,pixels.height)
    var source = layer; source.mask = nil; source.maskProperties = nil; source.vectorMask = nil; source.visible = true; source.style = nil
    let guide = try sampleAllLayers ? Renderer.composite(document) : Renderer.clippingCoverage(source,in:document)
    let mask: SelectionMask
    if fromLayerMask {
      guard layer.mask != nil else { throw CraftError.invalid("The layer has no pixel mask.") }
      var masked = layer; masked.vectorMask = nil
      var properties = masked.effectiveMaskProperties; properties.enabled = true; properties.density = 1; properties.feather = 0; masked.maskProperties = properties
      let sampler = try MaskSampler(layer:masked,canvasSize:(document.width,document.height))
      var bytes = [UInt8](repeating:0,count:document.width*document.height)
      for y in 0..<document.height { try Task.checkCancellation(); for x in 0..<document.width {
        bytes[y*document.width+x] = UInt8((min(1,max(0,sampler.coverage(x:Double(x)+0.5,y:Double(y)+0.5)))*255).rounded())
      } }
      mask = try SelectionMask(width:document.width,height:document.height,bytes:bytes)
    } else {
      mask = try document.coverageSelection() ?? SelectionMask(width:document.width,height:document.height,bytes:Array(repeating:0,count:document.width*document.height))
    }
    return Self(original:document,layerID:layerID,guide:guide,mask:mask)
  }
  public func refined(settings: SelectionRefinement,strokes: [SelectionRefinementStroke] = [], initial: SelectionMask? = nil) throws -> SelectionMask {
    let input = initial ?? mask, w = guide.width, h = guide.height
    guard input.width == w, input.height == h, strokes.count <= 1024, strokes.reduce(0,{ $0+$1.points.count }) <= 16384 else { throw CraftError.invalid("Refinement brush limit exceeded or input size differs.") }
    var bytes = (try input.bytes), edge = [UInt8](repeating:0,count:w*h), excluded = edge
    var visits = 0
    for stroke in strokes {
      try stroke.validate()
      if stroke.tool == .lassoAdd || stroke.tool == .lassoSubtract {
        visits += w*h; guard visits <= 250_000_000 else { throw CraftError.invalid("Refinement brush work limit exceeded.") }
        let polygon = try SelectionMask.make(.polygon(stroke.points.map { SelectionPoint($0[0],$0[1]) }),width:w,height:h,antiAlias:true)
        for i in bytes.indices { bytes[i] = stroke.tool == .lassoAdd ? max(bytes[i],polygon.byte(at:i)) : min(bytes[i],255-polygon.byte(at:i)) }
        continue
      }
      var coverage = [UInt8](repeating:0,count:w*h)
      let r = stroke.size/2
      for j in stroke.points.indices {
        let a = stroke.points[max(0,j-1)], b = stroke.points[j]
        let x0 = min(w,max(0,Int(floor(min(a[0],b[0])-r)))), x1 = min(w,max(0,Int(ceil(max(a[0],b[0])+r))))
        let y0 = min(h,max(0,Int(floor(min(a[1],b[1])-r)))), y1 = min(h,max(0,Int(ceil(max(a[1],b[1])+r))))
        visits += (x1-x0)*(y1-y0); guard visits <= 250_000_000 else { throw CraftError.invalid("Refinement brush work limit exceeded.") }
        let dx = b[0]-a[0], dy = b[1]-a[1], length = dx*dx+dy*dy
        for y in y0..<y1 { try Task.checkCancellation(); for x in x0..<x1 {
          let px = Double(x)+0.5-a[0], py = Double(y)+0.5-a[1]
          let t = length > 0 ? min(1,max(0,(px*dx+py*dy)/length)) : 0
          let d = hypot(px-t*dx,py-t*dy)/r
          let alpha = min(1,max(0,(1-d)/max(0.001,1-stroke.hardness)))
          coverage[y*w+x] = max(coverage[y*w+x],UInt8((alpha*255).rounded()))
        } }
      }
      for i in bytes.indices where coverage[i] > 0 {
        let c = Int(coverage[i])
        switch stroke.tool {
        case .add: bytes[i] = UInt8(Int(bytes[i])+(255-Int(bytes[i]))*c/255)
        case .subtract: bytes[i] = UInt8(Int(bytes[i])*(255-c)/255)
        case .refine: edge[i] = max(edge[i],coverage[i]); excluded[i] = min(excluded[i],255-coverage[i])
        case .eraseRefinement: excluded[i] = max(excluded[i],coverage[i]); edge[i] = min(edge[i],255-coverage[i])
        default: break
        }
      }
    }
    return try SelectionMatting.refine(SelectionMask(width:w,height:h,bytes:bytes),guide:guide,settings:settings,
      edge:SelectionMask(width:w,height:h,bytes:edge),excluded:SelectionMask(width:w,height:h,bytes:excluded))
  }
  public func edit(settings: SelectionRefinement,output: SelectionRefinementOutput,strokes: [SelectionRefinementStroke] = [],initial: SelectionMask? = nil) throws -> SelectionRefinementEdit {
    let mask = try refined(settings:settings,strokes:strokes,initial:initial)
    let corrected = try correctedPixels(mask:mask,settings:settings)
    return SelectionRefinementEdit(layerID:layerID,output:output.allowingDecontamination(settings.decontaminate),mask:mask,corrected:corrected)
  }
  public func correctedPixels(mask: SelectionMask,settings: SelectionRefinement) throws -> Surface? {
    try settings.validate()
    guard mask.width == original.width, mask.height == original.height else { throw CraftError.invalid("Refinement canvas sizes differ.") }
    var corrected: Surface?
    if settings.decontaminate, let layer = original.layers.first(where: { $0.id == layerID }), case .raster(let source) = layer.content {
      try SelectionMatting.checkSize(source.width,source.height)
      var bytes = [UInt8](repeating:0,count:source.width*source.height)
      for y in 0..<source.height { try Task.checkCancellation(); for x in 0..<source.width {
        let p = layer.coordinateTransform.point(Double(x)+0.5,Double(y)+0.5), ix = Int(floor(p.x)), iy = Int(floor(p.y))
        if ix >= 0, iy >= 0, ix < mask.width, iy < mask.height { bytes[y*source.width+x] = mask.byte(at:iy*mask.width+ix) }
      } }
      corrected = try SelectionMatting.decontaminate(source,mask:SelectionMask(width:source.width,height:source.height,bytes:bytes),settings:settings)
    }
    return corrected
  }
  public func previewGuide(mask: SelectionMask,settings: SelectionRefinement) throws -> Surface {
    guard let corrected = try correctedPixels(mask:mask,settings:settings), var layer = original.layers.first(where: { $0.id == layerID }) else { return guide }
    layer.content = .raster(corrected); layer.mask = nil; layer.maskProperties = nil; layer.vectorMask = nil; layer.style = nil; layer.visible = true
    return try Renderer.clippingCoverage(layer,in:original)
  }
}
