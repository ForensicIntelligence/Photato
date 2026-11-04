import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeChannelArithmeticWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var document=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.white,mode:.cmyk)
    document.selection = .init(x:299999,y:299999,width:1,height:1)
    document.alphaChannels=[AlphaChannel(name:"Source",pixels:try Surface(width:300000,height:300000,depth:.u16,fill:Pixel(0.25,0.25,0.25)))]
    return document
  }
  @MainActor func testMaximumNativeApplyImageDraftPreviewCancelCommitAndUndo()async throws {
    _ = NSApplication.shared
    let original=try fixture(),document=CraftNSDocument(model:original),controller=CraftDocumentController()
    controller.addDocument(document);let store=document.store
    defer {store.cancelChannelArithmetic();store.renderTask?.cancel();controller.removeDocument(document)}
    try store.selectModeComponents([0]);XCTAssertTrue(store.canBeginChannelArithmetic(.applyImage))
    store.beginChannelArithmetic(.applyImage);let draft=try XCTUnwrap(store.channelArithmeticWorkspace)
    draft.update {$0.source1.channel = .alpha(original.alphaChannels![0].id);$0.options.blending="normal"}
    await draft.task?.value;XCTAssertTrue(draft.ready);XCTAssertNil(draft.error);XCTAssertNotNil(draft.image)
    XCTAssertEqual(store.document,original);store.cancelChannelArithmetic();XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginChannelArithmetic(.applyImage);let active=try XCTUnwrap(store.channelArithmeticWorkspace)
    active.update {$0.source1.channel = .alpha(original.alphaChannels![0].id);$0.options.blending="normal"}
    await active.task?.value;XCTAssertTrue(active.ready);store.commitChannelArithmetic();await active.commitTask?.value
    XCTAssertNil(active.error);XCTAssertNil(store.channelArithmeticWorkspace);XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertEqual(store.modeComponentTargets,[0]);XCTAssertNotEqual(store.document,original)
    await store.undo();XCTAssertEqual(store.document,original)
  }
  @MainActor func testMaximumHTTPApplyImageMatchesDesktopAndValidatesBusyStaleAndSchema()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      defer{document.store.renderTask?.cancel()}
      try document.store.selectModeComponents([0])
      let channel=try XCTUnwrap(original.alphaChannels?.first)
      var request=ChannelArithmeticRequest(.applyImage);request.source1.channel = .alpha(channel.id);request.options.blending="normal"
      let prepared=try ChannelArithmeticPreparation.prepare(request,target:.pixels(original.layers[0].id,[0]),document:original)
      var expected=EditorSession(document:original);try expected.execute(XCTUnwrap(prepared.command))
      let parameters:[String:Any]=["source":["channel":"alpha","channelID":channel.id.uuidString],"blending":"normal"]
      let status=try await helper.edit(service,document,"image.applyImage",parameters)
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected.document);XCTAssertEqual(document.store.session.undoStack.count,1)
      let current=document.store.document
      let stale=try await helper.edit(service,document,"image.applyImage",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"image.applyImage",parameters);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let invalid=try await helper.edit(service,document,"image.applyImage",["opacity":101]);XCTAssertEqual(invalid,400)
      XCTAssertEqual(document.store.document,current)
      XCTAssertEqual(ChannelArithmeticAPI.capabilities["maximumNativePixels"] as? Int,90_000_000_000)
      let capacity=try XCTUnwrap(ChannelArithmeticAPI.capabilities["largeNativeArithmetic"] as? [String:Any])
      XCTAssertEqual(capacity["calculationsNewDocument"] as? Bool,true)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ChannelArithmeticAPI.capabilities))
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
  @MainActor func testMaximumHTTPCalculationsNewDocumentTransferPolicyAndNative86Download()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      defer{document.store.renderTask?.cancel()}
      let channel=try XCTUnwrap(original.alphaChannels?.first)
      let parameters:[String:Any]=["source1":["channel":"alpha","channelID":channel.id.uuidString],"source2":["channel":"alpha","channelID":channel.id.uuidString],"blending":"normal","result":"newDocument","name":"Maximum calculated"]
      let denied=try await helper.edit(service,document,"image.calculations",parameters);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let created=try await helper.edit(service,document,"image.calculations",parameters);XCTAssertEqual(created,201)
      let target=try XCTUnwrap(service.shares.last),output=try XCTUnwrap(target.document)
      defer{output.store.renderTask?.cancel();service.controller.removeDocument(output)}
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(output.store.document.colorMode,.grayscale);XCTAssertEqual(output.store.document.width,300000)
      let native=try XCTUnwrap(output.store.document.layers[0].nativeMode)
      XCTAssertEqual(native.rawWord(component:0,index:89_999_999_999),16384)
      let saved=try await files.request(service,path:"/v1/documents/\(target.id)/file.photato",headers:["X-Photato-Archive-Version":"86"])
      XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(saved.1),output.store.document)
    }
  }
}
