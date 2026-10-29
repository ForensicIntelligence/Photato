import Foundation

public struct HealingStroke: Sendable {
  public var stroke: CloneStroke
  /// Immutable destination context sampled with the same layer policy as the source.
  /// Nil uses the target's own pre-stroke pixels (Current Layer / mask editing).
  public var destination: CloneSample?
  public init(stroke: CloneStroke, destination: CloneSample? = nil) {
    self.stroke = stroke
    self.destination = destination
  }
}

public enum HealingPainter {
  @discardableResult public static func paint(
    _ healing: HealingStroke, on layer: inout Layer,
    canvasWidth: Int, canvasHeight: Int, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil, preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !healing.stroke.mask && (preserveTransparency || layer.protection.locksTransparency)
    let stroke = healing.stroke
    let sourceMapping = try ClonePainter.prepare(stroke)
    if let destination = healing.destination {
      try destination.surface.validated()
      _ = try destination.transform.inverted()
      guard destination.outside.isFinite, (0...1).contains(destination.outside.a) else {
        throw CraftError.invalid("Invalid Healing Brush destination context.")
      }
    }
    let outside = stroke.mask ? layer.effectiveMaskProperties.outside : 0
    let targetOutside = stroke.mask ? Pixel(outside, outside, outside) : .clear
    return try ClonePainter.paintTarget(
      stroke, on: &layer, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, selection: selection, preserveTransparency: preserve
    ) { pixels, transform, clipping in
      let coverage = try ClonePainter.strokeCoverage(stroke, surface: pixels, transform: transform)
      guard let bounds = coverage.bounds else { return false }
      // One known pixel around every unknown pixel supplies the Dirichlet boundary.
      // Include outside-storage samples; do not truncate the solve at a cropped layer edge.
      let region = IntRect(
        x: bounds.x - 1, y: bounds.y - 1,
        width: bounds.width + 2, height: bounds.height + 2)
      guard region.width <= HealingSolver.maxPixels / region.height else {
        throw CraftError.invalid(
          "Healing Brush region exceeds 4 megapixels. Use a smaller brush or shorter strokes.")
      }
      let destination =
        healing.destination
        ?? CloneSample(surface: pixels, transform: transform, outside: targetOutside)
      let destinationMap = try destination.transform.inverted() * transform
      let sourceMap = sourceMapping * transform
      let linear = pixels.depth == .f32 && !stroke.mask
      func sampled(_ sample: CloneSample, _ mapping: Transform2D, _ x: Int, _ y: Int) -> Pixel {
        let at = mapping.point(Double(x) + 0.5, Double(y) + 0.5)
        let nearest =
          mapping.a == 1 && mapping.b == 0 && mapping.c == 0 && mapping.d == 1
          && mapping.tx == mapping.tx.rounded() && mapping.ty == mapping.ty.rounded()
        return ClonePainter.sample(
          sample.surface, x: at.x, y: at.y, nearest: nearest,
          linear: linear, outside: sample.outside, grayscale: stroke.mask)
      }
      let count = region.width * region.height
      var source = [Float](repeating: 0, count: count * 4)
      var context = source
      var mask = [Bool](repeating: false, count: count)
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let i = y * region.width + x
          let sx = x + region.x
          let sy = y + region.y
          let a = sampled(stroke.source, sourceMap, sx, sy)
          let b = sampled(destination, destinationMap, sx, sy)
          source[i * 4] = a.r
          source[i * 4 + 1] = a.g
          source[i * 4 + 2] = a.b
          source[i * 4 + 3] = a.a
          context[i * 4] = b.r
          context[i * 4 + 1] = b.g
          context[i * 4 + 2] = b.b
          context[i * 4 + 3] = b.a
          mask[i] = coverage.value(x: sx, y: sy) > 0
        }
      }
      let solution = try HealingSolver.seamlessClone(
        width: region.width, height: region.height,
        channels: 4, source: source, destination: context, mask: mask)
      var healed = try Surface(width: region.width, height: region.height, depth: .f32)
      func clamp(_ x: Float) -> Float { pixels.depth == .f32 && !stroke.mask ? max(0, x) : unit(x) }
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let i = (y * region.width + x) * 4
          healed.setPixel(
            x: x, y: y,
            Pixel(
              clamp(solution[i]), clamp(solution[i + 1]),
              clamp(solution[i + 2]), unit(solution[i + 3])))
        }
      }
      let healedTransform = transform * .translation(Double(region.x), Double(region.y))
      var resolved = stroke
      resolved.source = CloneSample(surface: healed, transform: healedTransform)
      resolved.mapping = CloneMapping(source: .init(0, 0), anchor: .init(0, 0))
      return try ClonePainter.applyCoverage(
        resolved, on: &pixels, transform: transform,
        sourceMapping: healedTransform.inverted(), selection: clipping,
        selectionMask: selectionMask, coverage: coverage, preserveTransparency: preserve)
    }
  }
}
