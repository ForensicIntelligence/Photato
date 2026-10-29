import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AlphaChannelWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width:24,height:16)
    d.selection = .init(x:4,y:4,width:12,height:8); return d
  }
  @MainActor func testDesktopQuickMaskPaintingFilterHistoryAndGuards() async throws {
    let d = try fixture(), store = EditorStore(document:d)
    defer { store.renderTask?.cancel() }
    store.toggleQuickMask(); XCTAssertNotNil(store.document.quickMask); XCTAssertEqual(store.editingChannel,.quickMask)
    var brush = Brush(); brush.size = 4; brush.hardness = 1; brush.color = .black
    store.stroke([.init(x:8,y:8)],brush:brush)
    XCTAssertEqual(store.document.quickMask?.pixels.pixel(x:8,y:8).r,0); XCTAssertEqual(store.document.layers,d.layers)
    XCTAssertFalse(store.canCopy()); XCTAssertFalse(store.canBeginSelectMask); XCTAssertTrue(store.canUseMenuFill)
    XCTAssertThrowsError(try store.executeEditorCommand(.newPixelLayer(.init(name:"Wrong target"))))
    XCTAssertEqual(store.document.layers,d.layers)
    let before = store.document
    store.beginFilter(.gaussianBlur); XCTAssertNotNil(store.filterDraft); await store.renderTask?.value
    XCTAssertNotNil(store.image); XCTAssertEqual(store.document,before)
    store.cancelFilter(); XCTAssertEqual(store.document,before)
    store.beginFilter(.gaussianBlur); store.commitFilter(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertNotEqual(store.document.quickMask,before.quickMask); XCTAssertEqual(store.document.layers,d.layers)
    await store.undo(); XCTAssertEqual(store.document,before)
    store.toggleQuickMask(); XCTAssertNil(store.document.quickMask); XCTAssertNotNil(store.document.selection)
    await store.undo(); XCTAssertNotNil(store.document.quickMask)
    let saved = try NativeArchive.encodeChunked(store.document); XCTAssertEqual(try NativeArchive.decode(saved),store.document)
    XCTAssertNotNil(DocumentIO.persistenceIssue(store.document,format:.psd))
    XCTAssertThrowsError(try DocumentIO.encode(store.document,format:.psd))
  }
  @MainActor func testSavedSelectionDialogCancelAndTargetSwitch() async throws {
    let d = try fixture(), store = EditorStore(document:d); defer { store.renderTask?.cancel() }
    store.beginChannelDialog(.save); let draft = try XCTUnwrap(store.channelDialog)
    draft.name = "Subject"; store.commitChannelDialog(draft)
    let channel = try XCTUnwrap(store.document.alphaChannels?.first); XCTAssertEqual(channel.name,"Subject")
    try store.selectAlphaChannel(channel.id); XCTAssertTrue(store.editingComponent)
    store.fill(color:.white,opacity:0.5); XCTAssertEqual(store.document.layers,d.layers)
    // A channel target must not let an unrelated prepared edit alter image pixels.
    XCTAssertThrowsError(try store.executeCompositePreparedEdit(PreparedEdit(command:.fill(d.layers[0].id,.white),document:store.document)))
    store.beginChannelDialog(.options); let options = try XCTUnwrap(store.channelDialog); options.options.opacity = 0.2
    let before = store.document; store.channelDialog = nil; XCTAssertEqual(store.document,before)
    let revision = store.revision
    try store.selectEditingChannel(.composite); XCTAssertNil(store.editingChannel); XCTAssertGreaterThan(store.revision,revision)
    await store.renderTask?.value
    try store.selectAlphaChannel(channel.id); let alphaRevision = store.revision
    store.select(d.layers[0].id); XCTAssertNil(store.editingChannel); XCTAssertGreaterThan(store.revision,alphaRevision)
    store.perform(.selection(nil)); store.beginChannelDialog(.load); let load = try XCTUnwrap(store.channelDialog); store.commitChannelDialog(load)
    XCTAssertEqual(store.document.selection,d.selection)
    try store.selectAlphaChannel(channel.id,overlay:true); await store.renderTask?.value; XCTAssertNotNil(store.image)
    store.perform(.channel(.delete(channel.id))); XCTAssertNil(store.alphaEditingID)
    await store.undo(); XCTAssertNotNil(store.document.alphaChannels?.first)
    let preview = try AutomationService.png(store.document,auxiliary:.alpha(channel.id),overlay:true)
    XCTAssertFalse(preview.isEmpty)
  }
  @MainActor func testHTTPChannelsHistorySchemasAndNativeVersionNegotiation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let save = try await helper.edit(service,shared,"channel.edit",["action":"saveSelection","name":"Subject"]); XCTAssertEqual(save,200)
      let channel = try XCTUnwrap(shared.store.document.alphaChannels?.first)
      let expected = try AlphaChannel.coverage(d.coverageSelection(),width:d.width,height:d.height,depth:d.depth); XCTAssertEqual(channel.pixels,expected)
      let view = try await helper.edit(service,shared,"channel.view",["target":channel.id.uuidString,"overlay":true]); XCTAssertEqual(view,200); XCTAssertEqual(shared.store.alphaEditingID,channel.id)
      let fill = try await helper.edit(service,shared,"channel.edit",["action":"fill","target":channel.id.uuidString,"value":0.25]); XCTAssertEqual(fill,200)
      var reference = d; reference.alphaChannels = [channel]; try Command.channel(.fill(.alpha(channel.id),0.25,1)).apply(to:&reference)
      XCTAssertEqual(shared.store.document,reference)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document.alphaChannels?.first,channel)
      let before = shared.store.document
      let stale = try await helper.edit(service,shared,"channel.edit",["action":"delete","target":channel.id.uuidString],revision:"old"); XCTAssertEqual(stale,409)
      shared.store.beginChannelDialog(.save)
      let busy = try await helper.edit(service,shared,"channel.edit",["action":"create"]); XCTAssertEqual(busy,409); shared.store.channelDialog = nil
      let bad = try await helper.edit(service,shared,"channel.edit",["action":"delete","target":channel.id.uuidString,"value":1]); XCTAssertEqual(bad,400); XCTAssertEqual(shared.store.document,before)
      service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id)
      let old = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"19"]); XCTAssertEqual(old.0.statusCode,422)
      let saved = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"20"]); XCTAssertEqual(saved.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(saved.1),before)
      let state = service.state(service.shares[0],document:shared); XCTAssertEqual((state["channels"] as? [[String:Any]])?.count,1)
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
      for name in ["channel.edit","channel.view"] { XCTAssertNotNil(AutomationCommand.definitions.first(where:{$0.name == name})?.schema) }
    }
  }
  @MainActor func testAPIQuickMaskStrokeAndRevocationAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let enter = try await helper.edit(service,shared,"channel.edit",["action":"quickMask","enabled":true]); XCTAssertEqual(enter,200)
      let stroke = try await helper.edit(service,shared,"channel.edit",["action":"stroke","target":"quickMask","size":4,"points":[["x":8,"y":8]],"value":0]); XCTAssertEqual(stroke,200)
      XCTAssertEqual(shared.store.document.quickMask?.pixels.pixel(x:8,y:8).r,0); XCTAssertEqual(shared.store.document.layers,d.layers)
      let exit = try await helper.edit(service,shared,"channel.edit",["action":"quickMask","enabled":false]); XCTAssertEqual(exit,200); XCTAssertNil(shared.store.document.quickMask)
      var large = try CraftDocument(width:512,height:512); try Command.channel(.quickMask(true,.init())).apply(to:&large); shared.store.session = EditorSession(document:large)
      let task = Task { try await helper.edit(service,shared,"channel.edit",["action":"filter","target":"quickMask","filter":["kind":"gaussianBlur","radius":30]]) }
      let deadline = Date().addingTimeInterval(5)
      while !shared.store.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(shared.store.geometryBusy); service.stop()
      _ = try? await task.value; XCTAssertEqual(shared.store.document,large)
    }
  }
}
