import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension GenerativeExpandWindows {
  /// The core can overlap the old canvas, with one further context margin.
  /// Save disjoint strips so intersecting model windows share source samples.
  private var sourceRegions: [IntRect] {
    let reach = 2 * Self.side + Self.overlap
    let box = protected
    let top = box.y > 0 ? min(reach, box.height) : 0
    let bottom = box.y + box.height < frame.height ? min(reach, box.height - top) : 0
    let left = box.x > 0 ? min(reach, box.width) : 0
    let right = box.x + box.width < frame.width ? min(reach, box.width - left) : 0
    let middleY = box.y + top, middleHeight = box.height - top - bottom
    return [
      IntRect(x: box.x, y: box.y, width: box.width, height: top),
      IntRect(x: box.x, y: middleY, width: left, height: middleHeight),
      IntRect(x: box.x + box.width - right, y: middleY, width: right, height: middleHeight),
      IntRect(x: box.x, y: box.y + box.height - bottom, width: box.width, height: bottom),
    ].filter { $0.width > 0 && $0.height > 0 }
  }

  func captureSource(_ original: CraftDocument) throws -> [Layer] {
    let tile = Surface.tileSide
    return try sourceRegions.enumerated().map { index, box in
      let builder = try Surface.PagedBuilder(width: box.width, height: box.height,
        depth: original.depth, colorEncoding: encoding)
      for y in stride(from: 0, to: box.height, by: tile) {
        for x in stride(from: 0, to: box.width, by: 16 * tile) {
          try Task.checkCancellation()
          let patch = IntRect(x: box.x + x - protected.x, y: box.y + y - protected.y,
            width: min(16 * tile, box.width - x), height: min(tile, box.height - y))
          let pixels = try Renderer.composite(original, region: patch).cropped(to: patch)
          // The inference proxy stores samples at the document depth. Save
          // the same values before serializing the original model context.
          try builder.append(pixels.quantizedStoredDepth(original.depth), atX: x, atY: y)
        }
      }
      var layer = Layer(name: Self.sourceName(index), content: .raster(try builder.finish()))
      layer.visible = false
      layer.x = box.x - border.x
      layer.y = box.y - border.y
      return layer
    }
  }

  func sourceSampler(_ layers: ArraySlice<Layer>) throws -> (IntRect) throws -> (Int, Int) -> Pixel {
    let regions = sourceRegions
    guard layers.count == regions.count else { throw Self.invalidContext }
    let pieces = try zip(regions, layers).enumerated().map { index, pair -> (IntRect, Surface) in
      let (box, layer) = pair
      guard layer.name == Self.sourceName(index), !layer.visible, layer.mask == nil,
        layer.x == box.x - border.x, layer.y == box.y - border.y,
        case .raster(let pixels) = layer.content, pixels.width == box.width, pixels.height == box.height,
        pixels.colorEncoding == encoding else { throw Self.invalidContext }
      return (box, pixels)
    }
    return { region in
      let intersecting = pieces.filter { intersects($0.0, region) }
      let coverage = intersecting.reduce(0) { area, piece in
        let box = piece.0
        let width = min(box.x + box.width, region.x + region.width) - max(box.x, region.x)
        let height = min(box.y + box.height, region.y + region.height) - max(box.y, region.y)
        return area + width * height
      }
      guard coverage == region.width * region.height else { throw Self.invalidContext }
      return { x, y in
        for (box, pixels) in intersecting where box.contains(x, y) {
          return encoding == .linearRGB ? pixels.linearPixel(x: x - box.x, y: y - box.y) : pixels.pixel(x: x - box.x, y: y - box.y)
        }
        return .clear
      }
    }
  }

  private func intersects(_ a: IntRect, _ b: IntRect) -> Bool {
    a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
  }

  private static func sourceName(_ index: Int) -> String { "Expansion Context \(index + 1)" }
  private static let invalidContext = CraftError.invalid("The original Generative Expand context is incomplete.")
}
