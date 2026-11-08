import Foundation
import XCTest
@testable import PhotoCraftCore

final class HueRangeColorTests: XCTestCase {
  func value()->HueSaturationAdjustment {
    var value=HueSaturationAdjustment()
    value.ranges[0]=HueRange(bounds:[-8,22,52,82],displayColor:.init(hue:37,saturation:65,lightness:50))
    return value
  }
  func testLegacyMissingColorAndFactoryValuesKeepTheirSettingsAndVersion()throws {
    let legacy=Data("{\"values\":{\"hue\":0,\"saturation\":0,\"lightness\":0},\"bounds\":[-45,-15,15,45]}".utf8)
    let range=try JSONDecoder().decode(HueRange.self,from:legacy)
    XCTAssertEqual(range,HueRange.neutral(0));XCTAssertNil(range.displayColor)
    XCTAssertEqual(range.swatchColor,.init(hue:0,saturation:100,lightness:50))
    let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(range)) as! [String:Any]
    XCTAssertNil(encoded["displayColor"])
    var d=try CraftDocument(width:2,height:2);let original=d.minimumArchiveVersion
    d.layers.append(Layer(name:"Hue",content:.adjustment(.hueSaturation(.init()))))
    XCTAssertFalse(d.requiresHueRangeColorArchive);XCTAssertEqual(d.minimumArchiveVersion,original)
  }
  func testDisplayMetadataNeverChangesThePixelTransferAtAnyDepth()throws {
    let pixels:[Pixel]=[.black,.white,Pixel(0.1234567,0.7,0.2,0.25),Pixel(-0.0,1.2,-0.2,1),Pixel(0.2,0.4,0.8,0)]
    for depth in PixelDepth.allCases {for hue in [0,27] {
      var original=HueSaturationAdjustment();original.master.hue=hue;original.ranges[2].values.saturation=20
      var decorated=original;decorated.ranges[0].displayColor = .init(hue:37,saturation:65,lightness:50)
      for p in pixels {
        let a=HueSaturationTransfer(original,depth:depth).apply(p),b=HueSaturationTransfer(decorated,depth:depth).apply(p)
        for (x,y) in zip([a.r,a.g,a.b,a.a],[b.r,b.g,b.b,b.a]) {XCTAssertEqual(x.bitPattern,y.bitPattern)}
      }
    }}
  }
  func testRangeEditingPreservesSampledAxesAndInvalidMetadataRejects()throws {
    var range=value().ranges[0];range.moveEdge(2,to:131)
    XCTAssertEqual(range.displayColor,.init(hue:52,saturation:65,lightness:50)) // Clamped by the existing outer edge82.
    range.moveEdge(3,to:161);range.moveEdge(2,to:131)
    XCTAssertEqual(range.displayColor,.init(hue:76,saturation:65,lightness:50))
    range.bounds=[22,52,131,161];XCTAssertEqual(range.displayColor?.hue,91)
    XCTAssertEqual(range.displayColor?.saturation,65);XCTAssertEqual(range.displayColor?.lightness,50)
    var a=value()
    for color in [HueRangeColor(hue:361,saturation:65,lightness:50),.init(hue:0,saturation:101,lightness:50),.init(hue:0,saturation:0,lightness:-1)] {
      a.ranges[0].displayColor=color;XCTAssertThrowsError(try a.validate())
    }
  }
  func testNative92HistoryAndFramePayloadRetainEveryDisplayValue()throws {
    for depth in PixelDepth.allCases {
      let original=try CraftDocument(width:4,height:3,depth:depth);var session=EditorSession(document:original)
      let layer=Layer(name:"Sampled Hue",content:.adjustment(.hueSaturation(value())))
      try session.execute(.addLayer(layer));let result=session.document
      XCTAssertEqual(result.minimumArchiveVersion,92)
      for bytes in [try NativeArchive.encode(result),try NativeArchive.encodeChunked(result)] {
        XCTAssertEqual(try NativeArchive.decode(bytes),result)
        var lower=bytes;lower[8]=91;XCTAssertThrowsError(try NativeArchive.decode(lower))
      }
      try session.undo();XCTAssertEqual(session.document,original)
      try session.redo();XCTAssertEqual(session.document,result)
      var d=original,animation=FrameAnimation(layers:original.layers),sample=original.layers[0]
      sample.content=layer.content
      var inactive=animation.frames[0];inactive.id=UUID();inactive.layers[0].payload=AnimationLayerPayload(sample)
      animation.frames.append(inactive);d.animation=animation
      XCTAssertTrue(d.requiresHueRangeColorArchive);XCTAssertEqual(d.minimumArchiveVersion,92)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    }
  }
}
