import Foundation

/// Keep deep pixel/filter work out of the broad command switch's stack frame.
/// The algorithms and validation are shared unchanged with native/API/history paths.
enum PixelCommandEngine {
  @inline(never)
  static func filter(_ id:UUID,_ filter:RasterFilter,in d:inout CraftDocument)throws {
    if d.layers.first(where:{$0.id==id})?.smartObject != nil {
      try SmartFilterEngine.append(filter,to:id,in:&d)
    } else {try RasterFilterEngine.apply(filter,to:id,in:&d)}
  }
  @inline(never)
  static func stack(_ id:UUID,_ stack:SmartFilterStack?,in d:inout CraftDocument)throws {
    try SmartFilterEngine.set(stack,on:id,in:&d)
  }
  @inline(never)
  static func adjust(_ id:UUID,_ a:Adjustment,in d:inout CraftDocument)throws {
    func index(_ id:UUID)throws->Int {
      guard let i=d.layers.firstIndex(where:{$0.id==id}) else {throw CraftError.invalid("Layer no longer exists.")}
      guard !d.isLocked(id) else {throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")}
      return i
    }
    func raster(_ i:Int)throws->Surface {
      guard case .raster(let s)=d.layers[i].content else {throw CraftError.unsupported("Rasterize this layer before painting or applying pixel filters.")}
      guard s.width<=Surface.maximumDensePixels/s.height else {throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")}
      return s
    }
      try a.validate()
      let i = try index(id)
      var s = try raster(i)
      let evaluate: @Sendable (Pixel,Int,Int)->Pixel
      if case .modern(let value)=a {try value.validate(in:d)}
      if case .modern(let value)=a,value.needsNeighborhood {
        try value.validate(in:d)
        let edited=try value.neighborhood(s)
        evaluate={_,x,y in edited.pixel(x:x,y:y)}
      } else {evaluate=try a.spatialEvaluator(depth:d.depth)}
      let matrix = d.layers[i].coordinateTransform
      let before = d
      let linearLookup:ColorLookupTransfer?
      if before.depth == .f32,case .colorLookup(let settings)=a,settings.interpolation == .tetrahedral {
        linearLookup=try ColorLookupTransfer(settings,depth:.f32)
      }else{linearLookup=nil}
      for y in 0..<s.height {
        try Task.checkCancellation()
        for x in 0..<s.width {
          let p = s.pixel(x: x, y: y)
          let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
          let coverage = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
          if coverage == 0 { continue }
          if let transfer=linearLookup {
            let original=s.linearPixel(x:x,y:y),edited=transfer.applyLinear(original,x:Int(floor(q.x)),y:Int(floor(q.y)))
            let rgb=coverage==1 ? edited.rgb:original.rgb+(edited.rgb-original.rgb)*coverage
            let result=Pixel(rgb.x,rgb.y,rgb.z,original.a)
            guard result.isFinite else{throw CraftError.invalid("Adjustment result exceeds the floating-point range.")}
            s.setLinearPixel(x:x,y:y,result)
            continue
          }
          let edited:Pixel
          if case .modern(let value)=a,value.needsNeighborhood {edited=evaluate(p,x,y)}
          else {edited=evaluate(p, Int(floor(q.x)), Int(floor(q.y)))}
          let result: Pixel
          if a.usesDocumentToneSpace {
            result = LevelsTransfer.mix(p, with: edited, coverage: coverage, depth: before.depth)
            guard result.isFinite else {
              throw CraftError.invalid("Adjustment result exceeds the floating-point range.")
            }
          } else {
            result = p.mixing(edited, coverage: coverage)
          }
          s.setPixel(x: x, y: y, result)
        }
      }
      d.layers[i].content = .raster(s)
  }
}
