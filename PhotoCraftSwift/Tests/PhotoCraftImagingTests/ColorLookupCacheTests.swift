import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ColorLookupCacheTests:XCTestCase {
  func payload(_ source:Data,key:String,type:String)throws->Data {
    let keyBytes=Array(key.utf8),count=keyBytes.count
    let marker=Data([UInt8(count>>24),UInt8(count>>16),UInt8(count>>8),UInt8(count)]+keyBytes+Array(type.utf8))
    let found=try XCTUnwrap(source.range(of:marker));var reader=PSDReader(data:Data(source[found.upperBound...]));return try reader.bytes(reader.u32())
  }
  func cache()throws->(Data,ColorLUT){
    let f=IndependentColorLookupTests();return(try payload(f.file("photoshop-rgb8-product2"),key:"profile",type:"tdta"),try ColorLUTFile.read(f.file("owned-product-2","cube"),name:"owned.cube"))
  }
  func testOriginalNativeCachesMatchEveryEmbeddedTable()throws {
    let f=IndependentColorLookupTests()
    for name in f.names {
      let source=try f.file(name),cache=try payload(source,key:"profile",type:"tdta"),cube=try payload(source,key:"LUT3DFileData",type:"tdta")
      XCTAssertNoThrow(try PSDColorLookupCache.validate(cache,table:ColorLUTFile.read(cube,name:"owned.cube")),name)
    }
  }
  func testGeneratedCacheRetainsExactFloatCLUTAndUsesNativeDescriptorFraming()throws {
    let f=IndependentColorLookupTests()
    for edge in [2,3] {
      let table=try ColorLUTFile.read(f.file("owned-product-\(edge)","cube"),name:"owned.cube")
      let cache=try PSDColorLookupCache.encode(table)
      XCTAssertEqual(cache,try PSDColorLookupCache.encode(table));XCTAssertNoThrow(try PSDColorLookupCache.validate(cache,table:table))
      let encoded=try PSDColorLookup.write(.init(lut:table,interpolation:.tetrahedral,dither:false))
      XCTAssertEqual(encoded.count%4,0)
      let descriptor=try PSDDescriptor.read(Data(encoded.dropFirst(2)),padding:true)
      XCTAssertEqual(descriptor.name,[0]);XCTAssertNil(descriptor["NM  "])
      XCTAssertEqual(descriptor["Nm  "],.text(Array("owned.cube".utf16)+[0]))
      XCTAssertEqual(descriptor["LUT3DFileName"],.text(Array("owned.cube".utf16)+[0]))
      XCTAssertEqual(descriptor["profile"],.raw(cache))
      var bad=table;bad.domainMin=[-1,0,0];XCTAssertThrowsError(try PSDColorLookupCache.encode(bad))
      bad=table;bad.curve = .init(values:[0,0,0,1,1,1]);XCTAssertThrowsError(try PSDColorLookupCache.encode(bad))
    }
  }
  func testInvalidCacheExtentsSignaturesPipelinesAndSamplesReject()throws {
    let (original,table)=try cache()
    for count in [0,1,131,original.count-1]{XCTAssertThrowsError(try PSDColorLookupCache.validate(Data(original.prefix(count)),table:table))}
    func replacing(_ offset:Int,_ bytes:[UInt8])->Data {var d=original;d.replaceSubrange(offset..<offset+bytes.count,with:bytes);return d}
    let bad:[Data]=[
      replacing(0,[0xff,0xff,0xff,0xff]),replacing(8,[2]),replacing(12,Array("mntr".utf8)),replacing(16,Array("CMYK".utf8)),replacing(36,Array("xxxx".utf8)),
      replacing(128,[0xff,0xff,0xff,0xff]),replacing(136,[0xff,0xff,0xff,0xfc]),replacing(140,[0xff,0xff,0xff,0xff]),
      replacing(480,Array("mft2".utf8)),replacing(492,[0,0,0,2]),replacing(496,[0xff,0xff,0xff,0xfc]),
      replacing(504,Array("matf".utf8)),replacing(516,[255]),replacing(532,[0x7f,0xc0,0,0]),replacing(532,[0x3f,0x80,0,0])]
    for (index,data) in bad.enumerated(){XCTAssertThrowsError(try PSDColorLookupCache.validate(data,table:table),"case\(index)")}
    var changed=table;changed.domainMin=[-1,0,0];XCTAssertThrowsError(try PSDColorLookupCache.validate(original,table:changed))
    let other=try ColorLUT.identity(size:3);XCTAssertThrowsError(try PSDColorLookupCache.validate(original,table:other));XCTAssertEqual(original,try cache().0)
  }
  func testMismatchedCacheInNativeDescriptorCannotBeSilentlyIgnored()throws {
    let f=IndependentColorLookupTests(),source=try f.file("photoshop-rgb8-product2"),marker=Data("8BIMclrL".utf8),range=try XCTUnwrap(source.range(of:marker));var r=PSDReader(data:Data(source[range.upperBound...]));let data=try r.bytes(r.u32());var d=try PSDDescriptor.read(Data(data.dropFirst(2)),padding:true)
    d.items.removeAll{$0.key.text=="LUT3DFileData"};d.items.append(.init("LUT3DFileData",.raw(try f.file("owned-product-3","cube"))))
    var mismatched=Data([0,1]);mismatched.append(try d.encoded());XCTAssertThrowsError(try PSDColorLookup.read(mismatched))
    d.items.removeAll{$0.key.text=="lookupType"};d.items.append(.init("lookupType",.enumerated(.init("colorLookupType"),.init("abstractProfile"))));var standalone=Data([0,1]);standalone.append(try d.encoded());XCTAssertThrowsError(try PSDColorLookup.read(standalone))
  }
  func testLegacyTrilinearArchivesRemainExplicitAndCannotMaslabelEditablePSD()throws {
    let f=IndependentColorLookupTests();var d=try PSDCodec.read(f.file("photoshop-rgb8-input"));let lut=try ColorLUTFile.read(f.file("owned-product-2","cube"),name:"owned.cube"),legacy=ColorLookupAdjustment(lut:lut,dither:false)
    XCTAssertEqual(legacy.interpolation,.trilinear);d.layers.append(try legacy.layer(in:d));d.activeLayerID=d.layers.last?.id
    let data=try NativeArchive.encodeChunked(d);XCTAssertEqual(try NativeArchive.decode(data),d);XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(ColorLookupAdjustment.photoshopDefault.interpolation,.tetrahedral);XCTAssertEqual(AdjustmentBrushKind.colorLookup.initial,.colorLookup(.photoshopDefault))
  }
}
