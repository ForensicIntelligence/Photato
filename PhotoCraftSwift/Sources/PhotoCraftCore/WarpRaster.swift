import Foundation

/// Bounded forward tessellation with inverse UV sampling. Later triangles win at folds,
/// matching the Rust warp rasterizer's overlap convention. HDR samples stay linear.
public enum WarpRaster {
  public static let maximumPixels = 8_388_608
  public struct Mapping: Sendable { public let bounds:IntRect;public let uv:[PathPoint] }
  public static func mapping(_ warp:WarpDefinition,width:Int,height:Int,transform:Transform2D,projection:ProjectiveTransform?=nil) throws -> Mapping {
    try warp.validate();try transform.validated()
    guard width>0,height>0,width<=maximumPixels/height else { throw CraftError.unsupported("Warp supports source and output layers up to8,388,608 pixels.") }
    let nx=min(256,max(16,(width+7)/8)),ny=min(256,max(16,(height+7)/8))
    var vertices=[PathPoint](),inputs=[PathPoint]()
    for j in 0...ny { try Task.checkCancellation();for i in 0...nx {
      let p=PathPoint(Double(i)*Double(width)/Double(nx),Double(j)*Double(height)/Double(ny))
      let warped=warp.point(p.x,p.y,width:Double(width),height:Double(height))
      let mapped=try projection.map{try $0.point(warped.x,warped.y)} ?? warped
      let q=mapped.transformed(transform)
      guard q.x.isFinite,q.y.isFinite,abs(q.x)<=1_000_000,abs(q.y)<=1_000_000 else { throw CraftError.invalid("Warp exceeds supported coordinates.") }
      inputs.append(p);vertices.append(q)
    } }
    var triangles=[[Int]]()
    for j in 0..<ny { for i in 0..<nx { let a=j*(nx+1)+i,b=a+1,c=a+nx+1,d=c+1;triangles += [[a,b,d],[a,d,c]] } }
    return try mapping(vertices:vertices,inputs:inputs,triangles:triangles)
  }
  public static func mapping(vertices:[PathPoint],inputs:[PathPoint],triangles:[[Int]],bounds requested:IntRect?=nil) throws -> Mapping {
    guard !vertices.isEmpty,vertices.count == inputs.count,vertices.count<=66049,triangles.count<=131072,
      (vertices+inputs).allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}),
      triangles.allSatisfy({$0.count == 3 && $0.allSatisfy{vertices.indices.contains($0)}}) else { throw CraftError.invalid("Invalid warp triangle mapping.") }
    let x=requested?.x ?? Int(floor(vertices.map(\.x).min()!+1e-9)),y=requested?.y ?? Int(floor(vertices.map(\.y).min()!+1e-9))
    let w=requested?.width ?? max(1,Int(ceil(vertices.map(\.x).max()!-1e-9))-x),h=requested?.height ?? max(1,Int(ceil(vertices.map(\.y).max()!-1e-9))-y)
    guard w>0,h>0,w<=60000,h<=60000,w<=maximumPixels/h else { throw CraftError.unsupported("Warp output exceeds8,388,608 pixels.") }
    let bounds=IntRect(x:x,y:y,width:w,height:h)
    var uv=[PathPoint](repeating:PathPoint(.nan,.nan),count:w*h),work=0
    func triangle(_ a:Int,_ b:Int,_ c:Int) throws {
      let p=vertices[a],q=vertices[b],r=vertices[c],det=(q.x-p.x)*(r.y-p.y)-(r.x-p.x)*(q.y-p.y)
      guard abs(det)>1e-10 else { return }
      let x0=max(x,Int(floor(min(p.x,q.x,r.x)))),x1=min(x+w,Int(ceil(max(p.x,q.x,r.x))))
      let y0=max(y,Int(floor(min(p.y,q.y,r.y)))),y1=min(y+h,Int(ceil(max(p.y,q.y,r.y))))
      guard x1>x0,y1>y0 else { return };work += (x1-x0)*(y1-y0)
      guard work<=134_217_728 else { throw CraftError.unsupported("Warp folds exceed the rendering work budget.") }
      for yy in y0..<y1 { try Task.checkCancellation();for xx in x0..<x1 {
        let dx=Double(xx)+0.5-p.x,dy=Double(yy)+0.5-p.y
        let v=(dx*(r.y-p.y)-dy*(r.x-p.x))/det,t=((q.x-p.x)*dy-(q.y-p.y)*dx)/det,u=1-v-t
        if min(u,v,t)>=(-1e-9) { let aa=inputs[a],bb=inputs[b],cc=inputs[c];uv[(yy-y)*w+xx-x]=PathPoint(aa.x*u+bb.x*v+cc.x*t,aa.y*u+bb.y*v+cc.y*t) }
      } }
    }
    for t in triangles { try triangle(t[0],t[1],t[2]) }
    return Mapping(bounds:bounds,uv:uv)
  }
  public static func sample(_ s:Surface,_ p:PathPoint,method:Resampling,clampEdges:Bool=true,encoding:SurfaceColorEncoding?=nil) -> Pixel {
    guard p.x.isFinite,p.y.isFinite else { return .clear }
    func read(_ x:Int,_ y:Int)->Pixel { if !clampEdges && (x<0 || y<0 || x>=s.width || y>=s.height) { return .clear };let x=max(0,min(s.width-1,x)),y=max(0,min(s.height-1,y));return (encoding ?? (s.depth == .f32 ? .linearRGB:.sRGB)) == .linearRGB ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y) }
    if method == .nearest { return read(Int(floor(p.x)),Int(floor(p.y))) }
    let xx=p.x-0.5,yy=p.y-0.5,ix=Int(floor(xx)),iy=Int(floor(yy)),fx=Float(xx-Double(ix)),fy=Float(yy-Double(iy))
    func cubic(_ value:Float)->Float { let t=abs(value);if t<=1 { return 1.5*t*t*t-2.5*t*t+1 };if t<2 { return -0.5*t*t*t+2.5*t*t-4*t+2 };return 0 }
    let range=method == .bicubic ? -1...2:0...1;var v=SIMD4<Float>.zero
    for j in range { for i in range {
      let wx=method == .bicubic ? cubic(Float(i)-fx):(i == 0 ? 1-fx:fx)
      let wy=method == .bicubic ? cubic(Float(j)-fy):(j == 0 ? 1-fy:fy),q=read(ix+i,iy+j)
      v += SIMD4(q.r*q.a,q.g*q.a,q.b*q.a,q.a)*(wx*wy)
    } };return v.w>1e-8 ? Pixel(v.x/v.w,v.y/v.w,v.z/v.w,unit(v.w)):.clear
  }
  public static func render(_ source:Surface,using mapping:Mapping,method:Resampling,clampEdges:Bool=true) throws -> Surface {
    let b=mapping.bounds;var out=try Surface(width:b.width,height:b.height,depth:source.depth,colorEncoding:source.depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<b.height { try Task.checkCancellation();for x in 0..<b.width {
      let p=sample(source,mapping.uv[y*b.width+x],method:method,clampEdges:clampEdges)
      if source.depth == .f32 { out.setLinearPixel(x:x,y:y,p) } else { out.setPixel(x:x,y:y,p) }
    } };return out
  }
  /// Derives display pixels, leaving the committed source/cache and masks untouched.
  public static func baked(_ layer:Layer,in document:CraftDocument) throws -> Layer {
    guard case .raster(let source)=layer.content,layer.warp != nil || layer.sourceProjection != nil else{return layer}
    if let projection=layer.sourceProjection,let affine=try projection.affineValue(),layer.warp?.isIdentity != false {
      let maskWorld=layer.maskCoordinateTransform
      var result=layer;result.x=0;result.y=0;result.affine=layer.coordinateTransform*affine
      result.sourceProjection=nil;result.warp=nil;result.importedSmartAppearance=nil
      if layer.mask != nil,!layer.effectiveMaskProperties.linked {var properties=layer.effectiveMaskProperties;properties.transform=try result.coordinateTransform.inverted()*maskWorld;result.maskProperties=properties}
      return result
    }
    if let projection=layer.sourceProjection,layer.warp?.isIdentity != false {
      let full=try projection.followed(by:layer.coordinateTransform),bounds=try full.bounds(width:source.width,height:source.height)
      var result=layer;result.content = .raster(try ProjectiveRaster.renderPaged(source,placement:full,bounds:bounds,method:layer.warp?.interpolation ?? .bicubic))
      result.x=bounds.x;result.y=bounds.y;result.affine=nil;result.sourceProjection=nil;result.warp=nil;result.importedSmartAppearance=nil
      if layer.mask != nil {var properties=layer.effectiveMaskProperties;properties.transform=try result.coordinateTransform.inverted()*layer.maskCoordinateTransform;result.maskProperties=properties}
      return result
    }
    if layer.sourceProjection != nil,layer.mask != nil,layer.effectiveMaskProperties.linked {throw CraftError.unsupported("Combined Warp/projective linked masks require their mesh mapping before rerendering.")}
    guard let warp=layer.warp else{return layer}
    let paged=try PagedWarpRaster.mapping(warp,width:source.width,height:source.height,transform:layer.coordinateTransform,projection:layer.sourceProjection)
    if source.width>maximumPixels/source.height || paged.bounds.width>maximumPixels/paged.bounds.height || paged.bounds.width>60000 || paged.bounds.height>60000 {
      return try PagedWarpRaster.baked(layer,in:document,using:paged,method:warp.interpolation)
    }
    let mapping=try paged.denseMapping()
    return try baked(layer,in:document,using:mapping,method:warp.interpolation)
  }
  public static func baked(_ layer:Layer,in document:CraftDocument,using mapping:Mapping,method:Resampling,clampEdges:Bool=true) throws -> Layer {
    guard case .raster(let source)=layer.content else { throw CraftError.invalid("Warp requires raster pixels.") }
    let b=mapping.bounds
    var result=layer;result.content = .raster(try render(source,using:mapping,method:method,clampEdges:clampEdges));result.x=b.x;result.y=b.y;result.affine=nil;result.warp=nil;result.sourceProjection=nil;result.importedSmartAppearance=nil
    if layer.mask != nil {
      if layer.effectiveMaskProperties.linked {
        // Warp mask storage, preserving disabled/inverted/density/feather controls.
        // Applying effective coverage here would irreversibly discard a disabled mask.
        var raw=layer
        raw.maskProperties=layer.effectiveMaskProperties
        raw.maskProperties?.enabled=true;raw.maskProperties?.inverted=false
        raw.maskProperties?.density=1;raw.maskProperties?.feather=0
        let sampler=try MaskSampler(layer:raw,feather:false,canvasSize:(document.width,document.height))
        var mask=try Surface(width:b.width,height:b.height,depth:layer.mask!.depth)
        for y in 0..<b.height { try Task.checkCancellation();for x in 0..<b.width {
          let uv=mapping.uv[y*b.width+x];var k:Float=0
          if uv.x.isFinite { let p=uv.transformed(layer.coordinateTransform);k=sampler.coverage(x:p.x,y:p.y) }
          mask.setPixel(x:x,y:y,Pixel(k,k,k,1))
        } };result.mask=mask;result.maskProperties=layer.effectiveMaskProperties;result.maskProperties?.transform = .identity
      } else { var properties=layer.effectiveMaskProperties;properties.transform=try result.coordinateTransform.inverted()*layer.maskCoordinateTransform;result.maskProperties=properties }
    }
    return result
  }
}

