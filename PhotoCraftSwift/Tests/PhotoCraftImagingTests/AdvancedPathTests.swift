import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class AdvancedPathTests:XCTestCase {
  func testFreeformFitCurvatureAndBounds()throws{
    let line=(0...100).map{PathPoint(Double($0),20)},fit=try PathConstruction.fitted(line,tolerance:1)
    XCTAssertEqual(fit.knots.count,2);XCTAssertEqual(fit.knots.first?.anchor,line.first);XCTAssertEqual(fit.knots.last?.anchor,line.last)
    let circle=(0..<120).map{let a=Double($0)*2*Double.pi/120;return PathPoint(40+30*cos(a),40+30*sin(a))}
    let closed=try PathConstruction.fitted(circle,tolerance:1,closed:true);XCTAssertTrue(closed.closed);XCTAssertLessThan(closed.knots.count,30)
    let mask=try VectorRasterizer.coverage(.init(components:[closed]),width:80,height:80);XCTAssertEqual(mask.coverage(x:40,y:40),1);XCTAssertEqual(mask.coverage(x:2,y:2),0)
    let curve=try PathConstruction.curvature(.init(knots:[.init(.init(0,0),smooth:true),.init(.init(30,40),smooth:true),.init(.init(60,0),smooth:true)]))
    XCTAssertEqual(curve.knots[1].anchor,.init(30,40));XCTAssertLessThan(curve.knots[1].incoming.x,30);XCTAssertGreaterThan(curve.knots[1].outgoing.x,30)
    var corner=curve;corner.knots[1].smooth=false;corner=try PathConstruction.curvature(corner);XCTAssertEqual(corner.knots[1].incoming,corner.knots[1].anchor)
    XCTAssertThrowsError(try PathConstruction.fitted(line,tolerance:.nan));XCTAssertThrowsError(try PathConstruction.fitted([.init(0,0),.init(.infinity,0)],tolerance:2))
  }
  func testSelectionTraceHolesIslandsAndEmptyThreshold()throws{
    var bytes=[UInt8](repeating:0,count:80*60)
    for y in 5..<55{for x in 5..<65{bytes[y*80+x]=255}}
    for y in 20..<40{for x in 20..<45{bytes[y*80+x]=0}}
    for y in 25..<30{for x in 25..<30{bytes[y*80+x]=255}}
    let path=try PathTracing.trace(.init(width:80,height:60,bytes:bytes),tolerance:0.5)
    XCTAssertEqual(path.components.count,3);XCTAssertTrue(path.components.allSatisfy(\.closed))
    let mask=try VectorRasterizer.coverage(path,width:80,height:60)
    XCTAssertEqual(mask.coverage(x:10,y:10),1);XCTAssertEqual(mask.coverage(x:22,y:22),0);XCTAssertEqual(mask.coverage(x:27,y:27),1);XCTAssertEqual(mask.coverage(x:70,y:50),0)
    XCTAssertThrowsError(try PathTracing.trace(.init(width:10,height:10,bytes:[UInt8](repeating:127,count:100)),tolerance:2))
    var document=try CraftDocument(width:80,height:60);document.selection = .init(x:10,y:10,width:20,height:20);try PathTracing.command(document,tolerance:2).apply(to:&document);let id=document.paths!.first!.id;try PathTracing.command(document,tolerance:2).apply(to:&document);XCTAssertEqual(document.paths?.count,1);XCTAssertEqual(document.paths?.first?.id,id)
  }
  func testFillStrokeDepthsSelectionTransformPressureAndProtection()throws{
    for depth in PixelDepth.allCases {
      var document=try CraftDocument(width:64,height:64,depth:depth);document.layers[0].content = .raster(try Surface(width:50,height:50,depth:depth));document.layers[0].x=5;document.layers[0].y=5
      let id=document.activeLayerID!,path=VectorPath(components:[.init(knots:[.init(.init(10,10)),.init(.init(45,10)),.init(.init(45,45)),.init(.init(10,45))],closed:true)])
      var brush=Brush();brush.size=6;brush.color=Pixel(1,0,0);brush.hardness=1;brush.settings = .init()
      var filled=document;filled.selection = .init(x:0,y:0,width:30,height:64);try PathPainting.command(path,document:filled,layerID:id,brush:brush,stroke:false).apply(to:&filled)
      guard case .raster(let pixels)=filled.layers[0].content else{return XCTFail()};XCTAssertEqual(pixels.pixel(x:15,y:15).a,1);XCTAssertEqual(pixels.pixel(x:35,y:15).a,0)
      let open=VectorPath(components:[.init(knots:[.init(.init(10,30)),.init(.init(45,30))])]);try PathPainting.command(open,document:document,layerID:id,brush:brush,stroke:true,simulatePressure:true).apply(to:&document)
      guard case .raster(let stroke)=document.layers[0].content else{return XCTFail()};XCTAssertGreaterThan(stroke.pixel(x:22,y:25).a,0.9);XCTAssertEqual(stroke.pixel(x:22,y:15).a,0)
      try Command.lock(id,true).apply(to:&document);XCTAssertThrowsError(try PathPainting.command(path,document:document,layerID:id,brush:brush,stroke:true))
    }
  }
}
