import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class SelectionChannelPresentationWorkflowTests:XCTestCase {
  @MainActor func testSavedDocumentNamesMatchAPIWithoutChangingSourceModels()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,source in
      var model=try CraftDocument(width:16,height:4,name:"Untitled")
      model.selection = .init(x:2,y:0,width:8,height:4)
      source.store.session=EditorSession(document:model);source.displayName="Working source"
      let saved=CraftNSDocument(model:try model.selectionDocument(channelName:"Saved mask"))
      saved.displayName="Saved selection.photato";service.controller.addDocument(saved)
      defer{source.store.cancelChannelDialog();saved.store.renderTask?.cancel();service.controller.removeDocument(saved)}
      try service.share(source);try service.share(saved)
      let sourceBefore=source.store.document,savedBefore=saved.store.document
      source.store.beginChannelDialog(.load);let load=try XCTUnwrap(source.store.channelDialog)
      XCTAssertEqual(load.documentID,sourceBefore.id)
      load.documentID=savedBefore.id;load.resetDestination()
      XCTAssertEqual(load.documentID,savedBefore.id)
      XCTAssertEqual(load.displayName(for:sourceBefore),"Working source")
      XCTAssertEqual(load.displayName(for:savedBefore),"Saved selection.photato")
      let share=try XCTUnwrap(service.shares.first{$0.document === saved})
      XCTAssertEqual(service.state(share,document:saved)["name"] as? String,load.displayName(for:savedBefore))
      XCTAssertEqual(load.selectedDocument.name,"Untitled")
      source.store.cancelChannelDialog();source.store.beginChannelDialog(.save)
      let save=try XCTUnwrap(source.store.channelDialog);save.documentID=savedBefore.id
      XCTAssertEqual(save.displayName(for:save.selectedDocument),"Saved selection.photato")
      source.store.cancelChannelDialog()
      XCTAssertEqual(source.store.document,sourceBefore);XCTAssertEqual(saved.store.document,savedBefore)
      XCTAssertTrue(source.store.session.undoStack.isEmpty);XCTAssertTrue(saved.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testUnassociatedDialogRetainsModelNamesAndCapturesAliases()throws {
    var source=try CraftDocument(width:4,height:2,name:"Model source")
    source.selection = .init(x:0,y:0,width:4,height:2)
    let other=try source.selectionDocument(channelName:"Mask")
    let fallback=ChannelDialog(kind:.save,document:source,target:nil,defaults:.init(),sources:[other])
    XCTAssertEqual(fallback.displayName(for:source),"Model source")
    XCTAssertEqual(fallback.displayName(for:other),"Untitled")
    let named=ChannelDialog(kind:.load,document:source,target:nil,defaults:.init(),sources:[other],documentNames:[source.id:"Primary",other.id:"Saved selection.photato"])
    XCTAssertEqual(named.displayName(for:source),"Primary")
    XCTAssertEqual(named.displayName(for:other),"Saved selection.photato")
    XCTAssertEqual(named.documents,[source,other])
  }
}
