import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class ClassicFusedGradientIOTests: XCTestCase {
  let names=["random65-linear","random65-partial","uneven9-smooth"]
  func fixture(_ name:String)throws->Data {
    try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:"photoshop-holdout486-"+name,withExtension:"psd",subdirectory:"Fixtures/classic-fused486")))
  }
  func planes(_ data:Data)throws->(Int,Int,[UInt8]) {
    var r=PSDReader(data:data);_=try r.bytes(12);let channels=try r.u16(),h=try r.u32(),w=try r.u32(),depth=try r.u16(),mode=try r.u16()
    XCTAssertEqual(depth,16);XCTAssertEqual(mode,3)
    for _ in 0..<3{_=try r.section()}
    return(w,h,Array(try PSDChannelCodec.decode(r.bytes(r.remaining),width:w,height:h,depth:depth,channels:channels)))
  }
  func testFreshPhotoshopOpaqueRowsNativeArchiveAndBothPSDFormats()throws {
    for name in names {
      let input=try fixture(name),doc=try PSDCodec.read(input),expected=try planes(input)
      XCTAssertEqual(doc.width,4097);XCTAssertEqual(doc.height,4)
      let restored=try NativeArchive.decode(NativeArchive.encode(doc));XCTAssertEqual(restored,doc)
      for format in [PSDFileFormat.psd,.psb] {
        let output=try PSDCodec.writeRasterLayers(restored,format:format)
        // PSB uses eight-byte sections; decode its merged data with the actual public reader.
        var r=PSDReader(data:output);_=try r.bytes(26)
        _=try r.section();_=try r.section();_=try r.section(lengthBytes:format == .psb ? 8:4)
        let actual=Array(try PSDChannelCodec.decode(r.bytes(r.remaining),width:doc.width,height:doc.height,depth:16,channels:Int(output[12])<<8|Int(output[13]),format:format))
        var differences=0
        for c in 0..<4 {for i in 0..<(doc.width*3*2) {
          let at=c*doc.width*doc.height*2+i
          if actual[at] != expected.2[at]{differences+=1}
        }}
        XCTAssertEqual(differences,0,"\(name)/\(format)")
        XCTAssertEqual(try PSDCodec.read(output).layers.last?.content,doc.layers.last?.content)
        if let dir=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let url=URL(fileURLWithPath:dir).appendingPathComponent("classic-fused486",isDirectory:true)
          try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
          try output.write(to:url.appendingPathComponent(name+"."+(format == .psd ? "psd":"psb")))
        }
      }
    }
  }
}
