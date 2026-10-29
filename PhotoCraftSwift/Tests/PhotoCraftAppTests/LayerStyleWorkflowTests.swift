import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LayerStyleWorkflowTests: XCTestCase {
  @MainActor func testActualNumericBindingsDoNotOverlapObservedDraftAccess() throws {
    let store = EditorStore(document: try CraftDocument(width: 24, height: 24))
    defer { store.renderTask?.cancel() }
    store.beginLayerStyle(.dropShadow)
    let sheet = LayerStyleSheet(store: store)
    sheet.value(\.size, 5).wrappedValue = 18
    sheet.value(\.distance, 5).wrappedValue = 28
    XCTAssertEqual(store.layerStyleDraft?.style.effects[0].size, 18)
    XCTAssertEqual(store.layerStyleDraft?.style.effects[0].distance, 28)
    store.addLayerEffect(.gradientOverlay)
    sheet.gradientColor(false).wrappedValue = Pixel(1,0,0)
    store.removeLayerEffect()
    XCTAssertEqual(store.layerStyleDraft?.selected, 0)
    XCTAssertEqual(store.layerStyleDraft?.style.effects.count, 1)
    store.removeLayerEffect()
    XCTAssertEqual(store.layerStyleDraft?.style.effects.count, 0)
    store.cancelLayerStyle()
  }
  @MainActor func testPreviewCancelCommitCopyPasteClearAndHistory() async throws {
    let original=try CraftDocument(width:24,height:24),store=EditorStore(document:original)
    defer { store.renderTask?.cancel();EditorStore.copiedLayerStyle=nil }
    store.beginLayerStyle(.dropShadow);await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertTrue(store.hasToneDraft);XCTAssertFalse(store.canBeginLayerStyle)
    XCTAssertEqual(store.document,original);store.cancelLayerStyle();XCTAssertEqual(store.document,original)
    store.beginLayerStyle(.stroke);store.commitLayerStyle()
    XCTAssertNotNil(store.document.layers[0].style);XCTAssertEqual(store.session.undoStack.count,1)
    let changed=store.document
    store.copyLayerStyle();store.clearLayerStyle();XCTAssertNil(store.document.layers[0].style)
    store.pasteLayerStyle();XCTAssertEqual(store.document,changed)
    await store.undo();XCTAssertNil(store.document.layers[0].style)
    await store.redo();XCTAssertEqual(store.document,changed)
  }
  @MainActor func testHTTPStyleStateHistoryAndStaleBusyValidation() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      try service.share(shared)
      let before=shared.store.document,id=before.layers[0].id
      let parameters:[String:Any] = ["layerIDs":[id.uuidString],"style":["effects":[["kind":"dropShadow","size":3]]]]
      let status=try await helper.edit(service,shared,"layer.style",parameters);XCTAssertEqual(status,200)
      var expected=before;var effect=LayerEffect(.dropShadow);effect.size=3
      try Command.layerStyle([id],LayerStyle(effects:[effect])).apply(to:&expected)
      XCTAssertEqual(shared.store.document,expected)
      let stale=try await helper.edit(service,shared,"layer.style",parameters,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.beginLayerStyle()
      let busy=try await helper.edit(service,shared,"layer.style",parameters);XCTAssertEqual(busy,409)
      shared.store.cancelLayerStyle()
      let invalid=try await helper.edit(service,shared,"layer.style",["layerIDs":[id.uuidString],"style":["fillOpacity":2]])
      XCTAssertEqual(invalid,400);XCTAssertEqual(shared.store.document,expected)
      let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,before)
    }
  }
  @MainActor func testNativeDownloadRequiresVersion13AndStateExposesStyles() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try shared.store.session.execute(.layerStyle([shared.store.document.layers[0].id], LayerStyle(effects: [LayerEffect(.stroke)])))
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let stateReply = try await helper.request(service, path: "/v1/documents/\(id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateReply.1) as? [String: Any])
      XCTAssertNotNil((state["layers"] as? [[String: Any]])?.first?["style"] as? [String: Any])
      service.setDocumentTransfersEnabled(true)
      let old = try await helper.request(service, path: "/v1/documents/\(id)/file.photato")
      XCTAssertEqual(old.0.statusCode, 422)
      let current = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "13"])
      XCTAssertEqual(current.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(current.1), shared.store.document)
    }
  }
  func testAdobeDropShadowEditsUseNativeModelAndStrictContract() throws {
    let original=try CraftDocument(width:24,height:24);var session=EditorSession(document:original)
    let raw:[String:Any] = ["name":original.layers[0].name,"operation":["type":"edit"],"layerEffects":["dropShadow":[["distance":9,"opacity":80,"useGlobalLight":false,"angle":-45,"color":["rgb":["red":255,"green":0,"blue":0]]]]]]
    try AdobeProtectionEdit(raw,path:"layers[0]").apply(to:&session)
    let effect=try XCTUnwrap(session.document.layers[0].style?.effects.first)
    XCTAssertEqual(effect.kind,.dropShadow);XCTAssertEqual(effect.distance,9);XCTAssertEqual(effect.color,Pixel(1,0,0));XCTAssertEqual(effect.opacity,0.8)
    let result=try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
    XCTAssertEqual(result.layers[0].style?.effects.first?.distance,9)
    for fields:[String:Any] in [["noise":1],["antiAliased":true],["layerKnocksOut":false],["angle":181],["distance":true],["bogus":0]] {
      XCTAssertThrowsError(try AdobeLayerEffects.parse(["dropShadow":[fields]]))
    }
    XCTAssertThrowsError(try AdobeLayerEffects.parse(["dropShadow":[]]))
    XCTAssertEqual(try AdobeLayerEffects.parse(["dropShadow":[["distance":30000]]])?.first?.distance,30000)
  }
  @MainActor func testFactoryMenuStyleBindings() throws {
    try PhotoshopMenuTests().withMenus { _,menu in
      func find(_ menu:NSMenu,_ path:String)->NSMenuItem? {
        for item in menu.items { if item.identifier?.rawValue==path {return item};if let submenu=item.submenu,let result=find(submenu,path){return result} };return nil
      }
      for path in AppDelegate.layerStyleMenuPaths { XCTAssertEqual(try XCTUnwrap(find(menu,path)).action,#selector(AppDelegate.layerStyleMenu(_:))) }
    }
  }
}
