import Darwin
import Foundation
import PhotoCraftCore

/// A shared bound for retained metadata, distinct from streamed channel bytes.
final class PSDMetadataBudget {
  private var remaining = PSDCodec.maximumMetadataBytes
  func reserve(_ bytes:Int) throws {
    guard bytes >= 0,bytes <= remaining else {throw CraftError.invalid("Photoshop retained metadata exceeds its memory budget.")}
    remaining -= bytes
  }
}

enum PSDRasterPaging {
  static let patchWidth = 2048
  final class Context {
    let backing:RasterTileStore
    private var remaining:Int?
    init(heapByteLimit:Int? = nil,scratchByteLimit:Int = RasterTileStore.defaultMaximumBytes) throws {
      if let heapByteLimit,heapByteLimit < PSDCodec.pagedWorkingHeapReserveBytes {throw CraftError.invalid("Photoshop row/patch workspace exceeds its heap budget.")}
      backing=try RasterTileStore(maximumBytes:scratchByteLimit)
      remaining=heapByteLimit.map {$0-PSDCodec.pagedWorkingHeapReserveBytes}
    }
    func admitRaster(bytes:Int) throws {
      if let limit=remaining {
        guard bytes >= 0,bytes % 65536 == 0 else {throw CraftError.invalid("Invalid Photoshop raster heap admission.")}
        let tiles=bytes/65536
        let estimate=tiles < Surface.pagedIndexMinimumTiles ? tiles*Surface.smallMappedReferenceAdmissionBytes
          : Surface.runtimeIndexWriteBufferBytes+512+((tiles+1023)/1024)*128
        guard estimate <= limit else {throw CraftError.invalid("Photoshop tile metadata exceeds the configured heap budget.")}
        remaining=limit-estimate
      }
    }
  }
  /// Interleaved layer readers allow a64-row staging window. No full raster or
  /// whole strip of Float32 pixels is retained in heap memory, even at300000 px.
  static func layer(width:Int,height:Int,depth:PixelDepth,components:Int,
    fill:Pixel = .clear,mask:Bool = false,sourceDepth:Int? = nil,clampMask:Bool = true,context:Context,
    rows:(Int)throws->[[UInt8]]) throws -> Surface {
    let bits=sourceDepth ?? (depth == .u8 ? 8:depth == .u16 ? 16:32)
    let encoding:SurfaceColorEncoding = depth == .f32 && !mask ? .linearRGB:.sRGB
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:depth,fill:fill,colorEncoding:encoding,backing:context.backing)
    let stripe=try PSDPlaneScratch(width:width,height:min(64,height),depth:bits,components:components)
    for y in stride(from:0,to:height,by:64) {
      let h=min(64,height-y)
      for py in 0..<h {
        try Task.checkCancellation();let values=try rows(y+py)
        guard values.count == components else {throw CraftError.invalid("Missing Photoshop staging plane.")}
        for c in 0..<components {try stripe.write(values[c],row:py,component:c)}
      }
      try appendBand(stripe,to:builder,width:width,originY:y,storedY:0,height:h,depth:depth,fill:fill,mask:mask,merged:false,clampMask:clampMask)
    }
    return try builder.finish()
  }
  /// A flattened ZIP composite is one channel-major stream. Stage its raw planes
  /// in private disk storage before assembling ordered bounded raster patches.
  static func merged(width:Int,height:Int,depth:PixelDepth,components:Int,
    transparency:Bool,context:Context,reader:PSDChannelReader) throws -> Surface {
    let bits=depth == .u8 ? 8:depth == .u16 ? 16:32
    let planes=try PSDPlaneScratch(width:width,height:height,depth:bits,components:components)
    for c in 0..<components {for y in 0..<height {try planes.write(reader.nextRow(),row:y,component:c)}}
    let fill=Pixel(0,0,0,1),builder=try Surface.PagedBuilder(width:width,height:height,depth:depth,fill:fill,
      colorEncoding:bits == 32 ? .linearRGB:.sRGB,backing:context.backing)
    for y in stride(from:0,to:height,by:64) {
      try appendBand(planes,to:builder,width:width,originY:y,storedY:y,height:min(64,height-y),depth:depth,fill:fill,mask:false,merged:transparency)
    }
    return try builder.finish()
  }
  private static func appendBand(_ planes:PSDPlaneScratch,to builder:Surface.PagedBuilder,
    width:Int,originY:Int,storedY:Int,height:Int,depth:PixelDepth,fill:Pixel,mask:Bool,merged:Bool,clampMask:Bool = true) throws {
    let linear=depth == .f32 && !mask
    for x in stride(from:0,to:width,by:patchWidth) {
      var patch=try Surface(width:min(patchWidth,width-x),height:height,depth:depth,fill:fill,
        colorEncoding:linear ? .linearRGB:.sRGB)
      for py in 0..<height {
        try Task.checkCancellation()
        for px in 0..<patch.width {
          let p:Pixel
          if mask {let sample=try planes.sample(x:x+px,y:storedY+py,component:0),v=clampMask ? unit(sample):sample;p=Pixel(v,v,v)}
          else {
            let alpha=planes.components == 4 ? try planes.sample(x:x+px,y:storedY+py,component:3):1
            let value=try Pixel(planes.sample(x:x+px,y:storedY+py,component:0),planes.sample(x:x+px,y:storedY+py,component:1),planes.sample(x:x+px,y:storedY+py,component:2),alpha)
            p=merged ? PSDMergedSample.decode(value):value
          }
          if linear {patch.setLinearPixel(x:px,y:py,p)} else {patch.setPixel(x:px,y:py,p)}
        }
      }
      try builder.append(patch,atX:x,atY:originY)
    }
  }
}

