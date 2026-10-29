import XCTest
@testable import PhotoCraftCore

final class PaintToolTests: XCTestCase {
  let green=Pixel(0.2,0.6,0.2),blue=Pixel(0.1,0.1,0.5)
  func document(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:80,height:40,depth:depth)
    var s=try Surface(width:80,height:40,depth:depth,fill:green)
    for y in 0..<40 {for x in 40..<80 {s.setPixel(x:x,y:y,blue)}}
    d.layers[0].content = .raster(s);return d
  }
  func pixels(_ d:CraftDocument)->Surface {if case .raster(let s)=d.layers.last!.content{return s};fatalError()}
  func request(_ tool:PaintTool,_ d:CraftDocument)->PaintToolRequest {
    var b=Brush();b.size=12;b.hardness=1;b.color=Pixel(1,0,0);b.backgroundColor = .white;b.settings = .init();b.settings!.pressureSize=false;b.settings!.spacing=0.25
    return .init(tool:tool,target:.pixels(d.layers[0].id),points:[.init(x:20,y:20),.init(x:60,y:20)],brush:b)
  }
  func testPencilAliasingAutoEraseSelectionAndAutomaticLayer()throws {
    var d=try document();var r=request(.pencil,d);r.brush.size=1;r.points=[.init(x:20,y:20),.init(x:25,y:20)];r.brush.color=green;r.options.autoErase=true
    let e=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(pixels(e.result).pixel(x:22,y:20),.white);XCTAssertEqual(pixels(e.result).pixel(x:22,y:19),pixels(d).pixel(x:22,y:19))
    d.selection = .init(x:0,y:0,width:22,height:40)
    let limited=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(pixels(limited.result).pixel(x:23,y:20),pixels(d).pixel(x:23,y:20))
    d.layers[0].content = .fill(green);let created=try PaintingEdit.prepare(r,in:d)
    XCTAssertEqual(created.result.layers.count,2);XCTAssertEqual(created.result.layers[0],d.layers[0]);XCTAssertEqual(created.result.activeLayerID,r.newLayerID)
    var session=EditorSession(document:d);try session.execute(.painting(created));XCTAssertEqual(session.document,created.result);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,created.result)
  }
  func testColorReplacementSamplingConnectivityAndAlpha()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let d=try document(depth);var r=request(.colorReplacement,d);r.options.sampling = .once;r.options.limits = .discontiguous;r.options.tolerance=0.05
      let once=pixels(try PaintingEdit.prepare(r,in:d).result);XCTAssertGreaterThan(once.pixel(x:20,y:20).r,0.4);XCTAssertEqual(once.pixel(x:60,y:20),pixels(d).pixel(x:60,y:20));XCTAssertEqual(once.pixel(x:20,y:20).a,1)
      r.options.sampling = .continuous;let all=pixels(try PaintingEdit.prepare(r,in:d).result);XCTAssertGreaterThan(all.pixel(x:60,y:20).r,all.pixel(x:60,y:20).b)
    }
    var d=try document();var s=pixels(d);for y in 0..<40 {s.setPixel(x:24,y:y,blue)};d.layers[0].content = .raster(s)
    var r=request(.colorReplacement,d);r.brush.size=24;r.points=[.init(x:20,y:20)];r.options.tolerance=0.05;r.options.limits = .contiguous
    XCTAssertEqual(pixels(try PaintingEdit.prepare(r,in:d).result).pixel(x:27,y:20),s.pixel(x:27,y:20))
    r.options.limits = .discontiguous;XCTAssertNotEqual(pixels(try PaintingEdit.prepare(r,in:d).result).pixel(x:27,y:20),s.pixel(x:27,y:20))
  }
  func testBackgroundEraserSamplingProtectionAndBackgroundConversion()throws {
    var d=try document();var r=request(.backgroundEraser,d);r.options.sampling = .once;r.options.limits = .discontiguous;r.options.tolerance=0.05;r.brush.opacity=0
    let erased=pixels(try PaintingEdit.prepare(r,in:d).result);XCTAssertEqual(erased.pixel(x:20,y:20).a,0);XCTAssertEqual(erased.pixel(x:60,y:20).a,1)
    r.brush.color=green;r.options.protectForeground=true;XCTAssertEqual(try PaintingEdit.prepare(r,in:d).result,d)
    r.options.protectForeground=false;d.layers[0].protection=[.transparency,.position]
    let e=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(e.result.layers[0].name,"Layer 0");XCTAssertFalse(e.result.layers[0].protection.locksTransparency)
    d.layers[0].name="Protected";XCTAssertThrowsError(try PaintingEdit.prepare(r,in:d))
    d.layers[0].name="Background";d.layers[0].protection.insert(.image);XCTAssertThrowsError(try PaintingEdit.prepare(r,in:d))
  }
  func testMagicEraserRegionOpacityAndAllLayerSample()throws {
    let d=try document();var r=request(.magicEraser,d);r.points=[.init(x:20,y:20)];r.options.antiAlias=false;r.options.tolerance=0;r.brush.opacity=0.5
    let e=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(pixels(e.result).pixel(x:10,y:10).a,128.0/255,accuracy:0.004);XCTAssertEqual(pixels(e.result).pixel(x:60,y:20),pixels(d).pixel(x:60,y:20))
    r.options.sampleAllLayers=true;let sample=try Surface(width:80,height:40,fill:green)
    XCTAssertThrowsError(try PaintingEdit.prepare(r,in:d));XCTAssertLessThan(pixels(try PaintingEdit.prepare(r,in:d,sample:sample).result).pixel(x:60,y:20).a,0.6)
    r.points=[.init(x:-1,y:20)];XCTAssertEqual(try PaintingEdit.prepare(r,in:d).result,d)
  }
  func testMixerReservoirDecayWetPickupAndAtomicResult()throws {
    var d=try document();d.layers[0].content = .raster(try Surface(width:80,height:40))
    var r=request(.mixerBrush,d);r.options.wet=0;r.options.mix=0;r.options.load=0;r.options.cleanAfterStroke=false;r.options.loadAfterStroke=false;r.mixer.load(Pixel(1,0,0));r.points=[.init(x:4,y:20),.init(x:76,y:20)]
    let dry=try PaintingEdit.prepare(r,in:d);XCTAssertLessThan(dry.session.mixer.amount,0.2);XCTAssertGreaterThan(pixels(dry.result).pixel(x:10,y:20).a,pixels(dry.result).pixel(x:70,y:20).a)
    r.options.load=1;let full=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(full.session.mixer.amount,1,accuracy:0.00001)
    d=try document();r.target = .pixels(d.layers[0].id);r.options.wet=1;r.options.mix=1;r.mixer.clean();let wet=try PaintingEdit.prepare(r,in:d);XCTAssertNotNil(wet.session.mixer.pickup);XCTAssertNotEqual(wet.result,d)
    r.options.wet=0;XCTAssertEqual(try PaintingEdit.prepare(r,in:d).result,d)
  }
  func testPatternStampPlacementImpressionistAndTransparency()throws {
    var tile=try Surface(width:4,height:4,fill:Pixel(1,0,0));for y in 0..<4 {for x in 2..<4 {tile.setPixel(x:x,y:y,Pixel(0,0,1))}}
    var d=try document();d.layers[0].content = .raster(try Surface(width:80,height:40));var r=request(.patternStamp,d);r.pattern=try RasterPattern(name:"Original stripes",surface:tile);r.brush.size=12
    let precise=try PaintingEdit.prepare(r,in:d);XCTAssertNotEqual(pixels(precise.result).pixel(x:20,y:20),pixels(precise.result).pixel(x:22,y:20))
    r.options.impressionist=true;XCTAssertNotEqual(try PaintingEdit.prepare(r,in:d).result,precise.result)
    d.layers[0].protection = .transparency;XCTAssertEqual(try PaintingEdit.prepare(r,in:d).result,d)
  }
  func testMaskChannelAndRejectedStaleRequests()throws {
    var d=try document();try Command.createMask(d.layers[0].id,.revealAll).apply(to:&d)
    var r=request(.pencil,d);r.target = .layerMask(d.layers[0].id);r.brush.color = .black
    let e=try PaintingEdit.prepare(r,in:d);XCTAssertEqual(e.result.layers[0].mask!.pixel(x:20,y:20).r,0);XCTAssertEqual(e.result.layers[0].content,d.layers[0].content)
    var changed=d;changed.name="changed";XCTAssertThrowsError(try e.applied(to:changed))
    let channel=AlphaChannel(name:"Alpha",pixels:try Surface(width:80,height:40,fill:.white));try Command.channel(.create(channel)).apply(to:&d);r.target = .channel(.alpha(channel.id))
    XCTAssertEqual(try PaintingEdit.prepare(r,in:d).result.channel(.alpha(channel.id)).pixels.pixel(x:20,y:20).r,0)
    r.options.tolerance = .nan;XCTAssertThrowsError(try PaintingEdit.prepare(r,in:d))
    r.options.tolerance=0;r.tool = .backgroundEraser;XCTAssertThrowsError(try PaintingEdit.prepare(r,in:d))
  }
  func testTransformedPixelTargetSelectionAlphaAndNoop()throws {
    var d=try document(.u16);d.layers[0].content = .raster(try Surface(width:16,height:16,depth:.u16,fill:Pixel(0.2,0.6,0.2,0.4)))
    d.layers[0].x=10;d.layers[0].y=6;d.layers[0].affine = .scale(2,2);d.layers[0].protection = .transparency
    d.selection = .init(x:15,y:0,width:10,height:40)
    var r=request(.pencil,d);r.brush.size=20;r.points=[.init(x:22,y:20)];let before=pixels(d)
    let painted=pixels(try PaintingEdit.prepare(r,in:d).result)
    XCTAssertGreaterThan(painted.pixel(x:5,y:6).r,0.9);XCTAssertEqual(painted.pixel(x:5,y:6).a,before.pixel(x:5,y:6).a)
    XCTAssertEqual(painted.pixel(x:9,y:6),before.pixel(x:9,y:6))
    r.brush.opacity=0;XCTAssertTrue(try PaintingEdit.prepare(r,in:d).result==d)
    r.tool = .magicEraser;r.points=[.init(x:22,y:20)];r.brush.opacity=1;r.options.tolerance=0;r.options.antiAlias=false
    let erased=pixels(try PaintingEdit.prepare(r,in:d).result);XCTAssertEqual(erased.pixel(x:5,y:6).a,before.pixel(x:5,y:6).a);XCTAssertGreaterThan(erased.pixel(x:5,y:6).r,0.9)
  }
}
