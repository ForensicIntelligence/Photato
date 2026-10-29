import Foundation

public struct PhotoAlignEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let selectedLayerIDs: Set<UUID>
  public let projection: PhotoAlignSettings.Projection
  public let matchedPoints: Int
  public let rmsPixels: Double
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation();guard document == source else { throw CraftError.invalid("Document changed during Auto-Align.") };try result.validate();return result
  }
}
public enum PhotoAlign {
  public static let maximumLayers = 16
  public static let maximumPixels = 16_777_216
  public static let maximumTotalPixels = 33_554_432
  public static func targets(_ ids: Set<UUID>,in d: CraftDocument) throws -> [Layer] {
    guard (2...maximumLayers).contains(ids.count) else { throw CraftError.invalid("Select two to sixteen pixel layers for Auto-Align.") }
    let layers = d.layers.filter{ids.contains($0.id)}
    guard layers.count == ids.count else { throw CraftError.invalid("An Auto-Align layer no longer exists.") }
    var pixels = 0
    for l in layers {
      guard case .raster(let s) = l.content,l.smartObject == nil,l.smartFilters == nil,l.style == nil,l.vectorMask == nil,l.clipped != true,l.visible,l.parentID == layers[0].parentID else { throw CraftError.unsupported("Auto-Align requires visible pixel layers in one group. Rasterize Smart Objects, effects and vector masks first.") }
      guard s.width*s.height <= maximumPixels else { throw CraftError.unsupported("Auto-Align supports up to 16 megapixels per layer.") };pixels += s.width*s.height
    }
    guard pixels <= maximumTotalPixels else { throw CraftError.unsupported("Auto-Align exceeds the 32 megapixel combined working budget.") }
    guard layers.filter({d.isImageLocked($0.id) || d.isPositionLocked($0.id) || d.isTransparencyLocked($0.id)}).count <= 1 else { throw CraftError.unsupported("Only one locked reference layer can be selected for Auto-Align.") }
    return layers
  }
  public static func prepare(_ d: CraftDocument,layerIDs: Set<UUID>,settings: PhotoAlignSettings) throws -> PhotoAlignEdit {
    try Task.checkCancellation();try d.validate();try settings.validate();let layers = try targets(layerIDs,in:d)
    let locked = layers.firstIndex{d.isImageLocked($0.id) || d.isPositionLocked($0.id) || d.isTransparencyLocked($0.id)}
    let reference: Int
    if let id = settings.referenceLayerID { guard let i = layers.firstIndex(where:{$0.id == id}) else { throw CraftError.invalid("Reference layer must be selected.") };reference = i } else { reference = locked ?? 0 }
    guard locked == nil || locked == reference else { throw CraftError.unsupported("The locked layer must be the alignment reference.") }
    let surfaces = layers.compactMap { l -> Surface? in if case .raster(let s) = l.content { return s };return nil }
    let scale = min(1,900/Double(surfaces.map{max($0.width,$0.height)}.max() ?? 1))
    var features = [PhotoFeatures]()
    for (i,s) in surfaces.enumerated() {
      let w = max(1,Int(Double(s.width)*scale)),h = max(1,Int(Double(s.height)*scale))
      var luma = [Float](repeating:0,count:w*h),valid = [Bool](repeating:false,count:w*h)
      let layer = layers[i],mask = try layer.mask.map{_ in try MaskSampler(layer:layer,canvasSize:(d.width,d.height))}
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let sx = (Double(x)+0.5)/scale,sy = (Double(y)+0.5)/scale,p = CropGeometry.sample(s,x:sx,y:sy),global = layer.coordinateTransform.point(sx,sy)
        let value = 0.2126*p.r+0.7152*p.g+0.0722*p.b
        luma[y*w+x] = value.isFinite ? max(0,value):0;valid[y*w+x] = p.a > 0.9 && (mask?.coverage(x:global.x,y:global.y) ?? 1) > 0.9
      } }
      // Shared monotonic range compression keeps HDR detail usable for BRIEF.
      if d.depth == .f32 { luma = luma.map{$0/(1+$0)} }
      var f = try PhotoFeatures.detect(width:w,height:h,luma:luma,valid:valid)
      // Descriptors index pixel centers; geometry is expressed at image edges.
      f.points = f.points.map{$0+PhotoPoint(repeating:0.5)};features.append(f)
    }
    let registration = try PhotoRegistration.align(features,projection:settings.projection,reference:reference,focal:settings.focalLengthPixels.map{$0*scale})
    guard locked == nil || registration.projection.planar else { throw CraftError.unsupported("Cylindrical and Spherical projections also reshape the reference. Unlock the reference layer to use them.") }
    let anchor = layers[reference].coordinateTransform
    let referenceTransform = PhotoHomography([anchor.a,anchor.c,anchor.tx,anchor.b,anchor.d,anchor.ty,0,0,1])
    var placements = registration.placements.map{$0.scaled(1/scale)}
    // Retain the registration centers when scaling back to source coordinates.
    for i in placements.indices { placements[i].h = referenceTransform*placements[i].h }
    var result = d,total = 0
    for i in layers.indices {
      if i == reference,registration.projection.planar { continue }
      try Task.checkCancellation();let l = layers[i],s = surfaces[i],placement = placements[i]
      let bounds = try placement.bounds(width:Double(s.width),height:Double(s.height))
      guard bounds.width <= Surface.maxDimension,bounds.height <= Surface.maxDimension,bounds.width <= maximumPixels/bounds.height else { throw CraftError.unsupported("Projected layer exceeds the 16 megapixel output budget.") }
      total += bounds.width*bounds.height;guard total <= maximumTotalPixels else { throw CraftError.unsupported("Projected layers exceed the 32 megapixel output budget.") }
      guard let inverse = placement.h.inverse(),let index = result.layers.firstIndex(where:{$0.id == l.id}) else { throw CraftError.invalid("Invalid alignment transform.") }
      var out = try Surface(width:bounds.width,height:bounds.height,depth:s.depth,colorEncoding:s.colorEncoding)
      let maskSampler = try l.mask.map{_ in try MaskSampler(layer:l,canvasSize:(d.width,d.height))}
      var mask = try l.mask.map{old in try Surface(width:bounds.width,height:bounds.height,depth:old.depth)}
      for y in 0..<bounds.height { try Task.checkCancellation();for x in 0..<bounds.width {
        let global = PhotoPoint(Double(x+bounds.x)+0.5,Double(y+bounds.y)+0.5),denominator = inverse.m[6]*global.x+inverse.m[7]*global.y+inverse.m[8]
        guard denominator > 1e-12,let q = placement.unproject(inverse.apply(global)),q.x >= 0,q.y >= 0,q.x < Double(s.width),q.y < Double(s.height) else { continue }
        let pixel = CropGeometry.sample(s,x:q.x,y:q.y)
        if s.depth == .f32 { out.setLinearPixel(x:x,y:y,pixel) } else { out.setPixel(x:x,y:y,pixel) }
        if let maskSampler { let old = l.coordinateTransform.point(q.x,q.y),value = maskSampler.coverage(x:old.x,y:old.y);mask?.setPixel(x:x,y:y,Pixel(value,value,value,1)) }
      } }
      result.layers[index].content = .raster(out);result.layers[index].x = bounds.x;result.layers[index].y = bounds.y;result.layers[index].affine = nil
      if let mask { result.layers[index].mask = mask;var properties = MaskProperties();properties.linked = l.effectiveMaskProperties.linked;result.layers[index].maskProperties = properties }
    }
    try result.validate();return PhotoAlignEdit(source:d,result:result,selectedLayerIDs:layerIDs,projection:registration.projection,matchedPoints:registration.matches,rmsPixels:registration.rms/scale)
  }
}
