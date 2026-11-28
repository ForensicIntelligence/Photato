import Foundation
import PhotoCraftCore

enum RawGeometryRenderer {
  static func develop(_ pixels: Surface, geometry: RawGeometrySettings?, crop: RawCropBounds?) throws -> Surface {
    let width = pixels.width, height = pixels.height
    let cropRect = crop?.rectangle(width: width, height: height)
    guard let geometry, !geometry.isIdentity else {
      if let cropRect { return try pixels.cropped(to: cropRect) }
      return pixels
    }
    var placement = try placement(geometry, width: width, height: height)
    let canvas = IntRect(x: 0, y: 0, width: width, height: height)
    var bounds = cropRect ?? canvas
    if geometry.constrainCrop {
      let covered = try constrainedBounds(placement, source: canvas, in: bounds)
      if let cropRect, covered != cropRect {
        // Keep the recorded framing and dimensions while preventing a clear
        // edge if the recorded crop was made against another renderer.
        let fit = Transform2D.translation(Double(cropRect.x), Double(cropRect.y))
          * .scale(Double(cropRect.width) / Double(covered.width), Double(cropRect.height) / Double(covered.height))
          * .translation(-Double(covered.x), -Double(covered.y))
        placement = try placement.followed(by: fit)
      } else {
        bounds = covered
      }
    }
    return try ProjectiveRaster.renderPaged(pixels, placement: placement, bounds: bounds, method: .bicubic)
  }

  /// A centered homography combines keystone correction with the ordinary
  /// post-correction scale, aspect, rotation and translation.
  private static func placement(_ geometry: RawGeometrySettings, width: Int, height: Int) throws -> ProjectiveTransform {
    let w = Double(width), h = Double(height)
    let pitch = Double(geometry.vertical) * 0.009
    let yaw = Double(geometry.horizontal) * 0.009
    let cameraPlane = 0.94
    let keystone = try ProjectiveTransform([1 / cos(yaw), 0, 0, 0, 1 / cos(pitch), 0,
      -cameraPlane * sin(yaw) / w, -cameraPlane * sin(pitch) / h, 1])
    let factor = Double(geometry.scale) / 100
    let aspect = exp(-Double(geometry.aspect) / 1000)
    let affine = Transform2D.translation(w * (0.5 + Double(geometry.offsetX) * 0.00644),
      h * (0.5 - Double(geometry.offsetY) * 0.00680))
      * .rotation(Double(geometry.rotation)) * .scale(factor * aspect, factor / aspect)
    return try keystone.preceded(by: .translation(-w / 2, -h / 2)).followed(by: affine)
  }

  /// A transformed rectangle is convex. The horizontal intervals at a
  /// proposed crop's top and bottom bound its whole interior.
  private static func constrainedBounds(_ transform: ProjectiveTransform, source: IntRect,
    in canvas: IntRect) throws -> IntRect {
    let w = Double(source.width), h = Double(source.height)
    let corners = try [(0.0, 0.0), (w, 0), (w, h), (0, h)].map { try transform.point($0.0, $0.1) }
    let edges = zip(corners, Array(corners.dropFirst()) + [corners[0]])
    let top = Int(ceil(max(Double(canvas.y), corners.map(\.y).min()!)))
    let bottom = Int(floor(min(Double(canvas.y + canvas.height), corners.map(\.y).max()!)))
    guard top < bottom else { throw CraftError.invalid("The Geometry correction leaves no image inside the canvas.") }

    func interval(at y: Int) -> Range<Int>? {
      let row = Double(y)
      let crossings = edges.flatMap { a, b -> [Double] in
        guard min(a.y, b.y) <= row, row <= max(a.y, b.y) else { return [] }
        if a.y == b.y { return [a.x, b.x] }
        return [a.x + (b.x - a.x) * (row - a.y) / (b.y - a.y)]
      }
      guard let lower = crossings.min(), let upper = crossings.max() else { return nil }
      let left = Int(ceil(max(Double(canvas.x), lower)))
      let right = Int(floor(min(Double(canvas.x + canvas.width), upper)))
      return left < right ? left..<right : nil
    }
    let aspect = Double(canvas.width) / Double(canvas.height)
    var best: IntRect?
    var bestArea = 0
    var bestDistance = Double.infinity
    func evaluate(_ tops: [Int], _ bottoms: [Int]) {
      let startIntervals = tops.compactMap { y in interval(at: y).map { (y, $0) } }
      let endIntervals = bottoms.compactMap { y in interval(at: y).map { (y, $0) } }
      for (y, first) in startIntervals {
        for (bottom, last) in endIntervals where bottom > y {
          let height = bottom - y
          let width = max(1, Int((Double(height) * aspect).rounded()))
          let left = max(first.lowerBound, last.lowerBound)
          let right = min(first.upperBound, last.upperBound)
          let area = width * height
          guard width <= right - left, area >= bestArea else { continue }
          let x = min(right - width, max(left, canvas.x + (canvas.width - width) / 2))
          let distance = hypot(Double(2 * (x - canvas.x) + width - canvas.width),
            Double(2 * (y - canvas.y) + height - canvas.height))
          if area == bestArea && distance >= bestDistance { continue }
          best = IntRect(x: x, y: y, width: width, height: height)
          bestArea = area
          bestDistance = distance
        }
      }
    }
    func positions(_ first: Int, _ last: Int) -> [Int] {
      let span = last - first
      let subdivisions = min(128, span)
      guard subdivisions > 0 else { return [first] }
      return (0...subdivisions).map { first + span * $0 / subdivisions }
    }
    let rows = positions(top, bottom)
    evaluate(rows, rows)
    if let coarse = best, bottom - top > 128 {
      let step = (bottom - top + 127) / 128
      let lower = coarse.y + coarse.height
      evaluate(positions(max(top, coarse.y - step), min(bottom, coarse.y + step)),
               positions(max(top, lower - step), min(bottom, lower + step)))
    }
    guard let best else { throw CraftError.invalid("The Geometry correction leaves no image inside the canvas.") }
    return best
  }
}
