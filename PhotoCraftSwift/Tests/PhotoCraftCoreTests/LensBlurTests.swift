import XCTest
@testable import PhotoCraftCore

final class LensBlurTests:XCTestCase {
  func checker(_ depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:35,height:31,depth:depth)
    for y in 0..<s.height { for x in 0..<s.width { let v:Float=(x+y)%2 == 0 ? 0.2:0.8;s.setPixel(x:x,y:y,Pixel(v,1-v,v,1)) } };return s
  }
  func testIrisShapeRotationCurvatureAndConstantPreservation()throws {
    var impulse=try Surface(width:41,height:41,depth:.u16,fill:.black);impulse.setPixel(x:20,y:20,.white)
    var s=LensBlurSettings();s.radius=9;s.blades=3
    let triangle=try LensBlurEngine.render(impulse,settings:s);s.rotation=90;let rotated=try LensBlurEngine.render(impulse,settings:s)
    XCTAssertNotEqual(triangle,rotated);s.blades=6;let hexagon=try LensBlurEngine.render(impulse,settings:s);XCTAssertNotEqual(hexagon,rotated)
    s.bladeCurvature=100;let circle=try LensBlurEngine.render(impulse,settings:s);s.blades=3;s.rotation=20;XCTAssertEqual(circle,try LensBlurEngine.render(impulse,settings:s))
    let solid=try Surface(width:13,height:11,depth:.u16,fill:Pixel(0.31,0.57,0.83,0.6))
    for blades in 3...8 { s.blades=blades;s.radius=100;XCTAssertEqual(try LensBlurEngine.render(solid,settings:s).rgbaData(depth:.u16),try solid.rgbaData(depth:.u16)) }
  }
  func testDepthFocusInvertIdentityAndPremultipliedAlpha()throws {
    for depth in [PixelDepth.u8,.u16] {
      let src=try checker(depth);var s=LensBlurSettings();s.radius=5;s.depthSource = .layerMask
      let far=[Float](repeating:1,count:src.width*src.height),near=[Float](repeating:0,count:far.count)
      XCTAssertEqual(try LensBlurEngine.render(src,settings:s,depth:near),src)
      let blurred=try LensBlurEngine.render(src,settings:s,depth:far);XCTAssertLessThan(abs(blurred.pixel(x:16,y:15).r-0.5),0.03)
      s.invert=true;XCTAssertEqual(try LensBlurEngine.render(src,settings:s,depth:far),src)
      s.invert=false;s.focalDistance=255;XCTAssertEqual(try LensBlurEngine.render(src,settings:s,depth:far),src)
      s.depthSource = .none;s.radius=0;XCTAssertEqual(try LensBlurEngine.render(src,settings:s),src)
    }
    var src=try Surface(width:25,height:25,depth:.u16,fill:Pixel(1,0,0,0));src.setPixel(x:12,y:12,Pixel(0,0,1,1))
    var s=LensBlurSettings();s.radius=4;let out=try LensBlurEngine.render(src,settings:s)
    let p=out.pixel(x:13,y:12);XCTAssertEqual(p.r,0);XCTAssertEqual(p.b,1);XCTAssertGreaterThan(p.a,0);XCTAssertLessThan(p.a,1)
  }
  func testHighlightThresholdAndDeterministicNoise()throws {
    let source=try Surface(width:23,height:19,depth:.u16,fill:Pixel(0.5,0.5,0.5));var s=LensBlurSettings();s.radius=0;s.brightness=50
    let bright=try LensBlurEngine.render(source,settings:s);XCTAssertGreaterThan(bright.pixel(x:10,y:10).r,0.9)
    s.threshold=255;XCTAssertEqual(try LensBlurEngine.render(source,settings:s).rgbaData(depth:.u16),try source.rgbaData(depth:.u16))
    s.brightness=0;s.noiseAmount=40;s.monochromatic=true
    for mode in RasterFilter.Distribution.allCases {
      s.distribution=mode;let a=try LensBlurEngine.render(source,settings:s);XCTAssertEqual(a,try LensBlurEngine.render(source,settings:s));XCTAssertNotEqual(a,source)
      XCTAssertEqual(a.pixel(x:4,y:6).r,a.pixel(x:4,y:6).g);s.seed+=1;XCTAssertNotEqual(a,try LensBlurEngine.render(source,settings:s))
    }
    s.monochromatic=false;let color=try LensBlurEngine.render(source,settings:s);XCTAssertNotEqual(color.pixel(x:4,y:6).r,color.pixel(x:4,y:6).g)
  }
  func testRawDepthSourcesRespectTransformsAndIgnoreDisplayProperties()throws {
    var d=try CraftDocument(width:35,height:31),layer=d.layers[0];let src=try checker();layer.content = .raster(src);layer.x=3;layer.y=2
    var mask=try Surface(width:35,height:31,fill:.black);mask.setPixel(x:4,y:5,Pixel(0.7,0.7,0.7));layer.mask=mask
    var properties=MaskProperties();properties.enabled=false;properties.inverted=true;properties.density=0;properties.feather=8;properties.transform = .translation(2,1);layer.maskProperties=properties;d.layers=[layer]
    var s=LensBlurSettings();s.depthSource = .layerMask
    let values=try XCTUnwrap(LensBlurEngine.depthValues(s,source:src,layer:layer,document:d,pixelToDocument:layer.coordinateTransform));XCTAssertEqual(values[6*35+6],mask.pixel(x:4,y:5).r)
    s.depthSource = .alphaChannel;var channel=try Surface(width:35,height:31,fill:.black);channel.setPixel(x:9,y:8,Pixel(0.4,0.4,0.4));let alpha=AlphaChannel(name:"Focus",pixels:channel);d.alphaChannels=[alpha];s.depthChannelID=alpha.id
    let a=try XCTUnwrap(LensBlurEngine.depthValues(s,source:src,layer:layer,document:d,pixelToDocument:layer.coordinateTransform));XCTAssertEqual(a[6*35+6],channel.pixel(x:9,y:8).r)
    s.depthSource = .transparency;s.depthChannelID=nil;XCTAssertEqual(try LensBlurEngine.depthValues(s,source:src,layer:layer,document:d,pixelToDocument:layer.coordinateTransform),[Float](repeating:1,count:35*31))
  }
  func testStrictSchemaMissingSourcesAndDepthRejection()throws {
    for bad in ["{\"radius\":true}","{\"blades\":2}","{\"depthSource\":\"alphaChannel\"}","{\"depthChannelID\":\"\(UUID())\"}","{\"invert\":1}","{\"seed\":-1}","{\"threshold\":256}","{\"fake\":0}"] { XCTAssertThrowsError(try LensBlurSettings.decodeJSON(Data(bad.utf8))) }
    let f=RasterFilter(.lensBlur);XCTAssertEqual(try RasterFilter.decodeJSON(Data("{\"kind\":\"lensBlur\"}".utf8)),f)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LensBlurSettings.apiCapabilities))
    XCTAssertThrowsError(try LensBlurEngine.render(checker(.f32),settings:.init()))
    let d=try CraftDocument(width:35,height:31);var s=LensBlurSettings();s.depthSource = .layerMask
    XCTAssertThrowsError(try s.validateSources(layer:d.layers[0],document:d));XCTAssertThrowsError(try LensBlurEngine.render(checker(),settings:s));XCTAssertThrowsError(try LensBlurEngine.render(checker(),settings:s,depth:[0]))
  }
}