/// Readonly mapping, explicit checked writes and immediate unlink avoid exposing
/// mutable paths or taking writable-mmap faults when scratch storage is full.
final class PSDPlaneScratch {
  let width:Int,height:Int,depth:Int,components:Int
  let byteCount:Int
  private let rowBytes:Int
  private let fd:Int32
  private let address:UnsafeMutableRawPointer
  init(width:Int,height:Int,depth:Int,components:Int,directory:URL? = nil) throws {
    try Task.checkCancellation()
    let count=try PSDChannelCodec.streamByteCount(width:width,height:height,depth:depth,channels:components)
    guard [1,3,4].contains(components),count <= RasterTileStore.defaultMaximumBytes else {throw CraftError.invalid("Photoshop raw-plane staging exceeds its disk budget.")}
    let folder=directory ?? FileManager.default.temporaryDirectory
    guard folder.isFileURL else {throw CraftError.invalid("Photoshop staging requires a local directory.")}
    let url=folder.appendingPathComponent("photato-photoshop-planes-\(UUID().uuidString).tmp")
    let descriptor=url.withUnsafeFileSystemRepresentation {open($0!,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)}
    guard descriptor >= 0 else {throw RasterScratchFailure.io(operation:"Photoshop staging creation",code:errno)}
    guard url.withUnsafeFileSystemRepresentation({unlink($0!)}) == 0 else {let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"Photoshop staging unlink",code:code)}
    guard ftruncate(descriptor,off_t(count)) == 0 else {let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"Photoshop staging growth",code:code)}
    let mapping=mmap(nil,count,PROT_READ,MAP_SHARED,descriptor,0)
    guard let mapping,mapping != MAP_FAILED else {let code=errno;close(descriptor);throw RasterScratchFailure.io(operation:"Photoshop staging mapping",code:code)}
    self.width=width;self.height=height;self.depth=depth;self.components=components
    byteCount=count;rowBytes=width*(depth/8);fd=descriptor;address=mapping
    _ = madvise(mapping,count,MADV_SEQUENTIAL)
  }
  deinit {munmap(address,byteCount);close(fd)}
  func write(_ bytes:[UInt8],row:Int,component:Int) throws {
    try Task.checkCancellation()
    guard (0..<height).contains(row),(0..<components).contains(component),bytes.count == rowBytes else {throw CraftError.invalid("Invalid Photoshop staging row.")}
    if depth == 32 {for x in 0..<width {_ = try PSDChannelCodec.sample(bytes,x,depth:depth)}}
    try bytes.withUnsafeBytes { buffer in
      var done=0
      while done < buffer.count {
        try Task.checkCancellation()
        let size=min(65536,buffer.count-done)
        let n=pwrite(fd,buffer.baseAddress!.advanced(by:done),size,off_t((component*height+row)*rowBytes+done))
        if n < 0 && errno == EINTR {continue}
        guard n > 0 else {throw RasterScratchFailure.io(operation:"Photoshop staging write",code:n == 0 ? EIO:errno)}
        done += n
      }
    }
  }
  func sample(x:Int,y:Int,component:Int) throws -> Float {
    guard (0..<width).contains(x),(0..<height).contains(y),(0..<components).contains(component) else {throw CraftError.invalid("Invalid Photoshop staging sample.")}
    let offset=(component*height+y)*rowBytes+x*(depth/8)
    switch depth {
    case 8:return Float(address.load(fromByteOffset:offset,as:UInt8.self))/255
    case 16:return Float(UInt16(bigEndian:address.loadUnaligned(fromByteOffset:offset,as:UInt16.self)))/65535
    default:
      let value=Float(bitPattern:UInt32(bigEndian:address.loadUnaligned(fromByteOffset:offset,as:UInt32.self)))
      guard value.isFinite else {throw CraftError.invalid("Non-finite Photoshop staging sample.")};return value
    }
  }
}
