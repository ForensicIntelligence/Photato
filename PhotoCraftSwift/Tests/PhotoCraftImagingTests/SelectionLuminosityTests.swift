import AppKit
import CryptoKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SelectionLuminosityTests:XCTestCase {
  func input()throws->CraftDocument {
    try PSDCodec.read(Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/quick-mask-selection/composite-rgb8-input.psd")))
  }
  func testFactoryWorkingGrayHasItsOwnValidICCFramingAndLinear32Default()throws {
    let settings=ColorSettings(),data=try settings.profile(.grayscale,depth:.u8)
    XCTAssertEqual(NSColorSpace(iccProfileData:data)?.localizedName,"Dot Gain 20%")
    try NativeModeProfile.validate(data,mode:.grayscale,depth:.u8)
    XCTAssertEqual(try settings.profile(.grayscale,depth:.u16),data)
    XCTAssertEqual(try settings.profile(.grayscale,depth:.f32),try NativeModeProfile.standard(.grayscale,depth:.f32))
    XCTAssertNil(settings.workingGray)
  }
  func testCompositeSelectionMatchesActualPhotoshopColoredFixtureAndPreservesImage()throws {
    let source=try input(),mask=try SelectionChannelSource.composite.selection(in:source)
    let url=Bundle.module.resourceURL!.appendingPathComponent("Fixtures/quick-mask-selection/composite-rgb8-reference.json")
    let reference=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url))as? [String:Any])
    let expected=try XCTUnwrap(reference["coverage"]as? [UInt8])
    XCTAssertEqual(try mask.denseBytes(),expected)
    XCTAssertNil(source.selection);XCTAssertNil(source.quickMask);XCTAssertNil(source.alphaChannels)
    let inverted=try SelectionChannelSource.composite.selection(in:source,invert:true)
    XCTAssertEqual(try inverted.denseBytes(),expected.map{255-$0})
  }
  func testEveryRGB8InputMatchesIndependentPhotoshopCoverageDigest()throws {
    let table=try FactorySelectionTransfer.shared.get()
    var output=Data(count:1<<24)
    output.withUnsafeMutableBytes {raw in
      let bytes=raw.bindMemory(to:UInt8.self)
      for i in 0..<bytes.count {
        let p=Pixel(Float((i>>16)&255)/255,Float((i>>8)&255)/255,Float(i&255)/255)
        bytes[i]=UInt8((FactorySelectionTransfer.coverage(p,table:table)*255).rounded())
      }
    }
    // Independent PSD/PackBits extraction of actual Photoshop CommandOption2
    // output, not an expectation computed with the Swift transfer function.
    XCTAssertEqual(FactorySelectionTransfer.sha(output),"4518de76c475009c7875918b6544d3f153e407d7974fde399d0c4cf0f47005b4")
  }
  func testCustomGrayAndIntentAreNeverRoutedThroughTheFactoryPair()throws {
    let source=try input();var custom=ColorSettings()
    try custom.setProfile(NativeModeProfile.standard(.grayscale,depth:.f32),for:.grayscale)
    let data=try custom.profile(.grayscale,depth:.u8),rgb=try ColorProfileInput.effectiveProfile(source)
    XCTAssertFalse(try FactorySelectionTransfer.supports(source,settings:custom,source:rgb,gray:data))
    let mask=try SelectionChannelSource.composite.selection(in:source,colorSettings:custom)
    XCTAssertEqual(Array(try mask.denseBytes().prefix(3)),[57,183,15])
    var other=ColorSettings();other.intent = .absoluteColorimetric
    XCTAssertFalse(try FactorySelectionTransfer.supports(source,settings:other,source:rgb,gray:other.profile(.grayscale,depth:.u8)))
  }
  func testTaggedStandardSourceAndExplicitDefaultGrayUseTheSameTransform()throws {
    var source=try input();source.workingICC=try NativeModeProfile.standard(.rgb,depth:.u8)
    var settings=ColorSettings();settings.workingGray=WorkingGrayProfiles.dotGain20
    XCTAssertTrue(try FactorySelectionTransfer.supports(source,settings:settings,source:ColorProfileInput.effectiveProfile(source),gray:settings.profile(.grayscale,depth:.u8)))
    XCTAssertEqual(Array(try SelectionChannelSource.composite.selection(in:source,colorSettings:settings).denseBytes().prefix(3)),[107,211,51])
  }
  func testTransformResourceCorruptionFailsBeforeInflationOrMutation()throws {
    let source=try XCTUnwrap(FactorySelectionTransfer.resourceURL)
    var bytes=try Data(contentsOf:source);bytes[bytes.count/2] ^= 1
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let url=dir.appendingPathComponent("corrupt.zlib");try bytes.write(to:url)
    XCTAssertThrowsError(try FactorySelectionTransfer.load(url))
    XCTAssertEqual(try FactorySelectionTransfer.shared.get().count,1<<24)
  }
}
