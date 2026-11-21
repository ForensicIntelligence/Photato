import Foundation
import PhotoCraftCore

/// Full-resolution samples from the protected canvas perimeter.
/// Store just the four edges so later variations can use the same join.
struct GenerativeExpandBoundary: Codable, Sendable {
  let bounds: IntRect
  let samples: Data

  init(protected: IntRect, region: IntRect, composite: Surface) throws {
    let x = max(protected.x, region.x), y = max(protected.y, region.y)
    let right = min(protected.x + protected.width, region.x + region.width)
    let bottom = min(protected.y + protected.height, region.y + region.height)
    guard x < right, y < bottom else {
      throw CraftError.invalid("Include original canvas pixels beside the area to expand.")
    }
    bounds = IntRect(x: x, y: y, width: right - x, height: bottom - y)
    func sample(_ x: Int, _ y: Int) -> SIMD4<Float> {
      let xx = x - region.x, yy = y - region.y
      let p = composite.colorEncoding == .linearRGB ? composite.linearPixel(x: xx, y: yy) : composite.pixel(x: xx, y: yy)
      return SIMD4(p.r, p.g, p.b, p.a)
    }
    var edges = [SIMD4<Float>]()
    edges.reserveCapacity(2 * (bounds.width + bounds.height))
    for row in [y, bottom - 1] {
      for column in x..<right { edges.append(sample(column, row)) }
    }
    for column in [x, right - 1] {
      for row in y..<bottom { edges.append(sample(column, row)) }
    }
    samples = edges.withUnsafeBytes { Data($0) }
  }

  func validate(in region: IntRect) throws {
    guard bounds.width > 0, bounds.height > 0, bounds.width <= region.width,
      bounds.height <= region.height, bounds.x >= region.x, bounds.y >= region.y,
      bounds.x <= region.x + region.width - bounds.width,
      bounds.y <= region.y + region.height - bounds.height,
      samples.count == 2 * (bounds.width + bounds.height) * MemoryLayout<SIMD4<Float>>.stride
    else { throw CraftError.invalid("Invalid saved Generative Expand boundary.") }
  }

  func join(_ patch: inout Surface, selection: IntRect, selectedPixels: Data) throws {
    let width = bounds.width, height = bounds.height
    let right = bounds.x + width - 1, bottom = bounds.y + height - 1
    let radius = max(6, min(32, min(width, height) / 12))
    var edges = [SIMD4<Float>](repeating: .zero, count: 2 * (width + height))
    _ = edges.withUnsafeMutableBytes { samples.copyBytes(to: $0) }
    guard edges.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && (0...1).contains($0.w) })
    else { throw CraftError.invalid("Invalid saved Generative Expand samples.") }
    for row in 0..<patch.height {
      try Task.checkCancellation()
      let y = selection.y + row, edgeY = min(max(y, bounds.y), bottom)
      for column in 0..<patch.width {
        let x = selection.x + column, edgeX = min(max(x, bounds.x), right)
        let distance = max(abs(x - edgeX), abs(y - edgeY))
        guard distance > 0, distance < radius else { continue }
        let bit = row * patch.width + column
        guard selectedPixels[bit / 8] & (1 << (bit % 8)) != 0 else { continue }
        let edge: SIMD4<Float>
        if y < bounds.y {
          edge = edges[edgeX - bounds.x]
        } else if y > bottom {
          edge = edges[width + edgeX - bounds.x]
        } else {
          edge = edges[2 * width + (x > right ? height : 0) + edgeY - bounds.y]
        }
        // Transparent source edges carry no reliable color.
        guard edge.w == 1 else { continue }
        let p = patch.colorEncoding == .linearRGB ? patch.linearPixel(x: column, y: row) : patch.pixel(x: column, y: row)
        guard p.a == 1 else { continue }
        let t = Float(distance - 1) / Float(radius - 1)
        let weight = 1 - t * t * (3 - 2 * t)
        let rgb = distance == 1 ? SIMD3(edge.x, edge.y, edge.z)
          : p.rgb + (SIMD3(edge.x, edge.y, edge.z) - p.rgb) * weight
        let output = Pixel(rgb.x, rgb.y, rgb.z)
        if patch.colorEncoding == .linearRGB { patch.setLinearPixel(x: column, y: row, output) }
        else { patch.setPixel(x: column, y: row, output) }
      }
    }
  }
}
