import CoreGraphics
import Foundation
import PhotoCraftCore
import Darwin

/// Private unlinked sparse GRAY8 file. The virtual extent is separate from owned
/// patch memory and OS-managed mapped residency; never allocate a canvas Array.
private final class VectorGrayBacking {
  let memory:UnsafeMutableRawPointer
  let count:Int
  private let descriptor:Int32
  private let maximumPreparedBytes:Int
  private var preparedBytes=0
  private let zeros=[UInt8](repeating:0,count:64*1024)
  init(width:Int,height:Int,maximumPreparedBytes:Int)throws {
    guard maximumPreparedBytes>=0 else {throw CraftError.invalid("Invalid vector scratch write budget.")}
    self.maximumPreparedBytes=maximumPreparedBytes
    // A local context advertises bytesPerRow*height from its x-offset pointer.
    // Reserve one guard row so its final padding also lies inside the mapping.
    count=width*(height+1)
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-vector-"+UUID().uuidString)
    let fd=open(url.path,O_CREAT|O_EXCL|O_RDWR,mode_t(0o600))
    guard fd>=0 else {throw CraftError.invalid("Could not create vector scratch storage.")}
    var retained=false;defer{if !retained {close(fd)}}
    guard unlink(url.path)==0 else {throw CraftError.invalid("Could not isolate vector scratch storage.")}
    guard ftruncate(fd,off_t(count))==0,let mapped=mmap(nil,count,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0),mapped != MAP_FAILED else {
      throw CraftError.invalid("Could not map vector scratch storage.")
    }
    memory=mapped;descriptor=fd;retained=true
  }
  func prepare(x:Int,y:Int,width:Int,height:Int,stride:Int)throws {
    for row in y..<y+height {
      try Task.checkCancellation()
      var remaining=width,offset=row*stride+x
      while remaining>0 {
        let size=min(remaining,zeros.count)
        guard size<=maximumPreparedBytes-preparedBytes else {throw CraftError.unsupported("Vector scratch preparation exceeds its admitted write budget.")}
        let written=zeros.withUnsafeBytes {pwrite(descriptor,$0.baseAddress!,size,off_t(offset))}
        if written<0 && errno==EINTR {continue}
        guard written>0 else {throw CraftError.invalid("Could not prepare vector scratch storage.")}
        offset+=written;remaining-=written;preparedBytes+=written
      }
    }
    while fsync(descriptor) != 0 {
      if errno != EINTR {throw CraftError.invalid("Could not synchronize vector scratch storage.")}
      try Task.checkCancellation()
    }
  }
  deinit {munmap(memory,count);close(descriptor)}
}

extension VectorRasterizer {
  /// Native fill in bounded coordinate blocks on private file-backed GRAY8,
  /// followed by aligned bounded transfer into immutable coverage pages.
  static func pagedCoverage(_ path:VectorPath,width:Int,height:Int,
    origin:PathPoint = PathPoint(0,0),antiAlias:Bool = true,
    emptyRevealsAll:Bool = false,
    maximumScratchPreparedBytes:Int = Surface.maxPixels+Surface.maxDimension) throws -> Surface {
    try Task.checkCancellation();try path.validate()
    guard origin.x.isFinite,origin.y.isFinite else {throw CraftError.invalid("Invalid path raster origin.")}
    let region = try VectorPathGeometry.filledRegion(path)
    let outside:Float = path.isEmpty ? (emptyRevealsAll != path.inverted ? 1:0):(region.inverted ? 1:0)
    let empty=try Surface(width:width,height:height,fill:Pixel(outside,outside,outside))
    if path.isEmpty {return empty}
    if path.components.first?.operation != .subtract && coversCanvasRectangle(path,width:width,height:height,origin:origin) {
      let value:Float=region.inverted ? 0:1
      return try Surface(width:width,height:height,fill:Pixel(value,value,value))
    }
    return try pagedCoverage(region, template: empty, origin: origin, antiAlias: antiAlias,
      maximumScratchPreparedBytes: maximumScratchPreparedBytes)
  }

