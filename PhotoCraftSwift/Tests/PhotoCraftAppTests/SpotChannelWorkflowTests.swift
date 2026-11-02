import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SpotChannelWorkflowTests:XCTestCase {
  @MainActor func testNativeCreateOptionsCancelCommitAndHistory()async throws {
    var d=try CraftDocument(width:24,height:16);d.selection = .init(x:4,y:3,width:12,height:8)
    let store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    store.beginChannelDialog(.newSpot);var draft=try XCTUnwrap(store.channelDialog);draft.name="Varnish";draft.solidity=0.75
    store.channelDialog=nil;XCTAssertEqual(store.document,d)
    store.beginChannelDialog(.newSpot);draft=try XCTUnwrap(store.channelDialog);draft.name="Varnish";draft.spotColor=Pixel(0.125,0.5,1);draft.solidity=0.75;store.commitChannelDialog(draft)
    XCTAssertNil(store.channelDialog);XCTAssertNil(store.error)
    let channel=try XCTUnwrap(store.document.alphaChannels?.first);XCTAssertEqual(channel.spot?.solidity,0.75);XCTAssertEqual(store.editingChannel,.alpha(channel.id));XCTAssertTrue(store.alphaOverlay)
    let created=store.document
    store.beginChannelDialog(.options);draft=try XCTUnwrap(store.channelDialog);draft.solidity=0.25;draft.name="Proof ink";store.commitChannelDialog(draft)
    XCTAssertEqual(store.document.alphaChannels?.first?.pixels,channel.pixels);XCTAssertEqual(store.document.alphaChannels?.first?.name,"Proof ink")
    await store.undo();XCTAssertEqual(store.document,created);await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,created)
  }
  @MainActor func testStaleNativeDraftAndPreviewDoNotMutateArtwork()async throws {
    let store=EditorStore(document:try CraftDocument(width:24,height:16));defer{store.renderTask?.cancel()}
    store.beginChannelDialog(.newSpot);let draft=try XCTUnwrap(store.channelDialog)
    var changed=store.document;changed.name="Changed";store.session=EditorSession(document:changed);store.commitChannelDialog(draft)
    XCTAssertNotNil(draft.error);XCTAssertEqual(store.document,changed);store.channelDialog=nil
    let channel=try changed.newSpotChannel(name:"Ink",ink:SpotInk(color:Pixel(0,1,1),solidity:0.5),density:0.625)
    try store.executeEditorCommand(.channel(.create(channel)));let before=store.document
    try store.selectAlphaChannel(channel.id,overlay:true);await store.renderTask?.value
    XCTAssertEqual(store.document,before);XCTAssertNotNil(store.image)
    let composite=try Renderer.composite(before),image=try ChannelPresentation.image(composite,document:before,target:.alpha(channel.id),overlay:false)
    XCTAssertEqual(image.width,24);XCTAssertEqual(store.document,before)
  }
  @MainActor func testHTTPSpotActionsMatchNativeAndNegotiateVersion76()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      try service.share(shared)
      let code=try await helper.edit(service,shared,"channel.edit",["action":"createSpot","name":"Cyan","value":0.5,"spot":["color":[0,1,1],"solidity":0.625]])
      XCTAssertEqual(code,200);let channel=try XCTUnwrap(shared.store.document.alphaChannels?.first)
      XCTAssertEqual(channel.spot,SpotInk(color:Pixel(0,1,1),solidity:0.625));XCTAssertEqual(channel.pixels.pixel(x:0,y:0).r,Pixel(0.5,0.5,0.5).quantized(shared.store.document.depth).r)
      let before=shared.store.document
      let fill=try await helper.edit(service,shared,"channel.edit",["action":"fill","target":channel.id.uuidString,"value":0.25]);XCTAssertEqual(fill,200)
      var reference=before;try Command.channel(.fill(.alpha(channel.id),0.25,1)).apply(to:&reference);XCTAssertEqual(shared.store.document,reference)
      let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,before)
      let options=try await helper.edit(service,shared,"channel.edit",["action":"configure","target":channel.id.uuidString,"name":"Ink","spot":["color":[1,0,1],"solidity":0.125]]);XCTAssertEqual(options,200)
      XCTAssertEqual(shared.store.document.alphaChannels?.first?.pixels,channel.pixels)
      service.setDocumentTransfersEnabled(true);let id=try XCTUnwrap(service.shares.first?.id)
      let old=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"75"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"76"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),shared.store.document)
      let state=service.state(service.shares[0],document:shared),channels=try XCTUnwrap(state["channels"]as?[[String:Any]])
      XCTAssertEqual(channels[0]["kind"]as?String,"spot");XCTAssertNotNil(channels[0]["spot"]as?[String:Any])
      XCTAssertNotNil(ChannelAPI.parameterSchema("spot"));XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndConversionAreAtomic()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      try service.share(shared)
      let create=try await helper.edit(service,shared,"channel.edit",["action":"createSpot"]);XCTAssertEqual(create,200)
      let before=shared.store.document,id=try XCTUnwrap(before.alphaChannels?.first?.id).uuidString
      let bad=try await helper.edit(service,shared,"channel.edit",["action":"configure","target":id,"spot":["color":[0,0,0],"solidity":2]]);XCTAssertEqual(bad,400)
      let unknown=try await helper.edit(service,shared,"channel.edit",["action":"createSpot","spot":["color":[0,0,0],"solidity":0,"extra":true]]);XCTAssertEqual(unknown,400)
      let stale=try await helper.edit(service,shared,"channel.edit",["action":"configure","target":id,"spot":NSNull()],revision:"old");XCTAssertEqual(stale,409)
      shared.store.beginChannelDialog(.options)
      let busy=try await helper.edit(service,shared,"channel.edit",["action":"createSpot"]);XCTAssertEqual(busy,409);shared.store.channelDialog=nil;XCTAssertEqual(shared.store.document,before)
      let convert=try await helper.edit(service,shared,"channel.edit",["action":"configure","target":id,"spot":NSNull()]);XCTAssertEqual(convert,200);XCTAssertNil(shared.store.document.alphaChannels?.first?.spot)
    }
  }
}
