import Foundation

public enum VanishingEngine {
  static func over(_ foreground:Pixel,_ background:Pixel)->Pixel {
    let a=unit(foreground.a),b=unit(background.a),out=a+b*(1-a)
    guard out>1e-8 else { return .clear };return Pixel((foreground.r*a+background.r*b*(1-a))/out,(foreground.g*a+background.g*b*(1-a))/out,(foreground.b*a+background.b*b*(1-a))/out,out)
  }
  static func read(_ s:Surface,_ x:Int,_ y:Int)->Pixel { s.depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y) }
  static func write(_ s:inout Surface,_ x:Int,_ y:Int,_ p:Pixel) { if s.depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } }
  public static func render(_ program:VanishingProgram,sample:Surface) throws -> Surface {
    try program.validate();try sample.validated();guard sample.width<=WarpRaster.maximumPixels/sample.height else { throw CraftError.unsupported("Vanishing Point supports canvases up to8,388,608 pixels.") }
    let scene=try VanishingScene(program.settings,width:sample.width,height:sample.height),linear=sample.depth == .f32
    var output=try Surface(width:sample.width,height:sample.height,depth:sample.depth,colorEncoding:linear ? .linearRGB:.sRGB),work=0
    func region(_ points:[PathPoint]) throws -> IntRect {
      guard !points.isEmpty,points.allSatisfy({VanishingSettings.validPoint($0)}) else { throw CraftError.invalid("Operation crosses a projective horizon.") }
      let x=max(0,Int(floor(points.map(\.x).min()!))-1),y=max(0,Int(floor(points.map(\.y).min()!))-1),x1=min(sample.width,Int(ceil(points.map(\.x).max()!))+1),y1=min(sample.height,Int(ceil(points.map(\.y).max()!))+1)
      let r=IntRect(x:x,y:y,width:max(0,x1-x),height:max(0,y1-y));work += r.width*r.height
      guard work<=134_217_728 else { throw CraftError.unsupported("Vanishing Point exceeds the rendering work budget.") };return r
    }
    for op in program.operations {
      try Task.checkCancellation();let frame=scene.frames[op.plane],opacity=Float(op.opacity/100)
      if opacity==0 { continue }
      if op.kind == .paste {
        let source=try op.source!.converted(to:sample.depth),w=op.width*frame.width,h=w*Double(source.height)/Double(source.width),a=op.angle * .pi/180,c=cos(a),s=sin(a),origin=PathPoint(op.at.x*frame.width,op.at.y*frame.height)
        func metric(_ x:Double,_ y:Double)->PathPoint { .init(origin.x+x*c-y*s,origin.y+x*s+y*c) }
        let corners=[metric(0,0),metric(w,0),metric(w,h),metric(0,h)].map{frame.projected($0)},r=try region(corners)
        // Requiring a convex projected quad also detects a rectangle crossing the horizon.
        guard PerspectiveSettings.validQuad(corners) else { throw CraftError.invalid("Paste crosses the plane horizon.") }
        for y in r.y..<(r.y+r.height) { try Task.checkCancellation();for x in r.x..<(r.x+r.width) {
          let p=PathPoint(Double(x)+0.5,Double(y)+0.5);if op.clip && !frame.contains(p) { continue }
          let m=frame.metric(p),dx=m.x-origin.x,dy=m.y-origin.y,u=(dx*c+dy*s)/w,v=(-dx*s+dy*c)/h
          guard (0...1).contains(u),(0...1).contains(v) else { continue }
          var pixel=WarpRaster.sample(source,.init(u*Double(source.width),v*Double(source.height)),method:.bicubic);pixel.a *= opacity
          write(&output,x,y,over(pixel,read(output,x,y)))
        } }
      } else {
        let first=op.points[0],m0=frame.metric(first),probe=frame.metric(.init(first.x+op.diameter/2,first.y)),radius=hypot(probe.x-m0.x,probe.y-m0.y)
        guard radius.isFinite,radius>1e-9,frame.contains(first) else { throw CraftError.invalid("Start the stroke inside its perspective plane.") }
        let sourceFrame:VanishingScene.Frame?,offset:PathPoint
        if op.kind == .clone {
          guard let sourcePoint=op.sourcePoint,let sourcePlane=scene.plane(at:sourcePoint) else { throw CraftError.invalid("Clone source must lie on a perspective plane.") }
          sourceFrame=scene.frames[sourcePlane];let m=sourceFrame!.metric(sourcePoint);offset = .init(m.x-m0.x,m.y-m0.y)
        } else { sourceFrame=nil;offset = .init(0,0) }
        // A stroke samples an immutable pre-stroke image, including earlier operations.
        let previous=output
        var centers=[m0]
        for p in op.points.dropFirst() {
          let m=frame.metric(p),last=centers.last!,distance=hypot(m.x-last.x,m.y-last.y)
          guard distance.isFinite,distance/radius<16384 else { throw CraftError.invalid("Stroke crosses a projective horizon.") }
          let steps=max(1,Int(ceil(distance/max(1e-9,radius*0.2))))
          guard centers.count+steps<=16384 else { throw CraftError.unsupported("Perspective stroke has too many dabs.") }
          for i in 1...steps { let t=Double(i)/Double(steps);centers.append(.init(last.x+(m.x-last.x)*t,last.y+(m.y-last.y)*t)) }
        }
        for center in centers {
          let ring=(0..<32).map { k in let a=Double(k)/32*2 * .pi;return frame.projected(.init(center.x+radius*cos(a),center.y+radius*sin(a))) },r=try region(ring)
          for y in r.y..<(r.y+r.height) { try Task.checkCancellation();for x in r.x..<(r.x+r.width) {
            let p=PathPoint(Double(x)+0.5,Double(y)+0.5);if op.clip && !frame.contains(p) { continue }
            let m=frame.metric(p),d=hypot(m.x-center.x,m.y-center.y)/radius;guard d<1 else { continue }
            let hard=min(0.99,op.hardness/100),fall=d<=hard ? 1:1-(d-hard)/(1-hard),k=Float(fall*fall*(3-2*fall))*opacity
            var color:Pixel
            if let sourceFrame {
              let q=sourceFrame.projected(.init(m.x+offset.x,m.y+offset.y));guard VanishingSettings.validPoint(q) else { throw CraftError.invalid("Clone sampling crosses a projective horizon.") }
              color=over(WarpRaster.sample(previous,q,method:.bilinear,clampEdges:false),WarpRaster.sample(sample,q,method:.bilinear,clampEdges:false))
            } else { color=linear ? SRGBTransfer.linear(op.color):op.color }
            color.a *= k;write(&output,x,y,over(color,read(output,x,y)))
          } }
        }
      }
    };return output
  }
}
public struct VanishingEdit:Sendable {
  public let source:CraftDocument,result:CraftDocument
  public let layerID:UUID
  public let program:VanishingProgram
  public static func target(_ d:CraftDocument,layerID:UUID,newLayer:Bool=false) throws -> Layer {
    guard let layer=d.layers.first(where:{$0.id==layerID}),case .raster(let pixels)=layer.content,layer.smartObject==nil,
      newLayer || !d.isImageLocked(layerID),d.width<=WarpRaster.maximumPixels/d.height,pixels.width<=WarpRaster.maximumPixels/pixels.height else { throw CraftError.unsupported("Vanishing Point requires a pixel layer and a canvas up to8,388,608 pixels. Rasterize Smart Objects first; unlock pixels for current-layer output.") }
    return layer
  }
  public static func prepare(_ d:CraftDocument,layerID:UUID,program:VanishingProgram,sample:Surface) throws -> Self {
    try program.validate();let layer=try target(d,layerID:layerID,newLayer:program.newLayer)
    guard sample.width==d.width,sample.height==d.height else { throw CraftError.invalid("Vanishing Point sample does not match its document.") }
    let sample=try sample.converted(to:d.depth)
    let scene = try VanishingScene(program.settings,width:d.width,height:d.height)
    var result=d,settings=program.settings;settings.center=scene.center;settings.focalLength=scene.focal
    result.vanishingPoint=settings.planes.isEmpty ? nil:settings
    if !program.operations.isEmpty {
      let overlay=try VanishingEngine.render(program,sample:sample)
      if program.newLayer {
        guard d.layers.count<LayerLimits.maximumLayers else { throw CraftError.invalid("Layer limit reached.") }
        var pixels=overlay
        for y in 0..<d.height { try Task.checkCancellation();for x in 0..<d.width { var p=VanishingEngine.read(pixels,x,y);p.a *= d.selectionCoverage(x:x,y:y);VanishingEngine.write(&pixels,x,y,p) } }
        var new=Layer(name:"Vanishing Point",content:.raster(pixels));new.parentID=layer.parentID
        let index=d.layers.firstIndex(where:{$0.id==layerID})!;result.layers.insert(new,at:index+1);result.activeLayerID=new.id
      } else if case .raster(let original)=layer.content {
        var pixels=original;let alphaLocked=d.isTransparencyLocked(layerID)
        for y in 0..<original.height { try Task.checkCancellation();for x in 0..<original.width {
          let q=PathPoint(Double(x)+0.5,Double(y)+0.5).transformed(layer.coordinateTransform)
          guard q.x>=0,q.x<Double(d.width),q.y>=0,q.y<Double(d.height) else { continue }
          let coverage=d.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)));if coverage<=0 { continue }
          let ink=WarpRaster.sample(overlay,q,method:.bilinear,clampEdges:false);if ink.a==0 { continue }
          let before=VanishingEngine.read(original,x,y);if alphaLocked && before.a==0 { continue }
          var after=VanishingEngine.over(ink,before);if alphaLocked { after.a=before.a }
          let p=before.mixing(after,coverage:coverage);guard p.isFinite else { throw CraftError.invalid("Nonfinite Vanishing Point output.") };VanishingEngine.write(&pixels,x,y,p)
        } };result.layers[result.layers.firstIndex(where:{$0.id==layerID})!].content = .raster(pixels)
      }
    }
    try result.validate();try Task.checkCancellation();return Self(source:d,result:result,layerID:layerID,program:program)
  }
  public func applied(to document:CraftDocument) throws -> CraftDocument { guard document==source else { throw CraftError.invalid("Vanishing Point source changed; preview again.") };return result }
}
