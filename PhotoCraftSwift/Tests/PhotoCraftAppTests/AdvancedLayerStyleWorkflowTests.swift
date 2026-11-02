import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
import SwiftUI
@testable import PhotoCraft

final class AdvancedLayerStyleWorkflowTests:XCTestCase {
  @MainActor func expectEdit(_ helper:AutomationTests,_ service:AutomationService,_ document:CraftNSDocument,_ name:String,_ parameters:[String:Any]=[:],revision:String?=nil,expected:Int)async throws {
    let result=try await helper.edit(service,document,name,parameters,revision:revision);XCTAssertEqual(result,expected)
  }
  @MainActor func testExpandedBindingsSharedLightPreviewCancelCommitAndHistory()async throws {
    let original=try CraftDocument(width:24,height:24),store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    store.beginLayerStyle(.bevelEmboss);store.expandLayerEffect(0);let sheet=LayerStyleSheet(store:store)
    var value=try XCTUnwrap(store.layerStyleDraft?.style.effects.first)
    let controls=AdvancedLayerEffectControls(effect:Binding(get:{value},set:{value=$0}),document:original)
    controls.advanced(\.bevelStyle,.innerBevel).wrappedValue = .pillowEmboss
    controls.advanced(\.bevelTechnique,.smooth).wrappedValue = .chiselHard
    controls.advanced(\.directionUp,true).wrappedValue=false
    store.updateLayerEffect(0){$0=value};sheet.sharedLight(\.angle).wrappedValue=73.375;sheet.sharedLight(\.altitude).wrappedValue=31.25
    await store.renderTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,original)
    store.cancelLayerStyle();XCTAssertEqual(store.document,original)
    store.beginLayerStyle(.bevelEmboss);store.expandLayerEffect(0);sheet.sharedLight(\.angle).wrappedValue=73.375;sheet.sharedLight(\.altitude).wrappedValue=31.25;store.commitLayerStyle()
    XCTAssertEqual(store.document.globalLight,GlobalLight(angle:73.375,altitude:31.25));XCTAssertEqual(store.session.undoStack.count,1);let changed=store.document
    await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,changed)
  }
  @MainActor func testFactoryGlobalLightPathDoesNotCreateOrReplaceAStyle()async throws {
    let original=try CraftDocument(width:24,height:24),store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    XCTAssertTrue(AppDelegate.layerStyleMenuPaths.contains("Layer > Layer Style > Global Light…"));XCTAssertTrue(store.validateLayerStyleMenu("Layer > Layer Style > Global Light…"))
    store.beginGlobalLight();XCTAssertEqual(store.layerStyleDraft?.globalLightOnly,true);LayerStyleSheet(store:store).sharedLight(\.angle).wrappedValue=73.375;await store.renderTask?.value;XCTAssertEqual(store.document,original);store.cancelLayerStyle();XCTAssertEqual(store.document,original)
    store.beginGlobalLight();LayerStyleSheet(store:store).sharedLight(\.angle).wrappedValue=73.375;store.commitLayerStyle();XCTAssertNil(store.document.layers[0].style);XCTAssertEqual(store.document.globalLight?.angle,73.375);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,original)
  }
  @MainActor func testHTTPPatchPreservesIndependentDescriptorsAndUndoRejectsInvalidBusyStale()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let store=shared.store,id=store.document.layers[0].id
      var effect=LayerEffect(.dropShadow);effect.advanced=LayerEffectAdvanced();var style=LayerStyle(effects:[effect]);style.sourcePSDData=Data(repeating:37,count:100_000)
      try store.session.execute(.layerStyle([id],style));try service.share(shared);let original=store.document
      let parameters:[String:Any]=["layerIDs":[id.uuidString],"patch":["fillOpacity":0.375],"effectIndex":0,"effect":["size":7.125,"advanced":["knocksOut":false]],"globalLight":["angle":73.375,"altitude":31.25]]
      try await expectEdit(helper,service,shared,"layer.style.patch",parameters,expected:200)
      let changed=store.document;XCTAssertEqual(changed.layers[0].style?.sourcePSDData,style.sourcePSDData);XCTAssertEqual(changed.layers[0].style?.effects[0].size,7.125);XCTAssertEqual(changed.layers[0].style?.effects[0].advanced?.knocksOut,false);XCTAssertEqual(changed.globalLight,GlobalLight(angle:73.375,altitude:31.25))
      var expected=original;var edited=style;edited.fillOpacity=0.375;edited.effects[0].size=7.125;edited.effects[0].advanced?.knocksOut=false;try Command.layerStyles(LayerStyleEdit(layerIDs:[id],style:edited,globalLight:GlobalLight(angle:73.375,altitude:31.25))).apply(to:&expected);XCTAssertEqual(changed,expected)
      try await expectEdit(helper,service,shared,"layer.style.patch",parameters,revision:"stale",expected:409)
      store.beginLayerStyle();try await expectEdit(helper,service,shared,"document.globalLight",["angle":2,"altitude":30],expected:409);store.cancelLayerStyle()
      for bad:[String:Any] in [["layerIDs":[id.uuidString],"patch":["bogus":1]],["layerIDs":[id.uuidString],"effectIndex":31,"effect":["size":2]],["layerIDs":[id.uuidString,id.uuidString],"patch":["fillOpacity":0.2]],["layerIDs":[id.uuidString],"patch":["fillOpacity":2]]] {try await expectEdit(helper,service,shared,"layer.style.patch",bad,expected:400);XCTAssertEqual(store.document,changed)}
      try await expectEdit(helper,service,shared,"history.undo",expected:200);XCTAssertEqual(store.document,original)
      try await expectEdit(helper,service,shared,"history.redo",expected:200);XCTAssertEqual(store.document,changed)
    }
  }
  @MainActor func testNative75DownloadStateSchemaAndRecordedAction30()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,shared in
      try service.share(shared);try await expectEdit(helper,service,shared,"document.globalLight",["angle":113.375,"altitude":41.25],expected:200);service.setDocumentTransfersEnabled(true)
      let share=try XCTUnwrap(service.shares.first?.id),response=try await helper.request(service,path:"/v1/documents/\(share)");let state=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any]);XCTAssertEqual((state["globalLight"]as?[String:Any])?["angle"]as?Double,113.375)
      let old=try await helper.request(service,path:"/v1/documents/\(share)/file.photato");XCTAssertEqual(old.0.statusCode,422)
      let download=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"75"]);XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(download.1),shared.store.document)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(shared.store.document))
      let command=Command.globalLight(GlobalLight(angle:73.375,altitude:31.25)),step=RecordedActionStep(name:"Shared light",operation:ActionOperation(recording:command,in:shared.store.document));let action=RecordedAction(name:"Owned light",steps:[step]);var file=ActionLibraryFile();file.actions=[action];let bytes=try file.encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,30)
      let opening=try XCTUnwrap(AutomationService.documentOpeningCapabilities["pcraft"] as? [String:Any]);XCTAssertEqual(opening["sourceStyleArchiveVersion"] as? Int,75);XCTAssertEqual((opening["sourceLayerEffectKinds"] as? [String])?.count,10);XCTAssertEqual((opening["sourceAdjustmentExecutableKinds"] as? [String])?.count,16)
      let schema=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="layer.style.patch"});let envelope=try XCTUnwrap(schema.schema["properties"] as? [String:Any]),parameters=try XCTUnwrap(envelope["parameters"] as? [String:Any]),properties=try XCTUnwrap(parameters["properties"] as? [String:Any]);XCTAssertNotNil(properties["layerIDs"] as? [String:Any]);XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
}