public struct WarpEdit: Sendable {
  public let source:CraftDocument,result:CraftDocument
  public static func target(_ document:CraftDocument,layerID:UUID) throws -> Layer {
    guard let layer=document.layers.first(where:{$0.id == layerID}),case .raster(let s)=layer.content,
      !document.isImageLocked(layerID),!document.isPositionLocked(layerID),!document.isTransparencyLocked(layerID),document.selection == nil,
      layer.vectorMask == nil,document.colorMode == .rgb,document.inkMode == nil,document.restrictedMode == nil,layer.nativeMode == nil else {
      throw CraftError.unsupported("Warp currently needs an unlocked RGB pixel layer or Smart Object, without a selection or vector mask. Convert groups/type/shapes to a Smart Object first.")
    };return layer
  }
  public static func prepare(_ document:CraftDocument,layerID:UUID,warp:WarpDefinition) throws -> Self {
    try warp.validate();var layer=try target(document,layerID:layerID),result=document
    if layer.smartObject == nil && warp.isIdentity { return Self(source:document,result:document) }
    layer.warp=warp.isIdentity ? nil:warp
    if layer.smartObject == nil { layer=try WarpRaster.baked(layer,in:document) }
    else if layer.warp != nil { _ = try SmartFilterEngine.renderedLayer(layer,in:document) }
    result.layers[result.layers.firstIndex(where:{$0.id == layerID})!]=layer;try result.validate()
    return Self(source:document,result:result)
  }
  public func applied(to document:CraftDocument) throws -> CraftDocument {
    guard document == source else { throw CraftError.invalid("Warp source changed; preview again.") };return result
  }
}
