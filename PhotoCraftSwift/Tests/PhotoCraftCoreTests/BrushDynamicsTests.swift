import XCTest
@testable import PhotoCraftCore

final class BrushDynamicsTests:XCTestCase {
  func brush()->Brush { var b=Brush();b.size=10;b.hardness=1;b.color=Pixel(1,0,0);b.settings=BrushSettings();return b }
  func testBrushTilePublicationMatchesIndividualSettersInOwnedAndPagedStorage() throws {
    let scratch = try RasterTileStore()
    let formats: [(PixelDepth,SurfaceColorEncoding)] = [
      (.u8,.sRGB),(.u16,.sRGB),(.f32,.sRGB),(.f32,.linearRGB)
    ]
    for (depth,encoding) in formats {
      var original = try Surface(width:70,height:72,depth:depth,colorEncoding:encoding)
      original.setLinearPixel(x:67,y:66,Pixel(-0.0,0.187_331,2.6,0))
      original.setLinearPixel(x:66,y:67,Pixel(0.713_337,-0.0,1.42,1))
      let implicit = try Surface(width:70,height:72,depth:depth,fill:Pixel(0.31,0.74,0.02,0.43),colorEncoding:encoding)
      let inputs = try [original,original.spillingTiles(to:scratch),implicit]
      for source in inputs {
        var expected = source, actual = source
        let storedView = source.pixel(x:67,y:66)
        let first = Pixel(storedView.r,0.4,storedView.b,0.81)
        let second = Pixel(0.1,0.23,0.334,1)
        expected.setPixel(x:67,y:66,first)
        expected.setPixel(x:69,y:70,second)
        var coverage = [Float](repeating:0,count:4096)
        coverage[2*64+3] = 1
        coverage[6*64+5] = 0.2
        // Weight on padding must be ignored.
        coverage[63*64+63] = 1
        actual.updateBrushTile(3,coverage:coverage) { x,y,_,weight,encoded in
          XCTAssertTrue(encoded.hasSameBits(as:source.pixel(x:x,y:y)))
          return weight == 1 ? first : second
        }
        XCTAssertTrue(actual == expected)
        XCTAssertTrue(actual.linearPixel(x:66,y:67).hasSameBits(as:source.linearPixel(x:66,y:67)))
        XCTAssertTrue(actual.linearPixel(x:67,y:66).hasSameBits(as:expected.linearPixel(x:67,y:66)))
        XCTAssertEqual(actual.tileCount,expected.tileCount)
        XCTAssertEqual(actual.mappedTileCount,expected.mappedTileCount)
      }
    }
  }
  func testMaximumDiameterPaintsFullColorCoverageAcrossBands() throws {
    var value = brush()
    value.size = 5_000
    value.settings!.colorDynamics.enabled = true
    var surface = try Surface(width:5_408,height:5_408,fill:.clear)
    try Painter.stroke(surface:&surface,points:[.init(x:2700.5,y:2700.5)],brush:value)

    for boundary in [1024,2048,3072,4096] {
      for offset in [-1,0,1] {
        XCTAssertEqual(surface.pixel(x:boundary+offset,y:2700),value.color)
        XCTAssertEqual(surface.pixel(x:2700,y:boundary+offset),value.color)
      }
    }
    XCTAssertEqual(surface.pixel(x:199,y:2700),.clear)
    XCTAssertEqual(surface.pixel(x:200,y:2700).a,128/255,accuracy:1/255)
    XCTAssertEqual(surface.pixel(x:5200,y:2700).a,128/255,accuracy:1/255)
    XCTAssertEqual(surface.pixel(x:5201,y:2700),.clear)
    XCTAssertEqual(surface.pixel(x:300,y:300),.clear)
    XCTAssertGreaterThan(surface.tileCount * 4096 * 20,128*1024*1024)
  }

