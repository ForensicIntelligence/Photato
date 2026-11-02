import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ExposureInterchangeTests: XCTestCase {
  func fixture(_ name:String)throws->Data {
    let url=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:nil,subdirectory:"Fixtures/Exposure"))
    return try Data(contentsOf:url)
  }
  func testSpecBinaryAndEditablePSDPSBAllDepths() throws {
    let value=ClassicAdjustment.exposure(.init(exposure:0.5,offset:0.01,gammaCorrection:1.2))
    let binary=try fixture("expA-controls.bin")
    XCTAssertEqual(try PSDClassicAdjustment.write(value),binary)
    XCTAssertEqual(try PSDClassicAdjustment.read(binary,key:"expA"),value)
    for n in [0,1,2,10,13] {XCTAssertThrowsError(try PSDClassicAdjustment.read(binary.prefix(n),key:"expA"))}
    var invalid=binary;invalid[1]=2;XCTAssertThrowsError(try PSDClassicAdjustment.read(invalid,key:"expA"))
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:7,height:5,depth:depth)
      d.layers[0].content = .raster(try Surface(width:7,height:5,depth:depth,fill:Pixel(0.2,0.4,0.6)))
      d.selection = .init(x:1,y:1,width:4,height:3)
      d.layers.append(try value.layer(in:d));d.selection=nil
      for format in PSDFileFormat.allCases {
        let reopened=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
        XCTAssertEqual(reopened.layers.last?.content,d.layers.last?.content)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
      }
    }
  }
  func testOwnedOriginalRustSourceControlsSamplesAndAtomicValidation() throws {
    let helper=PcraftImportTests()
    for bits in ["u8","u16","f32"] {
      let bytes=try fixture("exposure-\(bits).pcraft"),d=try PcraftImport.read(bytes)
      XCTAssertEqual(d.layers.count,2)
      XCTAssertEqual(d.layers[1].content,.adjustment(.classic(.exposure(.init(exposure:0.5,offset:0.01,gammaCorrection:1.2)))))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
      let reference=try XCTUnwrap(JSONSerialization.jsonObject(with:fixture("expected-\(bits).json"))as?[String:Any])
      let expected=Data(try XCTUnwrap(reference["rgba8"]as?[NSNumber]).map(\.uint8Value))
      let actual=try Renderer.composite(d)
      var rgba=Data()
      for y in 0..<d.height {for x in 0..<d.width {
        let p=d.depth == .f32 ? actual.linearPixel(x:x,y:y):actual.pixel(x:x,y:y)
        rgba.append(contentsOf:[p.r,p.g,p.b,p.a].map{UInt8((min(1,max(0,$0))*255).rounded())})
      }}
      XCTAssertEqual(rgba,expected,"Original Rust \(bits) output")
      for raw:[String:Any] in [["exposure":0,"offset":0,"gamma":0],["exposure":true,"offset":0,"gamma":1],["exposure":0,"offset":0,"gamma":1,"unknown":true]] {
        let project=try helper.source(bytes){doc in
          var layers=doc["layers"]as![[String:Any]];layers[1]["content"]=["kind":"adjustment","adjustment":["Exposure":raw]];doc["layers"]=layers
        }
        XCTAssertThrowsError(try helper.convert(project))
      }
    }
  }
  func testBakedEditableSelectionAndMaximumRegionalPreview() throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:13,height:7,depth:depth)
      d.layers[0].content = .raster(try Surface(width:13,height:7,depth:depth,fill:Pixel(0.2,0.4,0.6)))
      d.selection = .init(x:3,y:2,width:5,height:3)
      let value=ClassicAdjustment.exposure(.init(exposure:0.75,offset:0.01,gammaCorrection:1.2))
      var baked=d;try Command.applyAdjustment(d.layers[0].id,.classic(value)).apply(to:&baked)
      d.layers.append(try value.layer(in:d))
      XCTAssertEqual(try Renderer.composite(baked).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
    }
    var maximum=try CraftDocument(width:300_000,height:300_000)
    maximum.layers[0].content = .raster(try Surface(width:300_000,height:300_000,fill:Pixel(0.2,0.4,0.6)))
    maximum.layers.append(try ClassicAdjustment.exposure(.init(exposure:0.5)).layer(in:maximum))
    let preview=try Renderer.composite(maximum,region:.init(x:299_995,y:299_997,width:5,height:3))
    XCTAssertEqual(preview.width,300_000);XCTAssertEqual(preview.height,300_000)
    XCTAssertLessThanOrEqual(preview.tileCount,4);XCTAssertEqual(preview.pixel(x:0,y:0),.clear)
    XCTAssertGreaterThan(preview.pixel(x:299_997,y:299_998).r,0.2)
  }
  func merged(_ data:Data)throws->Data {
    var r=PSDReader(data:data,offset:12)
    let channels=try r.u16(),height=try r.u32(),width=try r.u32(),depth=try r.u16();_ = try r.u16()
    for _ in 0..<3 {_ = try r.section()}
    let samples=try PSDChannelCodec.decode(r.bytes(r.remaining),width:width,height:height,depth:depth,channels:channels)
    return Data(samples.prefix(width*height*(depth/8)*3))
  }
  func testIndependentPhotoshopMergedSampleEquality() throws {
    for mode in ["rgb8","rgb16","rgb32"] {
      let source=try fixture("photoshop-\(mode)-exposure.psd"),doc=try PSDCodec.read(source)
      XCTAssertTrue(doc.layers.contains{if case .adjustment(.classic(let value))=$0.content{return value.kind == .exposure};return false})
      let expected=try merged(source),actual=try merged(PSDCodec.writeRasterLayers(doc))
      let differences=zip(expected,actual).filter{$0 != $1}.count
      print("Independent Photoshop Exposure \(mode): \(differences) changed merged bytes of \(expected.count)")
      XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(differences,0,"\(mode): strict Photoshop stored composite comparison remains a parity gate")
    }
  }
}
