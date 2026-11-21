import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LocalGeneratedImageReferenceTests: XCTestCase {
  private let side = LocalGenerativeFill.side

  private func artwork(swapped: Bool = false, colored: Bool = false) throws -> Data {
    let width = 320, height = 240
    var source = try CraftDocument(width: width, height: height)
    var pixels = try Surface(width: width, height: height, fill: colored ? Pixel(0.06, 0.10, 0.55) : .black)
    let big = swapped ? 238 : 82, small = swapped ? 64 : 256
    for y in 0..<height {
      for x in 0..<width {
        let shapes = hypot(Double(x - big), Double(y - 95)) < 65 || hypot(Double(x - small), Double(y - 167)) < 31
        if colored {
          let value = Float(sin(Double(x * y) / 1500) * 0.25 + 0.65)
          pixels.setPixel(x: x, y: y, Pixel(value * 0.8, value * 0.22, value * 0.05, 1))
        } else if shapes {
          pixels.setPixel(x: x, y: y, .white)
        }
      }
    }
    source.layers[0].content = .raster(pixels)
    return try DocumentIO.encode(source, format: .png)
  }

  func testBothReferenceModesAndEarlierVariationsSurviveEditableFormats() throws {
    var original = try CraftDocument(width: 96, height: 64)
    original.selection = IntRect(x: 4, y: 7, width: 8, height: 9)
    let image = try ImageGenerationReference.prepare(artwork())
    let red = try Surface(width: side, height: side, fill: Pixel(0.94, 0.12, 0.08))
    let blue = try Surface(width: side, height: side, fill: Pixel(0.05, 0.24, 0.93))
    var guideInputs: [Data] = []
    for kind in LocalGenerationGuide.Kind.allCases {
      let guide = try LocalGeneratedImage.makeGuide(image, use: kind, in: original)
      guideInputs.append(guide.rgba)
      let command = try LocalGeneratedImage.prepare(original, prompt: "oranges on a tabletop", seed: 14, count: 1, guide: guide) {
        prompt, seeds, samples, mask in
        XCTAssertEqual(prompt, "oranges on a tabletop")
        XCTAssertEqual(seeds, [14])
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
        XCTAssertTrue(mask.allSatisfy { $0 == 1 })
        return [red]
      }
      var session = EditorSession(document: original)
      try session.executePrepared(PreparedEdit(command: command, document: original))
      let edited = session.document
      XCTAssertEqual(edited.selection, original.selection)
      XCTAssertEqual(Array(edited.layers.dropLast()), original.layers)
      try session.undo()
      XCTAssertEqual(session.document, original)
      for format in [DocumentIO.Format.native, .psd, .psb] {
        var reopened = try DocumentIO.decode(DocumentIO.encode(edited, format: format), native: format == .native, name: "With Reference")
        let layer = try XCTUnwrap(reopened.layers.last)
        let metadata = try XCTUnwrap(GenerativeFillVariations.read(layer))
        XCTAssertEqual(metadata.guideUse, kind)
        let object = try XCTUnwrap(layer.smartObject)
        let inner = try SmartObjectIO.sourceDocument(object)
        XCTAssertEqual(try LocalGeneratedImage.savedGuide(from: inner, use: kind).rgba, guide.rgba)
        let before = reopened
        try GenerativeFillVariations.append(to: layer.id, in: before, prompt: nil, seed: 15, count: 1) {
          _, seeds, _, _ in
          XCTAssertEqual(seeds, [15])
          return [blue]
        }.apply(to: &reopened)
        let updated = try XCTUnwrap(reopened.layers.last)
        let updatedRecord = try XCTUnwrap(GenerativeFillVariations.read(updated))
        XCTAssertEqual(updatedRecord.entries.first, metadata.entries.first)
        XCTAssertEqual(updatedRecord.guideUse, kind)
        let updatedInner = try SmartObjectIO.sourceDocument(XCTUnwrap(updated.smartObject))
        XCTAssertEqual(try LocalGeneratedImage.savedGuide(from: updatedInner, use: kind).rgba, guide.rgba)
      }
    }
    XCTAssertNotEqual(guideInputs.first, guideInputs.last)
  }

  @MainActor func testReferenceHTTPValidatesPermissionsAndRejectsReplacingSavedInput() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let valid = ["prompt": "oranges", "referenceImage": ["use": "composition",
        "dataBase64": try artwork().base64EncodedString()]] as [String: Any]
      let denied = try await helper.edit(service, shared, GenerativeFillAPI.image, valid)
      XCTAssertEqual(denied, 403)
      service.setDocumentTransfersEnabled(true)
      let bad = ["prompt": "oranges", "referenceImage": ["use": "inspiration", "dataBase64": "eA=="]] as [String: Any]
      let invalid = try await helper.edit(service, shared, GenerativeFillAPI.image, bad)
      XCTAssertEqual(invalid, 400)
      let append = valid.merging(["targetLayerID": UUID().uuidString]) { left, _ in left }
      let replacement = try await helper.edit(service, shared, GenerativeFillAPI.image, append)
      XCTAssertEqual(replacement, 400)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      XCTAssertNil(shared.store.generativeFillOperationID)
    }
  }

  @MainActor func testRealReferenceNativeAndAuthenticatedHTTPProduceIdenticalPixels() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let promptModel = env["PHOTATO_TEST_PROMPT_FILL_MODEL"],
      let raw = env["PHOTATO_TEST_GUIDE_USE"], let use = LocalGenerationGuide.Kind(rawValue: raw),
      let guideModel = env["PHOTATO_TEST_GUIDE_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional prompt and chosen reference model.")
    }
    let key = GenerativeFillModelPreference.guideKey(use)
    let defaults = UserDefaults.standard
    let oldPrompt = defaults.data(forKey: GenerativeFillModelPreference.promptKey)
    let oldGuide = defaults.data(forKey: key)
    defaults.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: promptModel, isDirectory: true)),
      forKey: GenerativeFillModelPreference.promptKey)
    defaults.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: guideModel, isDirectory: true)), forKey: key)
    defer {
      defaults.set(oldPrompt, forKey: GenerativeFillModelPreference.promptKey)
      defaults.set(oldGuide, forKey: key)
    }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let source = try CraftDocument(width: 320, height: 240)
      let bytes = try artwork(colored: use == .style)
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      service.setDocumentTransfersEnabled(true)
      store.beginGenerateImage()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      draft.prompt = "Two oranges on a dark wooden tabletop, overhead view."
      draft.seed = 42
      draft.variationCount = 1
      draft.imageReference = try ImageGenerationReference.prepare(bytes)
      draft.referenceUse = use
      XCTAssertFalse(draft.missingGuideModel)
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document).rgbaData(depth: .u8)
      let target = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(GenerativeFillVariations.read(target)?.guideUse, use)
      let targetSource = try SmartObjectIO.sourceDocument(XCTUnwrap(target.smartObject))
      let guide = try LocalGeneratedImage.savedGuide(from: targetSource, use: use)
      await store.undo()
      XCTAssertEqual(store.document, source)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.image,
        ["prompt": draft.prompt, "seed": Int(draft.seed), "referenceImage": ["use": use.rawValue, "dataBase64": bytes.base64EncodedString()]],
        timeout: 300)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      let apiLayer = try XCTUnwrap(store.activeLayer)
      let apiInner = try SmartObjectIO.sourceDocument(XCTUnwrap(apiLayer.smartObject))
      XCTAssertEqual(try LocalGeneratedImage.savedGuide(from: apiInner, use: use).rgba, guide.rgba)
      await store.undo()
      XCTAssertEqual(store.document, source)
    }
  }
}