  func testWideBrushMatchesUnbandedScaledCoverageAndKeepsWorkAtomic() throws {
    var wide = brush()
    wide.size = 5_000
    wide.opacity = 0.73
    wide.settings!.aliased = true
    wide.settings!.spacing = 0.2
    wide.settings!.flow = 0.42
    wide.settings!.colorDynamics.enabled = true
    wide.settings!.colorDynamics.brightness = 0.2
    var small = wide
    small.size /= 4
    let points = [StrokePoint(x:760,y:52),.init(x:1890,y:52)]
    let scaled = points.map { StrokePoint(x:$0.x*4,y:$0.y*4) }
    let selected = IntRect(x:650,y:28,width:1670,height:48)
    let selectedScaled = IntRect(x:selected.x*4,y:selected.y*4,width:selected.width*4,height:selected.height*4)
    var source = try Surface(width:2560,height:112,fill:.clear)
    var expected = source
    try Painter.stroke(surface:&expected,points:points,brush:small,selection:selected)
    try Painter.stroke(surface:&source,points:scaled,brush:wide,selection:selectedScaled,transform:.scale(4,4))
    XCTAssertTrue(source == expected)

    let original = try Surface(width:80_000,height:20_000,fill:.clear)
    var rejected = original
    let overBudget = [StrokePoint(x:7000,y:7000),.init(x:43_000,y:7000)]
    XCTAssertThrowsError(try Painter.stroke(surface:&rejected,points:overBudget,brush:wide))
    XCTAssertTrue(rejected == original)
    var legacy = wide
    legacy.settings = nil
    XCTAssertThrowsError(try Painter.stroke(surface:&rejected,points:[.init(x:7000,y:7000)],brush:legacy))
    XCTAssertTrue(rejected == original)
  }

