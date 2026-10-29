import Foundation

private final class BrushCoverageTile {
  var coverage=[Float](repeating:0,count:4096)
  var colors:[SIMD4<Float>]
  init(color:Bool) { colors=color ? [SIMD4<Float>](repeating:.zero,count:4096):[] }
}
private struct BrushCoverage {
  var tiles:[Int:BrushCoverageTile]=[:]
  let columns:Int
  let color:Bool
  var bytes:Int { tiles.count*4096*(color ? 20:4) }
  func location(_ x:Int,_ y:Int)->(Int,Int) { ((y/64)*columns+x/64,(y%64)*64+x%64) }
  mutating func accumulate(_ x:Int,_ y:Int,value:Float,ceiling:Float,maximum:Bool,ink:Pixel)throws {
    guard value>0 else { return };let (key,index)=location(x,y)
    let tile:BrushCoverageTile
    if let found=tiles[key] { tile=found } else { guard bytes+4096*(color ? 20:4)<=128*1024*1024 else { throw CraftError.invalid("Brush stroke coverage exceeds128MiB.") };tile=BrushCoverageTile(color:color);tiles[key]=tile }
    let old=tile.coverage[index],next=maximum ? max(old,value*ceiling):max(old,old+value*(ceiling-old))
    guard next>old else { return }
    if color { let k=old<1 ? (next-old)/(1-old):0;let c=SIMD4(ink.r,ink.g,ink.b,ink.a);tile.colors[index]=c*k+tile.colors[index]*(1-k) }
    tile.coverage[index]=next
  }
  func value(_ x:Int,_ y:Int)->Float { let (key,index)=location(x,y);return tiles[key]?.coverage[index] ?? 0 }
  mutating func union(_ other:Self)throws {
    for (key,source) in other.tiles {
      let target:BrushCoverageTile
      if let found=tiles[key] { target=found } else { guard bytes+4096*(color ? 20:4)<=128*1024*1024 else { throw CraftError.invalid("Brush stroke coverage exceeds128MiB.") };target=BrushCoverageTile(color:color);tiles[key]=target }
      for i in 0..<4096 where source.coverage[i]>target.coverage[i] { target.coverage[i]=source.coverage[i];if color { target.colors[i]=source.colors[i] } }
    }
  }
}
public enum BrushPainter {
  static func smooth(_ t:Double)->Double { let t=min(1,max(0,t));return t*t*(3-2*t) }
  static func coverage(distance:Double,radius:Double,hardness:Double)->Double {
    guard distance<radius+0.5 else { return 0 };let edge=min(1,max(0,radius+0.5-distance)),inner=radius*hardness
    return edge*(distance<=inner || radius-inner<0.001 ? 1:1-smooth((distance-inner)/(radius-inner)))
  }
  public static func texture(_ b:BrushTexture,_ x:Double,_ y:Double)->Double {
    let px=x/b.scale-0.5,py=y/b.scale-0.5;var value:Double
    if let bitmap=b.bitmap { value=bitmap.sample(px,py,wrap:true) }
    else {
      switch b.pattern {
      case .noise:value=BrushRandom.pixel(Int(floor(px)),Int(floor(py)),b.seed)
      case .canvas:value=0.45+0.2*cos(px * .pi/3)+0.2*cos(py * .pi/3)
      case .paper:
        let noise=BrushRandom.pixel(Int(floor(px)),Int(floor(py)),b.seed),fiber=BrushRandom.pixel(Int(floor(px/4)),Int(floor(py/2)),b.seed &+ 1)
        value=0.3+noise*0.3+fiber*0.4
      case .dots:let dx=px-floor(px/8)*8-4,dy=py-floor(py/8)*8-4;value=1-smooth((hypot(dx,dy)-1)/2)
      }
    }
    value=min(1,max(0,(value-0.5)*(1+b.contrast)+0.5+b.brightness));return b.invert ? 1-value:value
  }
  static func symmetry(_ s:BrushSymmetry)->[Transform2D] {
    let c=s.center
    func around(_ t:Transform2D)->Transform2D { .translation(c.x,c.y)*t * .translation(-c.x,-c.y) }
    switch s.mode {
    case .off:return [.identity]
    case .vertical:return [.identity,around(.scale(-1,1))]
    case .horizontal:return [.identity,around(.scale(1,-1))]
    case .dual:return [.identity,around(.scale(-1,1)),around(.scale(1,-1)),around(.scale(-1,-1))]
    case .radial:return (0..<s.count).map{around(.rotation(Double($0)*360/Double(s.count)))}
    case .mandala:return (0..<s.count).flatMap{ i in let r=Transform2D.rotation(Double(i)*360/Double(s.count));return [around(r),around(r * .scale(-1,1))] }
    }
  }
  static func tipCoverage(_ dab:BrushDab,_ point:(x:Double,y:Double),bitmap:BrushBitmap?,hardness:Double,aliased:Bool)->(Double,Double) {
    var cx=dab.x,cy=dab.y
    if aliased { let n=max(1,Int((dab.radius*2).rounded()));cx=n%2==1 ? floor(cx)+0.5:cx.rounded();cy=n%2==1 ? floor(cy)+0.5:cy.rounded() }
    var ux=point.x-cx,uy = -(point.y-cy)
    if dab.projectionScale<0.999 {
      let ax=cos(dab.projectionAngle),ay=sin(dab.projectionAngle),t=(ux*ax+uy*ay)*(1/dab.projectionScale-1);ux += t*ax;uy += t*ay
    }
    let cs=cos(dab.angle),sn=sin(dab.angle),u=(ux*cs+uy*sn)*(dab.flipX ? -1:1),v=(-ux*sn+uy*cs)*(dab.flipY ? -1:1)
    let roundness=min(1,max(0.5/dab.radius,dab.roundness)),minor=max(0.5,dab.radius*roundness)
    if let bitmap {
      let scale=Double(max(bitmap.width,bitmap.height))/(2*dab.radius)
      let x=u*scale+Double(bitmap.width)/2-0.5,y = -(v/roundness)*scale+Double(bitmap.height)/2-0.5
      let sample=bitmap.sample(x,y);return (aliased ? (sample>=0.5 ? 1:0):sample,1-sample)
    }
    let distance=hypot(u*roundness,v),value=aliased ? (distance<=minor ? 1.0:0):coverage(distance:distance,radius:minor,hardness:hardness)
    return (value,distance/minor)
  }
  public static func validate(_ brush:Brush,points:[StrokePoint])throws {
    guard brush.size.isFinite,(0.5...2048).contains(brush.size),brush.hardness.isFinite,(0...1).contains(brush.hardness),brush.opacity.isFinite,(0...1).contains(brush.opacity),brush.color.isFinite,(0...1).contains(brush.color.a),brush.backgroundColor?.isFinite != false,points.count<=100_000 else { throw CraftError.invalid("Invalid brush settings or input count.") }
    try brush.settings?.validate();var previousTime=0.0
    for p in points { try p.validatedBrushInput();if let time=p.time { guard time>=previousTime else { throw CraftError.invalid("Brush timestamps must be monotonic.") };previousTime=time } }
  }
  public static func strokeBounds(points:[StrokePoint],brush:Brush)throws->IntRect? {
    try validate(brush,points:points);guard let settings=brush.settings,!points.isEmpty else { return nil }
    var generator=BrushDabGenerator(brush);var dabs=try generator.push(points).0;dabs += try generator.finish().0
    var x=Double.infinity,y=Double.infinity,r = -Double.infinity,b = -Double.infinity
    for pass in symmetry(settings.symmetry) { for dab in dabs where dab.radius>0 {
      let p=pass.point(dab.x,dab.y),radius=dab.radius*(settings.tip == nil ? 1:sqrt(2))+1
      x=min(x,p.x-radius);y=min(y,p.y-radius);r=max(r,p.x+radius);b=max(b,p.y+radius)
    } }
    guard x.isFinite else { return nil };return .init(x:Int(floor(x)),y:Int(floor(y)),width:Int(ceil(r)-floor(x)),height:Int(ceil(b)-floor(y)))
  }
  public static func stroke(surface:inout Surface,points:[StrokePoint],brush:Brush,selection:IntRect?=nil,selectionMask:SelectionMask?=nil,transform:Transform2D = .identity,grayscaleMask:Bool=false,preserveTransparency:Bool=false)throws {
    try validate(brush,points:points);try transform.validated();guard let b=brush.settings,!points.isEmpty else { return };try Task.checkCancellation()
    var generator=BrushDabGenerator(brush);var dabs=try generator.push(points);let tail=try generator.finish();dabs.0 += tail.0;dabs.1 += tail.1
    let inverse=try transform.inverted(),columns=(surface.width+63)/64,color=b.colorDynamics.enabled
    var merged=BrushCoverage(columns:columns,color:color),visits=0
    for pass in symmetry(b.symmetry) {
      let undoPass=try pass.inverted(),toLocal=inverse*pass,toOriginal=undoPass*transform
      var primary=BrushCoverage(columns:columns,color:color),dual=BrushCoverage(columns:columns,color:false)
      func raster(_ dabs:[BrushDab],isDual:Bool,map:inout BrushCoverage)throws {
        let bitmap=isDual ? b.dual.tip:b.tip,hardness=isDual ? b.dual.hardness:Double(brush.hardness)
        for (index,dab) in dabs.enumerated() {
          if index%32==0 { try Task.checkCancellation() }
          let reach=dab.radius*(bitmap==nil ? 1:Double(2).squareRoot())+1,center=toLocal.point(dab.x,dab.y)
          let rx=reach*hypot(toLocal.a,toLocal.c),ry=reach*hypot(toLocal.b,toLocal.d)
          let x0=Int(max(0,min(Double(surface.width),floor(center.x-rx)))),x1=Int(max(-1,min(Double(surface.width-1),ceil(center.x+rx))))
          let y0=Int(max(0,min(Double(surface.height),floor(center.y-ry)))),y1=Int(max(-1,min(Double(surface.height-1),ceil(center.y+ry))))
          guard x0<=x1,y0<=y1 else { continue }
          let area=(x1-x0+1)*(y1-y0+1);guard area<=134_217_728-visits else { throw CraftError.invalid("Brush stroke exceeds the raster work limit.") };visits += area
          for y in y0...y1 { for x in x0...x1 {
            let p=toOriginal.point(Double(x)+0.5,Double(y)+0.5),doc=transform.point(Double(x)+0.5,Double(y)+0.5)
            var (value,rn)=tipCoverage(dab,p,bitmap:bitmap,hardness:hardness,aliased:b.aliased && !isDual)
            guard value>0 else { continue }
            if !isDual {
              if b.noise && value<1 { let n=BrushRandom.pixel(Int(floor(doc.x)),Int(floor(doc.y)),0x6E6F697365);value += ((n<value ? 1:0)-value)*0.7 }
              if b.texture.enabled && b.texture.eachTip { value=b.texture.mode.combine(value,texture(b.texture,doc.x,doc.y),dab.depth) }
              if b.wetEdges { value *= 0.5+0.5*smooth((rn-0.5)*2) }
            }
            try map.accumulate(x,y,value:Float(value*dab.flow),ceiling:Float(dab.opacity),maximum:b.wetEdges && !isDual,ink:dab.color)
          } }
        }
      }
      try raster(dabs.0,isDual:false,map:&primary)
      if b.dual.enabled { try raster(dabs.1,isDual:true,map:&dual) }
      for (key,tile) in primary.tiles {
        let tx=(key%columns)*64,ty=(key/columns)*64
        for i in 0..<4096 where tile.coverage[i]>0 {
          let x=tx+i%64,y=ty+i/64;let old=tile.coverage[i];var value=Double(old)
          if b.dual.enabled { value=b.dual.mode.combine(value,Double(dual.value(x,y)),1) }
          if b.texture.enabled && !b.texture.eachTip { let doc=transform.point(Double(x)+0.5,Double(y)+0.5);value=b.texture.mode.combine(value,texture(b.texture,doc.x,doc.y),b.texture.depth) }
          tile.coverage[i]=Float(value);if color { tile.colors[i] *= Float(value)/old }
        }
      }
      try merged.union(primary)
    }
    // No target mutations until the entire bounded stroke has rendered successfully.
    var result=surface
    for key in merged.tiles.keys.sorted() {
      try Task.checkCancellation();let tile=merged.tiles[key]!,tx=(key%columns)*64,ty=(key/columns)*64
      for i in 0..<4096 where tile.coverage[i]>0 {
        let x=tx+i%64,y=ty+i/64;guard x<surface.width,y<surface.height else { continue }
        let doc=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(doc.x)),dy=Int(floor(doc.y))
        if let selection,!selection.contains(dx,dy) { continue }
        let mask=selectionMask?.coverage(x:dx,y:dy) ?? 1
        var ink=brush.color
        if color { let c=tile.colors[i]/tile.coverage[i];ink=Pixel(c.x,c.y,c.z,c.w) }
        let alpha=unit(tile.coverage[i]*brush.opacity*ink.a*mask);guard alpha>0 else { continue }
        var before=surface.pixel(x:x,y:y)
        if grayscaleMask { before=Pixel(before.r,before.r,before.r);let gray=unit(ink.r*0.2126+ink.g*0.7152+ink.b*0.0722);ink=Pixel(gray,gray,gray,ink.a) }
        if preserveTransparency && !grayscaleMask && before.a<=0 { continue }
        if brush.erase && !preserveTransparency && !grayscaleMask { result.setPixel(x:x,y:y,Pixel(before.r,before.g,before.b,before.a*(1-alpha)));continue }
        if brush.erase { ink=brush.backgroundColor ?? .white }
        ink.a=alpha
        let painted=preserveTransparency && !grayscaleMask ? ProtectedPixels.composite(b.mode,backdrop:before,source:ink,x:dx,y:dy):b.mode.composite(backdrop:before,source:ink,x:dx,y:dy)
        result.setPixel(x:x,y:y,painted)
      }
    }
    try Task.checkCancellation();surface=result
  }
}
