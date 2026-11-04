import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SelectionChannelDocumentWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:16,height:4,depth:depth);d.selection = .init(x:2,y:0,width:8,height:4);return d
  }
  @MainActor func testNativeNewDocumentLeavesSourceAndHistoryUntouched()async throws {
    _ = NSApplication.shared;_ = NSDocumentController.shared
    let controller=CraftDocumentController(),source=CraftNSDocument(model:try fixture());controller.addDocument(source)
    defer{for case let document as CraftNSDocument in controller.documents {document.store.renderTask?.cancel();document.close()}}
    source.makeWindowControllers();source.showWindows()
    let original=source.store.document;source.store.beginChannelDialog(.save);let draft=try XCTUnwrap(source.store.channelDialog)
    draft.documentID=draft.newDocumentID;draft.channelID=nil;draft.name="Standalone"
    source.store.commitChannelDialog(draft);await draft.task?.value
    XCTAssertNil(draft.error);XCTAssertNil(source.store.channelDialog)
    let created=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== source})
    XCTAssertTrue(created.store.document.isChannelOnly);XCTAssertEqual(created.store.document.alphaChannels?.first?.name,"Standalone")
    XCTAssertEqual(created.store.editingChannel,.alpha(try XCTUnwrap(created.store.document.alphaChannels?.first?.id)))
    XCTAssertTrue(created.isDocumentEdited);XCTAssertEqual(source.store.document,original);XCTAssertTrue(source.store.session.undoStack.isEmpty)
  }
  @MainActor func testStandaloneNativeBrushFillFilterCancelHistoryAndPersistencePolicy()async throws {
    let document=try fixture().selectionDocument(),store=EditorStore(document:document,quickMaskPreferences:QuickMaskPreferences())
    defer{store.renderTask?.cancel();store.cancelFilter()}
    store.tool = .brush;XCTAssertTrue(store.canUseBrush);XCTAssertTrue(store.canUsePixelPaint)
    var brush=Brush();brush.size=3;brush.hardness=1;brush.color = .black
    store.stroke([.init(x:4,y:2)],brush:brush)
    XCTAssertTrue(store.document.layers.isEmpty);XCTAssertNil(store.error);await store.undo();XCTAssertEqual(store.document,document)
    store.fill(color:.black);XCTAssertNil(store.error);XCTAssertTrue(store.document.layers.isEmpty);await store.undo();XCTAssertEqual(store.document,document)
    store.beginFilter(.gaussianBlur);XCTAssertNotNil(store.filterDraft);store.cancelFilter();XCTAssertEqual(store.document,document)
    store.beginFilter(.gaussianBlur);store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertTrue(store.document.isChannelOnly)
    XCTAssertNil(DocumentIO.persistenceIssue(store.document,format:.native));XCTAssertNil(DocumentIO.persistenceIssue(store.document,format:.psd))
    XCTAssertNotNil(DocumentIO.persistenceIssue(store.document,format:.png))
  }
  @MainActor func testLoadDialogIncludesActiveTransparencyWithoutSavedAlphaAndKeepsTarget()async throws {
    var model=try fixture();model.layers[0].background=nil;model.layers[0].content = .raster(try Surface(width:16,height:4,fill:Pixel(1,0,0,0.5)))
    model.setCoverageSelection(nil);let store=EditorStore(document:model);defer{store.cancelChannelDialog();store.renderTask?.cancel()}
    XCTAssertTrue(store.canLoadSelectionChannel);store.beginChannelDialog(.load);let draft=try XCTUnwrap(store.channelDialog)
    XCTAssertEqual(draft.selectionSource,.transparency(model.layers[0].id));store.commitChannelDialog(draft);await draft.task?.value
    XCTAssertNil(draft.error);XCTAssertEqual(store.document.layers,model.layers);XCTAssertEqual(try store.document.coverageSelection()?.byte(at:0),128)
  }
  @MainActor func testHTTPNewDocumentPermissionsNative85AndUntouchedSource()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,source in
      source.store.session=EditorSession(document:try self.fixture(.f32));try service.share(source);let original=source.store.document
      let parameters:[String:Any]=["action":"saveSelection","newDocument":true,"name":"Standalone"]
      let denied=try await helper.edit(service,source,"channel.edit",parameters);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true);let createdStatus=try await helper.edit(service,source,"channel.edit",parameters);XCTAssertEqual(createdStatus,201)
      let created=try XCTUnwrap(service.shares.last?.document);defer{created.store.renderTask?.cancel();service.controller.removeDocument(created)}
      XCTAssertTrue(created.store.document.isChannelOnly);XCTAssertEqual(source.store.document,original);XCTAssertTrue(source.store.session.undoStack.isEmpty)
      let id=try XCTUnwrap(service.shares.last?.id),path="/v1/documents/\(id)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"84"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"85"]);XCTAssertEqual(saved.0.statusCode,200)
      XCTAssertEqual(try NativeArchive.decode(saved.1),created.store.document)
      XCTAssertNotNil(service.state(try XCTUnwrap(service.shares.last),document:created)["channelOnly"])
    }
  }
  @MainActor func testHTTPSourceDescriptorsValidateAndMatchNativeWithComponentTarget()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      var model=try self.fixture();model.layers[0].background=nil;model.layers[0].content = .raster(try Surface(width:16,height:4,fill:Pixel(64/255,128/255,192/255,0.5)))
      document.store.session=EditorSession(document:model);try service.share(document);try document.store.selectEditingChannel(.red)
      let expected=try SelectionChannelSource.component(1).selection(in:model)
      let status=try await helper.edit(service,document,"channel.edit",["action":"loadSelection","source":["kind":"component","component":1]])
      XCTAssertEqual(status,200);XCTAssertEqual(try document.store.document.coverageSelection(),expected);XCTAssertEqual(document.store.componentTarget,.red)
      XCTAssertEqual(document.store.document.layers,model.layers)
      let saved=try await helper.edit(service,document,"channel.edit",["action":"saveSelection","name":"From Green"]);XCTAssertEqual(saved,200)
      XCTAssertEqual(document.store.document.layers,model.layers)
      for source:[String:Any] in [["kind":"component","component":4],["kind":"component","id":UUID().uuidString],["kind":"transparency"],["kind":"unknown"]] {
        let before=document.store.document,bad=try await helper.edit(service,document,"channel.edit",["action":"loadSelection","source":source]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,before)
      }
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testReplacedStandaloneSessionAndComponentSelectionPreparation()async throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()}
    let standalone=try fixture(.u16).selectionDocument()
    store.session=EditorSession(document:standalone);store.render()
    XCTAssertEqual(store.editingChannel,.alpha(try XCTUnwrap(standalone.alphaChannels?.first?.id)))
    store.tool = .brush;XCTAssertTrue(store.canUseBrush)
    var model=try fixture();model.layers[0].background=nil
    model.layers[0].content = .raster(try Surface(width:16,height:4,fill:Pixel(64/255,128/255,192/255)))
    store.session=EditorSession(document:model);store.render();try store.selectEditingChannel(.red)
    store.loadSelectionSource(.component(1));await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(try store.document.coverageSelection()?.byte(at:0),128)
    XCTAssertEqual(store.componentTarget,.red);XCTAssertEqual(store.document.layers,model.layers)
    let before=store.document
    store.performPreparedGeometry(label:"Forbidden RGB",allowAuxiliary:true,prepare:{document in
      try PreparedEdit(command:.fill(try XCTUnwrap(document.activeLayerID),.black),document:document)
    });await store.geometryTask?.value
    XCTAssertNotNil(store.error);XCTAssertEqual(store.document,before)
  }
  @MainActor func testFullChannelDestinationRetainsExistingAndNewDocumentChoicesAndAPIState()throws {
    var model=try fixture();let plane=try Surface(width:16,height:4,fill:.white)
    model.alphaChannels=(0..<52).map{AlphaChannel(name:"Saved \($0)",pixels:plane)}
    let store=EditorStore(document:model);defer{store.cancelChannelDialog();store.renderTask?.cancel()}
    store.beginChannelDialog(.save);let draft=try XCTUnwrap(store.channelDialog)
    XCTAssertNotNil(draft.channelID);XCTAssertTrue(draft.canSaveDestination)
    draft.channelID=nil;XCTAssertFalse(draft.canSaveDestination)
    draft.documentID=draft.newDocumentID;draft.resetDestination();XCTAssertTrue(draft.canSaveDestination)
    XCTAssertEqual(store.selectionChannelState["canSaveNewDocument"] as? Bool,false)
    store.cancelChannelDialog()
    XCTAssertEqual(store.selectionChannelState["canCreateAlpha"] as? Bool,false)
    XCTAssertEqual(store.selectionChannelState["canSaveNewDocument"] as? Bool,true)
    let sources=try XCTUnwrap(store.selectionChannelState["sources"] as? [[String:Any]])
    XCTAssertEqual(sources.filter{($0["kind"] as? String)=="alpha"}.count,52)
    for source in sources {let bytes=try JSONSerialization.data(withJSONObject:source);let raw=try JSONDecoder().decode(AutomationValue.self,from:bytes);_ = try SelectionChannelSourceAPI.decode(raw)}
  }

}
