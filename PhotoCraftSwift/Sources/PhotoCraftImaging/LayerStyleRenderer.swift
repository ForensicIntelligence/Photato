import Foundation
import PhotoCraftCore

/// CPU style stack following PhotoCraft's effects.rs ordering. Distance and blur
/// kernels are bounded native approximations; exact Photoshop contours remain open.
enum LayerStyleRenderer {
  /// Larger regional requests use paged patches to keep padded source maps
  /// and their temporary pixel arrays within the effect scratch budget.
  static let maximumDirectRegionPixels = 2_097_152

  struct Map {
    let w: Int, h: Int
    var v: [Float]
    func sample(_ x: Double, _ y: Double, outside: Float = 0, originX: Int = 0, originY: Int = 0) -> Float {
      let left = Int(floor(x)), top = Int(floor(y))
      let fx = Float(x - Double(left)), fy = Float(y - Double(top))
      let x0 = left - originX, y0 = top - originY
      func at(_ x: Int, _ y: Int) -> Float { x >= 0 && y >= 0 && x < w && y < h ? v[y*w+x] : outside }
      return (at(x0,y0)*(1-fx)+at(x0+1,y0)*fx)*(1-fy)
        + (at(x0,y0+1)*(1-fx)+at(x0+1,y0+1)*fx)*fy
    }
    func blurred(_ size: Double, outside: Float = 0) throws -> Self {
      if size <= 0 { return self }
      let radius = Self.blurRadius(size)
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
    static func blurRadius(_ size: Double) -> Int { size > 0 ? max(1, Int(ceil(size / 3))) : 0 }
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

  struct DropShadowGeometry {
    let dx: Double, dy: Double
    let spread: Float
    let blur: Double
    let halo: Int

    init(_ effect: LayerEffect, style: LayerStyle, in document: CraftDocument) {
      let degrees = effect.useGlobalLight
        ? PSDGlobalLight.angle(document.globalLight?.angle ?? style.lightAngle) : effect.angle
      let scale = style.scale / 100
      if style.requiresAdvancedArchive {
        let (x, y) = SourceEffectMap.offset(Float(degrees), Float(effect.distance) * Float(scale))
        dx = Double(x)
        dy = Double(y)
        let filters = SourceEffectMap.shadowFilters(effect, scale: Float(scale))
        spread = filters.spread
        blur = Double(filters.blur)
        // The tent filter runs two boxes per axis. Chamfer steps can span two pixels.
        halo = Int(spread) + 2 * SourceEffectMap.tentRadius(filters.blur) + 2
      } else {
        let angle = degrees * .pi / 180
        dx = -cos(angle) * (effect.distance * scale)
        dy = sin(angle) * (effect.distance * scale)
        spread = Float(effect.size * scale * effect.spread / 100)
        blur = effect.size * scale * (1 - effect.spread / 100)
        halo = Int(ceil(spread)) + 2 * Map.blurRadius(blur) + 1
      }
    }

    func legacyInput(for output: IntRect, in document: CraftDocument) -> IntRect {
      let left = Int(floor(Double(output.x) - dx)) - halo
      let top = Int(floor(Double(output.y) - dy)) - halo
      let right = Int(floor(Double(output.x + output.width - 1) - dx)) + halo + 2
      let bottom = Int(floor(Double(output.y + output.height - 1) - dy)) + halo + 2
      return IntRect(x: left, y: top, width: right - left, height: bottom - top)
        .clipped(toWidth: document.width, height: document.height)
    }

    func footprint(of source: IntRect, in document: CraftDocument) -> IntRect {
      let left = Int(floor(Double(source.x) + dx)) - halo - 1
      let top = Int(floor(Double(source.y) + dy)) - halo - 1
      return IntRect(x: left, y: top, width: source.width + 2 * halo + 3, height: source.height + 2 * halo + 3)
        .clipped(toWidth: document.width, height: document.height)
    }
  }

  static func styledContent(_ plain: Layer, clips: [Layer], in document: CraftDocument, cache: GroupRenderCache) throws -> Surface {
    let source = try Renderer.isolatedContent(plain, in: document, cache: cache)
    return clips.isEmpty ? source : try Renderer.compositeClips(clips, onto: source, in: document, cache: cache)
  }

  /// A plain raster over transparency contributes only its masked alpha to the
  /// shifted effect map. Other sources use the existing isolated compositor.
  static func copyShadowAlpha(_ layer: Layer, clips: [Layer], in document: CraftDocument,
    cache: GroupRenderCache, region: IntRect, to output: inout [Float], start: Int, stride: Int) throws {
    if case .raster(let source) = layer.content, clips.isEmpty, layer.visible,
      source.depth == document.depth, layer.affine == nil, layer.warp == nil,
      layer.smartObject == nil, layer.smartFilters == nil, layer.sourceProjection == nil,
      layer.importedSmartAppearance == nil, layer.nativeMode == nil, cache.inputTarget == nil {
      let local = IntRect(x: region.x - layer.x, y: region.y - layer.y,
        width: region.width, height: region.height).clipped(toWidth: source.width, height: source.height)
      guard local.width > 0, local.height > 0 else { return }
      let x0 = local.x + layer.x, y0 = local.y + layer.y
      let offset = start + (y0 - region.y) * stride + x0 - region.x
      try source.copyAlpha(in: local, to: &output, start: offset, stride: stride)
      let mask = try cache.facts.map { try $0.mask(layer, region: region) }
        ?? LayerMaskSampler.make(layer: layer, document: document, pixelRegion: region)
      for y in 0..<local.height {
        try Task.checkCancellation()
        let row = offset + y * stride
        for x in 0..<local.width {
          let coverage = mask?.coverage(x: Double(x0 + x) + 0.5, y: Double(y0 + y) + 0.5) ?? 1
          let alpha = output[row + x] * coverage
          output[row + x] = alpha > 0 ? unit(alpha) : 0
        }
      }
      return
    }
    let source = try styledContent(layer, clips: clips, in: document, cache: cache.window(region))
    for y in 0..<region.height {
      try Task.checkCancellation()
      let row = start + y * stride
      for x in 0..<region.width {
        output[row + x] = source.pixel(x: region.x + x, y: region.y + y).a
      }
    }
  }

  static func composite(_ layer: Layer, clips: [Layer] = [], in document: CraftDocument,
    over backdrop: Surface, region: IntRect, cache:GroupRenderCache = GroupRenderCache(),
    regionalEffects: Bool? = nil) throws -> Surface {
    guard let style = layer.style else { return backdrop }
    try style.validate(in: document)
    let regional = regionalEffects ?? LayerStyle.requiresRegionalEffects(in: document)
    guard style.supportsLayerCanvas(document) else {
      throw CraftError.unsupported("This layer style requires a whole-canvas effect map of at most 8,388,608 pixels.")
    }
    let work = regional ? region : IntRect(x: 0, y: 0, width: document.width, height: document.height)
    if regional, clips.contains(where: {
      if case .adjustment(.modern(let adjustment)) = $0.content { return adjustment.needsNeighborhood }
      return false
    }) {
      throw CraftError.unsupported("A clipped neighborhood adjustment requires whole-canvas layer style preparation.")
    }
    let w = work.width, h = work.height
    guard w > 0, h > 0 else { return backdrop }
    guard w <= LayerStyle.maximumWholeCanvasPixels / h else {
      throw CraftError.unsupported("This layer style render exceeds its effect map budget.")
    }
    let effectCache = regional ? cache.window(work) : cache.fullCanvas()
    if style.requiresAdvancedArchive {
      return try SourceLayerStyleRenderer.composite(layer, clips: clips, in: document, over: backdrop,
        region: region, cache: effectCache, sampleBounds: regional ? work : nil)
    }
    var plain = layer; plain.style = nil; plain.opacity = 1; plain.blendMode = .normal
    let source = try styledContent(plain, clips: clips, in: document, cache: effectCache)
    var alpha = Map(w:w,h:h,v:[Float](repeating:0,count:w*h))
    func index(_ x: Int, _ y: Int) -> Int { (y - work.y) * w + x - work.x }
    let effects = style.enabled ? style.effects.filter { $0.enabled && $0.opacity > 0 } : []
    let needsGradientFrame = effects.contains { $0.kind == .gradientOverlay && $0.gradient?.aligned == true }
    var left = work.x + w, top = work.y + h, right = work.x, bottom = work.y
    for y in work.y..<(work.y + h) {
      try Task.checkCancellation()
      for x in work.x..<(work.x + w) {
        let coverage = source.pixel(x: x, y: y).a
        alpha.v[index(x, y)] = coverage
        if needsGradientFrame, coverage > 0 {
          left = min(left, x); right = max(right, x + 1)
          top = min(top, y); bottom = max(bottom, y + 1)
        }
      }
    }
    let gradientFrame = right > left && bottom > top
      ? IntRect(x: left, y: top, width: right - left, height: bottom - top) : nil
    // Regional Drop Shadows prepare their own distance maps around the shifted source.
    let exteriorDistance = regional ? alpha : try alpha.distance(toInside: true)
    let interiorDistance = regional ? alpha : try alpha.distance(toInside: false)
    let linear = document.depth == .f32
    func read(_ s: Surface, _ x: Int, _ y: Int) -> Pixel { linear ? s.linearPixel(x:x,y:y) : s.pixel(x:x,y:y) }
    func write(_ p: Pixel, _ x: Int, _ y: Int, _ s: inout Surface) {
      if linear { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) }
    }
    func color(_ p: Pixel) -> Pixel { linear ? SRGBTransfer.linear(p) : p }
    func composite(_ p: Pixel, _ b: Pixel, _ mode: BlendMode, _ opacity: Float, _ x: Int, _ y: Int) -> Pixel {
      mode.composite(backdrop:b,source:p,opacity:opacity,x:x,y:y)
    }
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
      let geometry = DropShadowGeometry(effect, style: style, in: document)
      let map: Map
      let bounds: IntRect
      if regional {
        bounds = geometry.legacyInput(for: work, in: document)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        guard bounds.width <= LayerStyle.maximumWholeCanvasPixels / bounds.height else {
          throw CraftError.unsupported("Drop Shadow source coverage exceeds its effect map budget.")
        }
        var coverage = Map(w: bounds.width, h: bounds.height,
          v: [Float](repeating: 0, count: bounds.width * bounds.height))
        try copyShadowAlpha(plain, clips: clips, in: document, cache: cache, region: bounds,
          to: &coverage.v, start: 0, stride: bounds.width)
        if geometry.spread > 0 {
          let distance = try coverage.distance(toInside: true)
          for i in coverage.v.indices {
            coverage.v[i] = max(coverage.v[i], unit(geometry.spread - distance.v[i] + 1))
          }
        }
        map = try coverage.blurred(geometry.blur)
      } else {
        bounds = work
        map = try shadowMap(effect,inner:false)
      }
      let dx = effect.kind == .dropShadow ? geometry.dx : 0
      let dy = effect.kind == .dropShadow ? geometry.dy : 0
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        var p=color(effect.color)
        p.a *= map.sample(Double(x)-dx,Double(y)-dy,originX:bounds.x,originY:bounds.y)*(1-alpha.v[index(x, y)])
        write(composite(p,read(result,x,y),effect.blendMode,effect.opacity,x,y),x,y,&result)
      } }
    }
    var body=source
    if style.fillOpacity != 1 { for y in work.y..<(work.y + h) { try Task.checkCancellation(); for x in work.x..<(work.x + w) {
      var p=read(body,x,y);p.a *= style.fillOpacity;write(p,x,y,&body)
    } } }
    let order: [LayerEffect.Kind] = [.patternOverlay,.gradientOverlay,.colorOverlay,.satin,.innerGlow,.innerShadow,.stroke,.bevelEmboss]
    for kind in order { for effect in effects.reversed() where effect.kind == kind {
      let size = Float(effect.size*scale)
      let shadow = (kind == .innerGlow || kind == .innerShadow || kind == .satin) ? try shadowMap(effect,inner:kind != .satin) : nil
      let bevel = kind == .bevelEmboss ? try alpha.blurred(effect.size*scale+effect.soften) : nil
      let gradient = try effect.gradient.map { try GradientFillSampler($0, layer: layer, document: document,
        alignedFrame: kind == .gradientOverlay ? gradientFrame : nil, isOverlay: kind == .gradientOverlay) }
      let pattern = try effect.pattern.map {
        try PatternFillSampler.overlay($0, style: style, layer: layer, in: document, preparation: effectCache.facts?.patternPreparation)
      }
      let opacity = PatternFillSampler.overlayOpacity(effect, in: document)
      let angle = (effect.useGlobalLight ? PSDGlobalLight.angle(document.globalLight?.angle ?? style.lightAngle) : effect.angle)*Double.pi/180
      let dx = -cos(angle)*effect.distance*scale, dy = sin(angle)*effect.distance*scale
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        let a=alpha.v[index(x, y)];if a <= 0 { continue }
        var p=color(effect.color), coverage: Float = 1
        switch kind {
        case .gradientOverlay: if let gradient { p=color(gradient.sample(x:x,y:y)) }
        case .patternOverlay: if let pattern { p=color(pattern.sample(x:Double(x)+0.5,y:Double(y)+0.5)) }
        case .innerShadow: coverage=shadow!.sample(Double(x)-dx,Double(y)-dy,outside:1)
        case .innerGlow: coverage=shadow!.v[index(x, y)]
        case .satin: coverage=abs(shadow!.sample(Double(x)-dx,Double(y)-dy)-shadow!.sample(Double(x)+dx,Double(y)+dy))
        case .stroke:
          let inside = effect.position == .outside ? Float(0) : effect.position == .center ? size/2 : size
          coverage=unit(inside-interiorDistance.v[index(x, y)]+1)
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
        var edited=composite(p,b,effect.blendMode,opacity,x,y);edited.a *= a
        write(edited,x,y,&body)
      } }
    } }
    for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
      write(composite(read(body,x,y),read(result,x,y),layer.blendMode,1,x,y),x,y,&result)
    } }
    for effect in effects.reversed() where effect.kind == .stroke && effect.position != .inside {
      let size=Float(effect.size*scale*(effect.position == .center ? 0.5 : 1))
      for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
        var p=color(effect.color);p.a *= unit(size-exteriorDistance.v[index(x, y)]+1)*(1-alpha.v[index(x, y)])
        write(composite(p,read(result,x,y),effect.blendMode,effect.opacity,x,y),x,y,&result)
      } }
    }
    if layer.opacity != 1 { for y in region.y..<region.y+region.height { try Task.checkCancellation(); for x in region.x..<region.x+region.width {
      write(read(backdrop,x,y).mixing(read(result,x,y),coverage:layer.opacity),x,y,&result)
    } } }
    return result
  }
}
