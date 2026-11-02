import XCTest
@testable import PhotoCraftCore

final class ClassicAdjustmentTests: XCTestCase {
  func testKnownChannelAndBlackWhiteValuesPreserveAlpha() throws {
    var a = ClassicAdjustment(.channelMixer)
    a.matrix = [[0,100,0,0],[0,0,100,0],[100,0,0,0]]
    let p = Pixel(0.8,0.2,0.4,0.35), q = ClassicAdjustmentTransfer(a,depth:.u8).apply(p)
    XCTAssertEqual(q,Pixel(0.2,0.4,0.8,0.35))
    a.monochrome = true
    XCTAssertEqual(ClassicAdjustmentTransfer(a,depth:.u8).apply(p),Pixel(0.2,0.2,0.2,0.35))
    a = .init(.blackWhite)
    for (p,g): (Pixel,Float) in [(Pixel(1,0,0),0.4),(Pixel(1,1,0),0.6),(Pixel(0,0,1),0.2),(Pixel(0.5,0.5,0.5),0.5)] {
      XCTAssertEqual(ClassicAdjustmentTransfer(a,depth:.u8).apply(p).r,g,accuracy:1e-6)
    }
    a.tint = ClassicAdjustment.defaultTint
    let tinted = ClassicAdjustmentTransfer(a,depth:.u8).apply(Pixel(0.5,0.5,0.5))
    XCTAssertGreaterThan(tinted.r,tinted.b)
  }
  func testIdentityGrayProtectionSelectiveLocalityAndPhotoDensity() throws {
    for kind in [ClassicAdjustment.Kind.vibrance,.channelMixer,.selectiveColor] {
      let a = ClassicAdjustment(kind)
      for depth in PixelDepth.allCases { XCTAssertEqual(ClassicAdjustmentTransfer(a,depth:depth).apply(Pixel(1.4,-0.2,0.3,0.5)),Pixel(1.4,-0.2,0.3,0.5)) }
    }
    var v = ClassicAdjustment(.vibrance); v.vibrance = 100
    XCTAssertEqual(ClassicAdjustmentTransfer(v,depth:.u8).apply(Pixel(0.5,0.5,0.5)),Pixel(0.5,0.5,0.5))
    XCTAssertNotEqual(ClassicAdjustmentTransfer(v,depth:.u8).apply(Pixel(0.6,0.4,0.4)),Pixel(0.6,0.4,0.4))
    var s = ClassicAdjustment(.selectiveColor); s.relative = false; s.adjustments[0][0] = 100
    XCTAssertEqual(ClassicAdjustmentTransfer(s,depth:.u8).apply(Pixel(0.1,0.1,0.9)),Pixel(0.1,0.1,0.9))
    XCTAssertLessThan(ClassicAdjustmentTransfer(s,depth:.u8).apply(Pixel(0.9,0.1,0.1)).r,0.9)
    s = .init(.selectiveColor); s.adjustments[6][2] = 100
    XCTAssertEqual(ClassicAdjustmentTransfer(s,depth:.u8).apply(.white),.white)
    s.relative = false; XCTAssertEqual(ClassicAdjustmentTransfer(s,depth:.u8).apply(.white),Pixel(1,1,0))
    var f = ClassicAdjustment(.photoFilter); f.color = Pixel(1,0,0); f.density = 100; f.preserveLuminosity = false
    XCTAssertEqual(ClassicAdjustmentTransfer(f,depth:.u8).apply(Pixel(0.8,0.2,0.4)),Pixel(0.8,0,0))
  }
  func testSelectionsHistoryNative17AndMalformedSettings() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:3,height:2,depth:depth)
      d.layers[0].content = .raster(try Surface(width:3,height:2,depth:depth,fill:Pixel(0.8,0.2,0.4,0.5)))
      d.selection = IntRect(x:1,y:0,width:1,height:2)
      for kind in ClassicAdjustment.Kind.allCases {
        var v = ClassicAdjustment(kind); v.vibrance = 60; v.adjustments[0][0] = 30
        let layer = try v.layer(in:d)
        XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.black)
        XCTAssertEqual(layer.mask?.pixel(x:1,y:0),.white)
        var session = EditorSession(document:d)
        try session.execute(.addLayer(layer)); XCTAssertEqual(session.document.minimumArchiveVersion,kind == .exposure ? 67:17)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(session.document)),session.document)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document)
        var baked = d; try Command.applyAdjustment(d.layers[0].id,.classic(v)).apply(to:&baked)
        if case .raster(let surface) = baked.layers[0].content, case .raster(let original) = d.layers[0].content {
          XCTAssertEqual(surface.pixel(x:0,y:0),original.pixel(x:0,y:0))
          XCTAssertEqual(surface.pixel(x:1,y:0).a,original.pixel(x:1,y:0).a)
        }
      }
    }
    var invalid = ClassicAdjustment(.channelMixer); invalid.matrix = [[]]; XCTAssertThrowsError(try invalid.validate())
    invalid = .init(.blackWhite); invalid.weights = []; XCTAssertThrowsError(try invalid.validate())
    invalid = .init(.photoFilter); invalid.color = Pixel(.nan,0,0); XCTAssertThrowsError(try invalid.validate())
  }
  func testActionDescriptorsAndUnsupportedTargets() throws {
    let descriptors = [
      #"[{"_obj":"vibrance","vibrance":40,"saturation":-10}]"#,
      #"[{"_obj":"blackAndWhite","red":70,"useTint":false}]"#,
      #"[{"_obj":"photoFilter","color":{"_obj":"RGBColor","red":255,"grain":100,"blue":0},"density":50,"preserveLuminosity":false}]"#,
      #"[{"_obj":"channelMixer","monochromatic":true,"gray":{"_obj":"channelMatrix","red":40,"grain":40,"blue":20,"constant":0}}]"#,
      #"[{"_obj":"selectiveColor","method":{"_enum":"correctionMethod","_value":"absolute"},"colorCorrection":[{"_obj":"colorCorrection","colors":{"_enum":"colors","_value":"reds"},"cyan":30}]}]"#]
    var d = try CraftDocument(width:3,height:2)
    d.layers[0].content = .raster(try Surface(width:3,height:2,fill:Pixel(0.8,0.2,0.4)))
    for descriptor in descriptors {
      let program = try PhotoshopActionProgram(actionJSON:descriptor)
      guard case .adjustment(let v) = program.steps[0] else { return XCTFail() }
      var expected = d; try Command.applyAdjustment(d.layers[0].id,.classic(v)).apply(to:&expected)
      XCTAssertEqual(try program.applying(to:d).session.document,expected)
      XCTAssertThrowsError(try program.applying(to:d,components:.red))
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:#"[{"_obj":"vibrance","vibrance":true}]"#))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:#"[{"_obj":"vibrance","vibrance":101}]"#))
  }
}
