import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ColorSamplingTests:XCTestCase {
  func testFiveLayerSourcesAgainstLiteralStackAndAdjustments()throws {
    var d=try CraftDocument(width:4,height:4)
    d.layers[0].content = .fill(Pixel(1,0,0))
    let active=Layer(name:"Current",content:.fill(Pixel(0,1,0))),top=Layer(name:"Top",content:.fill(Pixel(0,0,1)))
    d.layers += [active,Layer(name:"Lower invert",content:.adjustment(.invert)),top,Layer(name:"Top invert",content:.adjustment(.invert))];d.activeLayerID=active.id
    let expected:[ColorSampleSource:Pixel]=[.current:Pixel(0,1,0),.currentAndBelow:Pixel(0,1,0),.all:Pixel(1,1,0),.allNoAdjustments:Pixel(0,0,1),.currentAndBelowNoAdjustments:Pixel(0,1,0)]
    for (source,color)in expected {var settings=ColorSampleSettings();settings.source=source;let result=try ColorSampling.sample(d,x:1,y:1,settings:settings);XCTAssertEqual(result.color,color,source.rawValue)}
    let original=d;var settings=ColorSampleSettings();settings.source = .allNoAdjustments
    _ = try ColorSampling.sample(d,x:1,y:1,settings:settings);XCTAssertTrue(d==original)
    settings.source = .current;XCTAssertThrowsError(try ColorSampling.sample(d,x:1,y:1,settings:settings,layerID:d.layers[2].id))
    XCTAssertThrowsError(try ColorSampling.sample(d,x:1,y:1,settings:settings,layerID:UUID()))
  }
  func testCurrentBelowRetainsParentGroupAndCurrentGroupSubtree()throws {
    var d=try CraftDocument(width:4,height:4)
    let group=Layer(name:"Group",content:.group(.init(passThrough:false)))
    d.layers[0].content = .fill(.white);d.layers[0].parentID=group.id
    var active=Layer(name:"Current",content:.raster(try Surface(width:4,height:4)));active.parentID=group.id
    var top=Layer(name:"Above",content:.fill(.black));top.parentID=group.id
    d.layers += [active,top,group];d.layers[3].opacity=0.5;d.activeLayerID=active.id
    var settings=ColorSampleSettings();settings.source = .currentAndBelow
    let q=try ColorSampling.sample(d,x:1,y:1,settings:settings);XCTAssertEqual(q.color,.white);XCTAssertEqual(q.coverage,0.5)
    settings.source = .current
    let g=try ColorSampling.sample(d,x:1,y:1,settings:settings,layerID:group.id);XCTAssertEqual(g.color,.black);XCTAssertEqual(g.coverage,0.5)
  }
  func testTransformedCurrentLayerAndAllDepthNativeRegionMatch()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:12,height:8,depth:depth);let surface=try Surface(width:4,height:4,depth:depth,fill:Pixel(0.25,0.5,0.75))
      d.layers[0].content = .raster(surface);d.layers[0].x=3;d.layers[0].y=2
      var settings=ColorSampleSettings();settings.source = .current
      XCTAssertEqual(try ColorSampling.sample(d,x:4,y:3,settings:settings).color,surface.pixel(x:1,y:1))
      XCTAssertThrowsError(try ColorSampling.sample(d,x:0,y:0,settings:settings))
      settings.source = .all;settings.size=3
      let a=try ColorSampling.sample(d,x:4,y:3,settings:settings),whole=try Renderer.composite(d)
      let b=try ColorAveraging.sample(region:.init(x:3,y:2,width:3,height:3),depth:depth){whole.pixel(x:$0,y:$1)}
      XCTAssertEqual(a,b)
    }
  }
  func test300000CanvasSamplesBoundedRegionWithoutFullCanvasAllocation()throws {
    var d=try CraftDocument(width:300000,height:300000);d.layers[0].content = .fill(Pixel(1,0,0))
    var settings=ColorSampleSettings();settings.size=101
    let q=try ColorSampling.sample(d,x:150000,y:150000,settings:settings)
    XCTAssertEqual(q.region,.init(x:149950,y:149950,width:101,height:101));XCTAssertEqual(q.visitedPixels,10201);XCTAssertEqual(q.color,Pixel(1,0,0))
  }
  func testWriteStrictArchitectureSamples()throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]else{return}
    var bytes=Data()
    for depth in PixelDepth.allCases{for size in ColorSampleSettings.sizes{
      let q=try ColorAveraging.sample(region:.init(x:0,y:0,width:size,height:size),depth:depth){x,y in Pixel(Float((x*17+y*31)%256)/255,Float((x*13+y*7)%65536)/65535,Float((x+y)%9)/4,Float((x+2*y)%5+1)/5)}
      for v in [q.color.r,q.color.g,q.color.b,q.color.a,q.coverage]{var bits=v.bitPattern.littleEndian;withUnsafeBytes(of:&bits){bytes.append(contentsOf:$0)}}
    }}
    try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("eyedropper-numerics.rgba32"))
  }
}
