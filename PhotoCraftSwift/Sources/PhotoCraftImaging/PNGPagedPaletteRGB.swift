import Foundation
import PhotoCraftCore

/// Large palette PNGs with complex alpha open as RGB. Keep the unfiltered
/// packed scanlines in scratch storage and expand only one destination patch
/// at a time, including when Adam7 scatters samples across the document.
enum PNGPagedPaletteRGB {
  private struct Pass {
    let x: Int
    let y: Int
    let dx: Int
    let dy: Int
    let stride: Int
    let rows: Int
    let offset: Int
  }

  static func read(_ compressed: Data, width: Int, height: Int, bits: Int, interlaced: Bool,
    palette: [Pixel]) throws -> Surface {
    var passes: [Pass] = []
    var packedSize = 0, filteredSize = 0
    for (x, y, dx, dy) in PNGRestrictedStorage.passes(interlaced) where width > x && height > y {
      let w = (width - x + dx - 1) / dx, h = (height - y + dy - 1) / dy
      let stride = (w * bits + 7) / 8
      passes.append(Pass(x: x, y: y, dx: dx, dy: dy, stride: stride, rows: h, offset: packedSize))
      packedSize += stride * h
      filteredSize += (stride + 1) * h
    }
    let inflater = try PSDZIPReader(PSDReader(data: compressed), expected: filteredSize, largeStream: true)
    var passIndex = 0, yInPass = 0
    var previous: [UInt8] = [], pending: [UInt8] = []
    var consumed = 0
    let scanlines = try FileBackedSource.retain(byteCount: packedSize) { _, length in
      var block = Data()
      block.reserveCapacity(length)
      while block.count < length {
        if consumed == pending.count {
          let pass = passes[passIndex]
          if yInPass == 0 { previous = [UInt8](repeating: 0, count: pass.stride) }
          let filtered = try inflater.read(pass.stride + 1)
          pending = Array(filtered.dropFirst())
          try PNGRestrictedStorage.restoreScanline(&pending, filter: filtered[0], previous: previous)
          previous = pending
          consumed = 0
          yInPass += 1
          if yInPass == pass.rows {
            passIndex += 1
            yInPass = 0
          }
        }
        let take = min(length - block.count, pending.count - consumed)
        block.append(contentsOf: pending[consumed..<consumed + take])
        consumed += take
      }
      return block
    }
    try inflater.finish()

    // The Adam7 assignment repeats on an 8 × 8 grid. For each coordinate we
    // need just one pass and one packed sample address, irrespective of zoom.
    let passForPhase = (0..<64).map { phase in
      let x = phase % 8, y = phase / 8
      return passes.firstIndex { x % $0.dx == $0.x && y % $0.dy == $0.y }
    }
    let mask = UInt8((1 << bits) - 1)
    return try scanlines.data.withUnsafeBytes { raw in
      func color(x: Int, y: Int) throws -> Pixel {
        guard let i = passForPhase[(y & 7) * 8 + (x & 7)] else {
          throw CraftError.invalid("A pixel is missing from the PNG interlace passes.")
        }
        let pass = passes[i]
        let packedX = (x - pass.x) / pass.dx * bits
        let row = pass.offset + (y - pass.y) / pass.dy * pass.stride
        let index = Int((raw[row + packedX / 8] >> (8 - bits - packedX % 8)) & mask)
        guard palette.indices.contains(index) else { throw CraftError.invalid("A pixel refers to a missing palette entry.") }
        return palette[index]
      }
      let fill = try color(x: 0, y: 0)
      return try RasterIO.pagedRaster(width: width, height: height, depth: .u8, colorEncoding: .sRGB,
        fill: fill) { region in
        var patch = try Surface(width: region.width, height: region.height, fill: fill)
        for y in 0..<region.height {
          try Task.checkCancellation()
          for x in 0..<region.width {
            let sample = try color(x: region.x + x, y: region.y + y)
            if sample != fill { patch.setPixel(x: x, y: y, sample) }
          }
        }
        return patch
      }
    }
  }
}
