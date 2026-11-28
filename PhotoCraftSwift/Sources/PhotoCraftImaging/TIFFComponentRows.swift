import Foundation
import PhotoCraftCore

/// Decodes classic TIFF numeric strips with one working row per physical plane.
enum TIFFComponentRows {
  static func read(_ file: TIFFContainer, geometry g: TIFFStorage.Geometry,
    mode: DocumentColorMode, photometric: Int, depth: PixelDepth, profile: Data,
    backing: RasterTileStore) throws -> NativeModeRaster {
    let builder = try NativeModeRaster.RowBuilder(width: g.width, height: g.height,
      mode: mode, depth: depth, profile: profile, backing: backing)
    let colorCount = mode.componentCount
    let bytesPerSample = g.bits / 8
    let integerMaximum: UInt32 = g.bits == 8 ? 255 : 65535
    let strips = (g.height - 1) / g.rows + 1
    let rowComponents = g.planar ? 1 : g.channels
    let rowBytes = g.width * rowComponents * bytesPerSample
    if g.channels == colorCount {
      try builder.fill(component: colorCount, word: depth == .f32 ? Float(1).bitPattern : integerMaximum)
    }
    func nativeWord(_ word: UInt32, component: Int) throws -> UInt32 {
      if component == colorCount { return word }
      if photometric == 0 {
        return depth == .f32 ? (1 - Float(bitPattern: word)).bitPattern : integerMaximum - word
      }
      if photometric == 8, component > 0 {
        let signed = g.bits == 8 ? Float(Int8(bitPattern: UInt8(word))) : Float(Int16(bitPattern: UInt16(word))) / 256
        let value = (signed + 128) / 255
        guard value <= 1 else { throw CraftError.unsupported("TIFF Lab chroma exceeds its native range.") }
        return UInt32((value * Float(integerMaximum)).rounded())
      }
      if photometric == 9, g.bits == 16 {
        guard word <= 65280 else { throw CraftError.unsupported("TIFF ICCLab sample exceeds its native range.") }
        return UInt32((Float(word) / 65280 * 65535).rounded())
      }
      return word
    }
    for plane in 0..<(g.planar ? g.channels : 1) {
      for strip in 0..<strips {
        let rows = min(g.rows, g.height - strip * g.rows)
        let index = plane * strips + strip
        var input = PSDReader(data: file.data, offset: g.offsets[index])
        var source = try input.view(g.counts[index])
        let nextRow: () throws -> [UInt8]
        let finish: () throws -> Void
        switch g.compression {
        case 1:
          guard source.remaining == rows * rowBytes else { throw CraftError.invalid("Truncated TIFF strip.") }
          nextRow = { Array(try source.bytes(rowBytes)) }
          finish = {}
        case 5:
          let packed = file.data[g.offsets[index]..<g.offsets[index] + g.counts[index]]
          let reader = try TIFFLZW.RowReader(packed, expected: rows * rowBytes)
          nextRow = { try reader.read(rowBytes) }
          finish = { try reader.finish() }
        default:
          let reader = try PSDZIPReader(source, expected: rows * rowBytes, largeStream: true)
          nextRow = {
            if rowBytes <= Surface.maxDimension * 4 { return try reader.read(rowBytes) }
            var row: [UInt8] = []
            row.reserveCapacity(rowBytes)
            while row.count < rowBytes {
              row.append(contentsOf: try reader.read(min(Surface.maxDimension * 4, rowBytes - row.count)))
            }
            return row
          }
          finish = { try reader.finish() }
        }
        var words = [UInt32](repeating: 0, count: g.width)
        for _ in 0..<rows {
          try Task.checkCancellation()
          let input = try nextRow()
          let samples = g.predictor == 1 ? input : TIFFStorage.restore(input, bits: g.bits,
            components: rowComponents, order: file.order, predictor: g.predictor)
          for channel in 0..<rowComponents {
            let component = g.planar ? plane : channel
            for x in 0..<g.width {
              let start = (x * rowComponents + channel) * bytesPerSample
              var word: UInt32 = 0
              for b in 0..<bytesPerSample {
                let offset = file.order == .big ? b : bytesPerSample - 1 - b
                word = word << 8 | UInt32(samples[start + offset])
              }
              words[x] = try nativeWord(word, component: component)
            }
            try builder.appendRow(words, component: component)
          }
        }
        try finish()
      }
    }
    var raster = try builder.finish()
    if g.associated {
      for component in 0..<colorCount {
        let neutral: Float = mode == .lab && component > 0 ? 128 / 255 : 0
        raster = try raster.mappingColorComponent(component, backing: backing) { color, alpha in
          alpha > 0 ? (color - neutral) / alpha + neutral : neutral
        }
      }
    }
    return raster
  }

  static func oriented(_ source: NativeModeRaster, orientation: Int, backing: RasterTileStore) throws -> NativeModeRaster {
    let width = orientation >= 5 ? source.height : source.width
    let height = orientation >= 5 ? source.width : source.height
    let builder = try NativeModeRaster.RowBuilder(width: width, height: height,
      mode: source.mode, depth: source.depth, profile: source.profile, intent: source.intent, backing: backing)
    var words = [UInt32](repeating: 0, count: width)
    for component in 0...source.mode.componentCount {
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          let sx: Int, sy: Int
          switch orientation {
          case 2: (sx, sy) = (source.width - 1 - x, y)
          case 3: (sx, sy) = (source.width - 1 - x, source.height - 1 - y)
          case 4: (sx, sy) = (x, source.height - 1 - y)
          case 5: (sx, sy) = (y, x)
          case 6: (sx, sy) = (y, source.height - 1 - x)
          case 7: (sx, sy) = (source.width - 1 - y, source.height - 1 - x)
          default: (sx, sy) = (source.width - 1 - y, x)
          }
          words[x] = source.rawWord(component: component, index: sy * source.width + sx)
        }
        try builder.appendRow(words, component: component)
      }
    }
    return try builder.finish()
  }
}
