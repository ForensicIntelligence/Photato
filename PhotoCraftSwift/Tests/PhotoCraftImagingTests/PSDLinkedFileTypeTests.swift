import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDLinkedFileTypeTests:XCTestCase {
  func testLicensedRustByteSignaturesAndEmptyCacheFallbackDoNotInventTIFF()throws {
    let vectors:[([UInt8],String)]=[([56,66,80,83,0,2],"8BPB"),([56,66,80,83,0,1],"8BPS"),([137,80,78,71],"PNGf"),([255,216],"JPEG"),([73,73,42,0],"TIFF"),([77,77,0,42],"TIFF"),([71,73,70],"GIFf"),([1,2,3,4],"    ")]
    for(bytes,expected)in vectors {
      let source=try SmartObject(fileName:"Owned.dat",mediaType:"image/bmp",data:Data(bytes),width:1,height:1)
      XCTAssertEqual(try LinkedSmartObjectIO.photoshopLinkedFileType(source),expected)
    }
    for (mime,type)in [("image/png","PNGf"),("image/gif","GIFf"),("application/x-photoshop","8BPB"),("application/pdf","PDF "),("application/octet-stream","    ")] {
      let reference=try LinkedSmartObjectSource(reference:"Links/Owned.dat",byteLength:1)
      var source=try SmartObject(fileName:"Owned.dat",mediaType:"application/octet-stream",data:Data(),width:1,height:1,linkedSource:reference)
      // Classification is deliberately independent of source rendering/page metadata.
      source.mediaType=mime;XCTAssertEqual(try LinkedSmartObjectIO.photoshopLinkedFileType(source),type)
    }
    XCTAssertEqual(LinkedSmartObjectIO.photoshopLinkedMediaType(fileType:"GIFf",fileName:"Owned.bin"),"image/gif")
    XCTAssertEqual(LinkedSmartObjectIO.photoshopLinkedMediaType(fileType:"8BPB",fileName:"Owned.bin"),"application/x-photoshop")
    XCTAssertEqual(LinkedSmartObjectIO.photoshopLinkedMediaType(fileType:"    ",fileName:"Owned.unregistered-photato-test-format"),"application/octet-stream")
  }
  func testExternalPSBSourceTypeAndUnknownCacheDeclarationRoundTrip()throws {
    let data=try PSDCodec.writeRasterLayers(CraftDocument(width:2,height:2),format:.psb)
    var outer=try CraftDocument(width:8,height:8)
    let reference=try LinkedSmartObjectSource(reference:"Links/Owned.psb",contentHash:LinkedSmartObjectSource.fingerprint(data),byteLength:UInt64(data.count))
    let layer=try LinkedSmartObjectIO.place(data,fileName:"Owned.psb",reference:reference,in:outer,fit:false)
    try Command.addLayer(layer).apply(to:&outer)
    for _ in 0..<2 {
      outer=try PSDCodec.read(PSDCodec.writeRasterLayers(outer))
      XCTAssertEqual(outer.layers.last?.smartObject?.mediaType,"application/x-photoshop")
      XCTAssertEqual(try outer.layers.last?.smartObject.map{try LinkedSmartObjectIO.photoshopLinkedFileType($0)},"8BPB")
      XCTAssertEqual(outer.layers.last?.smartObject?.linkedSource?.reference,"Links/Owned.psb")
    }
  }
  func testLinkedNativeOriginalIsNotAdvertisedAsTIFFOrWrittenIntoPhotoshopOutput()throws {
    let bytes=try NativeArchive.encodeChunked(CraftDocument(width:2,height:2))
    var outer=try CraftDocument(width:8,height:8)
    let reference=try LinkedSmartObjectSource(reference:"Links/Owned.photato",contentHash:LinkedSmartObjectSource.fingerprint(bytes),byteLength:UInt64(bytes.count))
    let layer=try LinkedSmartObjectIO.place(bytes,fileName:"Owned.photato",reference:reference,in:outer,fit:false)
    try Command.addLayer(layer).apply(to:&outer)
    XCTAssertThrowsError(try LinkedSmartObjectIO.photoshopLinkedFileType(layer.smartObject!))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(outer))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(outer)),outer)
  }
  func testUnknownExternalPreviewRetainsOpaqueTypeWithoutAcceptingUnknownEmbeddedSources()throws {
    XCTAssertThrowsError(try SmartObject(fileName:"Unknown.bin",mediaType:"application/octet-stream",data:Data([1]),width:2,height:2))
    let link=try LinkedSmartObjectSource(reference:"Links/Unknown.private-type",byteLength:12)
    let source=try SmartObject(fileName:"Unknown.private-type",mediaType:"application/octet-stream",data:Data(),width:2,height:2,linkedSource:link)
    for hint in [Data("ZZZZ".utf8),Data([0xff,0,0x81,1])] {
      var doc=try CraftDocument(width:2,height:2)
      doc.layers[0].smartObject=source;doc.layers[0].sourceTags=["PhFT":hint]
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
      let output=try PSDCodec.writeRasterLayers(doc),reopened=try PSDCodec.read(output)
      XCTAssertNil(output.range(of:Data("PhFT".utf8)),"Native file-type hint must not leak into PSD layer records.")
      XCTAssertEqual(reopened.layers[0].smartObject?.mediaType,"application/octet-stream")
      XCTAssertEqual(reopened.layers[0].sourceTags?["PhFT"],hint)
      XCTAssertNotNil(try PSDCodec.writeRasterLayers(reopened).range(of:hint))
      doc.layers[0].sourceTags?["PhFT"]=Data([1,2,3]);XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
    }
  }

}
