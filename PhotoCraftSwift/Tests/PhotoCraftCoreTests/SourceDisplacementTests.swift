import Foundation
import XCTest
@testable import PhotoCraftCore

final class SourceDisplacementTests:XCTestCase {
  func map(_ r:Float=0.5,_ g:Float?=nil)throws->FloatDisplacementMap {
    var data=Data();for value in [r]+(g.map{[$0]} ?? []){var bits=value.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}
    let m=FloatDisplacementMap(width:1,height:1,channels:g==nil ? 1:2,samples:data);try m.validate();return m
  }
  func filter(_ map:FloatDisplacementMap?=nil)->RasterFilter {var f=RasterFilter(.displace);var source=SourceDisplacement();source.map=map;f.distortion?.source=source;return f}
  func testFloatMapNumericalBitsChannelsAndStrictSchema()throws {
    var pixels=try Surface(width:2,height:1,depth:.f32,colorEncoding:.linearRGB);let p=Pixel(0.500_123,1.875,-0.25,0.2);pixels.setLinearPixel(x:0,y:0,p);pixels.setLinearPixel(x:1,y:0,Pixel(-0.75,0.125,0.5,1))
    let m=try FloatDisplacementMap.read(pixels,name:"Owned map");XCTAssertEqual(m.channels,2);XCTAssertEqual(m.values.map(\.bitPattern),[p.r,p.g,Float(-0.75),Float(0.125)].map(\.bitPattern));XCTAssertEqual(m.samples.count,16)
    let mono=try FloatDisplacementMap.read(Surface(width:1,height:1,depth:.f32,fill:Pixel(0.503,0.503,0.503,0.1)),name:"Mono");XCTAssertEqual(mono.channels,1);XCTAssertEqual(mono.values,[0.503])
    let f=filter(m),data=try JSONSerialization.data(withJSONObject:["kind":"displace","distortion":try XCTUnwrap(f.distortion).apiParameters(kind:.displace)]);XCTAssertEqual(try RasterFilter.decodeJSON(data),f)
    for bad in [#"{"source":{"unknown":1}}"#,#"{"source":{"reference":{"unknown":1}}}"#,#"{"source":{"reference":{"documentIndex":true}}}"#,#"{"source":{"reference":{"documentName":"a","documentIndex":1}}}"#,#"{"source":{"map":{"width":1,"height":1,"channels":3,"samples":"AAAAAA=="}}}"#] {
      XCTAssertThrowsError(try DistortionSettings.decodeJSON(Data(bad.utf8),kind:.displace),bad)
    }
    var invalid=m;invalid.samples=Data([0,0,192,127,0,0,0,0,0,0,0,0,0,0,0,0]);XCTAssertThrowsError(try invalid.validate())
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:DistortionSettings.apiSchema(kind:.displace)));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SourceDisplacement.apiSchema))
  }
  func testClosedFormNeutralWrapTransparentAndHDR()throws {
    for depth in PixelDepth.allCases {
      var s=try Surface(width:3,height:1,depth:depth);for x in 0..<3{let p=Pixel(Float(x+1)/4,0.3,depth == .f32 ? 2:0.8,Float(x+1)/4);if depth == .f32{s.setLinearPixel(x:x,y:0,p)}else{s.setPixel(x:x,y:0,p)}}
      let neutral=try XCTUnwrap(filter(map()).distortion);XCTAssertEqual(try DistortionEngine.render(s,kind:.displace,settings:neutral),s)
      var shift=try XCTUnwrap(filter(map(1,0.5)).distortion);shift.horizontalScale=100;shift.verticalScale=0;shift.edge = .wrapAround
      let wrapped=try DistortionEngine.render(s,kind:.displace,settings:shift);for x in 0..<3{let after=depth == .f32 ? wrapped.linearPixel(x:x,y:0):wrapped.pixel(x:x,y:0),before=depth == .f32 ? s.linearPixel(x:(x+2)%3,y:0):s.pixel(x:(x+2)%3,y:0);XCTAssertTrue(after.hasSameBits(as:before))}
      shift.edge = .transparent;let clear=try DistortionEngine.render(s,kind:.displace,settings:shift);for x in 0..<3{XCTAssertEqual(clear.pixel(x:x,y:0),.clear)}
      let translated=try DistortionEngine.render(s,kind:.displace,settings:neutral,referenceBounds:.init(x:0,y:0,width:23,height:19),pixelToDocument:.translation(3,2));XCTAssertEqual(translated,s)
    }
  }
  func testOrdinaryMissingMapSelectionProtectionAndCancellation()async throws {
    var d=try CraftDocument(width:8,height:6),f=filter();let id=d.layers[0].id;let original=d
    XCTAssertNoThrow(try f.validate());XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&d));XCTAssertTrue(d==original)
    f.distortion?.source?.map=try map(1,0.5);f.distortion?.horizontalScale=100;f.distortion?.verticalScale=0;f.distortion?.edge = .transparent
    var pixels=try Surface(width:8,height:6,fill:Pixel(0.3,0.6,0.9));pixels.setPixel(x:2,y:2,.clear);d.layers[0].content = .raster(pixels);d.selection = .init(x:1,y:1,width:3,height:3);var session=EditorSession(document:d);try session.execute(.applyFilter(id,f));guard case .raster(let changed)=session.document.layers[0].content else{return XCTFail()};XCTAssertEqual(changed.pixel(x:0,y:0),pixels.pixel(x:0,y:0));XCTAssertEqual(changed.pixel(x:1,y:1),.clear);try session.undo();XCTAssertTrue(session.document==d)
    var mixed=f;mixed.distortion?.map = .init(width:1,height:1,channels:1,samples:Data([128]));XCTAssertThrowsError(try mixed.validate())
    let input=pixels,settings=try XCTUnwrap(f.distortion);let worker=Task.detached {try Task.checkCancellation();return try DistortionEngine.render(input,kind:.displace,settings:settings)};worker.cancel();do{_ = try await worker.value;XCTFail("Cancelled work committed")}catch is CancellationError{}catch{XCTFail("Unexpected cancellation error \(error)")}
  }
  func testLegacyMapWireIdentityAndSourceFractionalValidation()throws {
    var old=DistortionSettings(kind:.displace);old.map = .init(width:1,height:1,channels:1,samples:Data([128]));try old.validate(kind:.displace);let json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any]);XCTAssertNil(json["source"]);XCTAssertFalse(old.requiresSourceDisplacementArchive)
    var source=old;source.map=nil;source.source=SourceDisplacement();source.horizontalScale=12.75;try source.validate(kind:.displace,requireMap:false);XCTAssertThrowsError(try source.validate(kind:.displace));XCTAssertTrue(source.requiresSourceDisplacementArchive)
    source.source?.reference.path="Owned Missing Map.psd";XCTAssertEqual(source.source?.reference.label,"Owned Missing Map.psd");source.source?.reference.path="bad\0hint";XCTAssertThrowsError(try source.validate(kind:.displace,requireMap:false))
    var extreme=filter(try map(Float.greatestFiniteMagnitude,-Float.greatestFiniteMagnitude));extreme.distortion?.horizontalScale=999;let s=try Surface(width:1,height:1);XCTAssertThrowsError(try DistortionEngine.render(s,kind:.displace,settings:XCTUnwrap(extreme.distortion)))
  }
}
