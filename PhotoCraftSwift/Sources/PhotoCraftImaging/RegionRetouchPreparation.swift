import Foundation
import PhotoCraftCore

/// Native selection repair. Normal Patch adapts PhotoCraft's retouch_cmds/patch.rs;
/// Move/Extend and Red Eye are independent Swift implementations, not Adobe algorithms.
public enum RegionRetouchPreparation {
  public static let maximumCanvasPixels = 16_777_216
  public static let maximumRegionPixels = 4_194_304

  public static func prepare(_ request: RegionRetouchRequest, document: CraftDocument, layerID: UUID) throws -> RegionRetouchEdit {
    try request.validate(); try document.validate(); try Task.checkCancellation()
    guard document.width <= maximumCanvasPixels/document.height,
      let layer = document.layers.first(where: { $0.id == layerID }),
      case .raster(let source) = layer.content, layer.smartObject == nil, !document.isImageLocked(layerID)
    else { throw CraftError.invalid("Retouching requires an unlocked raster layer and a canvas of at most 16 megapixels.") }
    // Current-layer sampling uses original pixels directly, excluding effects/masks. Composite
    // sampling is normalized at this boundary: renderer buffers are linear 32-bit even for RGB8/16.
    let rendered = try request.sampleAllLayers ? Renderer.composite(document) : nil
    let inverse = try layer.coordinateTransform.inverted()
    var guide = try Surface(width:document.width,height:document.height,depth:document.depth,colorEncoding:document.depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<document.height { try Task.checkCancellation();for x in 0..<document.width {
      let value: Pixel
      if let rendered { value = document.depth == .f32 ? rendered.linearPixel(x:x,y:y):rendered.pixel(x:x,y:y) }
      else { let p = inverse.point(Double(x)+0.5,Double(y)+0.5);value = CropGeometry.sample(source,x:p.x,y:p.y) }
      write(&guide,x,y,value)
    } }
    let selection = try document.coverageSelection()
    if request.kind == .redEye {
      return try redEye(request,document:document,layerID:layerID,guide:guide,selection:selection)
    }
    guard let selection, let bounds = selection.bounds else { throw CraftError.invalid("Select the area to retouch first.") }
    if request.kind == .patch {
      return try patch(request,document:document,layerID:layerID,guide:guide,selection:selection,bounds:bounds)
    }
    return try move(request,document:document,layerID:layerID,guide:guide,selection:selection,bounds:bounds)
  }

  private static func pixel(_ image: Surface,_ x: Int,_ y: Int) -> Pixel {
    image.depth == .f32 ? image.linearPixel(x:x,y:y) : image.pixel(x:x,y:y)
  }
  private static func write(_ image: inout Surface,_ x: Int,_ y: Int,_ value: Pixel) {
    if image.depth == .f32 { image.setLinearPixel(x:x,y:y,value) } else { image.setPixel(x:x,y:y,value) }
  }
  private static func flags(_ mask: SelectionMask,box: IntRect,threshold: UInt8) throws -> [Bool] {
    guard box.width > 0,box.height > 0,box.width <= maximumRegionPixels/box.height else { throw CraftError.invalid("Retouching region exceeds 4 megapixels.") }
    var result = [Bool](repeating:false,count:box.width*box.height)
    for y in 0..<box.height { try Task.checkCancellation();for x in 0..<box.width {
      result[y*box.width+x] = mask.bytes[(y+box.y)*mask.width+x+box.x] > threshold
    } }
    return result
  }
  private static func values(_ image: Surface,_ box: IntRect) throws -> [Float] {
    guard box.width > 0,box.height > 0,box.width <= maximumRegionPixels/box.height else { throw CraftError.invalid("Retouching region exceeds 4 megapixels.") }
    var result = [Float](repeating:0,count:box.width*box.height*4)
    for y in 0..<box.height { try Task.checkCancellation(); for x in 0..<box.width {
      let p = pixel(image,x+box.x,y+box.y),i = (y*box.width+x)*4
      result[i] = p.r; result[i+1] = p.g; result[i+2] = p.b; result[i+3] = p.a
    } }
    return result
  }
  private static func surface(_ data: [Float],box: IntRect,depth: PixelDepth) throws -> Surface {
    var image = try Surface(width:box.width,height:box.height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<box.height { try Task.checkCancellation(); for x in 0..<box.width {
      let i = (y*box.width+x)*4
      let p = Pixel(data[i],data[i+1],data[i+2],unit(data[i+3]))
      guard p.isFinite else { throw CraftError.invalid("Retouching produced non-finite pixels.") }
      write(&image,x,y,p)
    } }
    return image
  }
  private static func expand(_ box: IntRect,by n: Int,in document: CraftDocument) -> IntRect {
    IntRect(x:box.x-n,y:box.y-n,width:box.width+2*n,height:box.height+2*n).clipped(toWidth:document.width,height:document.height)
  }
  private static func union(_ a: IntRect,_ b: IntRect) -> IntRect {
    let x = min(a.x,b.x),y = min(a.y,b.y)
    return IntRect(x:x,y:y,width:max(a.x+a.width,b.x+b.width)-x,height:max(a.y+a.height,b.y+b.height)-y)
  }
  private static func commit(_ pixels: Surface,box: IntRect,coverage: SelectionMask,selection: SelectionMask?,document: CraftDocument,layerID: UUID,label: String) throws -> RegionRetouchEdit {
    var result = try ContentAwareEdit(layerID:layerID,output:.current,window:box,pixels:pixels,selection:coverage).applied(to:document)
    if let selection { result.setCoverageSelection(selection) } else { result.selection = nil; result.selectionMask = nil }
    return RegionRetouchEdit(source:document,result:result,label:label)
  }
  private static func patch(_ r: RegionRetouchRequest,document d: CraftDocument,layerID: UUID,guide: Surface,selection: SelectionMask,bounds: IntRect) throws -> RegionRetouchEdit {
    guard r.dx != 0 || r.dy != 0 else { throw CraftError.invalid("Drag the patch to a different area.") }
    let dx = Int(r.dx),dy = Int(r.dy)
    let shifted = IntRect(x:bounds.x+dx,y:bounds.y+dy,width:bounds.width,height:bounds.height)
    guard shifted == shifted.clipped(toWidth:d.width,height:d.height) else { throw CraftError.invalid("Keep the dragged patch inside the canvas.") }
    let destination = r.patchMode == .destination
    let targetMask = try destination ? selection.transformed(by:.translation(r.dx,r.dy),width:d.width,height:d.height) : selection
    let target = destination ? shifted:bounds, sx = destination ? -dx:dx,sy = destination ? -dy:dy
    var box = expand(target,by:2,in:d)
    // Like the source port, omit unavailable source boundary pixels rather than sampling clear outside the canvas.
    let x = max(box.x,-sx),y = max(box.y,-sy),right = min(box.x+box.width,d.width-sx),bottom = min(box.y+box.height,d.height-sy)
    box = IntRect(x:x,y:y,width:right-x,height:bottom-y)
    let dst = try values(guide,box),src = try values(guide,IntRect(x:box.x+sx,y:box.y+sy,width:box.width,height:box.height))
    let hole = try flags(targetMask,box:box,threshold:0)
    var solution = try HealingSolver.seamlessClone(width:box.width,height:box.height,channels:4,source:src,destination:dst,mask:hole)
    if r.patchType == .contentAware {
      let sampleMask = try destination ? selection : selection.transformed(by:.translation(r.dx,r.dy),width:d.width,height:d.height)
      let region = expand(union(bounds,shifted),by:4,in:d)
      var settings = ContentAwareSettings(); settings.colorAdaptation = .none;settings.seed = r.seed
      let image = try values(guide,region)
      let holes = try flags(targetMask,box:region,threshold:0)
      let allowed = try flags(sampleMask,box:region,threshold:127)
      let synthesized = try ContentAwareSynthesis.fill(width:region.width,height:region.height,image:image,hole:holes,source:allowed,settings:settings,hdr:d.depth == .f32)
      var adaptedSource = src
      let retain = Float(r.structure-1)/6
      for y in 0..<box.height { for x in 0..<box.width where hole[y*box.width+x] {
        let i = (y*box.width+x)*4,j = ((y+box.y-region.y)*region.width+x+box.x-region.x)*4
        for c in 0..<4 { adaptedSource[i+c] = src[i+c]*retain+synthesized[j+c]*(1-retain) }
      } }
      let healed = try HealingSolver.seamlessClone(width:box.width,height:box.height,channels:4,source:adaptedSource,destination:dst,mask:hole)
      let amount = Float(r.color)/10
      for i in solution.indices { solution[i] = adaptedSource[i]+(healed[i]-adaptedSource[i])*amount }
    } else if r.diffusion != 5 {
      // Vary the smooth boundary correction while retaining full-resolution source texture.
      let amount = Float(r.diffusion)/5
      for i in solution.indices { solution[i] = src[i]+(solution[i]-src[i])*amount }
    }
    var coverage = targetMask
    if r.transparent {
      var bytes = coverage.bytes
      for y in 0..<box.height { for x in 0..<box.width { let i = y*box.width+x,j = (y+box.y)*d.width+x+box.x; bytes[j] = UInt8((Float(bytes[j])*unit(src[i*4+3])).rounded()) } }
      coverage = try SelectionMask(width:d.width,height:d.height,bytes:bytes)
    }
    guard coverage.bounds != nil else { return RegionRetouchEdit(source:d,result:d,label:r.label) }
    return try commit(surface(solution,box:box,depth:d.depth),box:box,coverage:coverage,selection:destination ? targetMask:selection,document:d,layerID:layerID,label:r.label)
  }

  private static func move(_ r: RegionRetouchRequest,document d: CraftDocument,layerID: UUID,guide: Surface,selection: SelectionMask,bounds: IntRect) throws -> RegionRetouchEdit {
    let transform = r.transform(bounds:bounds)
    guard transform != .identity else { throw CraftError.invalid("Drag or transform the selected area first.") }
    let moved = try selection.transformed(by:transform,width:d.width,height:d.height)
    guard let destination = moved.bounds else { throw CraftError.invalid("Keep some of the moved area on the canvas.") }
    let window = expand(union(bounds,destination),by:2,in:d)
    var output = try values(guide,window)
    if r.moveMode == .move {
      let region = expand(bounds,by:max(32,max(bounds.width,bounds.height)/2),in:d)
      let image = try values(guide,region)
      let hole = try flags(selection,box:region,threshold:0)
      var settings = ContentAwareSettings();settings.seed = r.seed
      let filled = try ContentAwareSynthesis.fill(width:region.width,height:region.height,image:image,hole:hole,source:hole.map { !$0 },settings:settings,hdr:d.depth == .f32)
      for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
        let px = x+window.x,py = y+window.y,k = Float(selection.bytes[py*d.width+px])/255
        guard k > 0 else { continue }
        let i = (y*window.width+x)*4,j = ((py-region.y)*region.width+px-region.x)*4
        for c in 0..<4 { output[i+c] += (filled[j+c]-output[i+c])*k }
      } }
    }
    let inverse = try transform.inverted()
    var source = output
    let hole = try flags(moved,box:window,threshold:0)
    for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
      let p = inverse.point(Double(x+window.x)+0.5,Double(y+window.y)+0.5)
      let value = CropGeometry.sample(guide,x:p.x,y:p.y),i = (y*window.width+x)*4
      source[i] = value.r;source[i+1] = value.g;source[i+2] = value.b;source[i+3] = value.a
    } }
    let healed = try HealingSolver.seamlessClone(width:window.width,height:window.height,channels:4,source:source,destination:output,mask:hole)
    // Structure preserves source texture; color controls the low-frequency destination fit.
    let amount = Float(r.color)/10 * (1-Float(r.structure-1)/12)
    var changed = [UInt8](repeating:0,count:d.width*d.height)
    for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
      let j = (y+window.y)*d.width+x+window.x,i = (y*window.width+x)*4,k = Float(moved.bytes[j])/255
      if r.moveMode == .move && selection.bytes[j] > 0 { changed[j] = 255 }
      if k > 0 {
        changed[j] = 255
        let a = unit(source[i+3])*k,oldA = unit(output[i+3]),outA = a+oldA*(1-a)
        for c in 0..<3 { let value = source[i+c]+(healed[i+c]-source[i+c])*amount;output[i+c] = outA > 0 ? (value*a+output[i+c]*oldA*(1-a))/outA:0 }
        output[i+3] = outA
      }
    } }
    return try commit(surface(output,box:window,depth:d.depth),box:window,coverage:SelectionMask(width:d.width,height:d.height,bytes:changed),selection:moved,document:d,layerID:layerID,label:r.label)
  }

  private static func redEye(_ r: RegionRetouchRequest,document d: CraftDocument,layerID: UUID,guide: Surface,selection: SelectionMask?) throws -> RegionRetouchEdit {
    let box = r.region!.clipped(toWidth:d.width,height:d.height)
    var output = try values(guide,box),weights = [Float](repeating:0,count:box.width*box.height)
    var total = 0.0,cx = 0.0,cy = 0.0
    // Work in display RGB for redness detection, but retain linear HDR storage in the correction.
    for y in 0..<box.height { try Task.checkCancellation(); for x in 0..<box.width {
      let p = guide.pixel(x:x+box.x,y:y+box.y),i = y*box.width+x
      let red = max(0,p.r-max(p.g,p.b)*1.35-0.04)
      let selected = Float(selection?.bytes[(y+box.y)*d.width+x+box.x] ?? 255)/255
      let weight = red*selected*p.a;weights[i] = weight
      total += Double(weight);cx += Double(weight)*(Double(x)+0.5);cy += Double(weight)*(Double(y)+0.5)
    } }
    guard total > 0 else { return RegionRetouchEdit(source:d,result:d,label:r.label) }
    cx /= total;cy /= total
    let radius = max(1,Double(min(box.width,box.height))*(0.15+0.85*r.pupilSize/100)/2)
    var coverage = [UInt8](repeating:0,count:d.width*d.height)
    for y in 0..<box.height { try Task.checkCancellation(); for x in 0..<box.width {
      let i = y*box.width+x,j = (y+box.y)*d.width+x+box.x
      let edge = min(1,max(0,radius+0.5-hypot(Double(x)+0.5-cx,Double(y)+0.5-cy)))
      guard weights[i] > 0,edge > 0 else { continue }
      let p = i*4,neutral = (output[p+1]+output[p+2])/2,amount = Float(r.darken/100)
      output[p] = neutral*(1-0.75*amount)
      output[p+1] *= 1-0.75*amount;output[p+2] *= 1-0.75*amount
      coverage[j] = UInt8((edge*Double(selection?.bytes[j] ?? 255)).rounded())
    } }
    let mask = try SelectionMask(width:d.width,height:d.height,bytes:coverage)
    guard mask.bounds != nil else { return RegionRetouchEdit(source:d,result:d,label:r.label) }
    return try commit(surface(output,box:box,depth:d.depth),box:box,coverage:mask,selection:selection,document:d,layerID:layerID,label:r.label)
  }
}