  static func pagedCoverage(_ region: VectorPathGeometry.FilledRegion, template empty: Surface,
    origin: PathPoint, antiAlias: Bool = true,
    maximumScratchPreparedBytes: Int = Surface.maxPixels + Surface.maxDimension,
    window: IntRect? = nil, clipRectangle: Bool = false, compactTransfer: Bool = false
  ) throws -> Surface {
    let width = empty.width, height = empty.height, outside = empty.defaultPixel.r
    let outline=region.path,bounds=outline.boundingBoxOfPath
    if bounds.isNull || bounds.isEmpty {return empty}
    let pathLeft=Int(max(0,min(Double(width),floor(bounds.minX-origin.x-1))))
    let pathTop=Int(max(0,min(Double(height),floor(bounds.minY-origin.y-1))))
    let pathRight=Int(max(0,min(Double(width),ceil(bounds.maxX-origin.x+1))))
    let pathBottom=Int(max(0,min(Double(height),ceil(bounds.maxY-origin.y+1))))
    let x0=max(window?.x ?? 0,pathLeft),y0=max(window?.y ?? 0,pathTop)
    let x1=min(window.map { $0.x + $0.width } ?? width,pathRight)
    let y1=min(window.map { $0.y + $0.height } ?? height,pathBottom)
    guard x1>x0,y1>y0 else {return empty}
    let left=x0/64*64,top=y0/64*64,right=min(width,((x1+63)/64)*64),bottom=min(height,((y1+63)/64)*64)
    let backing=try VectorGrayBacking(width:width,height:height,maximumPreparedBytes:maximumScratchPreparedBytes)
    try backing.prepare(x:0,y:height,width:width,height:1,stride:width)
    // Whole native coordinate bases preserve legacy coverage when they fit.
    // Larger contexts lose far-edge pixels; local16K bases keep coordinates valid.
    let block=16_384
    // An integer clip can change curve subdivision in Core Graphics. Draw
    // arbitrary contours with the original clip and bound their transfer.
    // An axis-aligned rectangle can also limit the native drawing area.
    let drawWindow = clipRectangle ? window : nil
    for y in stride(from:y0/block*block,to:y1,by:block) {for x in stride(from:x0/block*block,to:x1,by:block) {
      try Task.checkCancellation()
      let w=min(block,width-x),h=min(block,height-y)
      let px=max(x,(drawWindow == nil ? pathLeft : x0)-64)
      let py=max(y,(drawWindow == nil ? pathTop : y0)-64)
      let pr=min(x+w,(drawWindow == nil ? pathRight : x1)+64)
      let pb=min(y+h,(drawWindow == nil ? pathBottom : y1)+64)
      try backing.prepare(x:px,y:py,width:pr-px,height:pb-py,stride:width)
      guard let context=CGContext(data:backing.memory.advanced(by:y*width+x),width:w,height:h,
        bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)
      else {throw CraftError.invalid("Could not rasterize the vector coordinate block.")}
      context.setShouldAntialias(antiAlias);context.setAllowsAntialiasing(antiAlias)
      context.translateBy(x:0,y:Double(h));context.scaleBy(x:1,y:-1)
      if let window = drawWindow {
        context.clip(to: CGRect(x: window.x - x, y: window.y - y, width: window.width, height: window.height))
      }
      context.translateBy(x:-origin.x-Double(x),y:-origin.y-Double(y))
      context.setFillColor(gray:1,alpha:1);context.addPath(outline);context.fillPath()
    }}
    let bytes=backing.memory.assumingMemoryBound(to:UInt8.self)
    if compactTransfer && window == nil && outside == (region.inverted ? 1 : 0) {
      // Keep the same Core Graphics context, origin, clip and Gray8 bytes.
      return try withExtendedLifetime(backing) {
        try compactGrayTransfer(bytes, template: empty, inverted: region.inverted,
          bounds: IntRect(x: left, y: top, width: right-left, height: bottom-top))
      }
    }
    let builder=try Surface.PagedBuilder(template:empty)
    for y in stride(from:top,to:bottom,by:64) {for x in stride(from:left,to:right,by:2048) {
      try Task.checkCancellation()
      let w=min(2048,right-x),h=min(64,bottom-y)
      var patch=try Surface(width:w,height:h,fill:Pixel(outside,outside,outside))
      for py in 0..<h {try Task.checkCancellation();for px in 0..<w {
        let raw=bytes[(y+py)*width+x+px],value=Float(region.inverted ? 255-raw:raw)/255
        if value != outside {patch.setPixel(x:px,y:py,Pixel(value,value,value))}
      }}
      try builder.append(patch,atX:x,atY:y)
    }}
    return try withExtendedLifetime(backing) {try builder.finish()}
  }

