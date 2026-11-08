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
  static func layer(width:Int,height:Int,depth:PixelDepth,descriptor:DocumentModeDescriptor,
    planes:[Int:PSDChannelReader],context:PSDRasterPaging.Context) throws -> NativeModeRaster {
    let output=try builder(width:width,height:height,depth:depth,descriptor:descriptor,context:context)
    let count=descriptor.mode.componentCount
    for y in 0..<height {
      try Task.checkCancellation()
      for c in 0..<count {
        guard let plane=planes[c] else {throw CraftError.invalid("Missing Photoshop component plane.")}
        try output.appendRow(words(plane.nextRow(),width:width,depth:depth,mode:descriptor.mode,component:c),component:c)
      }
      if let alpha=planes[-1] {try output.appendRow(words(alpha.nextRow(),width:width,depth:depth,mode:descriptor.mode,component:count),component:count)}
    }
    if planes[-1] == nil {try output.fill(component:count,word:depth == .f32 ? Float(1).bitPattern:depth == .u8 ? 255:65535)}
    return try output.finish()
  }
  static func merged(width:Int,height:Int,depth:PixelDepth,descriptor:DocumentModeDescriptor,
    imageChannels:Int,transparency:Bool,reader:PSDChannelReader,context:PSDRasterPaging.Context) throws -> NativeModeRaster {
    let output=try builder(width:width,height:height,depth:depth,descriptor:descriptor,context:context)
    for c in 0..<imageChannels {for _ in 0..<height {
      try output.appendRow(words(reader.nextRow(),width:width,depth:depth,mode:descriptor.mode,component:c),component:c)
    }}
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
}
