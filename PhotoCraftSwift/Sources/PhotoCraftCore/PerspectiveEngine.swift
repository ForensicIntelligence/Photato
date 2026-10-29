import Foundation

public enum PerspectiveEngine {
  public static func validateTarget(_ document:CraftDocument,layerID:UUID) throws {
    guard let layer=document.layers.first(where:{$0.id == layerID}),case .raster=layer.content,!document.isImageLocked(layerID),!document.isPositionLocked(layerID),!document.isTransparencyLocked(layerID),layer.vectorMask == nil,document.selection == nil else { throw CraftError.unsupported("Perspective Warp requires an unlocked RGB pixel layer or Smart Object without a selection or vector mask. Convert other layer types to a Smart Object first.") }
  }
  public static func mapping(width:Int,height:Int,origin:PathPoint,settings:PerspectiveSettings) throws -> WarpRaster.Mapping {
    guard width>0,height>0,width<=WarpRaster.maximumPixels/height else { throw CraftError.unsupported("Perspective Warp supports up to8,388,608 source pixels.") }
    let map=try PerspectiveMap(settings)
    if let transform=map.singleTransform,let inverse=transform.inverse() {
      let inputs=[PathPoint(0,0),PathPoint(Double(width),0),PathPoint(Double(width),Double(height)),PathPoint(0,Double(height))]
      let world=inputs.map{PathPoint($0.x+origin.x,$0.y+origin.y)}
      let weights=world.map{transform.m[6]*$0.x+transform.m[7]*$0.y+transform.m[8]}
      guard weights.allSatisfy({$0>1e-10}) || weights.allSatisfy({$0 < -1e-10}) else { throw CraftError.invalid("Perspective horizon crosses the source image.") }
      let coarse=try WarpRaster.mapping(vertices:world.map{map.point($0)},inputs:inputs,triangles:[[0,1,2],[0,2,3]]),b=coarse.bounds
      var uv=coarse.uv
      for y in 0..<b.height { try Task.checkCancellation();for x in 0..<b.width {
        let p=inverse.apply(PhotoPoint(Double(b.x+x)+0.5,Double(b.y+y)+0.5)),q=PathPoint(p.x-origin.x,p.y-origin.y)
        uv[y*b.width+x]=q.x>=0 && q.y>=0 && q.x<=Double(width) && q.y<=Double(height) ? q:PathPoint(.nan,.nan)
      } };return WarpRaster.Mapping(bounds:b,uv:uv)
    }
    let nx=min(256,max(16,(width+7)/8)),ny=min(256,max(16,(height+7)/8));var inputs=[PathPoint](),vertices=[PathPoint](),triangles=[[Int]]()
    for j in 0...ny { try Task.checkCancellation();for i in 0...nx {
      let p=PathPoint(Double(i)*Double(width)/Double(nx),Double(j)*Double(height)/Double(ny));inputs.append(p);vertices.append(map.point(PathPoint(p.x+origin.x,p.y+origin.y)))
    } }
    for j in 0..<ny { for i in 0..<nx { let a=j*(nx+1)+i,b=a+1,c=a+nx+1,d=c+1;triangles += [[a,b,d],[a,d,c]] } }
    return try WarpRaster.mapping(vertices:vertices,inputs:inputs,triangles:triangles)
  }
  public static func render(_ source:Surface,origin:PathPoint,settings:PerspectiveSettings) throws -> (Surface,IntRect) {
    try settings.validate();let settings=settings.normalized()
    if settings.isIdentity { return (source,IntRect(x:Int(origin.x),y:Int(origin.y),width:source.width,height:source.height)) }
    let map=try mapping(width:source.width,height:source.height,origin:origin,settings:settings)
    return (try WarpRaster.render(source,using:map,method:settings.interpolation,clampEdges:false),map.bounds)
  }
  public static func apply(_ settings:PerspectiveSettings,to id:UUID,in document:inout CraftDocument) throws {
    try settings.validate();try validateTarget(document,layerID:id);let settings=settings.normalized()
    guard !settings.isIdentity else { return }
    let i=document.layers.firstIndex{$0.id == id}!,original=document.layers[i]
    guard original.smartObject == nil,case .raster(let source)=original.content else { throw CraftError.invalid("Smart Objects require the retained Perspective filter path.") }
    let placed=try WarpRaster.mapping(WarpDefinition(),width:source.width,height:source.height,transform:original.coordinateTransform)
    let layer=try WarpRaster.baked(original,in:document,using:placed,method:settings.interpolation)
    guard case .raster(let pixels)=layer.content else { return }
    let mapping=try mapping(width:pixels.width,height:pixels.height,origin:PathPoint(Double(layer.x),Double(layer.y)),settings:settings)
    document.layers[i]=try WarpRaster.baked(layer,in:document,using:mapping,method:settings.interpolation,clampEdges:false)
  }
}
extension SmartFilterStack {
  public mutating func transformPerspectivePlanes(_ delta:Transform2D) {
    for i in filters.indices { if let settings=filters[i].filter.perspective { filters[i].filter.perspective=settings.transformed(delta) } }
  }
}
