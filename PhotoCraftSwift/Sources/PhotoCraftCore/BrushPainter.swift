import Foundation

fileprivate final class BrushCoverageTile {
  var coverage=[Float](repeating:0,count:4096)
  var colors:[SIMD4<Float>]
  func copied() -> BrushCoverageTile { let copy = BrushCoverageTile(color: !colors.isEmpty); copy.coverage = coverage; copy.colors = colors; return copy }
  init(color:Bool) { colors=color ? [SIMD4<Float>](repeating:.zero,count:4096):[] }

  func accumulate(_ weights: UnsafeMutableBufferPointer<Float>, x: Range<Int>, y: Range<Int>,
    ceiling: Float, maximum: Bool, ink: SIMD4<Float>) -> Bool {
    func update(_ values: UnsafeMutableBufferPointer<Float>, _ colors: UnsafeMutableBufferPointer<SIMD4<Float>>?) -> Bool {
      var changed = false
      for row in y {
        for column in x {
          let i = row * 64 + column, weight = weights[i]
          guard weight > 0 else { continue }
          let old = values[i]
          let next = maximum ? max(old,weight*ceiling) : max(old,old+weight*(ceiling-old))
          guard next > old else { continue }
          if let colors {
            let k = old < 1 ? (next-old)/(1-old) : 0
            colors[i] = ink*k + colors[i]*(1-k)
          }
          values[i] = next
          changed = true
        }
      }
      return changed
    }
    if colors.isEmpty { return coverage.withUnsafeMutableBufferPointer { update($0,nil) } }
    return coverage.withUnsafeMutableBufferPointer { values in
      colors.withUnsafeMutableBufferPointer { update(values,$0) }
    }
  }
}
enum BrushRetentionError: Error {
  case coverageBudget
}

