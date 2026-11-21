import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GenerativeFillWorkflowTests: XCTestCase {
  func testPromptCommandParametersAndLegacyBlankPrompt() throws {
    func options(_ parameters: [String: Any]) throws -> (prompt: String, seed: UInt32?, count: Int, target: UUID?, reference: UUID?) {
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
    let target = UUID()
    XCTAssertEqual(try options(["targetLayerID": target.uuidString, "variationCount": 2]).target, target)
    XCTAssertNil(try options(["targetLayerID": target.uuidString]).seed)
    XCTAssertThrowsError(try options(["targetLayerID": "not a UUID"]))
    XCTAssertThrowsError(try options(["targetLayerID": target.uuidString, "prompt": " "]))
    let reference = UUID()
    XCTAssertEqual(try options(["targetLayerID": target.uuidString, "referenceVariationID": reference.uuidString]).reference, reference)
    XCTAssertThrowsError(try options(["referenceVariationID": reference.uuidString]))
    XCTAssertThrowsError(try options(["targetLayerID": target.uuidString, "referenceVariationID": "invalid"]))
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

  @MainActor func testPromptedBatchAfterReopeningMatchesNativeAndHTTP() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional pinned prompt model on Apple Silicon with macOS 26 or later.")
    }
    let key = GenerativeFillModelPreference.promptKey
    let previous = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      var document = try CraftDocument(width: 128, height: 128)
      document.layers[0].content = .raster(try Surface(width: 128, height: 128, fill: Pixel(0.72, 0.62, 0.48)))
      document.selection = IntRect(x: 30, y: 27, width: 69, height: 73)
      store.session = EditorSession(document: document)
      try service.share(shared)
      let initial = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["prompt": "a small green pear on a table", "seed": 73], timeout: 120)
      XCTAssertEqual(initial, 200)
      var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(store.document))
      let layer = try XCTUnwrap(reopened.layers.last)
      reopened.activeLayerID = layer.id
      reopened.setCoverageSelection(nil)
      store.session = EditorSession(document: reopened)
      let original = try XCTUnwrap(GenerativeFillVariations.read(layer))
      XCTAssertEqual(original.entries.count, 1)
      store.beginGenerativeFillBatch(layer.id)
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertEqual(draft.prompt, original.prompt)
      draft.variationCount = 1
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertTrue(store.document == reopened)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["targetLayerID": layer.id.uuidString, "variationCount": 1], timeout: 120)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.document.layers.count, reopened.layers.count)
      XCTAssertEqual(store.activeLayer?.id, layer.id)
      XCTAssertEqual(store.activeLayer?.mask, layer.mask)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      let metadata = try XCTUnwrap(store.activeLayer.flatMap(GenerativeFillVariations.read))
      XCTAssertEqual(metadata.entries.map(\.seed), [73, 74])
      XCTAssertEqual(metadata.entries.first, original.entries.first)
      let state = try XCTUnwrap(GenerativeFillAPI.state(store)["selectedVariations"] as? [String: Any])
      XCTAssertEqual(state["canGenerateMore"] as? Bool, true)
      XCTAssertEqual(state["selectedID"] as? String, metadata.entries[1].id.uuidString)
      await store.undo()
      XCTAssertTrue(store.document == reopened)
    }
  }

  @MainActor func testRealGenerateSimilarAfterReopeningMatchesNativeAndHTTP() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_PROMPT_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional pinned prompt model on Apple Silicon with macOS 26 or later.")
    }
    let key = GenerativeFillModelPreference.promptKey
    let previous = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 128, height: 128)
      let background = try Surface(width: 128, height: 128, fill: Pixel(0.73, 0.62, 0.51))
      original.layers[0].content = .raster(background)
      let rectangle = IntRect(x: 31, y: 25, width: 68, height: 75)
      original.selection = rectangle
      let (recipe, mask) = try LocalGenerativeFill.capture(original)
      let colors = [Pixel(0.85, 0.18, 0.1), Pixel(0.1, 0.25, 0.85)]
      let candidates = try colors.map { color in
        var patch = try Surface(width: rectangle.width, height: rectangle.height, fill: Pixel(0.73, 0.62, 0.51))
        try patch.mapPixels(in: IntRect(x: 16, y: 22, width: 34, height: 31)) { _, _, _ in color }
        var layer = Layer(name: "Generative Fill", content: .raster(patch))
        layer.x = rectangle.x; layer.y = rectangle.y; layer.mask = mask
        return layer
      }
      let fill = try GenerativeFillVariations.pack(candidates, in: original, prompt: "a red ceramic mug on a table",
        seeds: [918, 919], context: recipe.encoded())
      try Command.generativeFill(fill).apply(to: &original)
      let first = try XCTUnwrap(GenerativeFillVariations.read(fill))
      try SmartObjectLayerCompIO.selection(in: original, layerID: fill.id, compID: first.entries[1].id).apply(to: &original)
      var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(original))
      let target = try XCTUnwrap(reopened.layers.last)
      reopened.activeLayerID = target.id
      reopened.setCoverageSelection(nil)
      let store = shared.store
      store.session = EditorSession(document: reopened)
      try service.share(shared)
      let referenceID = first.entries[0].id
      store.beginGenerativeFillBatch(target.id, referenceVariationID: referenceID)
      let draft = try XCTUnwrap(store.generativeFillDraft)
      XCTAssertEqual(draft.referenceVariationNumber, 1)
      XCTAssertEqual(draft.prompt, first.prompt)
      draft.variationCount = 1
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document)
      await store.undo()
      XCTAssertTrue(store.document == reopened)
      let parameters: [String: Any] = ["targetLayerID": target.id.uuidString, "referenceVariationID": referenceID.uuidString]
      let status = try await helper.edit(service, shared, GenerativeFillAPI.run, parameters, timeout: 120)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.document.layers.count, reopened.layers.count)
      XCTAssertEqual(store.activeLayer?.id, target.id)
      XCTAssertEqual(store.activeLayer?.mask, target.mask)
      let current = try Renderer.composite(store.document)
      XCTAssertEqual(try current.rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
      let metadata = try XCTUnwrap(store.activeLayer.flatMap(GenerativeFillVariations.read))
      XCTAssertEqual(Array(metadata.entries.prefix(2)), first.entries)
      XCTAssertEqual(metadata.entries.last?.seed, 920)
      XCTAssertEqual(metadata.entries.last?.referenceVariationID, referenceID)
      let state = try XCTUnwrap(GenerativeFillAPI.state(store)["selectedVariations"] as? [String: Any])
      XCTAssertEqual(state["canGenerateSimilar"] as? Bool, true)
      let entries = try XCTUnwrap(state["entries"] as? [[String: Any]])
      XCTAssertEqual(entries.last?["referenceVariationID"] as? String, referenceID.uuidString)
      for y in 0..<128 { for x in 0..<128 where !rectangle.contains(x, y) {
        XCTAssertTrue(current.pixel(x: x, y: y).hasSameBits(as: background.pixel(x: x, y: y)))
      } }
      await store.undo()
      XCTAssertTrue(store.document == reopened)
    }
  }
}
