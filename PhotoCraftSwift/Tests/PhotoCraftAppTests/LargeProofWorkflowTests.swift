import AppKit
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeProofWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,width:Int=300000,height:Int=300000)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    d.layers[0].content = .raster(try Surface(width:width,height:height,depth:depth,fill:Pixel(1,0,0),colorEncoding:depth == .f32 ? .linearRGB:.sRGB));return d
  }
  @MainActor func testMaximumNativeDraftCancelCommitUsesProofCanvasBaseWithoutHistory()async throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),s=EditorStore(document:d);defer{s.renderTask?.cancel()}
      s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);s.render();await s.renderTask?.value
      let before=try XCTUnwrap(s.image).dataProvider?.data as Data?
      s.beginProof();let draft=try XCTUnwrap(s.proofWorkspace);draft.settings.simulatePaper=true;draft.settings.simulateBlack=true;s.previewProof();await s.renderTask?.value
      XCTAssertNil(s.error);XCTAssertNil(s.proofDisplayError)
      let image=try XCTUnwrap(s.image),base=try XCTUnwrap(s.canvasRasterPreview?.base)
      XCTAssertEqual(image.width,base.width);XCTAssertEqual(image.dataProvider?.data as Data?,base.dataProvider?.data as Data?)
      XCTAssertNotEqual(image.dataProvider?.data as Data?,before)
      let view=s.viewport.largeCanvasRequest,request=try RasterPreviewRequest(region:view.region,width:view.width,height:view.height)
      let expected=try SoftProof.image(d,settings:s.effectiveProof,request:request)
      XCTAssertEqual(image.dataProvider?.data as Data?,expected.dataProvider?.data as Data?)
      s.cancelProof();await s.renderTask?.value;XCTAssertFalse(s.proofSettings.enabled);XCTAssertEqual(s.image?.dataProvider?.data as Data?,before)
      s.beginProof();s.proofWorkspace?.settings.simulatePaper=true;s.proofWorkspace?.settings.simulateBlack=true;s.commitProof();await s.renderTask?.value
      XCTAssertNil(s.proofWorkspace);XCTAssertTrue(s.proofSettings.enabled);XCTAssertNil(s.proofDisplayError)
      XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertEqual(s.surface,try Renderer.composite(d))
      s.render();s.renderTask?.cancel();await s.renderTask?.value;XCTAssertEqual(s.document,d)
    }
  }
  @MainActor func testNativeAboveOldLimitBelowViewportThresholdKeepsFullImageAndSource()async throws {
    let d=try fixture(width:4096,height:2049),s=EditorStore(document:d);defer{s.renderTask?.cancel()}
    s.updateViewport(size:CGSize(width:240,height:160),backingScale:1)
    var p=ProofSettings();p.enabled=true;p.simulateBlack=true;try s.setProof(p);await s.renderTask?.value
    XCTAssertNil(s.error);XCTAssertNil(s.proofDisplayError);XCTAssertEqual(s.image?.width,d.width);XCTAssertEqual(s.image?.height,d.height)
    XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPMaximumProofPreviewReadStateAndNormalExportRemainSeparate()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let d=try fixture(),s=doc.store;s.session=EditorSession(document:d);s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);try service.share(doc)
      let id=try XCTUnwrap(service.shares.first?.id),before=try AutomationService.png(d),revision=service.revision(s)
      let status=try await h.edit(service,doc,"proof.configure",["settings":["enabled":true,"simulatePaper":true,"simulateBlack":true]])
      XCTAssertEqual(status,200);await s.renderTask?.value;XCTAssertNil(s.proofDisplayError)
      let proof=try await h.request(service,path:"/v1/documents/\(id)/proof-preview.png")
      XCTAssertEqual(proof.0.statusCode,200);XCTAssertEqual(proof.1,try AutomationService.png(d,proof:s.proofSettings));XCTAssertNotEqual(proof.1,before)
      let imageSource=try XCTUnwrap(CGImageSourceCreateWithData(proof.1 as CFData,nil)),image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
      XCTAssertEqual(image.width,2048);XCTAssertEqual(image.height,2048)
      let normal=try await h.request(service,path:"/v1/documents/\(id)/preview.png");XCTAssertEqual(normal.1,before)
      let stale=try await h.edit(service,doc,"proof.configure",["settings":["enabled":false]],revision:revision);XCTAssertEqual(stale,409)
      XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
    }
  }
  @MainActor func testHTTPBusyInvalidRevokeAndCapabilitiesKeepSourceAndExistingContracts()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let d=try fixture(),s=doc.store;s.session=EditorSession(document:d);s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);try service.share(doc)
      let old=s.proofSettings
      let invalid=try await h.edit(service,doc,"proof.configure",["settings":["device":"custom","profile":"invalid"]]);XCTAssertGreaterThanOrEqual(invalid,400);XCTAssertEqual(s.proofSettings,old)
      s.beginProof();let busy=try await h.edit(service,doc,"proof.configure",["settings":["enabled":true]]);XCTAssertEqual(busy,409);s.cancelProof()
      let id=try XCTUnwrap(service.shares.first?.id);service.revoke(id)
      let revoked=try await h.request(service,path:"/v1/documents/\(id)/proof-preview.png");XCTAssertEqual(revoked.0.statusCode,404)
      XCTAssertEqual(ProofAPI.capabilities["maximumPixels"]as?Int,90_000_000_000);XCTAssertEqual(PrintAPI.capabilities["maximumPixels"]as?Int,8_388_608)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ProofAPI.capabilities));XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
      XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testMaximumNativeGrayAndCMYKPreserveNumbersThroughDesktopAndHTTP()async throws {
    for(mode,depth)in [(DocumentColorMode.grayscale,PixelDepth.f32),(.cmyk,.u16)] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
        var d=try fixture(depth),n=try NativeModeRaster(width:d.width,height:d.height,mode:mode,depth:depth)
        for c in 0..<mode.componentCount{n=try n.replacingChannel(c,with:Surface(width:d.width,height:d.height,depth:depth,fill:Pixel(0.25,0.25,0.25)))}
        n=try n.replacingOpacity(with:Surface(width:d.width,height:d.height,depth:depth,fill:.white));d.modeDescriptor=try .init(mode:mode,depth:depth,profile:n.profile)
        d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface())
        let s=doc.store;s.session=EditorSession(document:d);s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);try service.share(doc)
        let status=try await h.edit(service,doc,"proof.configure",["settings":["enabled":true,"device":"custom","profile":n.profile.base64EncodedString(),"profileName":"Owned native profile","preserveNumbers":true]])
        XCTAssertEqual(status,200);await s.renderTask?.value;XCTAssertNil(s.error);XCTAssertNil(s.proofDisplayError)
        XCTAssertTrue(s.proofSettings.preserveNumbers);XCTAssertEqual(s.image?.dataProvider?.data as Data?,s.canvasRasterPreview?.base.dataProvider?.data as Data?)
        let id=try XCTUnwrap(service.shares.first?.id),response=try await h.request(service,path:"/v1/documents/\(id)/proof-preview.png")
        XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(response.1,try AutomationService.png(d,proof:s.proofSettings))
        XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertFalse(doc.isDocumentEdited)
      }
    }
  }
}
