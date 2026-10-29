import Foundation

public enum WideAngleEngine {
  public static func render(_ source:Surface,settings:WideAngleSettings) throws -> Surface {
    try settings.validate();if settings.isIdentity { return source }
    let mesh=try WideAngleSolver.solve(settings,width:source.width,height:source.height)
    let map=try WarpRaster.mapping(vertices:mesh.vertices,inputs:mesh.inputs,triangles:mesh.triangles,bounds:.init(x:0,y:0,width:source.width,height:source.height))
    return try WarpRaster.render(source,using:map,method:settings.interpolation)
  }
  static func apply(_ settings:WideAngleSettings,to id:UUID,in document:inout CraftDocument) throws {
    try settings.validate();if settings.isIdentity { return }
    guard let i=document.layers.firstIndex(where:{$0.id==id}),case .raster(let source)=document.layers[i].content else { throw CraftError.invalid("Wide Angle requires pixels.") }
    let rendered=try render(source,settings:settings),transform=document.layers[i].coordinateTransform,linear=document.depth == .f32,protectAlpha=document.isTransparencyLocked(id)
    var result=source
    for y in 0..<source.height { try Task.checkCancellation();for x in 0..<source.width {
      let q=transform.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage<=0 { continue }
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      if protectAlpha && before.a == 0 { continue }
      var after=linear ? rendered.linearPixel(x:x,y:y):rendered.pixel(x:x,y:y)
      if protectAlpha { after.a=before.a }
      let mixed=before.mixing(after,coverage:coverage);guard mixed.isFinite else { throw CraftError.invalid("Nonfinite Wide Angle result.") }
      if linear { result.setLinearPixel(x:x,y:y,mixed) } else { result.setPixel(x:x,y:y,mixed) }
    } };document.layers[i].content = .raster(result)
  }
}