  func testSettingsStaySmallAndSnapshotsKeepValueSemantics()throws {
    XCTAssertLessThan(MemoryLayout<Brush>.size,128)
    var a=brush();a.settings!.texture.enabled=true;a.settings!.texture.seed=UInt64.max
    var b=a;b.settings!.shape.size.jitter=0.6
    XCTAssertEqual(a.settings!.shape.size.jitter,0);XCTAssertEqual(b.settings!.shape.size.jitter,0.6)
    var surface=try Surface(width:24,height:24)
    XCTAssertNoThrow(try Painter.stroke(surface:&surface,points:[.init(x:12,y:12)],brush:a))
    XCTAssertEqual(try JSONDecoder().decode(Brush.self,from:JSONEncoder().encode(a)),a)
  }
  func testSpacingDirectionAndInputChunking() throws {
    var b=brush();b.settings!.spacing=1;b.settings!.shape.enabled=true;b.settings!.shape.angle.control = .direction
    let points:[StrokePoint]=[.init(x:5,y:20),.init(x:25,y:20),.init(x:25,y:40)]
    var g=BrushDabGenerator(b);var all=try g.push(points).0;all += try g.finish().0
    XCTAssertEqual(all.count,5);XCTAssertEqual(all.map(\.x),[5,15,25,25,25]);XCTAssertEqual(all.map(\.y),[20,20,20,30,40]);XCTAssertEqual(all.last!.angle,-Double.pi/2,accuracy:1e-10)
    b.settings!.scattering.enabled=true;b.settings!.scattering.amount.jitter=2;b.settings!.scattering.count=3;b.settings!.shape.size.jitter=0.5;b.settings!.colorDynamics.enabled=true;b.settings!.colorDynamics.hue=0.8
    var full=BrushDabGenerator(b),chunked=BrushDabGenerator(b);var expected=try full.push(points).0;expected += try full.finish().0;var actual:[BrushDab]=[]
    for p in points { actual += try chunked.push([p]).0 };actual += try chunked.finish().0
    XCTAssertEqual(actual.count,expected.count)
    for (a,e) in zip(actual,expected) { XCTAssertEqual(a.x,e.x);XCTAssertEqual(a.y,e.y);XCTAssertEqual(a.radius,e.radius);XCTAssertEqual(a.color,e.color) }
    b.settings!.seed=43;var other=BrushDabGenerator(b);XCTAssertNotEqual(try other.push(points).0.map(\.x),expected.map(\.x))
  }
  func testFlowAccumulationOpacityCeilingAndAllDepths() throws {
    for depth in PixelDepth.allCases {
      var b=brush();b.opacity=0.5;b.settings!.flow=0.25;b.settings!.buildUp=true;b.settings!.buildUpRate=20
      var surface=try Surface(width:32,height:32,depth:depth)
      try Painter.stroke(surface:&surface,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:100)],brush:b)
      XCTAssertEqual(surface.pixel(x:16,y:16).a,Float((1-pow(0.75,3))*0.5),accuracy:depth == .u8 ? 1/255:0.0001)
      try Painter.stroke(surface:&surface,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:1000)],brush:b)
      XCTAssertGreaterThan(surface.pixel(x:16,y:16).a,0.6)
      b.settings!.flow=1;var one=try Surface(width:32,height:32,depth:depth)
      try Painter.stroke(surface:&one,points:[.init(x:16.5,y:16.5,time:0),.init(x:16.5,y:16.5,time:1000)],brush:b)
      XCTAssertEqual(one.pixel(x:16,y:16).a,0.5,accuracy:1/255)
    }
  }
  func testSampledTipRotationTextureDualAndSymmetry() throws {
    var b=brush();b.size=8;b.settings!.tip=BrushBitmap(width:4,height:2,bytes:Data([255,255,0,0,255,255,0,0]))
    var s=try Surface(width:40,height:32)
    try Painter.stroke(surface:&s,points:[.init(x:10,y:16)],brush:b)
    XCTAssertGreaterThan(s.pixel(x:7,y:16).a,0.9);XCTAssertEqual(s.pixel(x:12,y:16).a,0)
    b.settings!.flipX=true;var flipped=try Surface(width:40,height:32);try Painter.stroke(surface:&flipped,points:[.init(x:10,y:16)],brush:b)
    XCTAssertEqual(flipped.pixel(x:7,y:16).a,0);XCTAssertGreaterThan(flipped.pixel(x:12,y:16).a,0.9)
    b=brush();b.settings!.symmetry.mode = .vertical;b.settings!.symmetry.center = .init(20,16)
    var mirror=try Surface(width:40,height:32);try Painter.stroke(surface:&mirror,points:[.init(x:8,y:16)],brush:b)
    XCTAssertGreaterThan(mirror.pixel(x:8,y:16).a,0.9);XCTAssertGreaterThan(mirror.pixel(x:32,y:16).a,0.9);XCTAssertEqual(mirror.pixel(x:20,y:16).a,0)
    b.settings!.symmetry.mode = .off;b.settings!.dual.enabled=true;b.settings!.dual.size=2
    var dual=try Surface(width:40,height:32);try Painter.stroke(surface:&dual,points:[.init(x:20,y:16)],brush:b)
    XCTAssertEqual(dual.pixel(x:23,y:16).a,0);XCTAssertEqual(dual.pixel(x:20,y:16).a,Float(1.5-sqrt(0.5)),accuracy:1/255)
    b.settings!.dual.enabled=false;b.settings!.texture.enabled=true;b.settings!.texture.bitmap = .init(width:1,height:1,bytes:Data([128]))
    var texture=try Surface(width:40,height:32);try Painter.stroke(surface:&texture,points:[.init(x:20,y:16)],brush:b)
    XCTAssertEqual(texture.pixel(x:20,y:16).a,128/255,accuracy:1/255)
  }
  func testSelectionAffineLocksMaskAndHistory() throws {
    var b=brush();b.size=12;b.settings!.mode = .multiply
    var surface=try Surface(width:32,height:32,fill:Pixel(0.5,0.5,0.5,0.4));let before=surface
    try Painter.stroke(surface:&surface,points:[.init(x:30,y:20)],brush:b,selection:IntRect(x:30,y:0,width:32,height:32),transform:.translation(10,0),preserveTransparency:true)
    XCTAssertEqual(surface.pixel(x:19,y:20),before.pixel(x:19,y:20));XCTAssertEqual(surface.pixel(x:20,y:20).a,before.pixel(x:20,y:20).a);XCTAssertLessThan(surface.pixel(x:20,y:20).g,0.01)
    b.settings!.mode = .normal;b.settings!.colorDynamics.enabled=true;b.settings!.colorDynamics.hue=0.8
    var mask=try Surface(width:32,height:32,fill:.white);try Painter.stroke(surface:&mask,points:[.init(x:16,y:16)],brush:b,grayscaleMask:true)
    let p=mask.pixel(x:16,y:16);XCTAssertEqual(p.r,p.g);XCTAssertEqual(p.g,p.b);XCTAssertEqual(p.a,1)
    let doc=try CraftDocument(width:32,height:32);var session=EditorSession(document:doc)
    try session.execute(.stroke(doc.layers[0].id,[.init(x:16,y:16)],b));let changed=session.document;XCTAssertNotEqual(changed,doc);try session.undo();XCTAssertEqual(session.document,doc);try session.redo();XCTAssertEqual(session.document,changed)
  }
  func testLegacyDecodingInvalidAtomicityAndSettingsRoundtrip() throws {
    let legacy=Data(#"{"size":12,"hardness":1,"opacity":1,"color":{"r":1,"g":0,"b":0,"a":1},"erase":false}"#.utf8)
    let b=try JSONDecoder().decode(Brush.self,from:legacy);XCTAssertNil(b.settings)
    let p=try JSONDecoder().decode(StrokePoint.self,from:Data(#"{"x":3,"y":4,"pressure":0.5}"#.utf8));XCTAssertNil(p.time);XCTAssertNil(p.tiltX)
    var modern=brush();modern.settings!.tip = .init(width:1,height:1,bytes:Data([255]));modern.settings!.pose.enabled=true;modern.settings!.pose.overridePressure=true;modern.settings!.pose.pressure=0.25
    XCTAssertEqual(try JSONDecoder().decode(Brush.self,from:JSONEncoder().encode(modern)),modern)
    var s=try Surface(width:32,height:32);let original=s;modern.settings!.spacing=0
    XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[p],brush:modern));XCTAssertEqual(s,original)
    modern=brush();XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[.init(x:8,y:8,time:20),.init(x:10,y:10,time:10)],brush:modern));XCTAssertEqual(s,original)
    modern.settings!.buildUp=true;modern.settings!.buildUpRate=1000
    XCTAssertThrowsError(try Painter.stroke(surface:&s,points:[.init(x:8,y:8,time:0),.init(x:8,y:8,time:3_600_000)],brush:modern));XCTAssertEqual(s,original)
  }
  func testSmoothingPressureAndLockedPresetSections() throws {
    var b=brush();b.settings!.smoothing.amount=0.5;b.settings!.smoothing.pulledString=true;b.settings!.smoothing.catchUpOnEnd=false;b.settings!.pressureSize=true
    var g=BrushDabGenerator(b);let dabs=try g.push([.init(x:0,y:0),.init(x:20,y:0),.init(x:100,y:0,pressure:0.5)]).0
    XCTAssertLessThanOrEqual(dabs.last!.x,50.0001);XCTAssertEqual(dabs.last!.radius,5*(1-dabs.last!.x/100),accuracy:0.00001)
    var current=BrushSettings(),preset=BrushSettings();current.shape.enabled=true;current.shape.size.jitter=0.7;current.lockedSections=["shape"];current.protectTexture=true;current.texture.scale=2;preset.texture.enabled=true
    let picked=preset.picked(over:current);XCTAssertEqual(picked.shape,current.shape);XCTAssertEqual(picked.texture.scale,2)
  }
}
