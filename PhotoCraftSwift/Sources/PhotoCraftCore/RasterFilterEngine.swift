import Foundation

public enum RasterFilterEngine {
  public static let maximumPixels = 8_388_608
  public static var pagedFilterKinds:[RasterFilter.Kind] {PagedRasterFilters.kinds}
  public static var maximumPagedScratchPlaneBytes:Int {PagedRasterFilters.maximumPlaneBytes}
  typealias Sample = SIMD4<Double>

  public static func apply(_ filter: RasterFilter, to layerID: UUID, in document: inout CraftDocument) throws {
    try filter.validate()
    guard let index = document.layers.firstIndex(where: { $0.id == layerID }),
      !document.isLocked(layerID), !document.isImageLocked(layerID),
      case .raster(let source) = document.layers[index].content
    else { throw CraftError.invalid("Filters require an unlocked pixel layer.") }
    if filter.relight?.isIdentity==true{return}
    if source.width > maximumPixels/source.height {
      guard pagedFilterKinds.contains(filter.kind),document.colorMode == .rgb,
        document.inkMode==nil,document.restrictedMode==nil else {
        throw CraftError.unsupported("This filter or mode retains its 8,388,608-pixel preparation limit.")
      }
      try PagedRasterFilters.apply(filter,to:layerID,in:&document);return
    }
    if let settings=filter.lighting {try LightingEngine.apply(settings,source:source,layerID:layerID,index:index,document:&document);return}
    if let settings=filter.relight {try RelightEngine.apply(settings,source:source,layerID:layerID,index:index,document:&document);return}
    if let settings=filter.tone {try ClassicToneEngine.apply(.init(settings,layerID:layerID),to:&document);return}
    if let settings=filter.classicDetail {try ClassicDetailEngine.apply(settings,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return}
    if let settings=filter.otherVideo {try OtherVideoEngine.apply(settings,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return}
    if let settings=filter.renderSettings {try RenderFilterEngine.apply(settings,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return}
    if let stylize=filter.stylize {try StylizeEngine.apply(stylize,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return}
    if let pixelate=filter.pixelate { try PixelateEngine.apply(pixelate,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return }
    if let distortion=filter.distortion { try DistortionEngine.apply(distortion,kind:filter.kind,source:source,layerID:layerID,index:index,document:&document);return }
    if let lensBlur=filter.lensBlur { try LensBlurEngine.apply(lensBlur,source:source,layerID:layerID,index:index,document:&document);return }
    if filter.kind == .smartSharpen || filter.kind == .reduceNoise { try PhotoDetailEngine.apply(filter,source:source,layerID:layerID,index:index,document:&document);return }
    if filter.kind == .filterGallery { try ArtisticGalleryEngine.apply(filter.artistic!,source:source,layerID:layerID,index:index,document:&document);return }
    if filter.kind == .adaptiveWideAngle { try WideAngleEngine.apply(filter.wideAngle!,to:layerID,in:&document);return }
    if filter.kind == .perspectiveWarp { try PerspectiveEngine.apply(filter.perspective!,to:layerID,in:&document);return }
    if filter.kind == .puppetWarp { try PuppetEngine.apply(filter.puppet!,to:layerID,in:&document); return }
    if filter.kind == .cameraRaw {
      try applyCameraRaw(filter.cameraRaw!, source: source, layerID: layerID, index: index, document: &document); return
    }
    if filter.kind == .lensCorrection, filter.lens!.isIdentity { return }
    if filter.kind == .blurGallery, filter.gallery!.isIdentity { return }
    let w = source.width, h = source.height
    let linear = document.depth == .f32
    var input = [Sample](); input.reserveCapacity(w * h)
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let p = linear ? source.linearPixel(x: x, y: y) : source.pixel(x: x, y: y)
        guard p.isFinite, max(abs(p.r), abs(p.g), abs(p.b)) <= 1e12 else {
          throw CraftError.invalid("Filter input exceeds the supported numeric range.")
        }
        let a = Double(p.a)
        input.append(Sample(Double(p.r) * a, Double(p.g) * a, Double(p.b) * a, a))
      }
    }
    var galleryCoverage: [Double]?
    var output: [Sample]
    switch filter.kind {
    case .lensCorrection:
      output = try LensCorrectionEngine.process(input,width:w,height:h,settings:filter.lens!)
    case .blurGallery:
      let gallery = try BlurGalleryEngine.process(input,width:w,height:h,settings:filter.gallery!)
      output = gallery.pixels; galleryCoverage = gallery.coverage
    case .liquify:
      let field = try filter.liquify!.field(targetWidth: w, targetHeight: h)
      // An unchanged mesh must retain hidden RGB and every original sample bit.
      if field.isIdentity { return }
      output = try field.resample(input, width: w, height: h, preview: false)
    case .gaussianBlur, .highPass, .unsharpMask:
      output = try gaussian(input, w, h, filter.radius)
    case .boxBlur:
      output = try box(input, w, h, Int(filter.radius), horizontal: true)
      output = try box(output, w, h, Int(filter.radius), horizontal: false)
    case .motionBlur:
      output = try motion(input, w, h, filter)
    case .average:
      let matrix = document.layers[index].coordinateTransform
      var sum = Sample.zero, total = 0.0
      for y in 0..<h {
        try Task.checkCancellation()
        for x in 0..<w {
          let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
          let coverage = Double(document.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
          sum += input[y * w + x] * coverage; total += coverage
        }
      }
      output = total > 0 ? [Sample](repeating: sum / total, count: w * h) : input
    case .mosaic:
      output = input
      let cell = Int(filter.cellSize)
      for y0 in stride(from: 0, to: h, by: cell) {
        try Task.checkCancellation()
        for x0 in stride(from: 0, to: w, by: cell) {
          let x1 = min(w, x0 + cell), y1 = min(h, y0 + cell)
          var sum = Sample.zero
          for y in y0..<y1 { for x in x0..<x1 { sum += input[y * w + x] } }
          let average = sum / Double((x1 - x0) * (y1 - y0))
          for y in y0..<y1 { for x in x0..<x1 { output[y * w + x] = average } }
        }
      }
    case .lightingEffects, .relight, .shadowsHighlights, .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore, .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors, .clouds, .differenceClouds, .fibers, .lensFlare, .diffuse, .emboss, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind, .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize, .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag, .addNoise, .cameraRaw, .puppetWarp, .perspectiveWarp, .adaptiveWideAngle, .filterGallery, .smartSharpen, .reduceNoise, .lensBlur: output = input
    }
    let layer = document.layers[index]
    let matrix = layer.coordinateTransform
    let protectAlpha = document.isTransparencyLocked(layerID)
    var result = source
    var random = NoiseRandom(state: UInt64(filter.seed))
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        if galleryCoverage?[y*w+x] == 0 { continue }
        let before = linear ? source.linearPixel(x: x, y: y) : source.pixel(x: x, y: y)
        let sample = output[y * w + x]
        var edited = sample.w > 1e-15
          ? Pixel(Float(sample.x / sample.w), Float(sample.y / sample.w), Float(sample.z / sample.w), Float(sample.w))
          : Pixel.clear
        switch filter.kind {
        case .unsharpMask, .highPass:
          let difference = before.rgb - edited.rgb
          let threshold = Float(filter.threshold / 255)
          var rgb = before.rgb
          for channel in 0..<3 {
            if filter.kind == .highPass { rgb[channel] = 0.5 + difference[channel] }
            else if abs(difference[channel]) >= threshold {
              rgb[channel] += Float(filter.amount / 100) * difference[channel]
            }
          }
          edited = Pixel(rgb.x, rgb.y, rgb.z, before.a)
        case .addNoise:
          let amount = filter.amount / 100
          let first = random.noise(filter.distribution) * amount
          let g = filter.monochromatic ? first : random.noise(filter.distribution) * amount
          let b = filter.monochromatic ? first : random.noise(filter.distribution) * amount
          edited = Pixel(before.r + Float(first), before.g + Float(g), before.b + Float(b), before.a)
        default: break
        }
        if protectAlpha {
          if before.a == 0 { continue }
          edited.a = before.a
        }
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        let coverage = document.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
        if coverage <= 0 { continue }
        // Interpolate premultiplied colors at fractional selection boundaries.
        let mixed = before.mixing(edited, coverage: coverage)
        guard mixed.isFinite else { throw CraftError.invalid("Nonfinite filter result.") }
        if linear { result.setLinearPixel(x: x, y: y, mixed) }
        else { result.setPixel(x: x, y: y, mixed) }
      }
    }
    document.layers[index].content = .raster(result)
  }


  static func applyCameraRaw(_ settings: CameraRawSettings, source: Surface, layerID: UUID, index: Int, document: inout CraftDocument) throws {
    if settings.isIdentity { return }
    let edited = try CameraRawEngine.develop(source,settings:settings)
    let matrix = document.layers[index].coordinateTransform, protectAlpha = document.isTransparencyLocked(layerID)
    let linear = document.depth == .f32
    var result = source
    for y in 0..<source.height { try Task.checkCancellation(); for x in 0..<source.width {
      let q = matrix.point(Double(x)+0.5,Double(y)+0.5)
      let coverage = document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage <= 0 { continue }
      let before = linear ? source.linearPixel(x:x,y:y) : source.pixel(x:x,y:y)
      if protectAlpha && before.a == 0 { continue }
      let after = linear ? edited.linearPixel(x:x,y:y) : edited.pixel(x:x,y:y)
      let value = coverage >= 1 ? after : before.mixing(after,coverage:coverage)
      if linear { result.setLinearPixel(x:x,y:y,value) } else { result.setPixel(x:x,y:y,value) }
    } }
    document.layers[index].content = .raster(result)
  }

  static func gaussian(_ source: [Sample], _ w: Int, _ h: Int, _ sigma: Double) throws -> [Sample] {
    let ideal = sqrt(4 * sigma * sigma + 1)
    var lower = Int(floor(ideal)); if lower % 2 == 0 { lower -= 1 }
    lower = max(1, lower)
    let upper = lower + 2
    let count = Int(((12 * sigma * sigma - Double(3 * lower * lower + 12 * lower + 9)) / Double(-4 * lower - 4)).rounded())
    var result = source
    for pass in 0..<3 {
      let radius = ((pass < count ? lower : upper) - 1) / 2
      result = try box(result, w, h, radius, horizontal: true)
      result = try box(result, w, h, radius, horizontal: false)
    }
    return result
  }

  /// Running window keeps large blur radii linear in image size. Clamp at layer edges.
  static func box(_ source: [Sample], _ w: Int, _ h: Int, _ radius: Int, horizontal: Bool) throws -> [Sample] {
    if radius == 0 { return source }
    var result = source
    let length = horizontal ? w : h, lines = horizontal ? h : w
    let scale = 1 / Double(radius * 2 + 1)
    for line in 0..<lines {
      try Task.checkCancellation()
      func at(_ position: Int) -> Int {
        let p = min(length - 1, max(0, position))
        return horizontal ? line * w + p : p * w + line
      }
      var sum = Sample.zero
      for k in -radius...radius { sum += source[at(k)] }
      for p in 0..<length {
        result[at(p)] = sum * scale
        sum += source[at(p + radius + 1)] - source[at(p - radius)]
      }
    }
    return result
  }

  static func motion(_ source: [Sample], _ w: Int, _ h: Int, _ filter: RasterFilter) throws -> [Sample] {
    if filter.distance == 1 { return source }
    var result = source
    let radians = filter.angle * .pi / 180
    let dx = cos(radians), dy = -sin(radians)
    let samples = min(257, Int(filter.distance) + 1)
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        var sum = Sample.zero
        for i in 0..<samples {
          let offset = (Double(i) / Double(samples - 1) - 0.5) * (filter.distance - 1)
          let px = min(Double(w - 1), max(0, Double(x) + offset * dx))
          let py = min(Double(h - 1), max(0, Double(y) + offset * dy))
          let x0 = Int(px), y0 = Int(py), x1 = min(w - 1, x0 + 1), y1 = min(h - 1, y0 + 1)
          let fx = px - Double(x0), fy = py - Double(y0)
          let top = source[y0 * w + x0] * (1 - fx) + source[y0 * w + x1] * fx
          let bottom = source[y1 * w + x0] * (1 - fx) + source[y1 * w + x1] * fx
          sum += top * (1 - fy) + bottom * fy
        }
        result[y * w + x] = sum / Double(samples)
      }
    }
    return result
  }

  struct NoiseRandom {
    var state: UInt64
    mutating func unitValue() -> Double {
      state = state &+ 0x9E3779B97F4A7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
      z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
      z ^= z >> 31
      return (Double(z >> 11) + 0.5) / 9_007_199_254_740_992
    }
    mutating func noise(_ distribution: RasterFilter.Distribution) -> Double {
      if distribution == .uniform { return unitValue() * 2 - 1 }
      let u = unitValue(), v = unitValue()
      return sqrt(-2 * log(u)) * cos(2 * .pi * v) / 3
    }
  }
}
