import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class LargeCropGate:@unchecked Sendable{let condition=NSCondition();var released=false;func wait(){condition.lock();while !released{condition.wait()};condition.unlock()};func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}}

final class LargeCropWorkflowTests:XCTestCase {
  func fixture(width:Int=300000,height:Int=300000)throws->CraftDocument{var d=try CraftDocument(width:width,height:height),s=try Surface(width:width,height:height);s.setPixel(x:width/2,y:height/2,Pixel(1,0,0));d.layers[0].content = .raster(s);return d}
  @MainActor func testMaximumNativeDraftBoundedPreviewCommitUndoAndCancel()async throws {
    let source=try fixture(),s=EditorStore(document:source);defer{s.cancelCrop();s.geometryTask?.cancel();s.renderTask?.cancel()};XCTAssertTrue(s.canBeginCrop);s.beginCrop();var draft=try XCTUnwrap(s.cropDraft);draft.frame.scaleX=99.9;draft.frame.scaleY=99.9;draft.deletePixels=false;s.updateCrop(draft);await s.cropTask?.value;XCTAssertNil(s.cropError);XCTAssertEqual(s.cropReadyDraft,draft);let image=try XCTUnwrap(s.cropPreviewImage);XCTAssertLessThanOrEqual(image.width,1024);XCTAssertLessThanOrEqual(image.height,1024);XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    let result=try XCTUnwrap(s.cropPrepared).result;XCTAssertEqual(result.width,299700);XCTAssertEqual(result.layers[0].content,source.layers[0].content);XCTAssertTrue(s.commitCrop());await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,result);XCTAssertEqual(s.session.undoStack.count,1);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
    s.beginCrop();let task=s.cropTask;s.cancelCrop();await task?.value;XCTAssertNil(s.cropPrepared);XCTAssertEqual(s.document,source)
  }
  @MainActor func testHTTPLargeCropSharesFullResultDepthsHistoryAndNativeArchive()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      for depth in PixelDepth.allCases{var source=try self.fixture(width:100000,height:500);source.depth=depth;source.layers[0].content = .raster(try Surface(width:100000,height:500,depth:depth));doc.store.session=EditorSession(document:source);try service.share(doc);let params:[String:Any]=["x":1,"y":1,"width":99999,"height":499,"deleteCroppedPixels":true];let expected=try CropPreparation.prepare(.init(x:1,y:1,width:99999,height:499),document:source).result
        let status=try await h.edit(service,doc,"document.crop",params);XCTAssertEqual(status,200);XCTAssertEqual(doc.store.document,expected);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc.store.document)),expected);let undo=try await h.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(doc.store.document,source)
      }
    }
  }
  @MainActor func testLargeCropInvalidBusyStaleAndRevokedRequestsDoNotPublish()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let source=try self.fixture(width:100000,height:500),s=doc.store;s.session=EditorSession(document:source);try service.share(doc);let params:[String:Any]=["x":1,"y":1,"width":99999,"height":499]
      let invalid=try await h.edit(service,doc,"document.crop",params.merging(["width":300001]){_,b in b});XCTAssertEqual(invalid,400);let stale=try await h.edit(service,doc,"document.crop",params,revision:"old");XCTAssertEqual(stale,409);s.beginCrop();let busy=try await h.edit(service,doc,"document.crop",params);XCTAssertEqual(busy,409);s.cancelCrop()
      let gate=LargeCropGate();defer{gate.release()};s.cropPreparation={request,original in gate.wait();try Task.checkCancellation();return try CropPreparation.prepare(request,document:original)}
      let pending=Task{try await h.edit(service,doc,"document.crop",params)};let end=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<end{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();_=try? await pending.value;XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testPreparedNativeCropRejectsChangedDocumentAndStateMatchesSchema()async throws {
    let source=try fixture(width:100000,height:500),s=EditorStore(document:source);defer{s.cancelCrop();s.geometryTask?.cancel();s.renderTask?.cancel()};s.beginCrop();var draft=try XCTUnwrap(s.cropDraft);draft.frame.scaleX=99;s.updateCrop(draft);await s.cropTask?.value;XCTAssertNil(s.cropError);let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.cropState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:CropRequest.stateSchema));XCTAssertEqual(s.cropState["previewReady"] as? Bool,true);try s.session.execute(.renameLayer(source.layers[0].id,"Changed during crop"));let changed=s.document;XCTAssertTrue(s.commitCrop());await s.geometryTask?.value;XCTAssertNotNil(s.error);XCTAssertEqual(s.document,changed);XCTAssertEqual(s.session.undoStack.count,1)
  }
  @MainActor func testFullRangeSchemaNativeDraftAndAllModifierCursorsRemainShared()throws {
    let source=try fixture(),s=EditorStore(document:source);defer{s.cancelCrop();s.renderTask?.cancel()};XCTAssertEqual(CropRequest.apiSchema("width")?["maximum"] as? Int,300000);XCTAssertEqual(CropRequest.apiCapabilities["maximumCanvasPixels"] as? Int,90000000000);XCTAssertEqual(try CropDraft(document:source).request(background:.white).width,300000)
    let canvas=CraftCanvas(store:s),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift];s.tool = .crop
    for bits in 0..<16{let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,p in bits&(1<<p.offset) != 0 ? r.union(p.element):r};canvas.updateCursorModifiers(f);let before=canvas.toolCursor;_=s.cropState;canvas.updateCursorModifiers(f);XCTAssertEqual(canvas.toolCursor,before)};XCTAssertEqual(AutomationTests.expectedCommandCount,239);XCTAssertEqual(ActionLibraryFile.maximumVersion,44)
  }
  @MainActor func testBackgroundCropAvailabilityNativeCommitAndHTTPRemainConsistent()async throws {
    var source=try CraftDocument(width:100000,height:200);source.layers[0].background=true;let store=EditorStore(document:source);defer{store.cancelCrop();store.geometryTask?.cancel();store.renderTask?.cancel()};XCTAssertFalse(store.canRetainCroppedPixels);XCTAssertEqual(store.cropState["canRetainCroppedPixels"] as? Bool,false);store.beginCrop();var draft=try XCTUnwrap(store.cropDraft);draft.frame.scaleX=99;store.updateCrop(draft);await store.cropTask?.value;XCTAssertNil(store.cropError);XCTAssertTrue(store.commitCrop());await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertTrue(store.document.layers[0].isBackground);_=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,source)
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in doc.store.session=EditorSession(document:source);try service.share(doc);let expected=try CropPreparation.prepare(.init(x:10,y:1,width:99000,height:199),document:source).result;let code=try await h.edit(service,doc,"document.crop",["x":10,"y":1,"width":99000,"height":199]);XCTAssertEqual(code,200);XCTAssertEqual(doc.store.document,expected)}
  }

  @MainActor func testNativeDownloadVersionsPreserveBackgroundAndLinksWithoutDowngrade()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      var background=try CraftDocument(width:8,height:6);background.layers[0].background=true;doc.store.session=EditorSession(document:background);try service.share(doc);service.setDocumentTransfersEnabled(true);let id=try XCTUnwrap(service.shares.first?.id)
      for version in ["83","84"]{let response=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":version]);XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(response.1),background)}
      var linked=try self.fixture(width:8,height:6),copy=Layer(name:"Second",content:.raster(try Surface(width:8,height:6)));copy.visible=false;linked.layers.append(copy);try LayerLinks.apply(.link(linked.layers.map(\.id)),to:&linked);doc.store.session=EditorSession(document:linked)
      let legacy=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"83"]);XCTAssertEqual(legacy.0.statusCode,422)
      let accepted=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"84"]);XCTAssertEqual(accepted.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(accepted.1),linked)
      let metadata=try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String:Any]),header=try XCTUnwrap(metadata["downloadVersionHeader"] as? [String:Any]),schema=try XCTUnwrap(header["schema"] as? [String:Any]);XCTAssertEqual(schema["enum"] as? [String],(10...84).map(String.init));XCTAssertEqual(metadata["backgroundLayerVersion"] as? Int,83)
    }
  }

}