fileprivate struct BrushCoverage {
  private static let maximumBytes = 128 * 1024 * 1024
  var tiles:[Int:BrushCoverageTile]=[:]
  var dirty: Set<Int> = []
  var trackDirty = false
  private var shared: Set<Int> = []
  private let retainingWideRaster: Bool
  init(columns: Int, color: Bool, retainingWideRaster: Bool = false) {
    self.columns = columns; self.color = color; self.retainingWideRaster = retainingWideRaster
  }
  func fork() -> Self { var copy = self; copy.shared = Set(tiles.keys); copy.dirty = []; return copy }
  mutating func writable(_ key: Int) -> BrushCoverageTile? {
    guard let tile = tiles[key] else { return nil }
    if shared.remove(key) != nil { let copy = tile.copied(); tiles[key] = copy; return copy }; return tile
  }
  let columns:Int
  let color:Bool
  private var tileBytes: Int { 4096 * (color ? 20 : 4) }
  func location(_ x:Int,_ y:Int)->(Int,Int) { ((y/64)*columns+x/64,(y%64)*64+x%64) }
  mutating func accumulatingTile(_ key: Int) throws -> BrushCoverageTile {
    if let found = writable(key) { return found }
    try admitTile()
    let tile = BrushCoverageTile(color:color)
    tiles[key] = tile
    return tile
  }
  private func admitTile() throws {
    guard tiles.count < Self.maximumBytes / tileBytes else {
      if retainingWideRaster { throw BrushRetentionError.coverageBudget }
      throw CraftError.invalid("Brush stroke coverage exceeds128MiB.")
    }
  }
  func checkDabExtent(_ rect: IntRect) throws {
    guard retainingWideRaster else { return }
    let columns = (rect.x + rect.width - 1) / 64 - rect.x / 64 + 1
    let rows = (rect.y + rect.height - 1) / 64 - rect.y / 64 + 1
    if columns * rows > Self.maximumBytes / tileBytes { throw BrushRetentionError.coverageBudget }
  }
  func value(_ x:Int,_ y:Int)->Float { let (key,index)=location(x,y);return tiles[key]?.coverage[index] ?? 0 }
  mutating func union(_ other:Self)throws {
    for (key,source) in other.tiles {
      // The complete painter relinquishes each pass after merging it.
      guard let target=tiles[key] else {
        try admitTile()
        tiles[key] = source
        continue
      }
      for i in 0..<4096 where source.coverage[i]>target.coverage[i] { target.coverage[i]=source.coverage[i];if color { target.colors[i]=source.colors[i] } }
    }
  }
}
/// Prepared Normal color for a raster without per-pixel selection or ink.
fileprivate struct NormalRasterBrush {
  private let color: SIMD3<Float>
  private let colorAlpha: Float
  private let opacity: Float

  init?(_ brush: Brush, settings: BrushSettings, hasSelection: Bool,
    grayscale: Bool, preserveTransparency: Bool, pendingTexture: Bool = false) {
    guard settings.mode == .normal, !settings.colorDynamics.enabled, !brush.erase,
      !hasSelection, !grayscale, !preserveTransparency, !pendingTexture else { return nil }
    color = brush.color.rgb
    colorAlpha = brush.color.a
    opacity = brush.opacity
  }

  @inline(__always)
  func apply(_ coverage: Float, to backdrop: Pixel) -> Pixel? {
    let a = unit(coverage * opacity * colorAlpha)
    guard a > 0 else { return nil }
    return BlendMode.sourceOver(backdrop: backdrop, source: color, alpha: a, blend: color)
  }

  func write(_ coverage: [Float], key: Int, to surface: inout Surface, original: Surface? = nil) {
    surface.updateBrushTile(key, coverage: coverage, rebuildingFrom: original) { _, _, _, weight, pixel in
      apply(weight, to: pixel)
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
  /// Geometry and falloff shared by every destination sample of a dab.
  struct TipSampler {
    private let center: (x: Double, y: Double)
    private let direction: (cosine: Double, sine: Double)
    private let flip: (x: Double, y: Double)
    private let projection: (x: Double, y: Double, stretch: Double)?
    private let bitmap: BrushBitmap?
    private let bitmapScale: Double
    private let roundness: Double
    private let radius: Double
    private let inner: Double
    private let falloff: Double
    private let aliased: Bool
    let isAxisAlignedRound: Bool

    init(_ dab: BrushDab, bitmap: BrushBitmap?, hardness: Double, aliased: Bool) {
      if aliased {
        let diameter = max(1, Int((dab.radius * 2).rounded()))
        center = diameter % 2 == 1
          ? (floor(dab.x) + 0.5, floor(dab.y) + 0.5) : (dab.x.rounded(), dab.y.rounded())
      } else {
        center = (dab.x, dab.y)
      }
      direction = (cos(dab.angle), sin(dab.angle))
      flip = (dab.flipX ? -1 : 1, dab.flipY ? -1 : 1)
      projection = dab.projectionScale < 0.999
        ? (cos(dab.projectionAngle), sin(dab.projectionAngle), 1 / dab.projectionScale - 1) : nil
      self.bitmap = bitmap
      bitmapScale = bitmap.map { Double(max($0.width, $0.height)) / (2 * dab.radius) } ?? 0
      let roundness = min(1, max(0.5 / dab.radius, dab.roundness))
      self.roundness = roundness
      let radius = max(0.5, dab.radius * roundness)
      self.radius = radius
      inner = radius * hardness
      falloff = radius - inner
      self.aliased = aliased
      isAxisAlignedRound = bitmap == nil && dab.angle == 0 && roundness == 1 && projection == nil
    }

    @inline(__always)
    private func coverage(at distance: Double) -> Double {
      if aliased { return distance <= radius ? 1 : 0 }
      guard distance < radius + 0.5 else { return 0 }
      let edge = min(1, max(0, radius + 0.5 - distance))
      return edge * (distance <= inner || falloff < 0.001 ? 1 : 1 - BrushPainter.smooth((distance - inner) / falloff))
    }

    @inline(__always)
    func sample(_ point: (x: Double, y: Double)) -> (Double, Double) {
      var ux = point.x - center.x, uy = -(point.y - center.y)
      if let projection {
        let t = (ux * projection.x + uy * projection.y) * projection.stretch
        ux += t * projection.x
        uy += t * projection.y
      }
      let u = (ux * direction.cosine + uy * direction.sine) * flip.x
      let v = (-ux * direction.sine + uy * direction.cosine) * flip.y
      if let bitmap {
        let x = u * bitmapScale + Double(bitmap.width) / 2 - 0.5
        let y = -(v / roundness) * bitmapScale + Double(bitmap.height) / 2 - 0.5
        let sample = bitmap.sample(x, y)
        return (aliased ? (sample >= 0.5 ? 1 : 0) : sample, 1 - sample)
      }
      let distance = hypot(u * roundness, v)
      return (coverage(at: distance), distance / radius)
    }

    @inline(__always)
    func roundTile(_ weights: UnsafeMutableBufferPointer<Float>, x: Range<Int>, y: Range<Int>,
      tileX: Int, tileY: Int, flow: Double) -> Bool {
      let nearX = Double(tileX + x.lowerBound) + 0.5 - center.x
      let farX = Double(tileX + x.upperBound - 1) + 0.5 - center.x
      let nearY = Double(tileY + y.lowerBound) + 0.5 - center.y
      let farY = Double(tileY + y.upperBound - 1) + 0.5 - center.y
      let minimum = hypot(max(0, nearX, -farX), max(0, nearY, -farY))
      // Leave a half-pixel margin at each boundary and sample those tiles normally.
      let outer = aliased ? radius : radius + 0.5
      if minimum > outer + 0.5 { return false }
      let maximum = hypot(max(abs(nearX), abs(farX)), max(abs(nearY), abs(farY)))
      let solidRadius = aliased ? radius : min(inner, radius - 0.5)
      if maximum < solidRadius - 0.5 {
        let weight = Float(flow)
        for row in y {
          for column in x { weights[row * 64 + column] = weight }
        }
        return weight > 0
      }
      var hasCoverage = false
      for row in y {
        let dy = -(Double(tileY + row) + 0.5 - center.y)
        for column in x {
          let dx = Double(tileX + column) + 0.5 - center.x
          let weight = Float(coverage(at: hypot(dx, dy)) * flow)
          weights[row * 64 + column] = weight
          hasCoverage = hasCoverage || weight > 0
        }
      }
      return hasCoverage
    }
  }

  public static func validate(_ brush:Brush,points:[StrokePoint])throws {
    guard brush.size.isFinite,brush.supportedDiameterRange.contains(brush.size),brush.hardness.isFinite,(0...1).contains(brush.hardness),brush.opacity.isFinite,(0...1).contains(brush.opacity),brush.color.isFinite,(0...1).contains(brush.color.a),brush.backgroundColor?.isFinite != false,points.count<=100_000 else { throw CraftError.invalid("Invalid brush settings or input count.") }
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
  private static let rasterVisitLimit = 134_217_728
  private static let coverageBandSide = 1024

  private static func rasterBounds(_ dab: BrushDab, bitmap: BrushBitmap?, transform: Transform2D, extent: IntRect) -> IntRect? {
    let reach = dab.radius * (bitmap == nil ? 1 : sqrt(2)) + 1
    let center = transform.point(dab.x, dab.y)
    let rx = reach * hypot(transform.a, transform.c), ry = reach * hypot(transform.b, transform.d)
    let right = extent.x + extent.width, bottom = extent.y + extent.height
    let x0 = Int(max(Double(extent.x), min(Double(right), floor(center.x - rx))))
    let x1 = Int(max(Double(extent.x - 1), min(Double(right - 1), ceil(center.x + rx))))
    let y0 = Int(max(Double(extent.y), min(Double(bottom), floor(center.y - ry))))
    let y1 = Int(max(Double(extent.y - 1), min(Double(bottom - 1), ceil(center.y + ry))))
    guard x0 <= x1, y0 <= y1 else { return nil }
    return .init(x:x0,y:y0,width:x1-x0+1,height:y1-y0+1)
  }

  /// A large dab can need more coverage storage than one working set. Visit
  /// disjoint bands in tile order, reusing the exact per-pixel deposition.
  private static func coverageBands(_ dabs: [BrushDab], bitmap: BrushBitmap?, transforms: [Transform2D],
    extent: IntRect, surfaceWidth: Int) throws -> [IntRect] {
    let side = coverageBandSide
    let columns = (surfaceWidth + side - 1) / side
    var keys: Set<Int> = [], plannedVisits = 0
    for transform in transforms {
      for (index,dab) in dabs.enumerated() {
        if index % 32 == 0 { try Task.checkCancellation() }
        guard let rect = rasterBounds(dab,bitmap:bitmap,transform:transform,extent:extent) else { continue }
        let area = rect.width * rect.height
        guard area <= rasterVisitLimit - plannedVisits else {
          throw CraftError.invalid("Brush stroke exceeds the raster work limit.")
        }
        plannedVisits += area
        for y in rect.y/side...(rect.y+rect.height-1)/side {
          for x in rect.x/side...(rect.x+rect.width-1)/side { keys.insert(y * columns + x) }
        }
      }
    }
    return keys.sorted().map { key in
      let x = key % columns * side, y = key / columns * side
      let left = max(x, extent.x), top = max(y, extent.y)
      let right = min(x+side, extent.x+extent.width), bottom = min(y+side, extent.y+extent.height)
      return .init(x:left,y:top,width:right-left,height:bottom-top)
    }
  }

  fileprivate static func clippedBounds(_ selection: IntRect?, inverse: Transform2D, width: Int, height: Int) -> IntRect {
    let bounds = IntRect(x:0,y:0,width:width,height:height)
    guard let selection else { return bounds }
    guard selection.width > 0, selection.height > 0 else { return .init(x:0,y:0,width:0,height:0) }
    let left = Double(selection.x), top = Double(selection.y)
    let right = left + Double(selection.width), bottom = top + Double(selection.height)
    let corners = [inverse.point(left,top),inverse.point(right,top),inverse.point(left,bottom),inverse.point(right,bottom)]
    // Include a guard pixel because final admission samples transformed pixel centers.
    let x0 = Int(max(0,min(Double(width),floor(corners.map { $0.x }.min()!)-1)))
    let y0 = Int(max(0,min(Double(height),floor(corners.map { $0.y }.min()!)-1)))
    let x1 = Int(max(0,min(Double(width),ceil(corners.map { $0.x }.max()!)+1)))
    let y1 = Int(max(0,min(Double(height),ceil(corners.map { $0.y }.max()!)+1)))
    return .init(x:x0,y:y0,width:x1-x0,height:y1-y0)
  }

  fileprivate static func raster(_ dabs: [BrushDab], isDual: Bool, brush: Brush, toLocal: Transform2D,
    toOriginal: Transform2D, transform: Transform2D, extent: IntRect, map: inout BrushCoverage, visits: inout Int) throws {
    let b = brush.settings!
    let bitmap = isDual ? b.dual.tip : b.tip
    let hardness = isDual ? b.dual.hardness : Double(brush.hardness)
    let aliased = b.aliased && !isDual, maximum = b.wetEdges && !isDual
    let eachTipTexture = b.texture.enabled && b.texture.eachTip
    let usesEffects = !isDual && (b.noise || eachTipTexture || b.wetEdges)
    try withUnsafeTemporaryAllocation(of: Float.self, capacity: 4096) { weights in
      weights.initialize(repeating: 0)
      for (index,dab) in dabs.enumerated() {
        if index % 32 == 0 { try Task.checkCancellation() }
        guard let rect = rasterBounds(dab,bitmap:bitmap,transform:toLocal,extent:extent) else { continue }
        try map.checkDabExtent(rect)
        let area = rect.width * rect.height
        guard area <= rasterVisitLimit - visits else { throw CraftError.invalid("Brush stroke exceeds the raster work limit.") }
        visits += area
        let right = rect.x + rect.width, bottom = rect.y + rect.height
        let tip = TipSampler(dab, bitmap: bitmap, hardness: hardness, aliased: aliased)
        let ordinaryRound = tip.isAxisAlignedRound && toOriginal == .identity && !usesEffects
        let ink = SIMD4(dab.color.r,dab.color.g,dab.color.b,dab.color.a), ceiling = Float(dab.opacity)
        for row in rect.y/64...(bottom-1)/64 {
          let ty = row*64, yRange = (max(rect.y,ty)-ty)..<(min(bottom,ty+64)-ty)
          for column in rect.x/64...(right-1)/64 {
            try Task.checkCancellation()
            let tx = column*64, xRange = (max(rect.x,tx)-tx)..<(min(right,tx+64)-tx)
            var hasCoverage = false
            if ordinaryRound {
              hasCoverage = tip.roundTile(weights, x: xRange, y: yRange, tileX: tx, tileY: ty, flow: dab.flow)
            } else {
              for ly in yRange {
                for lx in xRange {
                  let x = Double(tx+lx)+0.5, y = Double(ty+ly)+0.5
                  let p = toOriginal.point(x,y)
                  var (value,rn) = tip.sample(p)
                  if value > 0 && usesEffects {
                    let doc = transform.point(x,y)
                    if b.noise && value<1 { let n=BrushRandom.pixel(Int(floor(doc.x)),Int(floor(doc.y)),0x6E6F697365);value += ((n<value ? 1:0)-value)*0.7 }
                    if eachTipTexture { value=b.texture.mode.combine(value,texture(b.texture,doc.x,doc.y),dab.depth) }
                    if b.wetEdges { value *= 0.5+0.5*smooth((rn-0.5)*2) }
                  }
                  let weight = Float(value*dab.flow)
                  weights[ly*64+lx] = weight
                  hasCoverage = hasCoverage || weight > 0
                }
              }
            }
            guard hasCoverage else { continue }
            let key = row*map.columns + column
            let tile = try map.accumulatingTile(key)
            let changed = tile.accumulate(weights,x:xRange,y:yRange,ceiling:ceiling,maximum:maximum,ink:ink)
            if changed && map.trackDirty { map.dirty.insert(key) }
          }
        }
      }
    }
  }

  public static func stroke(surface:inout Surface,points:[StrokePoint],brush:Brush,selection:IntRect?=nil,selectionMask:SelectionMask?=nil,transform:Transform2D = .identity,grayscaleMask:Bool=false,preserveTransparency:Bool=false)throws {
    try validate(brush,points:points);try transform.validated();guard let b=brush.settings,!points.isEmpty else { return };try Task.checkCancellation()
    var generator=BrushDabGenerator(brush);var dabs=try generator.push(points);let tail=try generator.finish();dabs.0 += tail.0;dabs.1 += tail.1
    let inverse = try transform.inverted(), columns = (surface.width+63)/64
    let passes = try symmetry(b.symmetry).map { pass in
      (toLocal: inverse * pass, toOriginal: try pass.inverted() * transform)
    }
    let regions: [IntRect]
    if brush.size > Brush.legacyDiameterRange.upperBound {
      if selectionMask != nil && selectionMask?.bounds == nil { return }
      let extent = clippedBounds(selection ?? selectionMask?.bounds, inverse:inverse, width:surface.width, height:surface.height)
      guard extent.width > 0, extent.height > 0 else { return }
      regions = try coverageBands(dabs.0, bitmap:b.tip, transforms:passes.map { $0.toLocal },
        extent:extent, surfaceWidth:surface.width)
    } else {
      regions = [.init(x:0,y:0,width:surface.width,height:surface.height)]
    }
    // Publish only after every band has completed successfully.
    var result = surface, visits = 0
    let textureAfterDabs = b.texture.enabled && !b.texture.eachTip
    let normal = NormalRasterBrush(brush, settings: b, hasSelection: selection != nil || selectionMask != nil,
      grayscale: grayscaleMask, preserveTransparency: preserveTransparency)
    for region in regions {
      var merged = BrushCoverage(columns:columns,color:b.colorDynamics.enabled)
      for (toLocal,toOriginal) in passes {
        var primary=BrushCoverage(columns:columns,color:b.colorDynamics.enabled),dual=BrushCoverage(columns:columns,color:false)
        try raster(dabs.0,isDual:false,brush:brush,toLocal:toLocal,toOriginal:toOriginal,transform:transform,extent:region,map:&primary,visits:&visits)
        if b.dual.enabled { try raster(dabs.1,isDual:true,brush:brush,toLocal:toLocal,toOriginal:toOriginal,transform:transform,extent:region,map:&dual,visits:&visits) }
        if b.dual.enabled || textureAfterDabs {
          for (key,tile) in primary.tiles {
            let tx=(key%columns)*64,ty=(key/columns)*64
            for i in 0..<4096 where tile.coverage[i]>0 {
              let x=tx+i%64,y=ty+i/64;let old=tile.coverage[i];var value=Double(old)
              if b.dual.enabled { value=b.dual.mode.combine(value,Double(dual.value(x,y)),1) }
              if textureAfterDabs { let doc=transform.point(Double(x)+0.5,Double(y)+0.5);value=b.texture.mode.combine(value,texture(b.texture,doc.x,doc.y),b.texture.depth) }
              tile.coverage[i]=Float(value);if b.colorDynamics.enabled { tile.colors[i] *= Float(value)/old }
            }
          }
        }
        try merged.union(primary)
      }
      for key in merged.tiles.keys.sorted() {
        try Task.checkCancellation()
        let tile = merged.tiles[key]!
        if let normal {
          normal.write(tile.coverage, key: key, to: &result)
          continue
        }
        let colors = tile.colors
        result.updateBrushTile(key,coverage:tile.coverage) { x,y,i,weight,base in
          let doc=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(doc.x)),dy=Int(floor(doc.y))
          if let selection,!selection.contains(dx,dy) { return nil }
          let mask=selectionMask?.coverage(x:dx,y:dy) ?? 1
          var ink=brush.color
          if b.colorDynamics.enabled { let c=colors[i]/weight;ink=Pixel(c.x,c.y,c.z,c.w) }
          let alpha=unit(weight*brush.opacity*ink.a*mask);guard alpha>0 else { return nil }
          var before=base
          if grayscaleMask { before=Pixel(before.r,before.r,before.r);let gray=unit(ink.r*0.2126+ink.g*0.7152+ink.b*0.0722);ink=Pixel(gray,gray,gray,ink.a) }
          if preserveTransparency && !grayscaleMask && before.a<=0 { return nil }
          if brush.erase && !preserveTransparency && !grayscaleMask { return Pixel(before.r,before.g,before.b,before.a*(1-alpha)) }
          if brush.erase { ink=brush.backgroundColor ?? .white }
          ink.a=alpha
          return preserveTransparency && !grayscaleMask ? ProtectedPixels.composite(b.mode,backdrop:before,source:ink,x:dx,y:dy):b.mode.composite(backdrop:before,source:ink,x:dx,y:dy)
        }
      }
    }
    try Task.checkCancellation();surface=result
  }
}

/// Retains spacing, smoothing, random state and stroke-wide opacity coverage between
/// input batches. Confined to one worker; published Surface values remain immutable.
/// Dual tips and symmetry retain the full painter until their incremental path is qualified.
public final class BrushStrokeSession {
  public static func supports(_ brush: Brush) -> Bool {
    supports(brush, allowingWideRaster: false)
  }
  static func supports(_ brush: Brush, allowingWideRaster: Bool) -> Bool {
    guard let settings = brush.settings else { return false }
    let limit = allowingWideRaster ? Brush.diameterRange.upperBound : Brush.legacyDiameterRange.upperBound
    return brush.size <= limit && !settings.dual.enabled && settings.symmetry.mode == .off
  }
  private struct ProvisionalFirstDab {
    let dab: BrushDab
    let coverage: BrushCoverage
    let visits: Int
  }
  private let original: Surface
  private let brush: Brush
  private let transform: Transform2D
  private let inverse: Transform2D
  private let extent: IntRect
  private let selection: IntRect?
  private let selectionMask: SelectionMask?
  private let grayscale: Bool
  private let preserveTransparency: Bool
  private var generator: BrushDabGenerator
  private var coverage: BrushCoverage
  private var result: Surface
  private var visits = 0
  private var count = 0
  private var previousTime = 0.0
  private var previousTail: Set<Int> = []
  private var firstPreview: ProvisionalFirstDab?
  private let retainsWideRaster: Bool
  private var failed = false

  public convenience init(surface: Surface, brush: Brush, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil, transform: Transform2D = .identity,
    grayscaleMask: Bool = false, preserveTransparency: Bool = false) throws {
    try self.init(surface: surface, brush: brush, selection: selection, selectionMask: selectionMask,
      transform: transform, grayscaleMask: grayscaleMask, preserveTransparency: preserveTransparency, allowingWideRaster: false)
  }

  init(surface: Surface, brush: Brush, selection: IntRect?, selectionMask: SelectionMask?,
    transform: Transform2D, grayscaleMask: Bool = false, preserveTransparency: Bool,
    allowingWideRaster: Bool) throws {
    guard Self.supports(brush, allowingWideRaster: allowingWideRaster) else {
      throw CraftError.unsupported("This brush uses the complete stroke renderer.")
    }
    try BrushPainter.validate(brush, points: []); try surface.validated(); try transform.validated()
    original = surface; result = surface; self.brush = brush; self.transform = transform
    let inverse = try transform.inverted()
    self.inverse = inverse; self.selection = selection; self.selectionMask = selectionMask
    grayscale = grayscaleMask; self.preserveTransparency = preserveTransparency
    retainsWideRaster = allowingWideRaster && brush.size > Brush.legacyDiameterRange.upperBound
    if retainsWideRaster {
      let bounds = selectionMask != nil && selectionMask?.bounds == nil
        ? IntRect(x: 0, y: 0, width: 0, height: 0) : selection ?? selectionMask?.bounds
      extent = BrushPainter.clippedBounds(bounds, inverse: inverse, width: surface.width, height: surface.height)
    } else {
      extent = .init(x: 0, y: 0, width: surface.width, height: surface.height)
    }
    generator = BrushDabGenerator(brush)
    coverage = BrushCoverage(columns: (surface.width + 63) / 64,
      color: brush.settings!.colorDynamics.enabled, retainingWideRaster: retainsWideRaster)
    coverage.trackDirty = true
  }

  /// Preview includes a provisional smoothing tail, just like a complete stroke.
  /// That tail is discarded before the next append, so input chunking cannot change pixels.
  public func append(_ points: [StrokePoint], includingReleaseTail: Bool = true) throws -> Surface {
    guard !failed else { throw CraftError.invalid("The cancelled or failed stroke must be restarted.") }
    do { return try update(points, includingReleaseTail: includingReleaseTail) } catch { failed = true; throw error }
  }
  private func update(_ points: [StrokePoint], includingReleaseTail: Bool) throws -> Surface {
    guard count + points.count <= 100_000 else { throw CraftError.invalid("Invalid brush input count.") }
    for point in points {
      try point.validatedBrushInput()
      if let time = point.time { guard time >= previousTime else { throw CraftError.invalid("Brush timestamps must be monotonic.") }; previousTime = time }
    }
    try Task.checkCancellation(); count += points.count; coverage.dirty = []
    let stable = try generator.push(points).0
    var ending = generator
    let released = try ending.finish(includingReleaseTail: includingReleaseTail).0
    if let firstPreview {
      if stable.isEmpty, released.count == 1, firstPreview.dab.hasSameRasterSamples(as: released[0]) {
        try Task.checkCancellation()
        return result
      }
      if let next = stable.first, firstPreview.dab.hasSameRasterSamples(as: next) {
        // Its published pixels and coverage already represent this exact dab.
        coverage = firstPreview.coverage
        coverage.dirty = []
        visits = firstPreview.visits
        previousTail = []
        try raster(Array(stable.dropFirst()), into: &coverage, visits: &visits)
      } else {
        try raster(stable, into: &coverage, visits: &visits)
      }
      self.firstPreview = nil
    } else {
      try raster(stable, into: &coverage, visits: &visits)
    }
    let changed = coverage.dirty
    if changed.isEmpty && released.isEmpty && previousTail.isEmpty {
      try Task.checkCancellation()
      return result
    }
    var preview = released.isEmpty ? coverage : coverage.fork()
    var tailVisits = visits
    try raster(released, into: &preview, visits: &tailVisits)
    let tail = released.isEmpty ? [] : preview.dirty
    let keys = changed.union(tail).union(previousTail)
    let settings = brush.settings!
    let normal = NormalRasterBrush(brush, settings: settings, hasSelection: selection != nil || selectionMask != nil,
      grayscale: grayscale, preserveTransparency: preserveTransparency,
      pendingTexture: settings.texture.enabled && !settings.texture.eachTip)
    for key in keys.sorted() {
      try Task.checkCancellation()
      let tile = preview.tiles[key]
      if let normal {
        normal.write(tile?.coverage ?? [], key: key, to: &result, original: original)
        continue
      }
      // Rebuild from the stroke's original pixels. This also clears a previous
      // tail when the revised stroke has no coverage on its former tile.
      result.updateBrushTile(key, coverage: tile?.coverage ?? [], rebuildingFrom: original) { x, y, i, old, base in
        let doc = transform.point(Double(x) + 0.5, Double(y) + 0.5)
        let dx = Int(floor(doc.x)), dy = Int(floor(doc.y))
        var value = Double(old)
        if settings.texture.enabled && !settings.texture.eachTip {
          value = settings.texture.mode.combine(value, BrushPainter.texture(settings.texture, doc.x, doc.y), settings.texture.depth)
        }
        guard value > 0, selection?.contains(dx, dy) != false else { return nil }
        let amount = Float(value), mask = selectionMask?.coverage(x: dx, y: dy) ?? 1
        var ink = brush.color
        if settings.colorDynamics.enabled, let tile {
          // Preserve the same Float32 rounding as the complete painter's texture pass.
          let color = (tile.colors[i] * (amount / old)) / amount
          ink = Pixel(color.x, color.y, color.z, color.w)
        }
        let alpha = unit(amount * brush.opacity * ink.a * mask)
        var before = base
        if grayscale {
          before = Pixel(before.r, before.r, before.r)
          let gray = unit(ink.r * 0.2126 + ink.g * 0.7152 + ink.b * 0.0722)
          ink = Pixel(gray, gray, gray, ink.a)
        }
        guard alpha > 0, !(preserveTransparency && !grayscale && before.a <= 0) else { return nil }
        if brush.erase && !preserveTransparency && !grayscale {
          return Pixel(before.r, before.g, before.b, before.a * (1 - alpha))
        }
        if brush.erase { ink = brush.backgroundColor ?? .white }
        ink.a = alpha
        return preserveTransparency && !grayscale
          ? ProtectedPixels.composite(settings.mode, backdrop: before, source: ink, x: dx, y: dy)
          : settings.mode.composite(backdrop: before, source: ink, x: dx, y: dy)
      }
    }
    try Task.checkCancellation(); previousTail = tail
    if retainsWideRaster && stable.isEmpty && released.count == 1 && visits == 0 {
      firstPreview = ProvisionalFirstDab(dab: released[0], coverage: preview, visits: tailVisits)
    }
    return result
  }
  private func raster(_ dabs: [BrushDab], into map: inout BrushCoverage, visits: inout Int) throws {
    guard !dabs.isEmpty else { return }
    try BrushPainter.raster(dabs, isDual: false, brush: brush, toLocal: inverse,
      toOriginal: transform, transform: transform, extent: extent,
      map: &map, visits: &visits)
  }
}
