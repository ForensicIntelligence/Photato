import Foundation

public struct PhotoBlendSettings: Codable, Equatable, Sendable {
  public enum Method: String, CaseIterable, Codable, Sendable { case panorama,stack }
  public var method: Method = .panorama
  public var seamlessTones = true
  public var fillTransparentAreas = true
  public init() {}
}
public struct PhotoBlendEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let selectedLayerIDs: Set<UUID>
  public init(source: CraftDocument,result: CraftDocument,selectedLayerIDs: Set<UUID>) { self.source = source;self.result = result;self.selectedLayerIDs = selectedLayerIDs }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source else { throw CraftError.invalid("Document changed during Auto-Blend.") }
    try result.validate();return result
  }
}
/// All operations use native pixel coordinates; registration is a separate workflow.
public enum PhotoBlend {
  public static let maximumPixels = 4_194_304
  public static let maximumTotalPixels = 16_777_216
  public static let maximumLayers = 16
  public static func targets(_ ids: Set<UUID>,in d: CraftDocument) throws -> [Layer] {
    guard (2...maximumLayers).contains(ids.count) else { throw CraftError.invalid("Select two to sixteen pixel layers for Auto-Blend.") }
    let layers = d.layers.filter { ids.contains($0.id) }
    guard layers.count == ids.count else { throw CraftError.invalid("An Auto-Blend layer no longer exists.") }
    let parent = layers[0].parentID
    for l in layers {
      guard case .raster = l.content,l.smartObject == nil,l.smartFilters == nil,l.style == nil,l.vectorMask == nil,
        l.blendMode == .normal,l.opacity == 1,l.clipped != true,l.visible,l.parentID == parent,
        !d.isImageLocked(l.id),!d.isTransparencyLocked(l.id)
      else { throw CraftError.unsupported("Auto-Blend requires visible, unlocked pixel layers in one group, with Normal blending and full opacity. Rasterize Smart Objects/effects first.") }
    }
    return layers
  }
  public static func prepare(_ d: CraftDocument,layerIDs: Set<UUID>,settings: PhotoBlendSettings) throws -> PhotoBlendEdit {
    try d.validate();let layers = try targets(layerIDs,in:d)
    var box: IntRect?
    for l in layers {
      guard case .raster(let s) = l.content else { continue }
      let b = try l.coordinateTransform.bounds(width:s.width,height:s.height).clipped(toWidth:d.width,height:d.height)
      guard b.width > 0,b.height > 0 else { continue }
      if let old = box { let x = min(old.x,b.x),y = min(old.y,b.y);box = IntRect(x:x,y:y,width:max(old.x+old.width,b.x+b.width)-x,height:max(old.y+old.height,b.y+b.height)-y) } else { box = b }
    }
    guard let box,box.width <= maximumPixels/box.height,box.width*box.height <= maximumTotalPixels/layers.count else { throw CraftError.unsupported("Auto-Blend exceeds the 4 megapixel output or 16 megapixel input working budget.") }
    let w = box.width,h = box.height,count = w*h
    var images = [[Float]](),alpha = [[Float]](),luma = [[Float]](),oldMasks = [[Float]]()
    for l in layers {
      guard case .raster(let s) = l.content else { continue }
      let inverse = try l.coordinateTransform.inverted(),mask = try l.mask.map { _ in try MaskSampler(layer:l,canvasSize:(d.width,d.height)) }
      var pixels = [Float](repeating:0,count:count*3),a = [Float](repeating:0,count:count),light = a,masks = a
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let dx = Double(x+box.x)+0.5,dy = Double(y+box.y)+0.5,p = inverse.point(dx,dy)
        let value = CropGeometry.sample(s,x:p.x,y:p.y),i = y*w+x,m = mask?.coverage(x:dx,y:dy) ?? 1
        pixels[i*3] = value.r;pixels[i*3+1] = value.g;pixels[i*3+2] = value.b
        a[i] = unit(value.a)*m;masks[i] = m;light[i] = 0.2126*value.r+0.7152*value.g+0.0722*value.b
      } }
      images.append(pixels);alpha.append(a);luma.append(light);oldMasks.append(masks)
    }
    guard alpha.allSatisfy({$0.contains(where:{$0 > 0})}) else { throw CraftError.invalid("Every selected layer must contain visible pixels inside the canvas.") }
    let weights = try settings.method == .stack ? PhotoBlendWeights.focus(width:w,height:h,luma:luma,alpha:alpha):PhotoBlendWeights.panorama(width:w,height:h,luma:luma,alpha:alpha)
    let rgb = try PhotoPyramid.blend(width:w,height:h,images:images,coverage:alpha,weights:weights,seamless:settings.seamlessTones)
    var rgba = [Float](repeating:0,count:count*4),coverage = [Float](repeating:0,count:count)
    for i in 0..<count {
      for c in 0..<3 { rgba[i*4+c] = rgb[i*3+c] }
      // Preserve the selected winner's alpha; never double-composite source edges.
      for k in weights.indices where weights[k][i] > 0 { coverage[i] = alpha[k][i];break }
      rgba[i*4+3] = coverage[i]
    }
    let holes = coverage.map { $0 <= 0 }
    if settings.fillTransparentAreas,holes.contains(true) {
      var fill = ContentAwareSettings();fill.colorAdaptation = .none;fill.seed = 1
      rgba = try ContentAwareSynthesis.fill(width:w,height:h,image:rgba,hole:holes,source:coverage.map{$0 > 0.99},settings:fill,hdr:d.depth == .f32)
      for i in 0..<count where holes[i] { rgba[i*4+3] = 1 }
    }
    var result = d
    let merged = settings.seamlessTones || settings.fillTransparentAreas
    for (k,l) in layers.enumerated() {
      guard let i = result.layers.firstIndex(where:{$0.id == l.id}) else { continue }
      var mask = try Surface(width:w,height:h,depth:.u8)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let value = weights[k][y*w+x]*oldMasks[k][y*w+x];mask.setPixel(x:x,y:y,Pixel(value,value,value,1))
      } }
      var properties = MaskProperties();properties.transform = try l.coordinateTransform.inverted() * .translation(Double(box.x),Double(box.y))
      result.layers[i].mask = mask;result.layers[i].maskProperties = properties
      if merged { result.layers[i].visible = false }
    }
    if merged {
      guard result.layers.count < 512,let top = result.layers.lastIndex(where:{layerIDs.contains($0.id)}) else { throw CraftError.unsupported("Cannot add a blended layer to this document.") }
      var pixels = try Surface(width:w,height:h,depth:d.depth,colorEncoding:d.depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let i = (y*w+x)*4,p = Pixel(rgba[i],rgba[i+1],rgba[i+2],unit(rgba[i+3]))
        guard p.isFinite else { throw CraftError.invalid("Auto-Blend produced nonfinite pixels.") }
        if d.depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) }
      } }
      var layer = Layer(name:"Auto-Blend Layers",content:.raster(pixels));layer.x = box.x;layer.y = box.y;layer.parentID = layers[0].parentID
      result.layers.insert(layer,at:top+1);result.activeLayerID = layer.id
    }
    try result.validate();return PhotoBlendEdit(source:d,result:result,selectedLayerIDs:merged ? Set(result.activeLayerID.map { [$0] } ?? []):layerIDs)
  }
}
