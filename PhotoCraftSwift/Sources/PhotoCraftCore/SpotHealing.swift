import Foundation

public enum SpotHealingType: String, CaseIterable, Sendable {
  case contentAware = "Content-Aware"
  case createTexture = "Create Texture"
  case proximityMatch = "Proximity Match"
}
public struct SpotHealingStroke: Sendable {
  public var sample: CloneSample
  public var brush: CloneBrush
  public var points: [StrokePoint]
  public var kind: SpotHealingType
  public var mask: Bool
  public init(
    sample: CloneSample, brush: CloneBrush, points: [StrokePoint],
    kind: SpotHealingType = .contentAware, mask: Bool = false
  ) {
    self.sample = sample
    self.brush = brush
    self.points = points
    self.kind = kind
    self.mask = mask
  }
}
public enum SpotHealingPainter {
  @discardableResult public static func paint(
    _ spot: SpotHealingStroke, on layer: inout Layer, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil
  ) throws -> Bool {
    var stroke = CloneStroke(
      source: spot.sample, mapping: .init(source: .init(0, 0), anchor: .init(0, 0)),
      brush: spot.brush, points: spot.points, mask: spot.mask)
    let mapping = try ClonePainter.prepare(stroke)
    let targetDepth: PixelDepth
    if spot.mask {
      guard let pixels = layer.mask else {
        throw CraftError.invalid("This layer has no pixel mask.")
      }
      targetDepth = pixels.depth
    } else {
      guard case .raster(let pixels) = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before retouching.")
      }
      targetDepth = pixels.depth
    }
    let canvas = try Surface(width: canvasWidth, height: canvasHeight)
    guard stroke.brush.opacity > 0 && stroke.brush.flow > 0 else { return false }
    // Synthesis runs in document coordinates, independent of the target's storage frame.
    let coverage = try ClonePainter.strokeCoverage(stroke, surface: canvas, transform: .identity)
    guard let bounds = coverage.bounds else { return false }
    let margin = Int(ceil(max(spot.brush.size, 8))) + 8
    let region = IntRect(
      x: bounds.x - margin, y: bounds.y - margin, width: bounds.width + 2 * margin,
      height: bounds.height + 2 * margin
    )
    .clipped(toWidth: canvasWidth, height: canvasHeight)
    guard region.width > 0, region.height > 0, region.width <= Inpainting.maxPixels / region.height
    else {
      throw CraftError.invalid(
        "Spot Healing search region exceeds 4 megapixels. Use a smaller brush or shorter strokes.")
    }
    let w = region.width
    let h = region.height
    let count = w * h
    var image = [Float](repeating: 0, count: count * 4)
    var hole = [Bool](repeating: false, count: count)
    let nearest =
      mapping.a == 1 && mapping.b == 0 && mapping.c == 0 && mapping.d == 1
      && mapping.tx == mapping.tx.rounded() && mapping.ty == mapping.ty.rounded()
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let dx = region.x + x
        let dy = region.y + y
        let i = y * w + x
        let at = mapping.point(Double(dx) + 0.5, Double(dy) + 0.5)
        let p = ClonePainter.sample(
          spot.sample.surface, x: at.x, y: at.y, nearest: nearest,
          linear: targetDepth == .f32 && !spot.mask, outside: spot.sample.outside,
          grayscale: spot.mask)
        image[i * 4] = p.r
        image[i * 4 + 1] = p.g
        image[i * 4 + 2] = p.b
        image[i * 4 + 3] = p.a
        hole[i] = coverage.value(x: dx, y: dy) > 0
      }
    }
    // Every completion/blend path preserves zero alpha if the entire context is empty.
    if !spot.mask && stride(from: 3, to: image.count, by: 4).allSatisfy({ image[$0] == 0 }) {
      return false
    }
    let domain = try Inpainting.dilate(w, h, hole, radius: 2)
    let healMask = try Inpainting.dilate(w, h, hole, radius: 1)
    let grid = Inpainting.Grid(w: w, h: h, ch: 4, image: image, hole: domain)
    try Inpainting.validate(grid)
    // Preserve empty targets/no-source cases instead of inventing colour or alpha.
    guard domain.contains(false) else {
      throw CraftError.invalid("There are no surrounding pixels to sample. Use a smaller brush.")
    }
    func contentAware() throws -> [Float] {
      try Inpainting.completion(grid) ?? Inpainting.membrane(grid)
    }
    let filled: [Float]
    switch spot.kind {
    case .contentAware: filled = try contentAware()
    case .createTexture:
      filled = try Inpainting.texture(
        grid, block: Int(min(32, max(6, spot.brush.size / 4))), seed: 0x5eed)
    case .proximityMatch:
      let ring = Int(min(16, max(3, spot.brush.size / 8)))
      if let offset = try Inpainting.offset(grid, ring: ring, maxRadius: margin) {
        var output = image
        for y in 0..<h {
          try Task.checkCancellation()
          for x in 0..<w where domain[y * w + x] {
            let i = (y * w + x) * 4
            let j = ((y + offset.y) * w + x + offset.x) * 4
            for c in 0..<4 { output[i + c] = image[j + c] }
          }
        }
        filled = output
      } else {
        filled = try contentAware()
      }
    }
    // Match PhotoCraft's tight Poisson solve (the marked area plus two known rings).
    guard let healingBounds = Inpainting.bbox(w, h, healMask) else { return false }
    let solve = IntRect(
      x: healingBounds.x - 1, y: healingBounds.y - 1,
      width: healingBounds.width + 2, height: healingBounds.height + 2
    ).clipped(toWidth: w, height: h)
    var src = [Float](repeating: 0, count: solve.width * solve.height * 4)
    var dst = src
    var mask = [Bool](repeating: false, count: solve.width * solve.height)
    for y in 0..<solve.height {
      try Task.checkCancellation()
      for x in 0..<solve.width {
        let i = y * solve.width + x
        let j = (y + solve.y) * w + x + solve.x
        for c in 0..<4 {
          src[i * 4 + c] = filled[j * 4 + c]
          dst[i * 4 + c] = image[j * 4 + c]
        }
        mask[i] = healMask[j]
      }
    }
    let result = try HealingSolver.seamlessClone(
      width: solve.width, height: solve.height, channels: 4, source: src, destination: dst,
      mask: mask)
    var repaired = try Surface(width: solve.width, height: solve.height, depth: .f32)
    func clamp(_ x: Float) -> Float { targetDepth == .f32 && !spot.mask ? max(0, x) : unit(x) }
    for y in 0..<solve.height {
      try Task.checkCancellation()
      for x in 0..<solve.width {
        let i = (y * solve.width + x) * 4
        repaired.setPixel(
          x: x, y: y,
          Pixel(clamp(result[i]), clamp(result[i + 1]), clamp(result[i + 2]), unit(result[i + 3])))
      }
    }
    stroke.source = .init(
      surface: repaired,
      transform: .translation(Double(region.x + solve.x), Double(region.y + solve.y)))
    let sourceMapping = try stroke.source.transform.inverted()
    return try ClonePainter.paintTarget(
      stroke, on: &layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight, selection: selection
    ) { pixels, transform, clipping in
      try ClonePainter.paintPrepared(
        stroke, on: &pixels, transform: transform, sourceMapping: sourceMapping,
        selection: clipping, selectionMask: selectionMask)
    }
  }
}
