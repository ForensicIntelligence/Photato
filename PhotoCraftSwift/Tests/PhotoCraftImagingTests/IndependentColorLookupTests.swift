import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class IndependentColorLookupTests:XCTestCase {
  let names=["photoshop-rgb8-product2","photoshop-rgb8-product3","photoshop-rgb16-product2","photoshop-rgb16-product3","photoshop-rgb32-product2","photoshop-rgb32-product3","photoshop-rgb8-odd-product3"]
  func file(_ name:String,_ ext:String="psd")throws->Data {
    try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:name,withExtension:ext,subdirectory:"Fixtures/color-lookup-photoshop")))
  }
  func merged(_ data:Data)throws->Data {
    var r=PSDReader(data:data);_=try r.bytes(12);let channels=try r.u16(),height=try r.u32(),width=try r.u32(),depth=try r.u16();_=try r.u16()
    for _ in 0..<3{_=try r.section()}
    let bytes=try PSDChannelCodec.decode(r.bytes(r.remaining),width:width,height:height,depth:depth,channels:channels)
    return Data(bytes.prefix(width*height*3*(depth/8)))
  }
  func testIndependentSavedStructureLoadsEditableCubeAtEveryDepth()throws {
    for name in names {
      do {
        let d=try PSDCodec.read(file(name));XCTAssertEqual(d.layers.count,2,name)
        let layer=try XCTUnwrap(d.layers.last);guard case .adjustment(.colorLookup(let value))=layer.content else{XCTFail("Missing editable lookup: "+name);continue}
        XCTAssertEqual(value.interpolation,.tetrahedral,name);XCTAssertFalse(value.dither,name)
        let edge=name.hasSuffix("2") ? 2:3
        XCTAssertEqual(value.lut?.size,edge,name);XCTAssertEqual(value.lut?.sourceData,try file("owned-product-\(edge)","cube"),name)
        XCTAssertEqual(layer.opacity,1,name);XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.white,name)
      }catch{XCTFail(name+": "+error.localizedDescription)}
    }
  }
  func testCompleteCompositeWordsMatchIndependentPhotoshopAtEveryDepth()throws {
    for name in names {
      do {
        let d=try PSDCodec.read(file(name)),expected=try file(name,"merged"),actual=try merged(PSDCodec.writeRasterLayers(d,compression:.raw))
        if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          try actual.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".actual.merged"))
        }
        XCTAssertEqual(actual.count,expected.count,name)
        XCTAssertEqual(zip(actual,expected).filter{$0 != $1}.count,0,name)
      }catch{XCTFail(name+": "+error.localizedDescription)}
    }
  }
  func testNativeArchiveAndPSDSaveRetainEditableLookupAndOriginalTable()throws {
    for name in names {
      do {
        let original=try PSDCodec.read(file(name)),archive=try NativeArchive.encodeChunked(original)
        let restored=try NativeArchive.decode(archive);XCTAssertEqual(restored,original,name)
        let encoded=try PSDCodec.writeRasterLayers(restored,compression:.raw),reopened=try PSDCodec.read(encoded)
        XCTAssertEqual(reopened.layers.last?.content,original.layers.last?.content,name)
        XCTAssertEqual(try merged(encoded),try file(name,"merged"),name)
        XCTAssertEqual(try NativeArchive.encodeChunked(original),archive,name)
      }catch{XCTFail(name+": "+error.localizedDescription)}
    }
  }
  func testDestructiveLookupMatchesEveryIndependentCompositeAndHistory()throws {
    for name in names {
      var source=try PSDCodec.read(file(name))
      guard case .adjustment(let adjustment)=source.layers.removeLast().content else{XCTFail(name);continue}
      source.activeLayerID=source.layers[0].id
      var session=EditorSession(document:source)
      try session.execute(.applyAdjustment(source.layers[0].id,adjustment))
      let result=session.document
      XCTAssertEqual(try merged(PSDCodec.writeRasterLayers(result,compression:.raw)),try file(name,"merged"),name)
      XCTAssertEqual(result.layers.count,1,name)
      try session.undo();XCTAssertEqual(session.document,source,name)
      try session.redo();XCTAssertEqual(session.document,result,name)
    }
  }
  func testLinearLookupOpacityAndBlendUseExactLinearSamples()throws {
    var d=try CraftDocument(width:1,height:1,depth:.f32)
    var base=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB)
    base.setLinearPixel(x:0,y:0,Pixel(0.125,0.375,0.625))
    d.layers[0].content = .raster(base)
    let table=try ColorLUT.generated(title:"Owned product",size:2){SIMD3($0.x*$0.y,$0.y*$0.z,$0.z*$0.x)}
    let value=ColorLookupAdjustment(lut:table,interpolation:.tetrahedral,dither:false)
    var layer=try value.layer(in:d);layer.opacity=0.5;d.layers.append(layer)
    XCTAssertEqual(try Renderer.composite(d).linearPixel(x:0,y:0),Pixel(0.125,0.375,0.375))
    d.layers[1].blendMode = .multiply
    XCTAssertEqual(try Renderer.composite(d).linearPixel(x:0,y:0),Pixel(0.0703125,0.2578125,0.3515625))
    d.layers[1].opacity=0;XCTAssertEqual(try Renderer.composite(d),base)
  }
  func testNativeSavedSourceAndIndependentExtractionHaveIdenticalSamples()throws {
    let source=try file("photoshop-rgb8-input"),expected=try file("photoshop-rgb8-input","merged")
    XCTAssertEqual(try merged(source),expected)
    let d=try PSDCodec.read(source);XCTAssertEqual(d.layers.count,1)
    XCTAssertEqual(try merged(PSDCodec.writeRasterLayers(d,compression:.raw)),expected)
    XCTAssertNotEqual(try file("photoshop-rgb8-product2","merged"),expected)
    XCTAssertNotEqual(try file("photoshop-rgb8-product2","merged"),try file("photoshop-rgb8-product3","merged"))
  }
}
