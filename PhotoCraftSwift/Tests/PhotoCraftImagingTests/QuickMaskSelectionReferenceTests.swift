import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class QuickMaskSelectionReferenceTests:XCTestCase {
  func fixture(_ name:String)throws->CraftDocument {
    let url=Bundle.module.resourceURL!.appendingPathComponent("Fixtures/quick-mask-selection/"+name+".psd")
    return try PSDCodec.read(Data(contentsOf:url))
  }
  func testRealPhotoshopLoadAndSaveCombinationPlanesAgree()throws {
    let loaded=try fixture("selection-results"),saved=try fixture("save-combine-results")
    let expected=[[255,228,208,196,192,196,208,228,255,255,160,160,0,239,255,255],
      [0,4,16,36,64,100,144,196,255,0,96,32,0,47,127,0],
      [0,28,48,60,64,60,48,28,0,255,32,32,0,145,128,128]]
    for i in 0..<3 {
      let a=try XCTUnwrap(loaded.alphaChannels?[i+2]),b=try XCTUnwrap(saved.alphaChannels?[i+1])
      XCTAssertEqual(try a.selection().denseBytes(),Array(repeating:expected[i].map(UInt8.init),count:4).flatMap{$0})
      XCTAssertEqual(try a.selection().denseBytes(),try b.selection().denseBytes())
    }
    XCTAssertEqual(try loaded.alphaChannels?[4].selection().denseBytes(),try loaded.alphaChannels?[5].selection().denseBytes())
  }
  func testSavedSelectionSamplesMatchRealPhotoshopAt16And32Bits()throws {
    for prefix in ["save-combine-16","photoshop-32"] {
      let original=try fixture(prefix+"-input"),reference=try fixture(prefix+"-results")
      let source=try XCTUnwrap(original.alphaChannels?.first)
      for (index,mode) in [SelectionMode.add,.subtract,.intersect].enumerated() {
        var edited=original;edited.setCoverageSelection(try source.selection())
        let channel=try XCTUnwrap(original.alphaChannels?[index+1])
        try Command.channel(.saveSelection(channel.id,nil,mode)).apply(to:&edited)
        let actual=try edited.channel(.alpha(channel.id)).pixels,expected=try XCTUnwrap(reference.alphaChannels?[index+1]).pixels
        for y in 0..<edited.height {for x in 0..<edited.width {
          XCTAssertEqual(actual.pixel(x:x,y:y).r.bitPattern,expected.pixel(x:x,y:y).r.bitPattern,"\(prefix) \(mode) \(x),\(y)")
        }}
        XCTAssertEqual(edited.layers,original.layers)
        if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
          try PSDCodec.writeRasterLayers(edited,compression:.raw).write(to:dir.appendingPathComponent("native-"+prefix+"-"+mode.rawValue+".psd"))
        }
      }
    }
  }
  func testNativePSDAndPSBReopenPreserveMasksOptionsNamesAndUntouchedLayers()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:16,height:4,depth:depth)
      let bytes:[UInt8]=[0,32,64,96,128,160,192,224,255,255,128,64,0,192,255,128]
      let mask=try SelectionMask(width:16,height:4,bytes:Array(repeating:bytes,count:4).flatMap{$0});d.setCoverageSelection(mask)
      try Command.channel(.saveSelection(nil,"Subject 日本語",.replace)).apply(to:&d)
      var options=ChannelDisplayOptions();options.opacity=0.37;options.color=Pixel(0,1,0);options.indicates = .selectedAreas
      try Command.channel(.quickMask(true,options)).apply(to:&d)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      for format:PSDFileFormat in [.psd,.psb] {
        let encoded=try PSDCodec.writeRasterLayers(d,format:format),reopened=try PSDCodec.read(encoded)
        XCTAssertEqual(reopened.alphaChannels?.first?.name,"Subject 日本語")
        XCTAssertEqual(try reopened.alphaChannels?.first?.selection().denseBytes(),try mask.denseBytes())
        XCTAssertEqual(reopened.quickMask?.options,options)
        XCTAssertEqual(try reopened.quickMask?.selection().denseBytes(),try mask.denseBytes())
      }
    }
  }
}
