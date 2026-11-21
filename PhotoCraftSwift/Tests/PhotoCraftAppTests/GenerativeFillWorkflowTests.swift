import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GenerativeFillWorkflowTests: XCTestCase {
  func testPromptCommandParametersAndLegacyBlankPrompt() throws {
    func options(_ parameters: [String: Any]) throws -> (prompt: String, seed: UInt32, count: Int) {
      let data = try JSONSerialization.data(withJSONObject: [
        "command": GenerativeFillAPI.run, "revision": "test", "parameters": parameters
      ])
      return try AutomationCommand(data: data).generativeFillOptions()
    }
    XCTAssertEqual(try options([:]).prompt, "")
    XCTAssertEqual(try options([:]).count, 1)
    XCTAssertEqual(try options(["prompt": "   "]).prompt, "")
    XCTAssertEqual(try options(["prompt": " blue mug ", "seed": 4_294_967_295]).prompt, "blue mug")
    XCTAssertEqual(try options(["prompt": "blue mug", "seed": 4_294_967_295]).seed, UInt32.max)
    XCTAssertThrowsError(try options(["seed": 7]))
    XCTAssertThrowsError(try options(["prompt": "mug", "seed": 2.5]))
    XCTAssertThrowsError(try options(["prompt": "mug", "seed": 4_294_967_296]))
    XCTAssertThrowsError(try options(["prompt": false]))
    XCTAssertThrowsError(try options(["prompt": "two\nlines"]))
    XCTAssertThrowsError(try options(["prompt": String(repeating: "x", count: 257)]))
    XCTAssertThrowsError(try options(["prompt": "blue mug", "modelURL": "file:///tmp/model"]))
    XCTAssertEqual(try options(["prompt": "mug", "variationCount": 3]).count, 3)
    XCTAssertThrowsError(try options(["prompt": "mug", "variationCount": 0]))
    XCTAssertThrowsError(try options(["prompt": "mug", "variationCount": 4]))
    XCTAssertThrowsError(try options(["prompt": "mug", "variationCount": 2.5]))
    XCTAssertThrowsError(try options(["variationCount": 2]))
  }

  @MainActor func testPromptChangesSelectedSubjectAndNativeMatchesHTTPAtSameSeed() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional pinned prompt model on Apple Silicon with macOS 26 or later.")
    }
    let key = GenerativeFillModelPreference.promptKey
    let previous = UserDefaults.standard.data(forKey: key)
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try LocalGenerativeFill.validatePromptModel(url)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: url), forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let seed: UInt32 = 472122
    let apple = "a shiny red apple resting on a table, studio product photograph"
    let mug = "a bright blue ceramic mug resting on a table, studio product photograph"
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 256, height: 256)
      var image = try Surface(width: 256, height: 256, fill: Pixel(211.0 / 255, 212.0 / 255, 205.0 / 255))
      try image.mapPixels(in: IntRect(x: 0, y: 135, width: 256, height: 121)) { _, _, _ in
        Pixel(175.0 / 255, 150.0 / 255, 128.0 / 255)
      }
      original.layers[0].content = .raster(image)
      let area = IntRect(x: 65, y: 57, width: 126, height: 129)
      original.setCoverageSelection(try SelectionMask.sampledCoverage(width: 256, height: 256, regions: [area]) { x, y in
        guard area.contains(x, y), x != 65 || y != 57 else { return 0 }
        return x == 65 || y == 57 ? 127 : 255
      })
      let store = shared.store
      store.session = EditorSession(document: original)
      try service.share(shared)
      store.beginGenerativeFill()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      draft.prompt = apple
      draft.seed = seed
      XCTAssertEqual(draft.variationCount, 3)
      draft.variationCount = 2
      XCTAssertNotNil(draft.selectedModel)
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document)
      let firstLayer = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(GenerativeFillVariations.read(firstLayer)?.entries.map(\.seed), [seed, seed + 1])
      let mask = try XCTUnwrap(store.activeLayer?.mask)
      XCTAssertEqual(mask.pixel(x: 0, y: 0).r, 0)
      XCTAssertEqual(mask.pixel(x: 1, y: 0).r, Float(127) / 255)
      XCTAssertEqual(store.document.selectionMask, original.selectionMask)
      await store.undo()
      XCTAssertEqual(store.document, original)

      let appleStatus = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["prompt": apple, "seed": seed, "variationCount": 2], timeout: 240)
      XCTAssertEqual(appleStatus, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
      let apiLayer = try XCTUnwrap(store.activeLayer)
      let choices = try XCTUnwrap(GenerativeFillVariations.read(apiLayer))
      XCTAssertEqual(choices.entries.map(\.seed), [seed, seed + 1])
      let state = try XCTUnwrap(GenerativeFillAPI.state(store)["selectedVariations"] as? [String: Any])
      XCTAssertEqual(state["selectedID"] as? String, choices.entries[0].id.uuidString)
      let switched = try await helper.edit(service, shared, SmartObjectLayerCompAPI.name,
        ["layerID": apiLayer.id.uuidString, "compID": choices.entries[1].id.uuidString], timeout: 60)
      XCTAssertEqual(switched, 200)
      XCTAssertEqual(store.activeLayer?.mask, mask)
      XCTAssertNotEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
      await store.undo()
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
      await store.undo()
      XCTAssertEqual(store.document, original)

      let mugStatus = try await helper.edit(service, shared, GenerativeFillAPI.run, ["prompt": mug, "seed": seed], timeout: 120)
      XCTAssertEqual(mugStatus, 200)
      let blue = try Renderer.composite(store.document)
      var redApple = 0, redMug = 0, blueApple = 0, blueMug = 0
      for y in 0..<original.height { for x in 0..<original.width {
        let a = native.pixel(x: x, y: y), b = blue.pixel(x: x, y: y)
        if original.selectionCoverage(x: x, y: y) == 0 {
          XCTAssertEqual(a, image.pixel(x: x, y: y))
          XCTAssertEqual(b, image.pixel(x: x, y: y))
        } else {
          if a.r > a.b + 0.18 && a.r > a.g + 0.18 { redApple += 1 }
          if b.r > b.b + 0.18 && b.r > b.g + 0.18 { redMug += 1 }
          if a.b > a.r + 0.18 { blueApple += 1 }
          if b.b > b.r + 0.18 { blueMug += 1 }
        }
      } }
      XCTAssertGreaterThan(redApple, redMug + 500)
      XCTAssertGreaterThan(blueMug, blueApple + 500)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }

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
