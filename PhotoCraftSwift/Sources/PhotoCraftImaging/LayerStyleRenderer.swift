import Foundation
import PhotoCraftCore

/// CPU style stack following PhotoCraft's effects.rs ordering. Distance and blur
/// kernels are bounded native approximations; exact Photoshop contours remain open.
enum LayerStyleRenderer {
  static let maximumPixels = 8_388_608
  struct Map {
    let w: Int, h: Int
    var v: [Float]
    func sample(_ x: Double, _ y: Double, outside: Float = 0) -> Float {
      let x0 = Int(floor(x)), y0 = Int(floor(y))
      let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
      func at(_ x: Int, _ y: Int) -> Float { x >= 0 && y >= 0 && x < w && y < h ? v[y*w+x] : outside }
      return (at(x0,y0)*(1-fx)+at(x0+1,y0)*fx)*(1-fy)
        + (at(x0,y0+1)*(1-fx)+at(x0+1,y0+1)*fx)*fy
    }
    func blurred(_ size: Double, outside: Float = 0) throws -> Self {
      if size <= 0 { return self }
      let radius = max(1, Int(ceil(size / 3)))
      var result = self
      for _ in 0..<2 { for horizontal in [true, false] {
        let input = result.v
        let length = horizontal ? w : h, lines = horizontal ? h : w
        for line in 0..<lines {
          try Task.checkCancellation()
          func at(_ p: Int) -> Float {
            guard p >= 0 && p < length else { return outside }
            return input[horizontal ? line*w+p : p*w+line]
          }
          var sum = Double(outside) * Double(radius + max(0, radius-length+1))
          for p in 0...min(radius, length-1) { sum += Double(at(p)) }
          for p in 0..<length {
            result.v[horizontal ? line*w+p : p*w+line] = Float(sum / Double(radius*2+1))
            sum += Double(at(p+radius+1))-Double(at(p-radius))
          }
        }
      } }
      return result
    }
    func distance(toInside: Bool) throws -> Self {
      let infinity = Float(w+h+1)
      var result = self
      result.v = v.map { ($0 >= 0.5) == toInside ? 0 : infinity }
      let diagonal: Float = 1.41421356
      for reverse in [false,true] {
        for row in 0..<h {
          try Task.checkCancellation()
          let y = reverse ? h-1-row : row
          for col in 0..<w {
            let x = reverse ? w-1-col : col, i=y*w+x, dx = reverse ? 1 : -1, dy = dx
            for (nx,ny,cost) in [(x+dx,y,Float(1)),(x,y+dy,Float(1)),(x-1,y+dy,diagonal),(x+1,y+dy,diagonal)] {
              if nx >= 0 && nx < w && ny >= 0 && ny < h {
                result.v[i] = min(result.v[i], result.v[ny*w+nx]+cost)
              } else if !toInside { result.v[i] = min(result.v[i],cost) }
            }
          }
        }
      }
      return result
    }
  }

