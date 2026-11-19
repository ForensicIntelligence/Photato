import Foundation

/// Render a paged preview from numerical plates. A full sparse canvas starts at
/// the composite of the implicit words and visits only touched output tiles.
enum InkProjection {
  static func surface(width: Int, height: Int, depth: PixelDepth, region: IntRect?, implicit: Pixel,
    storedRanges: [AnySequence<Range<Int>>], sample: (Int) -> Pixel) throws -> Surface {
    let bounds = IntRect(x: 0, y: 0, width: width, height: height)
    let requested = (region ?? bounds).clipped(toWidth: width, height: height)
    let side = Surface.tileSide
    let columns = (width + side - 1) / side
    let fill = requested == bounds ? implicit : .clear
    let backing = try Surface.PagedBuilder(width: width, height: height, depth: depth,
      fill: fill, colorEncoding: .sRGB)
    guard requested.width > 0, requested.height > 0 else { return try backing.finish() }

    func append(column: Int, row: Int) throws {
      try Task.checkCancellation()
      let originX = column * side, originY = row * side
      let w = min(side, width - originX), h = min(side, height - originY)
      let x = max(requested.x, originX), y = max(requested.y, originY)
      let right = min(requested.x + requested.width, originX + w)
      let bottom = min(requested.y + requested.height, originY + h)
      // Keep the backing tile aligned even when the viewport starts inside it.
      // The unrequested pixels in that tile retain the transparent fill.
      var patch = try Surface(width: w, height: h, depth: depth, fill: fill, colorEncoding: .sRGB)
      for pixelY in y..<bottom {
        let offset = pixelY * width
        for pixelX in x..<right {
          let pixel = sample(offset + pixelX)
          if pixel != fill { patch.setPixel(x: pixelX - originX, y: pixelY - originY, pixel) }
        }
      }
      if patch.storedTileKeys.makeIterator().next() != nil { try backing.append(patch, atX: originX, atY: originY) }
    }

    if requested == bounds, let keys = try tileKeys(for: storedRanges, width: width, columns: columns) {
      for key in keys { try append(column: key % columns, row: key / columns) }
    } else {
      for row in (requested.y / side)...((requested.y + requested.height - 1) / side) {
        for column in (requested.x / side)...((requested.x + requested.width - 1) / side) {
          try append(column: column, row: row)
        }
      }
    }
    return try backing.finish()
  }

  private static func tileKeys(for streams: [AnySequence<Range<Int>>], width: Int,
    columns: Int) throws -> [Int]? {
    let side = Surface.tileSide
    var keys = Set<Int>()
    for stream in streams {
      for range in stream {
        try Task.checkCancellation()
        var position = range.lowerBound
        while position < range.upperBound {
          let y = position / width, x = position % width
          let end = min(range.upperBound, (y + 1) * width)
          for column in (x / side)...(((end - 1) % width) / side) {
            keys.insert(y / side * columns + column)
          }
          if keys.count > 65_536 { return nil }
          position = end
        }
      }
    }
    return keys.sorted()
  }
}
