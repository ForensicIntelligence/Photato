import Foundation

public struct ContentAwareScaleRequest: Equatable,Sendable {
  public var width: Int,height: Int,x: Int?,y: Int?
  public var amount: Float = 100
  public var protectChannelID: UUID?
  public var protectSkinTones = false
  public init(width: Int,height: Int,x: Int? = nil,y: Int? = nil) { self.width = width;self.height = height;self.x = x;self.y = y }
  public func validate() throws {
    guard (1...60000).contains(width),(1...60000).contains(height),width <= SeamCarving.maximumPixels/height,
      amount.isFinite,(0...100).contains(amount),(x.map { (-1_000_000...1_000_000).contains($0) } ?? true),(y.map { (-1_000_000...1_000_000).contains($0) } ?? true)
    else { throw CraftError.invalid("Invalid Content-Aware Scale dimensions, position or Amount.") }
  }
}

public struct ContentAwareScaleEdit: Sendable {
  public let source: Layer
  public let result: Layer
  public let sourceSelection: SelectionMask?
  public let selection: SelectionMask?
  public static func bounds(_ document: CraftDocument,layerID: UUID) throws -> IntRect {
    guard let layer = document.layers.first(where: { $0.id == layerID }),case .raster(let surface) = layer.content,layer.smartObject == nil else { throw CraftError.invalid("Content-Aware Scale requires an ordinary raster layer.") }
    if let selection = try document.coverageSelection() { guard let box = selection.bounds else { throw CraftError.invalid("The selection is empty.") };return box }
    return try layer.coordinateTransform.bounds(width:surface.width,height:surface.height)
  }
  public static func prepare(_ document: CraftDocument,layerID: UUID,request: ContentAwareScaleRequest) throws -> Self {
    try request.validate();try Task.checkCancellation()
    guard !document.isImageLocked(layerID),!document.isPositionLocked(layerID),!document.isTransparencyLocked(layerID),
      document.width <= SeamCarving.maximumPixels/document.height,let source = document.layers.first(where: { $0.id == layerID }),case .raster(let surface) = source.content,source.smartObject == nil
    else { throw CraftError.invalid("Unlock the raster layer's image, position and transparency before Content-Aware Scale (maximum16 megapixel canvas).") }
    let box = try bounds(document,layerID:layerID),nw = request.width,nh = request.height
    guard box.width <= SeamCarving.maximumPixels/box.height else { throw CraftError.invalid("Content-Aware Scale source exceeds16 megapixels.") }
    let dx = request.x ?? Int((Double(box.x)+Double(box.width-nw)/2).rounded(.down)),dy = request.y ?? Int((Double(box.y)+Double(box.height-nh)/2).rounded(.down))
    let destination = IntRect(x:dx,y:dy,width:nw,height:nh),selected = try document.coverageSelection()
    let protect = try request.protectChannelID.map { try document.channel(.alpha($0)).selection() }
    if destination == box { return Self(source:source,result:source,sourceSelection:selected,selection:selected) }
    let inverse = try source.coordinateTransform.inverted(),count = box.width*box.height
    // Premultiplied RGBA plus selection coverage: auxiliary coverage follows the same seams.
    var image = [Float](repeating:0,count:count*5),protection = [Float](repeating:0,count:count)
    for y in 0..<box.height { try Task.checkCancellation();for x in 0..<box.width {
      let px = x+box.x,py = y+box.y,p = inverse.point(Double(px)+0.5,Double(py)+0.5),sample = sample(surface,x:p.x,y:p.y)
      let k = selected.map { coverage($0,px,py) } ?? 1,a = sample.a*k,i = y*box.width+x
      image[i*5] = sample.r*a;image[i*5+1] = sample.g*a;image[i*5+2] = sample.b*a;image[i*5+3] = a;image[i*5+4] = k
      protection[i] = protect.map { coverage($0,px,py) } ?? 0
      if request.protectSkinTones { protection[i] = max(protection[i],SeamCarving.skin(surface.pixel(x:Int(floor(p.x)),y:Int(floor(p.y))))) }
    } }
    let scaled = try SeamCarving.resize(width:box.width,height:box.height,channels:5,image:image,protect:protection,newWidth:nw,newHeight:nh,amount:request.amount/100,energyChannels:4)
    var pixels = try Surface(width:nw,height:nh,depth:document.depth,colorEncoding:document.depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<nh { try Task.checkCancellation();for x in 0..<nw { let i = (y*nw+x)*5,a = unit(scaled[i+3]),p = a > 1e-8 ? Pixel(scaled[i]/a,scaled[i+1]/a,scaled[i+2]/a,a):Pixel.clear;write(p,to:&pixels,x:x,y:y) } }
    var result = source
    if selected == nil {
      result.content = .raster(pixels);result.x = dx;result.y = dy;result.affine = nil
      let delta = Transform2D.translation(Double(dx),Double(dy)) * .scale(Double(nw)/Double(box.width),Double(nh)/Double(box.height)) * .translation(-Double(box.x),-Double(box.y))
      if source.mask != nil { var properties = source.effectiveMaskProperties;properties.transform = try result.coordinateTransform.inverted() * (properties.linked ? delta * source.maskCoordinateTransform:source.maskCoordinateTransform);result.maskProperties = properties }
      if source.vectorMask?.linked == true { result.vectorMask?.path = source.vectorMask!.path.transformed(delta) }
    } else {
      let x = min(box.x,dx),y = min(box.y,dy),union = IntRect(x:x,y:y,width:max(box.x+box.width,dx+nw)-x,height:max(box.y+box.height,dy+nh)-y)
      guard union.width <= SeamCarving.maximumPixels/union.height else { throw CraftError.invalid("Scaled selection storage exceeds16 megapixels.") }
      try ClonePainter.paintTarget(mask:false,bounds:union,on:&result,clipping:union) { target,transform,_ in
        guard target.width <= SeamCarving.maximumPixels/target.height else { throw CraftError.invalid("Content-Aware Scale output storage exceeds16 megapixels.") }
        for y in 0..<target.height { try Task.checkCancellation();for x in 0..<target.width {
          let p = transform.point(Double(x)+0.5,Double(y)+0.5),ix = Int(floor(p.x)),iy = Int(floor(p.y))
          guard union.contains(ix,iy) else { continue }
          let k = coverage(selected!,ix,iy),old = read(target,x,y),fill = sample(pixels,x:p.x-Double(dx),y:p.y-Double(dy))
          if k == 0 && fill.a == 0 { continue }
          let a = old.a*(1-k)*(1-fill.a)+fill.a
          let output = a > 1e-8 ? Pixel((old.r*old.a*(1-k)*(1-fill.a)+fill.r*fill.a)/a,(old.g*old.a*(1-k)*(1-fill.a)+fill.g*fill.a)/a,(old.b*old.a*(1-k)*(1-fill.a)+fill.b*fill.a)/a,a):Pixel.clear
          write(output,to:&target,x:x,y:y)
        } };return true
      }
    }
    var selection: SelectionMask?
    if selected != nil {
      var bytes = [UInt8](repeating:0,count:document.width*document.height)
      let clipped = destination.clipped(toWidth:document.width,height:document.height)
      if clipped.width > 0 && clipped.height > 0 { for y in clipped.y..<(clipped.y+clipped.height) { try Task.checkCancellation();for x in clipped.x..<(clipped.x+clipped.width) { bytes[y*document.width+x] = UInt8((unit(scaled[((y-dy)*nw+x-dx)*5+4])*255).rounded()) } } }
      selection = try SelectionMask(width:document.width,height:document.height,bytes:bytes)
    }
    return Self(source:source,result:result,sourceSelection:selected,selection:selection)
  }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    guard let i = original.layers.firstIndex(where: { $0.id == source.id }),original.layers[i] == source,try original.coverageSelection() == sourceSelection,
      !original.isImageLocked(source.id),!original.isPositionLocked(source.id),!original.isTransparencyLocked(source.id)
    else { throw CraftError.invalid("Content-Aware Scale source changed or is locked.") }
    var document = original;document.layers[i] = result;document.setCoverageSelection(selection);try document.validate();return document
  }
  private static func coverage(_ m: SelectionMask,_ x: Int,_ y: Int) -> Float { x >= 0 && y >= 0 && x < m.width && y < m.height ? Float(m.bytes[y*m.width+x])/255:0 }
  private static func read(_ s: Surface,_ x: Int,_ y: Int) -> Pixel { s.depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y) }
  private static func write(_ p: Pixel,to s: inout Surface,x: Int,y: Int) { if s.depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } }
  /// Sample premultiplied pixels without clamping HDR RGB; outside storage is transparent.
  private static func sample(_ s: Surface,x: Double,y: Double) -> Pixel {
    let ix = Int(floor(x-0.5)),iy = Int(floor(y-0.5)),fx = Float(x-0.5-Double(ix)),fy = Float(y-0.5-Double(iy))
    var v = SIMD4<Float>.zero
    for j in 0...1 { for i in 0...1 { let p = read(s,ix+i,iy+j),weight = (i == 0 ? 1-fx:fx)*(j == 0 ? 1-fy:fy);v += SIMD4(p.r*p.a,p.g*p.a,p.b*p.a,p.a)*weight } }
    return v.w > 1e-8 ? Pixel(v.x/v.w,v.y/v.w,v.z/v.w,unit(v.w)):.clear
  }
}
