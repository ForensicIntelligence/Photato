import Foundation
import PhotoCraftCore

/// Decodes classic TIFF numeric strips and tiles into bounded component rows.
enum TIFFComponentRows {
  static func read(_ file: TIFFContainer, geometry g: TIFFStorage.Geometry,
    mode: DocumentColorMode, photometric: Int, depth: PixelDepth, profile: Data,
    backing: RasterTileStore) throws -> (raster: NativeModeRaster, savedAlpha: [Surface]) {
    let builder = try NativeModeRaster.RowBuilder(width: g.width, height: g.height,
      mode: mode, depth: depth, profile: profile, backing: backing)
    let colorCount = mode.componentCount
    let bytesPerSample = g.bits / 8
    let integerMaximum: UInt32 = g.bits == 8 ? 255 : 65535
    let rowComponents = g.planar ? 1 : g.channels
    if g.opacitySample == nil {
      try builder.fill(component: colorCount, word: depth == .f32 ? Float(1).bitPattern : integerMaximum)
    }
    let saved = try g.savedAlphaSamples.map { _ in
      let builder = try NativeModeRaster.RowBuilder(width: g.width, height: g.height,
        mode: .grayscale, depth: depth, backing: backing)
      try builder.fill(component: 1, word: 255)
      return builder
    }
    let savedBySample = Dictionary(uniqueKeysWithValues: zip(g.savedAlphaSamples, saved))
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
    var words = [UInt32](repeating: 0, count: g.width)
    try packedRows(file, g, components: rowComponents) { plane, samples in
      for channel in 0..<rowComponents {
        let sample = g.planar ? plane : channel
        let savedPlane = savedBySample[sample]
        let component = sample < colorCount ? sample : colorCount
        for x in 0..<g.width {
          let start = (x * rowComponents + channel) * bytesPerSample
          var word: UInt32 = 0
          for b in 0..<bytesPerSample {
            let offset = file.order == .big ? b : bytesPerSample - 1 - b
            word = word << 8 | UInt32(samples[start + offset])
          }
          words[x] = savedPlane != nil ? word : try nativeWord(word, component: component)
        }
        if let savedPlane { try savedPlane.appendRow(words, component: 0) }
        else { try builder.appendRow(words, component: component) }
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
    return (raster, try saved.map { try $0.finish().channel(0) })
  }

  private static func packedRows(_ file: TIFFContainer, _ g: TIFFStorage.Geometry, components: Int,
    consume: (_ plane: Int, _ samples: [UInt8]) throws -> Void) throws {
    let bands = (g.height - 1) / g.rows + 1
    let planeCount = g.planar ? g.channels : 1
    let bytesPerPixel = g.bits / 8 * components
    if let tileWidth = g.tileWidth {
      let across = (g.width - 1) / tileWidth + 1
      let staged = try PSDPlaneScratch(width: g.width, height: min(g.rows, g.height),
        depth: g.bits, components: components, interleaved: true)
      for plane in 0..<planeCount {
        for band in 0..<bands {
          let rows = min(g.rows, g.height - band * g.rows)
          for column in 0..<across {
            let x = column * tileWidth
            let validBytes = min(tileWidth, g.width - x) * bytesPerPixel
            let index = (plane * bands + band) * across + column
            try readBlock(file, g, index: index, rows: g.rows, width: tileWidth, components: components) { row, samples in
              if row < rows {
                try staged.writeSegment(samples.prefix(validBytes), row: row, component: 0, byteOffset: x * bytesPerPixel)
              }
            }
          }
          for row in 0..<rows {
            try Task.checkCancellation()
            try consume(plane, staged.rawRow(row, plane: 0))
          }
        }
      }
    } else {
      for plane in 0..<planeCount {
        for band in 0..<bands {
          let rows = min(g.rows, g.height - band * g.rows)
          try readBlock(file, g, index: plane * bands + band, rows: rows, width: g.width,
            components: components) { _, samples in try consume(plane, samples) }
        }
      }
    }
  }

  private static func readBlock(_ file: TIFFContainer, _ g: TIFFStorage.Geometry, index: Int,
    rows: Int, width: Int, components: Int, consume: (_ row: Int, _ samples: [UInt8]) throws -> Void) throws {
    let rowBytes = width * components * (g.bits / 8)
    var source = try file.reader(at: g.offsets[index], count: g.counts[index])
    let nextRow: () throws -> [UInt8]
    let finish: () throws -> Void
    switch g.compression {
    case 1:
      guard source.remaining == rows * rowBytes else { throw CraftError.invalid("Truncated TIFF sample block.") }
      nextRow = { Array(try source.bytes(rowBytes)) }
      finish = {}
    case 5:
      let reader = try TIFFLZW.RowReader(source, expected: rows * rowBytes)
      nextRow = { try reader.read(rowBytes) }
      finish = { try reader.finish() }
    default:
      let reader = try PSDZIPReader(source, expected: rows * rowBytes, largeStream: true)
      nextRow = {
        if rowBytes <= Surface.maxDimension * 4 { return try reader.read(rowBytes) }
        var data: [UInt8] = []
        data.reserveCapacity(rowBytes)
        while data.count < rowBytes {
          data.append(contentsOf: try reader.read(min(Surface.maxDimension * 4, rowBytes - data.count)))
        }
        return data
      }
      finish = { try reader.finish() }
    }
    for row in 0..<rows {
      try Task.checkCancellation()
      let input = try nextRow()
      let samples = g.predictor == 1 ? input : TIFFStorage.restore(input, bits: g.bits,
        components: components, order: file.order, predictor: g.predictor)
      try consume(row, samples)
    }
    try finish()
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
