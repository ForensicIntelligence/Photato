import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedWarpTests: XCTestCase {
  func fixture(width: Int = 17, height: Int = 13, depth: PixelDepth = .u8, fill: Pixel = .clear) throws -> Surface {
    var surface = try Surface(width: width, height: height, depth: depth, fill: fill,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<min(height,13) { for x in 0..<min(width,17) {
      let p = Pixel(Float(x)/8-0.25, Float(y)/6, Float((x+y)%7)/3, Float((x+3*y)%5)/4)
      if depth == .f32 { surface.setLinearPixel(x:x,y:y,p) } else { surface.setPixel(x:x,y:y,p) }
    } }
    return surface
  }
  func translation(width: Int, height: Int) throws -> WarpDefinition {
    var warp = try WarpDefinition().custom(width:width,height:height)
    warp.interpolation = .nearest
    warp.mesh!.points = warp.mesh!.points.map { .init($0.x+3,$0.y+2) }
    return warp
  }
  func testWarpAdmitsSparseSourceBeyondLegacyUVTableLimit() throws {
    var document = try CraftDocument(width: 4097, height: 2048)
    var source = try Surface(width: 4097, height: 2048)
    source.setPixel(x: 100, y: 100, Pixel(1, 0, 0, 1))
    let layer = Layer(name: "Large owned warp", content: .raster(source))
    document.layers = [layer]; document.activeLayerID = layer.id
    var warp = WarpDefinition(); warp.style = .arch; warp.bend = 20; warp.interpolation = .nearest
    let edit = try WarpEdit.prepare(document, layerID: layer.id, warp: warp)
    guard case .raster(let result) = edit.result.layers[0].content else { return XCTFail("Expected raster") }
    XCTAssertEqual(result.width, source.width)
    XCTAssertGreaterThan(result.height, source.height)
    XCTAssertGreaterThan(result.tileCount, 0)
    XCTAssertEqual(document.layers[0].content, .raster(source))
  }
  func testPagedKernelRetainsLegacyBitsForEveryPresetOrientationDepthAndInterpolation() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth:depth)
      for style in WarpStyle.allCases where style != .custom {
        for vertical in [false,true] {
          var warp=WarpDefinition();warp.style=style;warp.bend=43;warp.horizontalDistortion=17;warp.verticalDistortion = -23;warp.vertical=vertical
          let old=try WarpRaster.mapping(warp,width:source.width,height:source.height,transform:.translation(-2,3))
          let paged=try PagedWarpRaster.mapping(warp,width:source.width,height:source.height,transform:.translation(-2,3))
          XCTAssertEqual(old.bounds,paged.bounds)
          for method in Resampling.allCases {
            XCTAssertEqual(try PagedWarpRaster.render(source,using:paged,method:method),
              try WarpRaster.render(source,using:old,method:method),"\(style)/\(vertical)/\(depth)/\(method)")
          }
        }
      }
    }
  }
  func testOverlappingTriangleOrderAndOutsideSamplingMatchDenseBits() throws {
    let vertices=[PathPoint(0,0),.init(23,0),.init(0,21),.init(0,0),.init(23,0),.init(0,21),.init(8,8),.init(8,8),.init(8,8)]
    let inputs=[PathPoint(-1,-1),.init(17,-1),.init(-1,13),.init(17,13),.init(-1,13),.init(17,-1),.init(0,0),.init(1,1),.init(2,2)]
    for order in [[[0,1,2],[3,4,5],[6,7,8]],[[3,4,5],[0,1,2],[6,7,8]]] {
      let old=try WarpRaster.mapping(vertices:vertices,inputs:inputs,triangles:order)
      let paged=try PagedWarpRaster.mapping(vertices:vertices,inputs:inputs,triangles:order)
      for depth in PixelDepth.allCases {for method in Resampling.allCases {for clamp in [false,true] {
        let source=try fixture(depth:depth)
        XCTAssertEqual(try PagedWarpRaster.render(source,using:paged,method:method,clampEdges:clamp),
          try WarpRaster.render(source,using:old,method:method,clampEdges:clamp))
      }}}
    }
  }
  func testPatchSeamsAndRawLinkedUnlinkedMasksRetainDenseBitsAndProperties() throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(width:2051,height:65,depth:depth,fill:Pixel(0.2,0.4,0.8,0.75))
      var layer=Layer(name:"Seam source",content:.raster(source))
      var mask=try Surface(width:2051,height:65,depth:depth,fill:.white)
      for (x,y) in [(0,0),(63,63),(2047,63),(2048,64),(2050,64)] {mask.setPixel(x:x,y:y,Pixel(0.25,0.25,0.25,1))}
      layer.mask=mask
      var props=MaskProperties();props.enabled=false;props.inverted=true;props.density=0.6;props.feather=2;props.outside=0.3
      let document=try CraftDocument(width:2060,height:80,depth:depth)
      let warp=try translation(width:source.width,height:source.height)
      let old=try WarpRaster.mapping(warp,width:source.width,height:source.height,transform:.identity)
      let paged=try PagedWarpRaster.mapping(warp,width:source.width,height:source.height,transform:.identity)
      for linked in [false,true] {
        props.linked=linked;layer.maskProperties=props
        let expected=try WarpRaster.baked(layer,in:document,using:old,method:.nearest)
        let actual=try PagedWarpRaster.baked(layer,in:document,using:paged,method:.nearest)
        XCTAssertEqual(actual,expected)
        XCTAssertEqual(actual.mask?.depth,depth)
        XCTAssertEqual(actual.maskProperties,expected.maskProperties)
      }
    }
  }
  func testMaximumLogicalCanvasCanCommitEmptyTranslatedWarpAndRoundTripHistory() throws {
    var document=try CraftDocument(width:300_000,height:300_000)
    let layer=Layer(name:"Maximum empty layer",content:.raster(try Surface(width:document.width,height:document.height)))
    document.layers=[layer];document.activeLayerID=layer.id
    let edit=try WarpEdit.prepare(document,layerID:layer.id,warp:translation(width:document.width,height:document.height))
    guard case .raster(let result)=edit.result.layers[0].content else{return XCTFail("Missing raster")}
    XCTAssertEqual(result.width,300_000);XCTAssertEqual(result.height,300_000);XCTAssertEqual(result.tileCount,0)
    XCTAssertEqual(edit.result.layers[0].x,3);XCTAssertEqual(edit.result.layers[0].y,2)
    var session=EditorSession(document:document);try session.execute(.warp(edit))
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)),edit.result)
    try session.undo();XCTAssertEqual(session.document,document)
    try session.redo();XCTAssertEqual(session.document,edit.result)
  }
  func testActualDenseOutputBeyondEightMegapixelsRetainsTranslatedSamplesInPagedStorage() throws {
    var document=try CraftDocument(width:4097,height:2048)
    var source=try Surface(width:4097,height:2048,fill:Pixel(0.2,0.4,0.8,0.75))
    source.setPixel(x:4096,y:2047,Pixel(0.7,0.1,0.3,1))
    source.setPixel(x:2048,y:64,Pixel(1,0,0,0))
    var layer=Layer(name:"Dense large layer",content:.raster(source))
    var mask=try Surface(width:source.width,height:source.height,fill:.white)
    mask.setPixel(x:2048,y:64,Pixel(0.25,0.25,0.25,1))
    var properties=MaskProperties();properties.enabled=false;properties.inverted=true
    properties.density=0.6;properties.feather=2;properties.outside=0.3
    layer.mask=mask;layer.maskProperties=properties
    document.layers=[layer];document.activeLayerID=layer.id
    let edit=try WarpEdit.prepare(document,layerID:layer.id,warp:translation(width:source.width,height:source.height))
    guard case .raster(let result)=edit.result.layers[0].content else{return XCTFail("Missing raster")}
    XCTAssertEqual(result,source)
    XCTAssertGreaterThan(result.mappedBytes,0)
    XCTAssertGreaterThan(result.tileCount,1024)
    XCTAssertEqual(edit.result.layers[0].mask,mask)
    XCTAssertEqual(edit.result.layers[0].maskProperties,properties)
    XCTAssertGreaterThan(try XCTUnwrap(edit.result.layers[0].mask).mappedBytes,0)
    XCTAssertEqual(document.layers[0].content,.raster(source))
  }
  func testCancelledPagedWarpDoesNotPublishAndInvalidGeometryRejects() async throws {
    let source=try fixture(),warp=try translation(width:source.width,height:source.height)
    let task=Task {
      withUnsafeCurrentTask{$0?.cancel()}
      let mapping=try PagedWarpRaster.mapping(warp,width:source.width,height:source.height,transform:.identity)
      return try PagedWarpRaster.render(source,using:mapping,method:.nearest)
    }
    do {_ = try await task.value;XCTFail("Expected cancellation")}catch is CancellationError {}catch{XCTFail("Unexpected \(error)")}
    XCTAssertThrowsError(try PagedWarpRaster.mapping(vertices:[.init(.nan,0)],inputs:[.init(0,0)],triangles:[]))
    XCTAssertThrowsError(try PagedWarpRaster.mapping(vertices:[.init(0,0)],inputs:[.init(0,0)],triangles:[[0,1,2]]))
    XCTAssertThrowsError(try PagedWarpRaster.mapping(vertices:[.init(0,0)],inputs:[.init(0,0)],triangles:[],bounds:.init(x:0,y:0,width:300_001,height:1)))
  }
  func testSparseBoundarySupportRetainsClampedOutsideInputCoordinates() throws {
    let vertices=[PathPoint(0,0),.init(4,0),.init(0,3)]
    for inputs in [[PathPoint(9,9),.init(9,9),.init(9,9)],[PathPoint(-0.1,0.5),.init(-0.1,0.5),.init(-0.1,0.5)]] {
    let triangles=[[0,1,2]]
    let old=try WarpRaster.mapping(vertices:vertices,inputs:inputs,triangles:triangles)
    let paged=try PagedWarpRaster.mapping(vertices:vertices,inputs:inputs,triangles:triangles)
    for depth in PixelDepth.allCases {
      var source=try Surface(width:4,height:3,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      source.setPixel(x:3,y:2,Pixel(1,0.25,0.5,1))
      source.setPixel(x:0,y:0,Pixel(0,1,0,0.5))
      for method in Resampling.allCases {for clamp in [false,true] {
        XCTAssertEqual(try PagedWarpRaster.render(source,using:paged,method:method,clampEdges:clamp),
          try WarpRaster.render(source,using:old,method:method,clampEdges:clamp),"\(depth)/\(method)/\(clamp)")
      }}
    }
    }
  }
}
