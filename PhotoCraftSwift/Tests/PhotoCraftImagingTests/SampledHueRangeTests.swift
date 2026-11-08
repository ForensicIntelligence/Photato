import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SampledHueRangeTests: XCTestCase {
  static let cases: [(String,[Int],[Int])] = [
    ("ps-red-range-orange-sample",[352,22,52,82],[37,65,50]),
    ("ps-red-range-add-green",[352,22,131,161],[76,65,50]),
    ("ps-red-range-subtract-orange",[22,52,131,161],[91,65,50]),
    ("ps-red-range-gray-sample",[291,321,40,70],[0,0,50])]
  func fixture(_ name:String)throws->Data {
    let url=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"psd",subdirectory:"Fixtures/sampled-hue-ranges485"))
    return try Data(contentsOf:url)
  }
  func record(_ data:Data)throws->Data {
    let signature=Data("8BIMhue2".utf8),range=try XCTUnwrap(data.range(of:signature)),offset=range.upperBound
    XCTAssertNil(data.range(of:signature,in:range.upperBound..<data.endIndex))
    let length=data[offset..<offset+4].reduce(0){($0<<8)|Int($1)}
    XCTAssertEqual(length,136)
    return data.subdata(in:offset+4..<offset+4+length)
  }
  func testOwnedPhotoshopSampledRangePSDImports()throws {
    for (name,_,_) in Self.cases {
      let bytes=try fixture(name),document=try PSDCodec.read(bytes)
      let layer=try XCTUnwrap(document.layers.first{if case .adjustment(.hueSaturation)=$0.content{return true};return false})
      XCTAssertEqual(layer.sourceTags?["hue2"],try record(bytes),name)
    }
  }
  func testAHUPresetAcceptsActualSampledSwatchesAndPreservesWords()throws {
    for (name,_,_) in Self.cases {
      let bytes=try record(fixture(name)),adjustment=try HueSaturationPresetCodec.read(bytes)
      XCTAssertEqual(try HueSaturationPresetCodec.write(adjustment,original:bytes),bytes,name)
      XCTAssertEqual(try HueSaturationPresetCodec.write(adjustment),bytes,name)
    }
  }
  func testAllSavedSwatchesAndRangeBoundsMatchIndependentWords()throws {
    for (name,bounds,color) in Self.cases {
      let value=try HueSaturationPresetCodec.read(record(fixture(name)))
      XCTAssertEqual(value.ranges[0].bounds.map{($0%360+360)%360},bounds)
      XCTAssertEqual(value.ranges[0].displayColor,.init(hue:color[0],saturation:color[1],lightness:color[2]))
      XCTAssertTrue(value.ranges.dropFirst().allSatisfy{$0.displayColor==nil})
    }
  }
  func testPSDBothContainersAndNative92KeepFreshAndRetainedTags()throws {
    for (name,_,_) in Self.cases {
      let input=try fixture(name),tag=try record(input),original=try PSDCodec.read(input)
      XCTAssertEqual(original.minimumArchiveVersion,92)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(original)),original)
      for format in [PSDFileFormat.psd,.psb] {for fresh in [false,true] {
        var d=original
        if fresh {for i in d.layers.indices {d.layers[i].sourceTags=nil}}
        let bytes=try PSDCodec.writeRasterLayers(d,format:format)
        XCTAssertEqual(try record(bytes),tag) // Independent public-format block extraction, before native decoding.
        if let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let dir=URL(fileURLWithPath:root).appendingPathComponent("sampled-hue-ranges")
          try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
          let suffix=(format == .psd ? "psd":"psb")+"-"+(fresh ? "fresh":"retained")
          try bytes.write(to:dir.appendingPathComponent(name+"-"+suffix+"."+(format == .psd ? "psd":"psb")))
          try tag.write(to:dir.appendingPathComponent(name+"-reference.hue2"))
        }
        let reopened=try PSDCodec.read(bytes),layer=try XCTUnwrap(reopened.layers.first{if case .adjustment(.hueSaturation)=$0.content{return true};return false})
        XCTAssertEqual(layer.sourceTags?["hue2"],tag)
        XCTAssertEqual(layer.content,original.layers.first{if case .adjustment(.hueSaturation)=$0.content{return true};return false}?.content)
      }}
    }
  }
  func testEditingOneParameterRetainsAllSwatchWords()throws {
    for (name,_,_) in Self.cases {
      let source=try record(fixture(name));var value=try HueSaturationPresetCodec.read(source)
      value.master.hue=27;let edited=try HueSaturationPresetCodec.write(value,original:source)
      XCTAssertEqual(edited.count,136);XCTAssertEqual(edited.suffix(36),source.suffix(36))
      var expected=source;expected[10]=0;expected[11]=27;XCTAssertEqual(edited,expected)
    }
  }
  func testMalformedSampledColorsRejectWithoutDiscardingTheTrailer()throws {
    let source=try record(fixture(Self.cases[0].0))
    for (offset,value) in [(100,361),(102,101),(104,101)] {
      var bad=source;bad[offset]=UInt8(value>>8);bad[offset+1]=UInt8(value&255)
      XCTAssertThrowsError(try HueSaturationPresetCodec.read(bad))
    }
    XCTAssertThrowsError(try HueSaturationPresetCodec.read(source.dropLast()))
    XCTAssertThrowsError(try HueSaturationPresetCodec.read(source+Data([0])))
  }

}
