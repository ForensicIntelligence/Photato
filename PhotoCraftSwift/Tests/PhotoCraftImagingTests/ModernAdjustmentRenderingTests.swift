import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ModernAdjustmentRenderingTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:31,height:23,depth:depth)
    var s=try Surface(width:d.width,height:d.height,depth:depth)
    for y in 0..<d.height {for x in 0..<d.width {s.setPixel(x:x,y:y,Pixel(Float(x+1)/33,Float(y+1)/25,Float(x+y+1)/57))}}
    d.layers[0].content = .raster(s)
    return d
  }
  func testFourLayerKindsMaskOpacityRegionalPixelsAndSourcePreservation() throws {
    for depth in [PixelDepth.u8,.u16] {for kind in ModernAdjustment.Kind.allCases {
      let source=try fixture(depth:depth)
      var d=source,value=ModernAdjustment(kind)
      value.values[kind.keys[0]]=kind == .light ? 0.5:40
      if kind == .light {value.values["highlights"] = -15;value.values["shadows"]=24}
      var layer=try value.layer(in:d);layer.opacity=0.6
      layer.mask?.setPixel(x:0,y:0,.black)
      try Command.addLayer(layer).apply(to:&d)
      let full=try Renderer.composite(d),before=try Renderer.composite(source)
      XCTAssertEqual(full.pixel(x:0,y:0),before.pixel(x:0,y:0))
      XCTAssertNotEqual(full.pixel(x:10,y:10),before.pixel(x:10,y:10))
      let region=IntRect(x:7,y:5,width:13,height:11),partial=try Renderer.composite(d,region:region)
      for y in region.y..<region.y+region.height {for x in region.x..<region.x+region.width {XCTAssertEqual(partial.pixel(x:x,y:y),full.pixel(x:x,y:y),"\(kind) regional seam")}}
      XCTAssertEqual(d.layers[0].content,source.layers[0].content)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d)) {error in XCTAssertTrue(error.localizedDescription.contains("Modern adjustment descriptors"))}
    }}
  }
  func testGroupedModernNeighborhoodsAndCoordinateStableGrain() throws {
    var d=try fixture()
    var value=ModernAdjustment(.clarityDehaze);value.values["clarity"]=25;value.values["dehaze"]=18
    let layer=try value.layer(in:d);try Command.addLayer(layer).apply(to:&d)
    var options=NewLayerGroupOptions(name:"Adjustments");options.mode = .normal
    try Command.newGroup(options,children:d.layers.map(\.id)).apply(to:&d)
    let full=try Renderer.composite(d),part=try Renderer.composite(d,region:.init(x:4,y:3,width:7,height:8))
    XCTAssertEqual(full.pixel(x:6,y:6),part.pixel(x:6,y:6))
    var large=try CraftDocument(width:300_000,height:300_000)
    large.layers[0].content = .fill(.white)
    var grain=ModernAdjustment(.grain);grain.values["grainAmount"]=60;grain.seed=327
    try Command.addLayer(grain.layer(in:large)).apply(to:&large)
    let a=try Renderer.composite(large,region:.init(x:4096,y:2048,width:64,height:64))
    let b=try Renderer.composite(large,region:.init(x:4128,y:2064,width:64,height:64))
    for y in 2064..<2112 {for x in 4128..<4160 {XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:x,y:y))}}
    XCTAssertNotEqual(a.pixel(x:4100,y:2050),a.pixel(x:4101,y:2050))
  }
  func testNeighborhoodAdjustmentInvalidatesSnapshotAfterSourceEdit() throws {
    for kind in [ModernAdjustment.Kind.clarityDehaze,.light] {
      var d=try fixture()
      var value=ModernAdjustment(kind)
      if kind == .light {value.values["shadows"]=45} else {value.values["clarity"]=45}
      try Command.addLayer(value.layer(in:d)).apply(to:&d)
      let previous=try Renderer.render(d)
      guard case .raster(var source)=d.layers[0].content else {return XCTFail("Missing source")}
      source.setPixel(x:15,y:11,.white);d.layers[0].content = .raster(source)
      let next=try Renderer.render(d,reusing:previous)
      XCTAssertEqual(next.update,.full)
      XCTAssertEqual(next.surface,try Renderer.composite(d))
    }
  }
  func testMaximumPointwiseLayerKeepsImplicitStorageAndNativeReopen() throws {
    var large=try CraftDocument(width:300_000,height:300_000);large.layers[0].content = .fill(.white)
    var value=ModernAdjustment(.colorVibrance);value.values["temperature"]=35
    try Command.addLayer(value.layer(in:large)).apply(to:&large)
    let result=try Renderer.composite(large)
    XCTAssertLessThan(result.allocatedBytes,1_048_576)
    XCTAssertNotEqual(result.pixel(x:150_000,y:150_000),.white)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(large)),large)
  }
}