  static func composite(_ layer: Layer, clips: [Layer] = [], in document: CraftDocument,
    over backdrop: Surface, region: IntRect, cache:GroupRenderCache = GroupRenderCache()) throws -> Surface {
    guard let style = layer.style else { return backdrop }
    try style.validate(in: document)
    if style.requiresAdvancedArchive { return try SourceLayerStyleRenderer.composite(layer,clips:clips,in:document,over:backdrop,region:region,cache:cache) }
    let w=document.width, h=document.height
    guard w <= maximumPixels / h else { throw CraftError.unsupported("Layer styles support canvases up to 8,388,608 pixels.") }
    var plain = layer; plain.style = nil; plain.opacity = 1; plain.blendMode = .normal
    var source = try Renderer.isolatedContent(plain, in: document, cache: cache)
    if !clips.isEmpty { source = try Renderer.compositeClips(clips, onto: source, in: document, cache: cache) }
    var alpha = Map(w:w,h:h,v:[Float](repeating:0,count:w*h))
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w { alpha.v[y*w+x]=source.pixel(x:x,y:y).a } }
    let exteriorDistance = try alpha.distance(toInside:true)
    let interiorDistance = try alpha.distance(toInside:false)
    let linear = document.depth == .f32
    func read(_ s: Surface, _ x: Int, _ y: Int) -> Pixel { linear ? s.linearPixel(x:x,y:y) : s.pixel(x:x,y:y) }
    func write(_ p: Pixel, _ x: Int, _ y: Int, _ s: inout Surface) {
      if linear { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) }
    }
    func color(_ p: Pixel) -> Pixel { linear ? SRGBTransfer.linear(p) : p }
    func composite(_ p: Pixel, _ b: Pixel, _ mode: BlendMode, _ opacity: Float, _ x: Int, _ y: Int) -> Pixel {
      mode.composite(backdrop:b,source:p,opacity:opacity,x:x,y:y)
    }
    let effects = style.enabled ? style.effects.filter { $0.enabled && $0.opacity > 0 } : []
    let scale = style.scale/100
    func shadowMap(_ effect: LayerEffect, inner: Bool) throws -> Map {
      var map = alpha
      let spread = Float(effect.size*scale*effect.spread/100)
      if spread > 0 {
        for i in map.v.indices {
          map.v[i] = inner ? 1-unit(interiorDistance.v[i]-spread) : max(alpha.v[i],unit(spread-exteriorDistance.v[i]+1))
        }
      } else if inner { map.v = map.v.map { 1-$0 } }
      return try map.blurred(effect.size*scale*(1-effect.spread/100), outside: inner ? 1 : 0)
    }
    var result=backdrop
    // Exterior effects blend directly against the backdrop using their own modes.
    for effect in effects.reversed() where effect.kind == .dropShadow || effect.kind == .outerGlow {
      let map = try shadowMap(effect,inner:false)
      let angle=(effect.useGlobalLight ? PSDGlobalLight.angle(document.globalLight?.angle ?? style.lightAngle) : effect.angle) * .pi/180
      let distance=effect.kind == .dropShadow ? effect.distance*scale : 0
      let dx = -cos(angle)*distance, dy=sin(angle)*distance
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        var p=color(effect.color)
        p.a *= map.sample(Double(x)-dx,Double(y)-dy)*(1-alpha.v[y*w+x])
        write(composite(p,read(result,x,y),effect.blendMode,effect.opacity,x,y),x,y,&result)
      } }
    }
    var body=source
    if style.fillOpacity != 1 { for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      var p=read(body,x,y);p.a *= style.fillOpacity;write(p,x,y,&body)
    } } }
    let order: [LayerEffect.Kind] = [.patternOverlay,.gradientOverlay,.colorOverlay,.satin,.innerGlow,.innerShadow,.stroke,.bevelEmboss]
    for kind in order { for effect in effects.reversed() where effect.kind == kind {
      let size = Float(effect.size*scale)
      let shadow = (kind == .innerGlow || kind == .innerShadow || kind == .satin) ? try shadowMap(effect,inner:kind != .satin) : nil
      let bevel = kind == .bevelEmboss ? try alpha.blurred(effect.size*scale+effect.soften) : nil
      let gradient = try effect.gradient.map { try GradientFillSampler($0,layer:layer,document:document) }
      let pattern = try effect.pattern.map { try PatternFillSampler($0,in:document) }
      let angle = (effect.useGlobalLight ? PSDGlobalLight.angle(document.globalLight?.angle ?? style.lightAngle) : effect.angle)*Double.pi/180
      let dx = -cos(angle)*effect.distance*scale, dy = sin(angle)*effect.distance*scale
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        let a=alpha.v[y*w+x];if a <= 0 { continue }
        var p=color(effect.color), coverage: Float = 1
        switch kind {
        case .gradientOverlay: if let gradient { p=color(gradient.sample(x:x,y:y)) }
        case .patternOverlay: if let pattern { p=color(pattern.sample(x:Double(x)+0.5,y:Double(y)+0.5)) }
        case .innerShadow: coverage=shadow!.sample(Double(x)-dx,Double(y)-dy,outside:1)
        case .innerGlow: coverage=shadow!.v[y*w+x]
        case .satin: coverage=abs(shadow!.sample(Double(x)-dx,Double(y)-dy)-shadow!.sample(Double(x)+dx,Double(y)+dy))
        case .stroke:
          let inside = effect.position == .outside ? Float(0) : effect.position == .center ? size/2 : size
          coverage=unit(inside-interiorDistance.v[y*w+x]+1)
        case .bevelEmboss:
          let gx=bevel!.sample(Double(x+1),Double(y))-bevel!.sample(Double(x-1),Double(y))
          let gy=bevel!.sample(Double(x),Double(y+1))-bevel!.sample(Double(x),Double(y-1))
          let shade=(gx*Float(cos(angle))-gy*Float(sin(angle)))*Float(effect.depth/100)*max(1,size)*Float(cos((effect.useGlobalLight ? (document.globalLight?.altitude ?? style.lightAltitude) : style.lightAltitude)*Double.pi/180))
          p=color(shade >= 0 ? effect.highlightColor : effect.shadowColor)
          coverage=unit(abs(shade))*(shade >= 0 ? effect.highlightOpacity : effect.shadowOpacity)
        default: break
        }
        var b=read(body,x,y); b.a=unit(b.a/a)
        p.a *= unit(coverage)
        var edited=composite(p,b,effect.blendMode,effect.opacity,x,y);edited.a *= a
        write(edited,x,y,&body)
      } }
    } }
    for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
      write(composite(read(body,x,y),read(result,x,y),layer.blendMode,1,x,y),x,y,&result)
    } }
    for effect in effects.reversed() where effect.kind == .stroke && effect.position != .inside {
      let size=Float(effect.size*scale*(effect.position == .center ? 0.5 : 1))
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        var p=color(effect.color);p.a *= unit(size-exteriorDistance.v[y*w+x]+1)*(1-alpha.v[y*w+x])
        write(composite(p,read(result,x,y),effect.blendMode,effect.opacity,x,y),x,y,&result)
      } }
    }
    if layer.opacity != 1 { for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
      write(read(backdrop,x,y).mixing(read(result,x,y),coverage:layer.opacity),x,y,&result)
    } } }
    return result
  }
}
