import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MultichannelOrderWorkflowTests: XCTestCase {
  @MainActor func testSavedRowCanDropBetweenInkPlatesAndHTTPUsesTheSameFinalIndex() async throws {
    let automation = AutomationTests()
    try await automation.withService(pressedMouseButtons: { 0 }) { service, file in
      var original = try CraftDocument(width: 2, height: 2)
      let ink = try InkPlane(width: 2, height: 2, depth: .u8, value: 0.25)
      let a = InkPlate(name: "Cyan", color: Pixel(0, 1, 1), samples: ink)
      let b = InkPlate(name: "Black", color: .black, samples: ink)
      original = try original.replacingInkMode(.multichannel(.init(plates: [a, b])))
      let mask = AlphaChannel(name: "Saved", pixels: try Surface(width: 2, height: 2, fill: .white))
      original.alphaChannels = [mask]
      let store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      file.store.session = .init(document: original)
      try service.share(file)
      let provider = ChannelDrag.provider(store: store, source: .alpha(mask.id))
      let accepted = await ChannelDrag.receive(provider, destination: .reorder(.plate(a.id), after: true), in: store)
      XCTAssertTrue(accepted)
      let order = [a.id, mask.id, b.id]
      XCTAssertEqual(store.document.multichannelChannelOrder, order)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let parameters: [String: Any] = ["action": "moveMultichannel", "target": mask.id.uuidString, "index": 1]
      let stale = try await automation.edit(service, file, "channel.edit", parameters, revision: "obsolete")
      XCTAssertEqual(stale, 409)
      let code = try await automation.edit(service, file, "channel.edit", parameters)
      XCTAssertEqual(code, 200)
      XCTAssertEqual(file.store.document, store.document)
      XCTAssertEqual(file.store.selectionChannelState["multichannelOrder"] as? [String], order.map(\.uuidString))
      let undo = try await automation.edit(service, file, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(file.store.document, original)
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }
}
