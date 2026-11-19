import Darwin
import Foundation
import PhotoCraftCore

/// Keep original numerical separations independently of their RGB display cache.
/// Public PSD words are big endian; integer CMYK ink inversion is exact.
enum PSDModePaging {
  private static func words(_ row:[UInt8],width:Int,depth:PixelDepth,mode:DocumentColorMode,component:Int) throws -> [UInt32] {
    let stride=depth == .u8 ? 1:depth == .u16 ? 2:4
    guard row.count == width*stride else {throw CraftError.invalid("Incomplete Photoshop component row.")}
    var result=[UInt32](repeating:0,count:width)
    for x in 0..<width {
      if x%4096 == 0 {try Task.checkCancellation()}
      var word:UInt32=0
      for b in 0..<stride {word=(word<<8)|UInt32(row[x*stride+b])}
      if mode == .cmyk,component<mode.componentCount {word=(depth == .u8 ? 255:65535)-word}
      result[x]=word
    }
    return result
  }
  private static func builder(width:Int,height:Int,depth:PixelDepth,descriptor:DocumentModeDescriptor,
    context:PSDRasterPaging.Context) throws -> NativeModeRaster.RowBuilder {
    try context.admitComponents(width:width,height:height,count:descriptor.mode.componentCount+1,bytesPerSample:depth == .u8 ? 1:depth == .u16 ? 2:4)
    return try NativeModeRaster.RowBuilder(width:width,height:height,mode:descriptor.mode,depth:depth,
      profile:descriptor.profile,intent:descriptor.intent,backing:context.backing)
  }
  private static func appendSparsePlane(_ reader: PSDChannelReader, component: Int,
    width: Int, height: Int, depth: PixelDepth, mode: DocumentColorMode,
    to output: NativeModeRaster.RowBuilder) throws {
    let sampleBytes = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
    let count = min(height, 7)
    var prefetched: [[UInt8]] = []
    let sample = try PSDRasterPaging.representativeSample(width: width, sampleSize: sampleBytes) { observe in
      if reader.hasSeekableRows {
        let rows = (0..<count).map { $0 * (height - 1) / max(1, count - 1) }
        try reader.inspectPlaneRows(at: rows, height: height, observe)
      } else {
        let prefixCount = min(count, (6 * 1024 * 1024) / (width * sampleBytes))
        for _ in 0..<prefixCount {
          let row = try reader.nextRow()
          prefetched.append(row)
          observe(row)
        }
      }
    }
    let seed = try words(sample, width: 1, depth: depth, mode: mode, component: component)[0]
    try output.seedImplicitWord(seed, component: component)
    let expected = PSDChannelWriter.repeating(Data(sample), count: width)
    func matches(_ row: [UInt8]) -> Bool {
      row.withUnsafeBytes { actual in
        expected.withUnsafeBytes { implicit in
          memcmp(actual.baseAddress!, implicit.baseAddress!, actual.count) == 0
        }
      }
    }
    func append(_ row: [UInt8]?) throws {
      if let row {
        try output.appendRow(words(row, width: width, depth: depth, mode: mode, component: component), component: component)
      } else {
        try output.appendImplicitRow(component: component)
      }
    }
    let sampledCount = prefetched.count
    for row in prefetched { try append(matches(row) ? nil : row) }
    prefetched = []
    var uniformPacket: Data?
    for _ in sampledCount..<height {
      try append(reader.nextSparseRow(uniformPacket: &uniformPacket, isUniform: matches))
    }
  }

  static func layer(width:Int,height:Int,depth:PixelDepth,descriptor:DocumentModeDescriptor,
    planes:[Int:PSDChannelReader],context:PSDRasterPaging.Context) throws -> NativeModeRaster {
    let output=try builder(width:width,height:height,depth:depth,descriptor:descriptor,context:context)
    let count=descriptor.mode.componentCount
    for component in 0..<count {
      guard let plane = planes[component] else { throw CraftError.invalid("Missing Photoshop component plane.") }
      try appendPlane(plane, component: component, width: width, height: height, depth: depth,
        mode: descriptor.mode, to: output)
    }
    if let alpha = planes[-1] {
      try appendPlane(alpha, component: count, width: width, height: height, depth: depth, mode: descriptor.mode, to: output)
    } else {
      try output.fill(component: count, word: depth == .f32 ? Float(1).bitPattern : depth == .u8 ? 255 : 65535)
    }
    return try output.finish()
  }
  static func merged(width:Int,height:Int,depth:PixelDepth,descriptor:DocumentModeDescriptor,
    imageChannels:Int,transparency:Bool,reader:PSDChannelReader,context:PSDRasterPaging.Context) throws -> NativeModeRaster {
    let output=try builder(width:width,height:height,depth:depth,descriptor:descriptor,context:context)
    let views = width > NativeModeRaster.maximumPixels / height && reader.hasSeekableRows
      ? try reader.detachSeekablePlanes(count: imageChannels, height: height) : nil
    for component in 0..<imageChannels {
      try appendPlane(views?[component] ?? reader, component: component, width: width, height: height,
        depth: depth, mode: descriptor.mode, to: output)
    }
    if imageChannels == descriptor.mode.componentCount {
      try output.fill(component:descriptor.mode.componentCount,word:depth == .f32 ? Float(1).bitPattern:depth == .u8 ? 255:65535)
    }
    let native=try output.finish()
    if transparency,descriptor.mode == .grayscale {
      return try native.mappingColorComponent(0,backing:context.backing) {value,alpha in
        PSDMergedSample.decode(Pixel(value,value,value,alpha)).r
      }
    }
    return native
  }

  private static func appendPlane(_ reader: PSDChannelReader, component: Int,
    width: Int, height: Int, depth: PixelDepth, mode: DocumentColorMode,
    to output: NativeModeRaster.RowBuilder) throws {
    if width > NativeModeRaster.maximumPixels / height {
      try appendSparsePlane(reader, component: component, width: width, height: height, depth: depth, mode: mode, to: output)
    } else {
      for _ in 0..<height {
        try output.appendRow(words(reader.nextRow(), width: width, depth: depth, mode: mode, component: component),
          component: component)
      }
    }
  }
}
