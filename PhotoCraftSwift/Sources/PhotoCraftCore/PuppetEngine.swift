import Foundation

public enum PuppetEngine {
  public struct Deformation:Sendable { public let mesh:PuppetMesh,vertices:[PathPoint],order:[Int] }
  public static func validateTarget(_ document:CraftDocument,layerID:UUID) throws {
    guard let layer=document.layers.first(where:{$0.id == layerID}),case .raster=layer.content,!document.isImageLocked(layerID),!document.isPositionLocked(layerID),!document.isTransparencyLocked(layerID),layer.vectorMask == nil,document.selection == nil else { throw CraftError.unsupported("Puppet Warp currently requires an unlocked RGB pixel layer or Smart Object without a selection or vector mask. Convert other layer types to a Smart Object first.") }
  }
  /// Settings use document pixels; the working surface origin is explicit.
  public static func deform(_ source:Surface,origin:PathPoint,settings:PuppetSettings) throws -> Deformation {
    try settings.validate();let local=settings.transformed(.translation(-origin.x,-origin.y))
    let mesh=try PuppetMesh.build(source,density:settings.density,expansion:settings.expansion)
    if mesh.vertices.isEmpty { return Deformation(mesh:mesh,vertices:[],order:[]) }
    if local.isIdentity { return Deformation(mesh:mesh,vertices:mesh.vertices,order:Array(mesh.triangles.indices)) }
    let solver=try PuppetSolver(mesh:mesh,pins:local.pins)
    let points=local.isIdentity ? mesh.vertices:try solver.solve(pins:local.pins,mode:local.mode)
    return Deformation(mesh:mesh,vertices:points,order:solver.drawOrder(pins:local.pins))
  }
  public static func mapping(_ deformation:Deformation,origin:PathPoint,bounds:IntRect?=nil) throws -> WarpRaster.Mapping {
    try WarpRaster.mapping(vertices:deformation.vertices.map{PathPoint($0.x+origin.x,$0.y+origin.y)},inputs:deformation.mesh.vertices,triangles:deformation.order.map{deformation.mesh.triangles[$0]},bounds:bounds)
  }
  public static func render(_ source:Surface,origin:PathPoint,settings:PuppetSettings) throws -> (Surface,IntRect) {
    try settings.validate();let original=IntRect(x:Int(origin.x),y:Int(origin.y),width:source.width,height:source.height)
    if settings.isIdentity { return (source,original) }
    let deformation=try deform(source,origin:origin,settings:settings)
    if deformation.mesh.vertices.isEmpty { return (source,original) }
    let map=try mapping(deformation,origin:origin)
    return (try WarpRaster.render(source,using:map,method:settings.interpolation,clampEdges:false),map.bounds)
  }
  public static func apply(_ settings:PuppetSettings,to id:UUID,in document:inout CraftDocument) throws {
    try settings.validate();try validateTarget(document,layerID:id)
    guard !settings.isIdentity else { return }
    let index=document.layers.firstIndex{$0.id == id}!,original=document.layers[index]
    guard original.smartObject == nil,case .raster(let source)=original.content else { throw CraftError.invalid("Smart Objects require the retained Puppet filter path.") }
    let placed=try WarpRaster.mapping(WarpDefinition(),width:source.width,height:source.height,transform:original.coordinateTransform)
    let layer=try WarpRaster.baked(original,in:document,using:placed,method:settings.interpolation)
    guard case .raster(let pixels)=layer.content else { return }
    let origin=PathPoint(Double(layer.x),Double(layer.y)),deformation=try deform(pixels,origin:origin,settings:settings)
    guard !deformation.mesh.vertices.isEmpty else { return }
    let map=try mapping(deformation,origin:origin)
    document.layers[index]=try WarpRaster.baked(layer,in:document,using:map,method:settings.interpolation,clampEdges:false)
  }
  public static func union(_ a:IntRect,_ b:IntRect) throws -> IntRect {
    let x=min(a.x,b.x),y=min(a.y,b.y),w=max(a.x+a.width,b.x+b.width)-x,h=max(a.y+a.height,b.y+b.height)-y
    guard w>0,h>0,w<=60000,h<=60000,w<=WarpRaster.maximumPixels/h else { throw CraftError.unsupported("Puppet filter extent exceeds8,388,608 pixels.") };return IntRect(x:x,y:y,width:w,height:h)
  }
  /// Integer framing preserves every working-depth sample without resampling.
  public static func reframe(_ source:Surface,from:IntRect,to:IntRect) throws -> Surface {
    if from == to { return source }
    var result=try Surface(width:to.width,height:to.height,depth:source.depth,colorEncoding:source.colorEncoding)
    for y in 0..<source.height { try Task.checkCancellation();for x in 0..<source.width {
      let xx=from.x+x-to.x,yy=from.y+y-to.y
      if xx>=0,yy>=0,xx<to.width,yy<to.height {
        if source.depth == .f32 { result.setLinearPixel(x:xx,y:yy,source.linearPixel(x:x,y:y)) } else { result.setPixel(x:xx,y:yy,source.pixel(x:x,y:y)) }
      }
    } };return result
  }
}
extension SmartFilterStack {
  public mutating func transformPuppetPins(_ delta:Transform2D) {
    for i in filters.indices { if let settings=filters[i].filter.puppet { filters[i].filter.puppet=settings.transformed(delta) } }
  }
}