  private static func compactGrayTransfer(_ bytes: UnsafePointer<UInt8>, template: Surface, inverted: Bool,
    bounds: IntRect
  ) throws -> Surface {
    let width = template.width, height = template.height, side = Surface.tileSide
    if bounds == IntRect(x: 0, y: 0, width: width, height: height), bytes[0] == 0 || bytes[0] == 255 {
      let pattern = [UInt8](repeating: bytes[0], count: 65_536)
      let uniform = try pattern.withUnsafeBytes { raw in
        for i in stride(from: 0, to: width * height, by: raw.count) {
          try Task.checkCancellation()
          if memcmp(bytes + i, raw.baseAddress!, min(raw.count, width * height - i)) != 0 { return false }
        }
        return true
      }
      if uniform {
        let value: Float = (bytes[0] == 255) != inverted ? 1 : 0
        return try Surface(width: width, height: height, depth: template.depth,
          fill: Pixel(value, value, value), colorEncoding: template.colorEncoding)
      }
    }
    let builder = try Surface.PagedBuilder(template: template)
    let zero = [UInt8](repeating: 0, count: side)
    let full = [UInt8](repeating: 255, count: side)
    var solid: [Int: Surface.PagedBuilder.PreparedTile] = [:]
    let other: Float = inverted ? 0 : 1
    for y in stride(from: bounds.y, to: bounds.y + bounds.height, by: side) {
      try Task.checkCancellation()
      let h = min(side, height - y)
      for x in stride(from: bounds.x, to: bounds.x + bounds.width, by: side) {
        let w = min(side, width - x), raw = bytes + y * width + x
        let first = raw[0]
        if first == 0 || first == 255 {
          let uniform = (first == 0 ? zero : full).withUnsafeBytes { row in
            (0..<h).allSatisfy { memcmp(raw + $0 * width, row.baseAddress!, w) == 0 }
          }
          if uniform {
            if first == 0 { continue }
            let key = w * (side + 1) + h
            let tile: Surface.PagedBuilder.PreparedTile
            if let saved = solid[key] {
              tile = saved
            } else {
              let patch = try Surface(width: w, height: h, depth: template.depth,
                fill: Pixel(other, other, other), colorEncoding: template.colorEncoding)
              tile = try builder.prepareTile(patch)
              solid[key] = tile
            }
            try builder.append(tile, row: y / side, columns: (x / side)..<(x / side + 1))
            continue
          }
        }
        var patch = try Surface(width: w, height: h, depth: template.depth,
          fill: template.defaultPixel, colorEncoding: template.colorEncoding)
        for row in 0..<h {
          for column in 0..<w {
            let gray = raw[row * width + column]
            if gray != 0 {
              let value = Float(inverted ? 255 - gray : gray) / 255
              patch.setPixel(x: column, y: row, Pixel(value, value, value))
            }
          }
        }
        try builder.append(patch, atX: x, atY: y)
      }
    }
    return try builder.finish()
  }
  static func coversCanvasRectangle(_ path:VectorPath,width:Int,height:Int,origin:PathPoint)->Bool {
    guard let rect = axisAlignedRectangle(path) else { return false }
    return rect.minX <= origin.x && rect.minY <= origin.y
      && rect.maxX >= origin.x + Double(width) && rect.maxY >= origin.y + Double(height)
  }

  static func integerRectangle(_ path: VectorPath) -> IntRect? {
    guard let rect = axisAlignedRectangle(path),
      let x = Int(exactly: rect.minX), let y = Int(exactly: rect.minY),
      let right = Int(exactly: rect.maxX), let bottom = Int(exactly: rect.maxY),
      right > x, bottom > y
    else { return nil }
    return IntRect(x: x, y: y, width: right - x, height: bottom - y)
  }

  static func axisAlignedRectangle(_ path: VectorPath) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
    guard path.components.count==1,let part=path.components.first,part.closed,part.knots.count==4,
      part.knots.allSatisfy({$0.incoming==$0.anchor && $0.outgoing==$0.anchor}) else {return nil}
    let points=part.knots.map(\.anchor)
    guard (0..<4).allSatisfy({i in (i+1..<4).allSatisfy{points[i] != points[$0]}}) else {return nil}
    for i in 0..<4 {
      let a=points[i],b=points[(i+1)%4]
      if (a.x==b.x)==(a.y==b.y) {return nil}
    }
    let xs=points.map(\.x),ys=points.map(\.y)
    return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
  }
}
