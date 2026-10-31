import Foundation

/// Storage changes only. Pixel math stays in SmartFilterEngine and RasterGeometry.
enum PagedSmartFilterStorage {
  static func placed(_ source:Surface,transform:Transform2D,bounds:IntRect)throws->Surface {
    // At integer translated centers the clamped bicubic neighborhood of a
    // constant source is identical everywhere. Evaluate the original sampler.
    if source.tileCount==0,transform.a==1,transform.b==0,transform.c==0,transform.d==1,
      transform.tx==Double(bounds.x),transform.ty==Double(bounds.y),
      source.width==bounds.width,source.height==bounds.height {
      let first=try RasterGeometry.render(source,transform:transform,
        bounds:IntRect(x:bounds.x,y:bounds.y,width:1,height:1),method:.bicubic,clampEdges:true)
      return try source.reframedImplicitValue(width:bounds.width,height:bounds.height,
        sample:read(first,0,0),linear:source.depth == .f32)
    }
    return try RasterGeometry.render(source,transform:transform,bounds:bounds,method:.bicubic,clampEdges:true)
  }
  static func read(_ s:Surface,_ x:Int,_ y:Int)->Pixel {
    s.depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y)
  }
  static func combine(_ a:Surface,_ b:Surface,pointwise:Bool,extraSources:[Surface]=[],
    implicitOperation:((Pixel,Pixel)->Pixel)?=nil,
    operation:(Pixel,Pixel,Int,Int)->Pixel)throws->Surface {
    try Task.checkCancellation()
    let implicitA=try a.reframedImplicitValue(width:1,height:1)
    let implicitB=try b.reframedImplicitValue(width:1,height:1)
    // The legacy combiner chooses one working domain from the base layer,
    // including when a derived filter result has a different storage depth.
    func working(_ s:Surface,_ x:Int,_ y:Int)->Pixel {a.depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y)}
    let value=implicitOperation?(working(implicitA,0,0),working(implicitB,0,0))
      ?? operation(working(implicitA,0,0),working(implicitB,0,0),0,0)
    // Spatial operations have no global default proof and visit every patch.
    let template=try a.reframedImplicitValue(width:a.width,height:a.height,
      sample:pointwise ? value:.clear,linear:a.depth == .f32)
    let builder=try Surface.PagedBuilder(template:template)
    func append(_ rect:IntRect)throws {
      var patch=try template.reframedImplicitValue(width:rect.width,height:rect.height)
      for y in 0..<rect.height {try Task.checkCancellation();for x in 0..<rect.width {
        let px=rect.x+x,py=rect.y+y,p=operation(working(a,px,py),working(b,px,py),px,py)
        if a.depth == .f32 {patch.setLinearPixel(x:x,y:y,p)}else{patch.setPixel(x:x,y:y,p)}
      }}
      try builder.append(patch,atX:rect.x,atY:rect.y)
    }
    if pointwise {
      let columns=(a.width+63)/64
      var keys=TileKeys([a,b]+extraSources).makeIterator(),next=keys.next()
      while let first=next {
        try Task.checkCancellation()
        let row=first/columns;var end=first+1;next=keys.next()
        while let key=next,key==end,key/columns==row,end-first<32 {end+=1;next=keys.next()}
        let x=first%columns*64,y=row*64
        try append(IntRect(x:x,y:y,width:min(a.width-x,(end-first)*64),height:min(64,a.height-y)))
      }
    }else{
      for y in stride(from:0,to:a.height,by:64){for x in stride(from:0,to:a.width,by:2048){
        try append(IntRect(x:x,y:y,width:min(2048,a.width-x),height:min(64,a.height-y)))
      }}
    }
    return try builder.finish()
  }
  private struct TileKeys:Sequence {
    let sources:[Surface]
    init(_ sources:[Surface]){self.sources=sources}
    func makeIterator()->AnyIterator<Int>{
      var iterators=sources.map{$0.storedTileKeys.makeIterator()}
      var heads=iterators.indices.map{iterators[$0].next()}
      return AnyIterator {
        guard let key=heads.compactMap({$0}).min() else{return nil}
        for i in heads.indices where heads[i]==key{heads[i]=iterators[i].next()}
        return key
      }
    }
  }
}
