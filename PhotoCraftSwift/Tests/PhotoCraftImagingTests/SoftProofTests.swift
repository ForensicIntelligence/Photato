import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SoftProofTests: XCTestCase {
  func source(_ depth: PixelDepth = .u16) throws -> CraftDocument {
    var pixels = try Surface(width: 6, height: 1, depth: depth)
    for (x,p) in [Pixel.black, .white, Pixel(1,0,0,0.5), Pixel(0,1,0), Pixel(0,0,1), Pixel(0.5,0.5,0.5,0)].enumerated() { pixels.setPixel(x:x,y:0,p) }
    var d = try CraftDocument(width: 6, height: 1, depth: depth); d.layers = [Layer(name: "Reference", content: .raster(pixels))]; d.activeLayerID = d.layers[0].id; return d
  }
  func testIdentityProofPreservesAlphaAndDocumentAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      let doc = try source(depth), before = try JSONEncoder().encode(doc), original = try Renderer.composite(doc)
      var settings = ProofSettings(); settings.enabled = true; settings.device = .sRGB
      let proof = try SoftProof.surface(doc, composite: original, settings: settings)
      for x in 0..<6 { let p = proof.pixel(x:x,y:0), a = original.pixel(x:x,y:0)
        XCTAssertEqual(p.a,a.a); if a.a > 0 { XCTAssertEqual(p.r,a.r,accuracy:0.0003); XCTAssertEqual(p.g,a.g,accuracy:0.0003); XCTAssertEqual(p.b,a.b,accuracy:0.0003) }
      }
      // Compare models as JSON encoders are not ordered by default.
      XCTAssertEqual(try JSONDecoder().decode(CraftDocument.self,from:before),doc)
    }
  }
  func testPaperBlackAndIntentChangeOnlyProofAndRemainFinite() throws {
    let doc = try source(); var settings = ProofSettings(); settings.enabled = true
    let normal = try SoftProof.surface(doc,settings:settings)
    settings.simulateBlack = true; let black = try SoftProof.surface(doc,settings:settings)
    settings.simulatePaper = true; let paper = try SoftProof.surface(doc,settings:settings)
    XCTAssertNotEqual(try normal.rgbaData(depth:.u16),try black.rgbaData(depth:.u16))
    XCTAssertNotEqual(try black.rgbaData(depth:.u16),try paper.rgbaData(depth:.u16))
    for intent in ModeRenderingIntent.allCases { settings.intent=intent; let result=try SoftProof.surface(doc,settings:settings); for x in 0..<6 { XCTAssertTrue(result.pixel(x:x,y:0).isFinite) } }
  }
  func testGamutWarningDetectsSaturatedCMYKLossAndIgnoresTransparency() throws {
    let doc=try source(); var settings=ProofSettings(); settings.gamutWarning=true; settings.warningColor=Pixel(1,0,1)
    let result=try SoftProof.surface(doc,settings:settings)
    XCTAssertEqual(result.pixel(x:2,y:0).r,1); XCTAssertEqual(result.pixel(x:2,y:0).b,1)
    XCTAssertEqual(result.pixel(x:2,y:0).a,try Renderer.composite(doc).pixel(x:2,y:0).a)
    XCTAssertEqual(result.pixel(x:5,y:0).a,0)
    settings.device = .sRGB; let same=try SoftProof.surface(doc,settings:settings)
    XCTAssertLessThan(same.pixel(x:2,y:0).b,0.001)
  }
  func testInvalidProfilesAndIncompatiblePreserveNumbersReject() throws {
    let doc=try source(); var settings=ProofSettings(); settings.preserveNumbers=true
    XCTAssertThrowsError(try SoftProof.surface(doc,settings:settings))
    settings.device = .custom; settings.profile=Data(repeating:0,count:132)
    XCTAssertThrowsError(try settings.validate())
    settings=ProofSettings(); settings.device = .sRGB; settings.plate = .cyan
    XCTAssertThrowsError(try settings.validate())
    settings=ProofSettings(); settings.warningOpacity = .nan; XCTAssertThrowsError(try settings.validate())
  }
  func testIndependentCoreGraphicsReferenceForPreservedRGBNumbers() throws {
    let doc=try source(); var settings=ProofSettings(); settings.enabled=true; settings.device = .custom
    let p3=try XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)); settings.profile=try XCTUnwrap(p3.copyICCData() as Data?)
    settings.preserveNumbers=true; settings.simulateBlack=true
    let result=try SoftProof.surface(doc,settings:settings), composite=try Renderer.composite(doc)
    let srgb=try XCTUnwrap(CGColorSpace(name:CGColorSpace.sRGB))
    for x in 0..<5 {
      let p=composite.pixel(x:x,y:0), color=try XCTUnwrap(CGColor(colorSpace:p3,components:[CGFloat(p.r),CGFloat(p.g),CGFloat(p.b),1]))
      let expected=try XCTUnwrap(color.converted(to:srgb,intent:.relativeColorimetric,options:nil)?.components), actual=result.pixel(x:x,y:0)
      XCTAssertEqual(actual.r,unit(Float(expected[0])),accuracy:0.0004); XCTAssertEqual(actual.g,unit(Float(expected[1])),accuracy:0.0004); XCTAssertEqual(actual.b,unit(Float(expected[2])),accuracy:0.0004)
    }
  }
  func testNativeCMYKPlatesPreserveOriginalNumbersAndLabEncoding() throws {
    let rgb=try source()
    for mode in [DocumentColorMode.cmyk,.lab,.grayscale] {
      let doc=try rgb.convertingMode(.init(mode:mode,depth:.u16)); let native=try XCTUnwrap(doc.layers.first?.nativeMode)
      var settings=ProofSettings(); settings.device = .custom; settings.profile=native.profile; settings.preserveNumbers=true; settings.enabled=true; settings.simulateBlack=true
      let before=doc; let preview=try SoftProof.surface(doc,settings:settings)
      for x in 0..<5 { let actual=preview.pixel(x:x,y:0), expected=try native.surface().pixel(x:x,y:0)
        XCTAssertEqual(actual.r,expected.r,accuracy:0.001); XCTAssertEqual(actual.g,expected.g,accuracy:0.001); XCTAssertEqual(actual.b,expected.b,accuracy:0.001)
      }
      if mode == .cmyk {
        for (index,plate) in [ProofSettings.Plate.cyan,.magenta,.yellow,.black].enumerated() {
          settings.plate=plate; let result=try SoftProof.surface(doc,settings:settings)
          for x in 0..<5 { XCTAssertEqual(result.pixel(x:x,y:0).r,1-native.value(component:index,index:x),accuracy:0.00001) }
        }
      }
      XCTAssertEqual(doc,before)
    }
  }
  func testLiteralLabNeutralDoesNotAcquireColorCast() throws {
    for depth in [PixelDepth.u8,.u16] {
      var raster=try NativeModeRaster(width:1,height:1,mode:.lab,depth:depth)
      try raster.set(0.5,component:0,index:0)
      try raster.set(128/255,component:1,index:0); try raster.set(128/255,component:2,index:0); try raster.set(1,component:3,index:0)
      let color=try raster.surface().pixel(x:0,y:0)
      XCTAssertEqual(color.r,color.g,accuracy:1/65535); XCTAssertEqual(color.g,color.b,accuracy:1/65535)
    }
  }
  func testCancellationStopsProofBeforeRendering() async throws {
    let doc=try source(); let task=Task { () throws -> Surface in
      try await Task.sleep(for:.seconds(1)); return try SoftProof.surface(doc,settings:ProofSettings())
    }; task.cancel()
    do { _=try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
  }
}
