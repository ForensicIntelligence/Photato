import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class GalleryTextureLoaderTests:XCTestCase {
  func file(_ name:String)throws->URL {try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"psd",subdirectory:"Fixtures/OwnedGallery453"))}
  func testMergedPSDGrayValuesRowOrientationAndFileByteAgreement()throws {
    for name in ["owned-step-texture","owned-xy-texture"] {
      let url=try file(name),data=try Data(contentsOf:url),loaded=try GalleryTextureLoader.read(url),decoded=try GalleryTextureLoader.decode(data,name:url.lastPathComponent)
      XCTAssertEqual(loaded,decoded);XCTAssertEqual(loaded.width,8);XCTAssertEqual(loaded.height,8)
      let expected=name.contains("step") ? Array(repeating:[UInt8(0),32,64,96,128,160,192,255],count:8).flatMap{$0}:(0..<64).map{UInt8($0*4)}
      XCTAssertEqual(loaded.samples,Data(expected));XCTAssertThrowsError(try GalleryTextureLoader.decode(Data([8])+data,name:"Prefixed"))
    }
  }
  func testColorHeightConversionAndOwnedPSDReadableAsOrdinaryDocument()throws {
    let url=try file("owned-color-texture"),data=try Data(contentsOf:url),texture=try GalleryTextureLoader.decode(data,name:"Color")
    XCTAssertEqual(Array(texture.samples.prefix(8)),[76,150,29,255,128,0,159,64])
    let doc=try RasterIO.read(data,name:"Owned");XCTAssertEqual(doc.width,8);XCTAssertEqual(doc.height,8)
    let flat=try GalleryTextureLoader.read(try file("owned-flat-gray"));XCTAssertEqual(flat.samples,Data(repeating:128,count:96*72))
  }
  func testPSBMergedTextureRetainsTheSameHeightSamples()throws {
    let psb=try XCTUnwrap(Bundle.module.url(forResource:"owned-step-texture",withExtension:"psb",subdirectory:"Fixtures/OwnedGallery453"))
    let actual=try GalleryTextureLoader.read(psb),expected=try GalleryTextureLoader.read(file("owned-step-texture"))
    XCTAssertEqual(actual.samples,expected.samples);XCTAssertEqual(actual.width,8);XCTAssertEqual(actual.height,8)
  }
  func testMalformedBoundedHeaderAndUnsupportedImagesRejectBeforeAllocation()throws {
    let valid=try Data(contentsOf:file("owned-step-texture"))
    for count in [0,3,26,39] {XCTAssertThrowsError(try GalleryTextureLoader.decode(valid.prefix(count),name:"Short"))}
    for offset in [4,14,18] {var bad=valid;for i in offset..<offset+(offset==4 ? 2:4){bad[i]=255};XCTAssertThrowsError(try GalleryTextureLoader.decode(bad,name:"Invalid"))}
    XCTAssertThrowsError(try GalleryTextureLoader.decode(Data("not a PSD".utf8),name:"Wrong"))
    XCTAssertThrowsError(try GalleryTextureLoader.read(URL(string:"https://example.invalid/texture.psd")!))
    let padded=Data([9,9])+valid;XCTAssertEqual(try GalleryTextureLoader.decode(padded[2...],name:"Slice").width,8)
  }
}
