import Foundation

/// Normal Patch's pattern donor, using the shared native sampler and healing solver.
/// Photoshop phase, alpha and solver fidelity require independent reference outputs.
public enum PatternPatch {
  public static let maximumRegionPixels = HealingSolver.maxPixels
  public static func prepare(_ request: RegionRetouchRequest, pattern: RasterPattern,
    document: CraftDocument, layerID: UUID) throws -> RegionRetouchEdit {
    try request.validate(); try pattern.validate(); try document.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb, request.kind == .patch, request.patchType == .normal, request.dx == 0, request.dy == 0,
      request.patchMode == .source, !request.sampleAllLayers,
      let index = document.layers.firstIndex(where: { $0.id == layerID }),
      case .raster(let source) = document.layers[index].content,
      document.layers[index].smartObject == nil, document.layers[index].sourceProjection == nil,
      !document.isImageLocked(layerID), let selection = try document.coverageSelection(),
      let bounds = selection.bounds else {
      throw CraftError.invalid("Select an area on an unlocked ordinary raster layer for Normal Pattern Patch.")
    }
    let window = IntRect(x: bounds.x-2, y: bounds.y-2, width: bounds.width+4, height: bounds.height+4)
      .clipped(toWidth: document.width, height: document.height)
    guard window.width > 0, window.height > 0, window.width <= maximumRegionPixels/window.height else {
      throw CraftError.unsupported("Pattern Patch currently supports a selected solve window of at most4megapixels.")
    }
    let layer = document.layers[index], inverse = try layer.coordinateTransform.inverted()
    let sampler = try PatternSampler(pattern), count = window.width*window.height
    var donor = [Float](repeating: 0, count: count*4), destination = donor
    var holes = [Bool](repeating: false, count: count), coverage = [Float](repeating: 0, count: count)
    for y in 0..<window.height {
      try Task.checkCancellation()
      for x in 0..<window.width {
        let px = x+window.x, py = y+window.y, i = y*window.width+x
        let q = inverse.point(Double(px)+0.5, Double(py)+0.5)
        let old = CropGeometry.sample(source, x: q.x, y: q.y)
        let sampled = sampler.sample(x: Double(px)+0.5, y: Double(py)+0.5)
        let ink = document.depth == .f32 ? SRGBTransfer.linear(sampled) : sampled
        let k = Float(selection.byte(at: py*document.width+px))/255
        holes[i] = k > 0
        coverage[i] = request.transparent ? Float((k*255*unit(sampled.a)).rounded())/255 : k
        for (c,v) in [ink.r,ink.g,ink.b,ink.a].enumerated() { donor[i*4+c] = v }
        for (c,v) in [old.r,old.g,old.b,old.a].enumerated() { destination[i*4+c] = v }
      }
    }
    var solution = try HealingSolver.seamlessClone(width: window.width, height: window.height,
      channels: 4, source: donor, destination: destination, mask: holes)
    if request.diffusion != 5 {
      let amount = Float(request.diffusion)/5
      for i in solution.indices { solution[i] = donor[i]+(solution[i]-donor[i])*amount }
    }
    var edited = layer
    let protect = document.isTransparencyLocked(layerID)
    let changed = try ClonePainter.paintTarget(mask: false, bounds: bounds, on: &edited,
      clipping: bounds, preserveTransparency: protect) { target, transform, _ in
      let local = try (transform.inverted() * .translation(Double(window.x), Double(window.y)))
        .bounds(width: window.width, height: window.height)
        .clipped(toWidth: target.width, height: target.height)
      guard local.width == 0 || local.height == 0 || local.width <= maximumRegionPixels/local.height else {
        throw CraftError.unsupported("Pattern Patch transformed output currently exceeds4megapixels.")
      }
      var changed = false
      for y in local.y..<(local.y+local.height) {
        try Task.checkCancellation()
        for x in local.x..<(local.x+local.width) {
          let p = transform.point(Double(x)+0.5, Double(y)+0.5)
          let ix = Int(floor(p.x)), iy = Int(floor(p.y))
          guard window.contains(ix,iy) else { continue }
          let i = (iy-window.y)*window.width+ix-window.x, k = coverage[i]
          guard k > 0 else { continue }
          let old = document.depth == .f32 ? target.linearPixel(x:x,y:y) : target.pixel(x:x,y:y)
          guard !protect || old.a > 0 else { continue }
          let a = unit(solution[i*4+3]), fill = Pixel(solution[i*4],solution[i*4+1],solution[i*4+2],a)
          guard fill.isFinite else { throw CraftError.invalid("Pattern Patch produced non-finite pixels.") }
          let value = k == 1 ? Pixel(fill.r,fill.g,fill.b,protect ? old.a:fill.a)
            : Pixel(old.r+(fill.r-old.r)*k,old.g+(fill.g-old.g)*k,old.b+(fill.b-old.b)*k,
              protect ? old.a:old.a+(fill.a-old.a)*k)
          guard !value.hasSameBits(as:old) else { continue }
          if document.depth == .f32 { target.setLinearPixel(x:x,y:y,value) }
          else { target.setPixel(x:x,y:y,value) }
          changed = true
        }
      }
      return changed
    }
    var result = document
    if changed { result.layers[index] = edited }
    try Task.checkCancellation(); try result.validate()
    return .init(source: document, result: result, label: "Patch (Pattern)")
  }
}
