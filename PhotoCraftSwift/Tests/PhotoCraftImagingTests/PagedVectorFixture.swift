import PhotoCraftCore

/// Original owned geometry captured through the qualified290 renderer.
enum PagedVectorFixture {
  static func rectangle(_ x:Double,_ y:Double,_ w:Double,_ h:Double,
    operation:PathOperation = .combine)->PathComponent {
    .init(knots:[PathPoint(x,y),PathPoint(x+w,y),PathPoint(x+w,y+h),PathPoint(x,y+h)].map{PathKnot($0)},closed:true,operation:operation)
  }
  static func path(_ variant:Int,inverted:Bool)->VectorPath {
    if variant==6 {return VectorPath(inverted:inverted)}
    if variant==7 {return VectorPath(components:[rectangle(-20,-20,2200,200)],inverted:inverted)}
    var path=VectorPath(components:[rectangle(1.125,3.25,2100.25,60.75),
      rectangle(2046.75,12.125,40.25,40.125,operation:PathOperation.allCases[variant%5])],inverted:inverted)
    if variant==5 {
      path.fillRule = .evenOdd
      path.components[0].knots[0].outgoing = PathPoint(80,-50)
      path.components[0].knots[1].incoming = PathPoint(1800,90)
      path.components[0].knots[2].outgoing = PathPoint(1700,110)
    }
    return path
  }
}
