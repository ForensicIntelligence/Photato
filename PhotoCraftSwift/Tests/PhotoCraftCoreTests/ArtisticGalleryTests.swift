import XCTest
@testable import PhotoCraftCore

final class ArtisticGalleryTests:XCTestCase {
  func sample(_ depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:32,height:24,depth:depth)
    for y in 0..<24{for x in 0..<32{s.setPixel(x:x,y:y,Pixel(Float((x*17+y*3)%256)/255,Float((x*5+y*23)%256)/255,Float((x*11+y*7)%256)/255,Float(64+(x+y)%192)/255))}};return s
  }
  func testEveryGalleryEffectProducesFiniteDistinctOutputAndRetainsAlpha()throws {
    let source=try sample();var hashes=Set<Data>()
    XCTAssertEqual(GalleryFilter.allCases.count,47)
    for kind in GalleryFilter.allCases {
      var settings=ArtisticGallerySettings();settings.effects=[.init(kind)]
      let output=try ArtisticGalleryEngine.render(source,settings:settings)
      XCTAssertNotEqual(output,source,kind.rawValue);var bytes=Data()
      for y in 0..<24{for x in 0..<32{let p=output.pixel(x:x,y:y);XCTAssertTrue(p.isFinite);XCTAssertEqual(p.a,source.pixel(x:x,y:y).a);bytes.append(contentsOf:[UInt8((p.r*255).rounded()),UInt8((p.g*255).rounded()),UInt8((p.b*255).rounded())])}}
      hashes.insert(bytes)
      XCTAssertEqual(try JSONDecoder().decode(ArtisticGallerySettings.self,from:JSONEncoder().encode(settings)),settings)
    }
    XCTAssertEqual(hashes.count,47)
  }
  func testStackOrderVisibilityIdentityAndHighDepth()throws {
    let source=try sample();var settings=ArtisticGallerySettings();settings.effects=[.init(.cutout),.init(.glowingEdges)]
    let a=try ArtisticGalleryEngine.render(source,settings:settings);settings.effects.reverse();let b=try ArtisticGalleryEngine.render(source,settings:settings);XCTAssertNotEqual(a,b)
    settings.effects[0].visible=false;var only=ArtisticGallerySettings();only.effects=[settings.effects[1]]
    XCTAssertEqual(try ArtisticGalleryEngine.render(source,settings:settings),try ArtisticGalleryEngine.render(source,settings:only))
    settings.effects[1].visible=false;XCTAssertEqual(try ArtisticGalleryEngine.render(source,settings:settings),source)
    settings.effects=[];XCTAssertEqual(try ArtisticGalleryEngine.render(source,settings:settings),source)
    for depth in [PixelDepth.u16,.f32]{let input=try sample(depth),output=try ArtisticGalleryEngine.render(input,settings:only);XCTAssertEqual(output.depth,depth);XCTAssertEqual(output.pixel(x:4,y:5).a,input.pixel(x:4,y:5).a)}
  }
  func testStrictParametersColorsChoiceDefaultsAndStackBounds()throws {
    let raw: [String:Any]=["effects":[["filter":"glass","values":["texture":2,"invert":1]]]]
    let settings=try ArtisticGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:raw));XCTAssertEqual(settings.effects[0].choice("texture"),"canvas");XCTAssertTrue(settings.effects[0].flag("invert"));XCTAssertEqual(settings.effects[0].get("distortion"),5)
    for raw:[String:Any] in [["unknown":1],["effects":[["filter":"missing"]]],["effects":[["filter":"glass","values":["texture":99]]]],["effects":[["filter":"glass","values":["invert":true]]]],["effects":[["filter":"cutout","values":["numberOfLevels":2.5]]]],["effects":[["filter":"cutout","foreground":["r":-1,"g":0,"b":0,"a":1]]]]]{XCTAssertThrowsError(try ArtisticGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:raw)))}
    var invalid=settings;invalid.effects=Array(repeating:settings.effects[0],count:33);XCTAssertThrowsError(try invalid.validate())
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ArtisticGallerySettings.apiSchema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ArtisticGallerySettings.apiCapabilities))
  }
  func testIndependentOriginalRustDefaultEffectOracles() throws {
    let source=try sample();var measurements=[[String:Any]]()
    for kind in GalleryFilter.allCases {
      let url=try XCTUnwrap(Bundle.module.url(forResource:kind.rawValue,withExtension:"rgba",subdirectory:"Fixtures/Gallery")),expected=[UInt8](try Data(contentsOf:url))
      var settings=ArtisticGallerySettings();settings.effects=[.init(kind)];let result=try ArtisticGalleryEngine.render(source,settings:settings)
      var maximum=0,different=0,total=0
      for y in 0..<24 { for x in 0..<32 { let p=result.pixel(x:x,y:y),channels=[p.r,p.g,p.b,p.a];for c in 0..<4 { let difference=abs(Int((channels[c]*255).rounded())-Int(expected[(y*32+x)*4+c]));maximum=max(maximum,difference);total+=difference;if difference>0{different+=1} } } }
      measurements.append(["effect":kind.rawValue,"maxByteDifference":maximum,"differentSamples":different,"totalDifference":total])
      XCTAssertLessThanOrEqual(maximum,1,kind.rawValue)
    }
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/gallery-oracle-comparisons")
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(UUID().uuidString+".json"))
  }

}
