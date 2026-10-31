import XCTest
@testable import PhotoCraftCore

final class ModernAdjustmentTests:XCTestCase {
  func testDefaultsControlsIdentityAndMalformedValues() throws {
    let p=Pixel(1.25,-0.125,0.35,0.5),hidden=Pixel(0.8,0.1,0.4,0)
    for kind in ModernAdjustment.Kind.allCases {
      let a=ModernAdjustment(kind);try a.validate();XCTAssertTrue(a.isIdentity)
      XCTAssertEqual(Set(a.values.keys),Set(kind.keys))
      XCTAssertEqual(ModernAdjustmentTransfer(a).apply(p,x:4097,y:99),p)
      XCTAssertEqual(ModernAdjustmentTransfer(a).apply(hidden,x:0,y:0),hidden)
      var bad=a;bad.values["unknown"]=1;XCTAssertThrowsError(try bad.validate())
      bad=a;bad.values[kind.keys[0]] = .nan;XCTAssertThrowsError(try bad.validate())
      bad=a;bad.values[kind.keys[0]]=1000;XCTAssertThrowsError(try bad.validate())
    }
    var light=try CraftDocument(width:5,height:5,depth:.f32)
    XCTAssertThrowsError(try ModernAdjustment(.light).validate(in:light))
    light=try CraftDocument(width:300_000,height:300_000)
    var spatial=ModernAdjustment(.clarityDehaze);spatial.values["clarity"]=10
    XCTAssertThrowsError(try spatial.validate(in:light))
    XCTAssertThrowsError(try Adjustment.modern(spatial).spatialEvaluator(depth:.u8))
  }
  func testPointwiseTransfersMatchExistingNativeRawPipelineWithoutRewritingReferences() throws {
    var source=try Surface(width:13,height:9,depth:.f32)
    for y in 0..<9 {for x in 0..<13 {source.setPixel(x:x,y:y,Pixel(Float(x+1)/15,Float(y+1)/11,Float(x+y+1)/24,0.75))}}
    for kind in [ModernAdjustment.Kind.colorVibrance,.light,.grain] {
      var a=ModernAdjustment(kind)
      switch kind {
      case .colorVibrance:a.values["temperature"]=25;a.values["tint"] = -13;a.values["vibrance"]=37;a.values["saturation"] = -9
      case .light:a.values["exposure"]=0.25;a.values["contrast"]=18;a.values["whites"]=12;a.values["blacks"] = -7
      case .grain:a.values["grainAmount"]=43;a.values["grainSize"]=34;a.values["grainRoughness"]=61;a.seed=194
      default:break
      }
      let expected=try CameraRawEngine.develop(source,settings:a.settings),transfer=ModernAdjustmentTransfer(a)
      for y in 0..<9 {for x in 0..<13 {
        XCTAssertEqual(transfer.apply(source.pixel(x:x,y:y),x:x,y:y),expected.pixel(x:x,y:y),"\(kind) at\(x),\(y)")
      }}
    }
  }
  func testSelectionMasksNative65HistoryAndSpatialApply() throws {
    for kind in ModernAdjustment.Kind.allCases {
      var original=try CraftDocument(width:17,height:11)
      var pixels=try Surface(width:17,height:11,fill:Pixel(0.3,0.5,0.7))
      pixels.setPixel(x:5,y:5,Pixel(0.8,0.2,0.1))
      original.layers[0].content = .raster(pixels);original.selection = .init(x:3,y:2,width:5,height:4)
      var value=ModernAdjustment(kind)
      value.values[kind.keys[0]]=kind == .light ? 0.5:35
      var session=EditorSession(document:original)
      let added=try value.layer(in:original)
      XCTAssertEqual(added.mask?.pixel(x:0,y:0),.black);XCTAssertEqual(added.mask?.pixel(x:4,y:3),.white)
      try session.execute(.addLayer(added))
      XCTAssertEqual(session.document.minimumArchiveVersion,65)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document,minimumVersion:65)),session.document)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(session.document)),session.document)
      try session.undo();XCTAssertEqual(session.document,original)
      try session.execute(.applyAdjustment(original.layers[0].id,.modern(value)))
      guard case .raster(let result)=session.document.layers[0].content else {return XCTFail("Missing raster")}
      XCTAssertEqual(result.pixel(x:0,y:0),pixels.pixel(x:0,y:0))
      let developed=try CameraRawEngine.develop(pixels,settings:value.settings)
      var changed=0
      for y in 0..<11 {for x in 0..<17 {
        let selected=(3..<8).contains(x) && (2..<6).contains(y)
        XCTAssertEqual(result.pixel(x:x,y:y),selected ? developed.pixel(x:x,y:y):pixels.pixel(x:x,y:y),"\(kind) selection at\(x),\(y)")
        if selected,result.pixel(x:x,y:y) != pixels.pixel(x:x,y:y) {changed += 1}
      }}
      XCTAssertGreaterThan(changed,0,"\(kind) selected pixels must change")
      try session.undo();XCTAssertEqual(session.document,original)
    }
  }
}
