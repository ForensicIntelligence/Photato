import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class LiveShapeTests:XCTestCase {
  func testParametricPrimitivesAndValidation()throws{
    for kind in ShapeGeometry.Kind.allCases where kind != .custom {
      var g=ShapeGeometry(kind:kind,width:60,height:40);g.radii=[5,10,15,20];g.cornerRadius=3;g.arrowStart=true;g.arrowEnd=true
      let d=ShapeDefinition(geometry:g);try d.validate();XCTAssertFalse(try ShapeRenderer.outline(d).isEmpty)
      XCTAssertGreaterThan(try d.renderBounds().width,0)
    }
    var star=ShapeGeometry(kind:.star);XCTAssertEqual(try star.path().knotCount,10);star.sides=100;XCTAssertEqual(try star.path().knotCount,200)
    star.sides=101;XCTAssertThrowsError(try star.validate());star.sides=5;star.width = .nan;XCTAssertThrowsError(try star.validate())
    var rectangle=ShapeGeometry(width:10,height:10);rectangle.radii=[100,100,100,100]
    let p=try rectangle.path();XCTAssertTrue(p.components.flatMap(\.knots).allSatisfy{(0...10).contains($0.anchor.x) && (0...10).contains($0.anchor.y)})
    var line=ShapeGeometry(kind:.line,width:60,height:0);line.arrowEnd=true;XCTAssertEqual(try line.path().components.count,2)
  }
  func testCompoundPathsStrokeEdgesAndDepths()throws{
    for depth in PixelDepth.allCases {
      var document=try CraftDocument(width:80,height:80,depth:depth)
      var definition=ShapeDefinition(geometry:.init(width:40,height:40),fill:.init(color:Pixel(1,0,0)))
      definition.components.append(.init(geometry:.init(kind:.ellipse,width:20,height:20),transform:.translation(10,10),operation:.subtract))
      definition.stroke.paint = .init(color:Pixel(0,0,1));definition.stroke.width=4;definition.stroke.alignment = .outside
      try Command.shape(.create("Compound",definition,.translation(15,15))).apply(to:&document)
      let image=try Renderer.layerSurface(document.layers.last!,in:document),layer=document.layers.last!,inverse=try layer.coordinateTransform.inverted()
      func sample(_ x:Double,_ y:Double)->Pixel{let p=inverse.point(x,y);return image.pixel(x:Int(p.x),y:Int(p.y))}
      XCTAssertGreaterThan(sample(14,25).b,0.9);XCTAssertGreaterThan(sample(18,25).r,0.9);XCTAssertEqual(sample(35,35).a,0)
      XCTAssertEqual(document.minimumArchiveVersion,33);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)),document)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)),document)
      let vector=try ShapeRenderer.vectorPath(definition);XCTAssertFalse(vector.isEmpty)
      var repeated=definition;repeated.components=[.init(geometry:.init(kind:.custom,width:1,height:1))];repeated.components[0].geometry.customPath=vector.transformed(.scale(0.01,0.01));repeated.components[0].geometry.width=100;repeated.components[0].geometry.height=100
      let original=try ShapeRenderer.outline(definition),copy=try ShapeRenderer.outline(repeated)
      XCTAssertEqual(original.contains(.init(x:20,y:20)),copy.contains(.init(x:20,y:20)))
    }
  }
  func testGeometryConfigurationPreservesPlacementMasksUndoAndActions()throws{
    let original=try CraftDocument(width:100,height:80);var session=EditorSession(document:original)
    var definition=ShapeDefinition(geometry:.init(kind:.star,width:35,height:25))
    let create=Command.shape(.create("Star",definition,.translation(20,20)));let operation=ActionOperation(recording:create,in:original)
    try session.execute(create);let first=session.document,id=first.activeLayerID!,origin=try first.layers.last!.shapeTransform()
    definition.stroke.paint = .init();definition.stroke.width=12;definition.stroke.alignment = .outside
    try session.execute(.shape(.configure(id,definition)));XCTAssertEqual(try session.document.layers.last!.shapeTransform(),origin)
    try session.undo();XCTAssertEqual(session.document,first);try session.redo();XCTAssertEqual(session.document.layers.last!.shape?.definition,definition)
    var replay=original;try operation.command(in:replay)!.apply(to:&replay);XCTAssertEqual(replay.layers.last!.shape?.definition,first.layers.last!.shape?.definition)
    var masked=session.document;try Command.mask(id,Surface(width:20,height:20,fill:.white)).apply(to:&masked);let oldMask=masked.layers.last!.maskCoordinateTransform
    definition.stroke.width=2;try Command.shape(.configure(id,definition)).apply(to:&masked);XCTAssertEqual(masked.layers.last!.maskCoordinateTransform,oldMask)
    try Command.lock(id,true).apply(to:&masked);XCTAssertThrowsError(try Command.shape(.configure(id,definition)).apply(to:&masked))
  }
  func testGradientPatternPathAndPixelOutputs()throws{
    var document=try CraftDocument(width:64,height:64)
    document.layers[0].content = .raster(try Surface(width:64,height:64))
    var definition=ShapeDefinition(geometry:.init(kind:.ellipse,width:30,height:30))
    definition.fill.kind = .gradient;definition.fill.gradient = .init();definition.fill.gradient?.dither=false
    try ShapeRenderer.creation(definition,name:"Path",placement:.translation(10,10),mode:.path,target:nil,document:document).apply(to:&document)
    XCTAssertEqual(document.paths?.count,1);XCTAssertEqual(document.layers.count,1)
    let id=document.activeLayerID!;try ShapeRenderer.creation(definition,name:"Pixels",placement:.translation(10,10),mode:.pixels,target:id,document:document).apply(to:&document)
    guard case .raster(let surface)=document.layers[0].content else{return XCTFail()};XCTAssertGreaterThan(surface.pixel(x:25,y:25).a,0);XCTAssertEqual(surface.pixel(x:0,y:0).a,0)
    var pixels=try Surface(width:2,height:2,fill:Pixel(0,1,0));pixels.setPixel(x:0,y:0,Pixel(0,0,1));let pattern=try RasterPattern(name:"Tiles",surface:pixels)
    let patternID=try document.installPattern(pattern);definition.fill.kind = .pattern;definition.fill.gradient=nil;definition.fill.pattern = .init(patternID:patternID)
    try Command.shape(.create("Pattern",definition,.translation(5,5))).apply(to:&document)
    XCTAssertGreaterThan(try Renderer.layerSurface(document.layers.last!,in:document).pixel(x:15,y:15).a,0)
    definition.stroke.dash=[0];XCTAssertThrowsError(try definition.validate())
  }
}
