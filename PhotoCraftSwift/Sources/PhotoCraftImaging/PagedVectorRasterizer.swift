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
    let outside:Float = path.isEmpty ? (emptyRevealsAll != path.inverted ? 1:0):(path.inverted ? 1:0)
    let empty=try Surface(width:width,height:height,fill:Pixel(outside,outside,outside))
    if path.isEmpty {return empty}
    if coversCanvasRectangle(path,width:width,height:height,origin:origin) {
      let value:Float=path.inverted ? 0:1
      return try Surface(width:width,height:height,fill:Pixel(value,value,value))
    }
    let outline=try filledPath(path),bounds=outline.boundingBoxOfPath
    if bounds.isNull || bounds.isEmpty {return empty}
    let x0=Int(max(0,min(Double(width),floor(bounds.minX-origin.x-1))))
    let y0=Int(max(0,min(Double(height),floor(bounds.minY-origin.y-1))))
    let x1=Int(max(0,min(Double(width),ceil(bounds.maxX-origin.x+1))))
    let y1=Int(max(0,min(Double(height),ceil(bounds.maxY-origin.y+1))))
    guard x1>x0,y1>y0 else {return empty}
    let left=x0/64*64,top=y0/64*64,right=min(width,((x1+63)/64)*64),bottom=min(height,((y1+63)/64)*64)
    let backing=try VectorGrayBacking(width:width,height:height,maximumPreparedBytes:maximumScratchPreparedBytes)
    try backing.prepare(x:0,y:height,width:width,height:1,stride:width)
    // Whole native coordinate bases preserve legacy coverage when they fit.
    // Larger contexts lose far-edge pixels; local16K bases keep coordinates valid.
    let block=16_384
    for y in stride(from:y0/block*block,to:y1,by:block) {for x in stride(from:x0/block*block,to:x1,by:block) {
      try Task.checkCancellation()
      let w=min(block,width-x),h=min(block,height-y)
      // Charge checked physical writes before mapped native drawing. Contexts
      // never overlap; preserve a conservative64-pixel rasterization margin.
      let px=max(x,x0-64),py=max(y,y0-64),pr=min(x+w,x1+64),pb=min(y+h,y1+64)
      try backing.prepare(x:px,y:py,width:pr-px,height:pb-py,stride:width)
      guard let context=CGContext(data:backing.memory.advanced(by:y*width+x),width:w,height:h,
        bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)
      else {throw CraftError.invalid("Could not rasterize the vector coordinate block.")}
      context.setShouldAntialias(antiAlias);context.setAllowsAntialiasing(antiAlias)
      context.translateBy(x:0,y:Double(h));context.scaleBy(x:1,y:-1)
      context.translateBy(x:-origin.x-Double(x),y:-origin.y-Double(y))
      context.setFillColor(gray:1,alpha:1);context.addPath(outline);context.fillPath()
    }}
    let builder=try Surface.PagedBuilder(template:empty)
    let bytes=backing.memory.assumingMemoryBound(to:UInt8.self)
    for y in stride(from:top,to:bottom,by:64) {for x in stride(from:left,to:right,by:2048) {
      try Task.checkCancellation()
      let w=min(2048,right-x),h=min(64,bottom-y)
      var patch=try Surface(width:w,height:h,fill:Pixel(outside,outside,outside))
      for py in 0..<h {try Task.checkCancellation();for px in 0..<w {
        let raw=bytes[(y+py)*width+x+px],value=Float(path.inverted ? 255-raw:raw)/255
        if value != outside {patch.setPixel(x:px,y:py,Pixel(value,value,value))}
      }}
      try builder.append(patch,atX:x,atY:y)
    }}
    return try withExtendedLifetime(backing) {try builder.finish()}
  }
  private static func coversCanvasRectangle(_ path:VectorPath,width:Int,height:Int,origin:PathPoint)->Bool {
    guard path.components.count==1,let part=path.components.first,part.closed,part.knots.count==4,
      part.knots.allSatisfy({$0.incoming==$0.anchor && $0.outgoing==$0.anchor}) else {return false}
    let points=part.knots.map(\.anchor)
    guard (0..<4).allSatisfy({i in (i+1..<4).allSatisfy{points[i] != points[$0]}}) else {return false}
    for i in 0..<4 {
      let a=points[i],b=points[(i+1)%4]
      if (a.x==b.x)==(a.y==b.y) {return false}
    }
    let xs=points.map(\.x),ys=points.map(\.y)
    return xs.min()!<=origin.x && ys.min()!<=origin.y &&
      xs.max()!>=origin.x+Double(width) && ys.max()!>=origin.y+Double(height)
  }
}
