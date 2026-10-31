import CryptoKit
import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedSmartFilterTests:XCTestCase {
  func testPagedStorageMatches48ActualPriorNativeOutputs()throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paged-smart-filters")
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("manifest.json")))as![[String:Any]]
    XCTAssertEqual(manifest.count,48)
    for(di,depth)in PixelDepth.allCases.enumerated(){for kind in PagedSmartFilterFixture.kinds{for variant in 0..<2{
      let doc=try PagedSmartFilterFixture.document(depth,kind:kind,variant:variant)
      let result=try SmartFilterEngine.renderedLayer(doc.layers[0],in:doc,paged:true)
      guard case .raster(let pixels)=result.content else{return XCTFail("Missing pixels")}
      let name="\(di)-\(kind.rawValue)-\(variant).rgba",expected=try Data(contentsOf:folder.appendingPathComponent(name))
      XCTAssertEqual(SHA256.hash(data:expected).map{String(format:"%02x",$0)}.joined(),manifest.first{$0["file"]as?String==name}?["sha256"]as?String)
      XCTAssertEqual(try pixels.rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB),expected,name)
      XCTAssertNil(result.smartFilters);XCTAssertNil(result.smartObject)
    }}}
  }
  func testMaximumStackSelectionMaskBlendOrderAndSourceAtomicity()throws {
    for depth in PixelDepth.allCases {
      var d=try PagedSmartFilterFixture.constantDocument(width:300_000,height:300_000,depth:depth)
      let original=d,id=d.layers[0].id
      try Command.selectShape(.rectangle(IntRect(x:149_999,y:150_000,width:2,height:3)),.replace,true,0).apply(to:&d)
      try Command.applyFilter(id,RasterFilter(.highPass)).apply(to:&d)
      XCTAssertEqual(d.layers[0].content,original.layers[0].content);XCTAssertEqual(d.layers[0].smartObject,original.layers[0].smartObject)
      var rendered=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
      guard case .raster(let first)=rendered.content else{return XCTFail("Missing pixels")}
      XCTAssertEqual(first.pixel(x:0,y:0),.white);XCTAssertLessThan(first.pixel(x:150_000,y:150_001).r,1)
      XCTAssertLessThan(first.allocatedBytes,8*1_024*1_024);XCTAssertGreaterThan(first.mappedBytes,0)
      var stack=try XCTUnwrap(d.layers[0].smartFilters);stack.filters[0].opacity=0.5;stack.filters[0].blendMode = .multiply
      try Command.smartFilters(id,stack).apply(to:&d);rendered=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
      guard case .raster(let blended)=rendered.content else{return XCTFail("Missing pixels")}
      XCTAssertGreaterThan(blended.pixel(x:150_000,y:150_001).r,first.pixel(x:150_000,y:150_001).r)
      stack.enabled=false;try Command.smartFilters(id,stack).apply(to:&d)
      let disabled=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
      guard case .raster(let restored)=disabled.content else{return XCTFail("Missing pixels")}
      XCTAssertEqual(restored.tileCount,0);XCTAssertEqual(restored.pixel(x:150_000,y:150_001),.white)
      stack.enabled=true;stack.filters.append(SmartFilter(filter:RasterFilter(.cameraRaw)))
      let before=d;XCTAssertThrowsError(try Command.smartFilters(id,stack).apply(to:&d));XCTAssertEqual(d,before)
    }
  }
  func testNineMillionPixelPagedBlendRetainsEveryChangedSampleAndDefault()throws {
    var a=try Surface(width:6000,height:1500,depth:.f32,fill:Pixel(0.2,0.3,0.4),colorEncoding:.linearRGB)
    var b=try Surface(width:6000,height:1500,depth:.f32,fill:Pixel(0.7,0.1,0.8,0.6),colorEncoding:.linearRGB)
    a.setLinearPixel(x:5999,y:1499,Pixel(-2,5,9,0.4));b.setLinearPixel(x:63,y:64,Pixel(10,-1,2,0.7))
    let output=try PagedSmartFilterStorage.combine(a,b,pointwise:true){p,q,x,y in BlendMode.screen.composite(backdrop:p,source:q,opacity:0.625,x:x,y:y)}
    XCTAssertGreaterThan(output.mappedBytes,0);XCTAssertLessThan(output.allocatedBytes,8*1_024*1_024)
    for(x,y)in[(0,0),(63,64),(5999,1499),(64,63),(5998,1498)]{
      let expected=BlendMode.screen.composite(backdrop:a.linearPixel(x:x,y:y),source:b.linearPixel(x:x,y:y),opacity:0.625,x:x,y:y)
      XCTAssertTrue(output.linearPixel(x:x,y:y).hasSameBits(as:expected))
    }
  }
  func testCancelledStackLeavesDocumentAndHistoryUnchanged()async throws {
    let d=try PagedSmartFilterFixture.constantDocument(width:300_000,height:300_000),id=try XCTUnwrap(d.activeLayerID)
    let task=Task {var session=EditorSession(document:d);withUnsafeCurrentTask{$0?.cancel()}
      XCTAssertThrowsError(try session.execute(.applyFilter(id,RasterFilter(.highPass))))
      XCTAssertEqual(session.document,d);XCTAssertTrue(session.undoStack.isEmpty)
    };try await task.value
  }
  func testWhiteMaskKeepsEncodedFloatSetterSemantics()throws {
    var d=try PagedSmartFilterFixture.document(.f32,kind:.highPass,variant:0)
    guard case .raster(let pixels)=d.layers[0].content else{return XCTFail("Missing pixels")}
    let encoded=try pixels.interpretingSamples(as:.sRGB)
    d.layers[0].content = .raster(encoded)
    var source=try CraftDocument(width:encoded.width,height:encoded.height,depth:.f32)
    source.layers[0].content = .raster(encoded)
    d.layers[0].smartObject?.data=try NativeArchive.encodeChunked(source)
    d.layers[0].smartFilters?.mask=try Surface(width:d.width,height:d.height,fill:.white)
    let legacy=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
    let paged=try SmartFilterEngine.renderedLayer(d.layers[0],in:d,paged:true)
    guard case .raster(let a)=legacy.content,case .raster(let b)=paged.content else{return XCTFail("Missing pixels")}
    XCTAssertEqual(try a.rgbaData(depth:.f32,colorEncoding:.linearRGB),try b.rgbaData(depth:.f32,colorEncoding:.linearRGB))
  }
  func testMaximumDepthConversionMatchesLegacySettersAndSharesSparseExtent()throws {
    for from in PixelDepth.allCases {for to in PixelDepth.allCases where from != to {
      var large=try Surface(width:300_000,height:300_000,depth:from,fill:Pixel(0.3,0.7,0.2),colorEncoding:from == .f32 ? .linearRGB:.sRGB)
      let inputs=[Pixel(-0.0,0.12345,0.98765,0.5),Pixel(2,-1,5,0)]
      for(i,p)in inputs.enumerated(){if from == .f32 {large.setLinearPixel(x:299_998+i,y:299_999,p)}else{large.setPixel(x:299_998+i,y:299_999,p)}}
      let output=try large.converted(to:to)
      XCTAssertEqual(output.depth,to);XCTAssertGreaterThan(output.mappedBytes,0);XCTAssertLessThan(output.allocatedBytes,8*1_024*1_024)
      let bounded=try large.cropped(to:IntRect(x:299_997,y:299_999,width:3,height:1))
      XCTAssertEqual(bounded.mappedBytes,0)
      let expected=try bounded.converted(to:to) // Unchanged bounded legacy path.
      XCTAssertTrue(output.pixel(x:0,y:0).hasSameBits(as:expected.pixel(x:0,y:0)))
      for i in 0..<2 {XCTAssertTrue(output.pixel(x:299_998+i,y:299_999).hasSameBits(as:expected.pixel(x:i+1,y:0)))}
    }}
  }
}
