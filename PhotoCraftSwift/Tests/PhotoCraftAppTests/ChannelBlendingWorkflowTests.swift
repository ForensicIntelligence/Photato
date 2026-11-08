import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ChannelBlendingWorkflowTests:XCTestCase {
  func style(_ values:[Int])->LayerStyle {var s=LayerStyle();s.restrictedChannels=values;return s}
  @MainActor func testNativeCheckboxMethodsPreviewCancelCommitUndoRedoAndStaleOriginal()async throws {
    let d=try CraftDocument(width:8,height:6),s=EditorStore(document:d);defer{s.renderTask?.cancel()}
    XCTAssertTrue(s.canBeginBlendingOptions);s.beginBlendingOptions();s.setBlendingChannel(0,enabled:false);await s.renderTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document,d);XCTAssertEqual(s.layerStyleDraft?.style.restrictedChannels,[0]);s.cancelLayerStyle();XCTAssertEqual(s.document,d)
    s.beginBlendingOptions();s.setBlendingChannel(2,enabled:false);s.commitLayerStyle();XCTAssertEqual(s.document.layers[0].style?.restrictedChannels,[2]);XCTAssertEqual(s.session.undoStack.count,1)
    let changed=s.document;await s.undo();XCTAssertEqual(s.document,d);await s.redo();XCTAssertEqual(s.document,changed)
    s.beginBlendingOptions();s.setBlendingChannel(1,enabled:false);try s.session.execute(.opacity(d.layers[0].id,0.5));let external=s.document;s.commitLayerStyle();XCTAssertEqual(s.document,external);XCTAssertNotNil(s.error)
  }
  @MainActor func testMaximumGeometryAvailabilityCopyPasteClearAndLocks()throws {
    let d=try CraftDocument(width:300000,height:300000,depth:.f32),s=EditorStore(document:d);defer{s.renderTask?.cancel();EditorStore.copiedLayerStyle=nil}
    XCTAssertFalse(s.canBeginLayerStyle);XCTAssertTrue(s.canBeginBlendingOptions);s.beginBlendingOptions();XCTAssertTrue(s.layerStyleDraft?.blendingOnly==true);s.setBlendingChannel(0,enabled:false);s.commitLayerStyle();XCTAssertNil(s.error)
    let changed=s.document;s.copyLayerStyle();XCTAssertTrue(s.canClearLayerStyle);s.clearLayerStyle();XCTAssertNil(s.document.layers[0].style);XCTAssertTrue(s.canPasteLayerStyle);s.pasteLayerStyle();XCTAssertEqual(s.document,changed)
    var locked=s.document;locked.layers[0].protection=[.all];s.session=EditorSession(document:locked);XCTAssertFalse(s.canBeginBlendingOptions)
  }
  @MainActor func testHTTPStylePatchStateUndoInvalidStaleBusyAndVersion89Download()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      let d=try CraftDocument(width:8,height:6);file.store.session=EditorSession(document:d);try service.share(file);let layer=d.layers[0].id
      var code=try await h.edit(service,file,"layer.style.patch",["layerIDs":[layer.uuidString],"patch":["restrictedChannels":[0,2]]]);XCTAssertEqual(code,200)
      let native=EditorStore(document:d);defer{native.renderTask?.cancel()};native.beginBlendingOptions();native.setBlendingChannel(0,enabled:false);native.setBlendingChannel(2,enabled:false);native.commitLayerStyle();XCTAssertEqual(file.store.document,native.document)
      let changed=file.store.document
      for bad:[String:Any]in [["restrictedChannels":[0,0]],["restrictedChannels":[3]],["restrictedChannels":[true]],["restrictedChannels":[0.5]]] {
        code=try await h.edit(service,file,"layer.style.patch",["layerIDs":[layer.uuidString],"patch":bad]);XCTAssertEqual(code,400);XCTAssertEqual(file.store.document,changed)
      }
      code=try await h.edit(service,file,"layer.style.patch",["layerIDs":[layer.uuidString],"patch":["restrictedChannels":[]]],revision:"old");XCTAssertEqual(code,409)
      file.store.beginBlendingOptions();code=try await h.edit(service,file,"layer.style.patch",["layerIDs":[layer.uuidString],"patch":["restrictedChannels":[]]]);XCTAssertEqual(code,409);file.store.cancelLayerStyle()
      let share=try XCTUnwrap(service.shares.first?.id);service.setDocumentTransfersEnabled(true)
      let old=try await h.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"88"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"89"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      let reply=try await h.request(service,path:"/v1/documents/\(share)");let state=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1)as?[String:Any]),layers=try XCTUnwrap(state["layers"]as?[[String:Any]]),json=try XCTUnwrap(layers[0]["style"]as?[String:Any]);XCTAssertEqual(json["restrictedChannels"]as?[Int],[0,2])
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:json));XCTAssertNoThrow(try BrushAPI.merge(value,schema:LayerStyle.apiSchema))
      code=try await h.edit(service,file,"history.undo");XCTAssertEqual(code,200);XCTAssertEqual(file.store.document,d)
    }
  }
  @MainActor func testPortableActions56StyleAndPatchReplayAndOldVersionReject()throws {
    let d=try CraftDocument(width:8,height:6);var s=EditorSession(document:d);try s.startActionRecording(name:"Channels");try s.execute(.layerStyle([d.layers[0].id],style([1])));let action=try XCTUnwrap(s.actionRecording?.snapshot);s.stopActionRecording()
    var library=ActionLibraryFile();library.actions=[action];library.version=56;XCTAssertEqual(library.requiredVersion,56);XCTAssertNoThrow(try ActionLibraryFile.decode(library.encoded()))
    library.version=55;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(library)));library.version=56
    var replay=EditorSession(document:d);try replay.execute(.action(action));XCTAssertEqual(replay.document,s.document)
    let edit=LayerStyleEdit(layerIDs:[d.layers[0].id],style:style([2]));var recording=EditorSession(document:d);try recording.startActionRecording(name:"Patch");try recording.execute(.layerStyles(edit));let patch=try XCTUnwrap(recording.actionRecording?.snapshot);recording.stopActionRecording();library.actions=[patch];XCTAssertEqual(library.requiredVersion,56)
  }
  @MainActor func testMenuRoutingTargetsAndPresentationKeepFactoryBindings()throws {
    try LayerStyleWorkflowTests().testFactoryMenuStyleBindings()
    let d=try CraftDocument(width:8,height:6),s=EditorStore(document:d);defer{s.renderTask?.cancel()}
    XCTAssertTrue(s.validateLayerStyleMenu("Layer > Layer Style > Blending Options…"));s.beginBlendingOptions();XCTAssertFalse(s.validateLayerStyleMenu("Layer > Layer Style > Blending Options…"));s.cancelLayerStyle()
    XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
  }
}
