import Foundation
import PhotoCraftCore

/// The existing scalar statistics, evaluated only on allocated sample support.
/// Frame order, transparency admission, alpha maximum and depth rounding match
/// the legacy path. Implicit samples are evaluated once, without a dense grid.
enum PagedImageStatistics {
  /// Reuse the Core exact-word spill operation; retained inputs stay unchanged.
  static func backed(_ source:Surface)throws->Surface {
    try Task.checkCancellation()
    guard source.mappedTileCount<source.tileCount else{return source}
    return try source.spillingTiles(to:RasterTileStore())
  }
  static func surface(_ frames:[Surface],width:Int,height:Int,depth:PixelDepth,mode:ImageStackMode)throws->Surface {
    try Task.checkCancellation()
    guard frames.allSatisfy({$0.width==width && $0.height==height})else{throw CraftError.invalid("Stack frame dimensions differ.")}
    var r=[Float](),g=[Float](),b=[Float]()
    r.reserveCapacity(frames.count);g.reserveCapacity(frames.count);b.reserveCapacity(frames.count)
    func statistic(_ sample:(Int)->Pixel)throws->Pixel {
      r.removeAll(keepingCapacity:true);g.removeAll(keepingCapacity:true);b.removeAll(keepingCapacity:true)
      var alpha:Float=0
      for i in frames.indices{let p=sample(i);if p.a>0{r.append(p.r);g.append(p.g);b.append(p.b);alpha=max(alpha,p.a)}}
      let value=Pixel(mode.statistic(r),mode.statistic(g),mode.statistic(b),alpha)
      guard value.isFinite else{throw CraftError.invalid("Image statistic exceeds the finite floating-point range.")}
      return value
    }
    let defaults=try frames.map {frame in
      depth == .f32 ? (frame.colorEncoding == .linearRGB ? try frame.interpretingSamples(as:.sRGB).defaultPixel:SRGBTransfer.linear(frame.defaultPixel)):frame.defaultPixel
    }
    let fill=try statistic{defaults[$0]}
    var template=try Surface(width:width,height:height,depth:depth,fill:fill)
    if depth == .f32{template=try template.interpretingSamples(as:.linearRGB)}
    let builder=try Surface.PagedBuilder(template:template),columns=(width+63)/64
    var keys=TileKeys(frames).makeIterator(),next=keys.next()
    while let first=next {
      try Task.checkCancellation();let row=first/columns;var end=first+1;next=keys.next()
      while let key=next,key==end,key/columns==row,end-first<32{end+=1;next=keys.next()}
      let left=first%columns*64,top=row*64,w=min(width-left,(end-first)*64),h=min(64,height-top)
      var patch=try Surface(width:w,height:h,depth:depth,fill:fill)
      if depth == .f32{patch=try patch.interpretingSamples(as:.linearRGB)}
      for y in 0..<h{try Task.checkCancellation();for x in 0..<w{
        let value=try statistic{depth == .f32 ? frames[$0].linearPixel(x:left+x,y:top+y):frames[$0].pixel(x:left+x,y:top+y)}
        if depth == .f32{patch.setLinearPixel(x:x,y:y,value)}else{patch.setPixel(x:x,y:y,value)}
      }}
      try builder.append(patch,atX:left,atY:top)
    }
    try Task.checkCancellation();return try builder.finish()
  }
  private struct TileKeys:Sequence {
    let sources:[Surface]
    init(_ sources:[Surface]){self.sources=sources}
    func makeIterator()->AnyIterator<Int> {
      var iterators=sources.map{$0.storedTileKeys.makeIterator()}
      var heads=iterators.indices.map{iterators[$0].next()}
      return AnyIterator {
        var first:Int?
        for head in heads{if let head{first=first.map{Swift.min($0,head)} ?? head}}
        guard let key=first else{return nil}
        for i in heads.indices where heads[i]==key{heads[i]=iterators[i].next()}
        return key
      }
    }
  }
}
