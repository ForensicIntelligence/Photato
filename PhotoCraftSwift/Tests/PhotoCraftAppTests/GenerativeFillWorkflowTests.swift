import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GenerativeFillWorkflowTests: XCTestCase {
  @MainActor func testNativeAndAPIProduceTheSameLocalFillAndOneUndo() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_LAMA_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional pinned local model on Apple Silicon with macOS 26 or later.")
    }
    let key = GenerativeFillModelPreference.key
    let previous = UserDefaults.standard.data(forKey: key)
    let bookmark = try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path))
    UserDefaults.standard.set(bookmark, forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 96, height: 72)
      var image = try Surface(width: original.width, height: original.height, fill: Pixel(0.18, 0.67, 0.83))
      try image.mapPixels(in: IntRect(x: 40, y: 29, width: 15, height: 12)) { _, _, _ in Pixel(0.95, 0.05, 0.12) }
      original.layers[0].content = .raster(image)
      original.selection = IntRect(x: 38, y: 27, width: 19, height: 16)
      let store = shared.store
      store.session = EditorSession(document: original)
      XCTAssertTrue(store.canBeginGenerativeFill)
      store.beginGenerativeFill()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertNotNil(draft.model)
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document)
      XCTAssertNotEqual(native.pixel(x: 45, y: 32), image.pixel(x: 45, y: 32))
      await store.undo()
      XCTAssertEqual(store.document, original)
      try service.share(shared)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.run, [:], timeout: 60)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertNotNil(store.activeLayer?.mask)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .f32), try native.rgbaData(depth: .f32))
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }
}
