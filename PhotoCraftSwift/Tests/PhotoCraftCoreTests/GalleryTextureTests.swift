import Foundation
import XCTest
@testable import PhotoCraftCore

final class GalleryTextureTests:XCTestCase {
  func texture(_ samples:[UInt8]=[0,85,170,255])throws->GalleryTextureSource {try .init(name:"Owned height",width:samples.count,height:1,samples:Data(samples))}
  func source(_ depth:PixelDepth = .u8)throws->Surface {try Surface(width:12,height:8,depth:depth,fill:Pixel(128.0/255,128.0/255,128.0/255,0.5))}
  func testCanonicalBoundedValueCodableSlicesAndRepeatingBilinearSamples()throws {
    let padded=Data([9,9,0,85,170,255,9]),t=try GalleryTextureSource(name:"Owned",width:4,height:1,samples:padded[2..<6])
    XCTAssertEqual(t.samples.startIndex,0);XCTAssertEqual(t.sample(x:0,y:0),0);XCTAssertEqual(t.sample(x:3,y:8),1)
    XCTAssertEqual(t.sample(x:-1,y:0),1);XCTAssertEqual(t.sample(x:4,y:0),0);XCTAssertEqual(t.sample(x:1.5,y:0),0.5,accuracy:1e-6)
    XCTAssertEqual(t.sample(x:3,y:0,scale:2),0.5,accuracy:1e-6);XCTAssertEqual(t.sample(x:1,y:0,scale:Float.leastNonzeroMagnitude),0)
    for encoder in [false,true] {let data=try encoder ? PropertyListEncoder().encode(t):JSONEncoder().encode(t);let result=try encoder ? PropertyListDecoder().decode(GalleryTextureSource.self,from:data):JSONDecoder().decode(GalleryTextureSource.self,from:data);XCTAssertEqual(result,t)}
    let good=try JSONSerialization.jsonObject(with:JSONEncoder().encode(t))as! [String:Any]
    for change in [["width":0],["height":300001],["width":300000,"height":300000],["width":true],["samples":"AAAA"],["samples":"AFWq/w==\n"],["path":"/not/a/resource"],["name":"bad\nname"]]as[[String:Any]] {var bad=good;bad.merge(change){_,b in b};XCTAssertThrowsError(try JSONDecoder().decode(GalleryTextureSource.self,from:JSONSerialization.data(withJSONObject:bad)))}
    XCTAssertThrowsError(try GalleryTextureSource(name:"",width:1,height:1,samples:Data([0])))
  }
  func testAnalyticRampLightInvertAndConstantHeightHaveLiteralByteResults()throws {
    let input=try source();var effect=GalleryEffect(.texturizer);effect.texture=try texture();effect.values["relief"]=50;effect.values["light"]=6
    var settings=ArtisticGallerySettings();settings.effects=[effect]
    let output=try ArtisticGalleryEngine.render(input,settings:settings)
    let expected:[UInt8]=[0,181,181,0]
    for y in 0..<8 {for x in 0..<12 {XCTAssertEqual(Int((output.pixel(x:x,y:y).r*255).rounded()),Int(expected[x%4]));XCTAssertEqual(output.pixel(x:x,y:y).a,input.pixel(x:x,y:y).a)}}
    settings.effects[0].values["invert"]=1;let inverted=try ArtisticGalleryEngine.render(input,settings:settings)
    for x in 0..<12 {XCTAssertEqual(Int((inverted.pixel(x:x,y:0).r*255).rounded()),Int(x%4==0 || x%4==3 ? 181:0))}
    for kind in [GalleryFilter.texturizer,.glass] {var e=GalleryEffect(kind);e.texture=try texture([64]);settings.effects=[e];XCTAssertEqual(try ArtisticGalleryEngine.render(input,settings:settings),input)}
  }
  func testAllFiveEffectsDepthsVisibilityAndOriginalTextureChoicesStayIndependent()throws {
    for depth in PixelDepth.allCases {let input=try ArtisticGalleryTests().sample(depth);for kind in GalleryFilter.allCases.filter({GalleryTextureSource.supports($0)}) {
      var e=GalleryEffect(kind);if kind == .glass {e.values["smoothness"]=2};e.texture=try texture();var s=ArtisticGallerySettings();s.effects=[e]
      let result=try ArtisticGalleryEngine.render(input,settings:s);XCTAssertNotEqual(result,input,kind.rawValue)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder=URL(fileURLWithPath:path).appendingPathComponent("gallery-texture-buffers",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try result.rgbaData(depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB).write(to:folder.appendingPathComponent(kind.rawValue+"-"+depth.rawValue+".rgba"))
      }
      s.effects[0].texture=try texture([64]);let flat=try ArtisticGalleryEngine.render(input,settings:s);XCTAssertNotEqual(result,flat,kind.rawValue)
      s.effects[0].visible=false;XCTAssertEqual(try ArtisticGalleryEngine.render(input,settings:s),input)
      for y in 0..<input.height {for x in 0..<input.width {XCTAssertTrue(result.pixel(x:x,y:y).isFinite);XCTAssertEqual(result.pixel(x:x,y:y).a,input.pixel(x:x,y:y).a)}}
    }}
  }
  func testStrictFilterJSONRejectsUnsupportedHiddenTexturesAndRetainsOrdinaryPayloads()throws {
    let t=try texture(),object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(t))
    let raw:[String:Any]=["effects":[["filter":"texturizer","texture":object]]];let s=try ArtisticGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:raw));XCTAssertEqual(s.effects[0].texture,t)
    for kind in ["cutout","grain","watercolor"] {XCTAssertThrowsError(try ArtisticGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:["effects":[["filter":kind,"visible":false,"texture":object]]])))}
    let ordinary=try ArtisticGallerySettings.decodeJSON(Data("{\"effects\":[{\"filter\":\"texturizer\",\"texture\":null}]}".utf8));XCTAssertNil(ordinary.effects[0].texture)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ArtisticGallerySettings.apiSchema))
  }
}
