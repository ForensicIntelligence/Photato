import AppKit
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ChannelViewWorkflowTests: XCTestCase {
  @MainActor func testUnrelatedPointerDoesNotBlockWindowlessSharedDocument() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 1 }) { service, doc in
      XCTAssertNil(doc.windowForSheet)
      try service.share(doc)
      let selected = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Red"])
      XCTAssertEqual(selected, 200)
      XCTAssertEqual(doc.store.channelView, RGBChannelView(preview: .red))
      doc.store.geometryBusy = true
      let busy = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Blue"])
      XCTAssertEqual(busy, 409)
      XCTAssertEqual(doc.store.channelView, RGBChannelView(preview: .red))
      doc.store.geometryBusy = false
    }
  }

  @MainActor func testNativeViewPreservesArchiveHistoryAndIndependentDocument() async throws {
    let doc = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 3, height: 2, background: Pixel(0.2, 0.4, 0.8)))
    let second = CraftNSDocument(model: doc.store.document)
    defer {
      doc.close()
      second.close()
    }
    let before = try doc.data(ofType: CraftNSDocument.nativeType)
    doc.store.previewChannel(.red)
    XCTAssertTrue(doc.store.setChannelVisibility(.green, visible: true))
    await doc.store.renderTask?.value
    XCTAssertEqual(doc.store.channelView.visible, [.red, .green])
    XCTAssertEqual(second.store.channelView, RGBChannelView())
    let image = try XCTUnwrap(doc.store.image)
    let displayed = try RasterIO.surface(image)
    let p = displayed.pixel(x: 0, y: 0)
    XCTAssertGreaterThan(p.r, 0)
    XCTAssertGreaterThan(p.g, 0)
    XCTAssertEqual(p.b, 0)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    XCTAssertTrue(doc.store.session.redoStack.isEmpty)
    XCTAssertEqual(doc.store.surface, try Renderer.composite(doc.store.document))
  }

  @MainActor func testVisibilityGuardsAndNoopDoNotInvalidateRevision() throws {
    let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 3, height: 2))
    defer { doc.close() }
    let store = doc.store
    store.previewChannel(.red)
    let before = store.channelView
    let revision = store.revision
    XCTAssertTrue(store.setChannelVisibility(.red, visible: false))
    XCTAssertEqual(store.revision, revision)
    store.geometryBusy = true
    XCTAssertFalse(store.setChannelVisibility(.green, visible: true))
    store.geometryBusy = false
    store.beginChannelPanelOptions()
    XCTAssertFalse(store.setChannelVisibility(.green, visible: true))
    store.cancelChannelPanelOptions()
    XCTAssertEqual(store.channelView, before)
    store.displayChannel = Int.max
    XCTAssertEqual(store.channelView, RGBChannelView())
  }

  @MainActor func testRealHTTPViewStateMatchesDesktopAndPreservesExistingPreviewContract()
    async throws
  {
    let helper = AutomationTests()
    try await helper.withService { service, doc in
      try doc.store.executeEditorCommand(
        .fill(try XCTUnwrap(doc.store.document.activeLayerID), Pixel(0.2, 0.4, 0.8)))
      try service.share(doc)
      let before = try doc.data(ofType: CraftNSDocument.nativeType)
      let historyCount = doc.store.session.undoStack.count
      let share = try XCTUnwrap(service.shares.first)
      let base = "/v1/documents/\(share.id)"
      let capabilities = try await helper.request(service, path: "/v1/capabilities")
      let catalogue = try XCTUnwrap(
        JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
      let schemas = try XCTUnwrap(catalogue["stateSchemas"] as? [String: Any])
      let schema = try XCTUnwrap(schemas["channelView"] as? [String: Any])
      XCTAssertEqual(schema["required"] as? [String], ["preview", "visible", "componentEditing"])
      XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
      let original = try await helper.request(service, path: base + "/preview.png")
      let oldRevision = service.revision(doc.store)
      let selected = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Red"])
      XCTAssertEqual(selected, 200)
      let visible = try await helper.edit(
        service, doc, "view.channelVisibility", ["channel": "Green", "visible": true])
      XCTAssertEqual(visible, 200)
      var expected = RGBChannelView(preview: .red)
      expected.setVisible(.green, true)
      XCTAssertEqual(doc.store.channelView, expected)
      await doc.store.renderTask?.value
      let response = try await helper.request(service, path: base + "/channel-preview.png")
      XCTAssertEqual(response.0.statusCode, 200)
      let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(response.1 as CFData, nil))
      let apiImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
      let apiPixels = try RasterIO.surface(apiImage)
      XCTAssertEqual(apiPixels, try RasterIO.surface(XCTUnwrap(doc.store.image)))
      XCTAssertEqual(apiPixels.pixel(x: 0, y: 0).b, 0)
      let unchanged = try await helper.request(service, path: base + "/preview.png")
      XCTAssertEqual(unchanged.1, original.1)
      let state = service.state(share, document: doc)
      let view = try XCTUnwrap(state["channelView"] as? [String: Any])
      XCTAssertEqual(view["preview"] as? String, "Red")
      XCTAssertEqual(view["visible"] as? [String], ["Red", "Green"])
      XCTAssertEqual(view["componentEditing"] as? Bool, false)
      let stale = try await helper.edit(
        service, doc, "view.channelPreview", ["channel": "Blue"], revision: oldRevision)
      XCTAssertEqual(stale, 409)
      let beforeNoop = service.revision(doc.store)
      let noop = try await helper.edit(
        service, doc, "view.channelVisibility", ["channel": "RGB", "visible": false])
      XCTAssertEqual(noop, 200)
      XCTAssertEqual(service.revision(doc.store), beforeNoop)
      XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
      XCTAssertEqual(doc.store.session.undoStack.count, historyCount)
      // A desktop view change is observable to the same client.
      doc.store.previewChannel(.blue)
      XCTAssertEqual(
        (service.state(share, document: doc)["channelView"] as? [String: Any])?["preview"]
          as? String, "Blue")
    }
  }

  @MainActor func testAPIRejectsInvalidBusyAndUnsharedViewRequestsWithoutMutation() async throws {
    let helper = AutomationTests()
    try await helper.withService { service, doc in
      try service.share(doc)
      let before = doc.store.channelView
      for parameters: [String: Any] in [
        ["channel": "Cyan"], ["channel": 2], ["channel": "red"], ["channel": "RGB", "extra": true],
      ] {
        let status = try await helper.edit(service, doc, "view.channelPreview", parameters)
        XCTAssertEqual(status, 400)
      }
      let invalidBool = try await helper.edit(
        service, doc, "view.channelVisibility", ["channel": "Red", "visible": "yes"])
      XCTAssertEqual(invalidBool, 400)
      doc.store.geometryBusy = true
      let busy = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Red"])
      XCTAssertEqual(busy, 409)
      doc.store.geometryBusy = false
      XCTAssertEqual(doc.store.channelView, before)
      let share = try XCTUnwrap(service.shares.first)
      let unauthorized = try await helper.request(
        service, path: "/v1/documents/\(share.id)/channel-preview.png", authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      service.revoke(share.id)
      let revoked = try await helper.request(
        service, path: "/v1/documents/\(share.id)/channel-preview.png")
      XCTAssertEqual(revoked.0.statusCode, 404)
    }
  }

  @MainActor func testMaskTargetRejectsVisibilityAndPreviewExitsItWithoutEditing() async throws {
    let helper = AutomationTests()
    try await helper.withService { service, doc in
      let fixture = try MaskInteractionTests().fixture()
      doc.store.session = EditorSession(document: fixture.document)
      let id = try XCTUnwrap(doc.store.document.activeLayerID)
      try service.share(doc)
      doc.store.toggleMaskView(id, mode: .gray)
      XCTAssertNotNil(doc.store.currentMaskView)
      let before = try doc.data(ofType: CraftNSDocument.nativeType)
      let rejected = try await helper.edit(
        service, doc, "view.channelVisibility", ["channel": "Blue", "visible": false])
      XCTAssertEqual(rejected, 422)
      XCTAssertEqual(doc.store.channelView, RGBChannelView())
      let preview = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Red"])
      XCTAssertEqual(preview, 200)
      XCTAssertNil(doc.store.currentMaskView)
      XCTAssertNil(doc.store.maskEditingLayerID)
      XCTAssertEqual(doc.store.channelView, RGBChannelView(preview: .red))
      XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
}
