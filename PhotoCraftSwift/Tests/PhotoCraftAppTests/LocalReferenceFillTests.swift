import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LocalReferenceFillTests: XCTestCase {
  private struct RoundedSubject: ForegroundDetecting {
    func mask(for image: Surface) async throws -> SelectionMask {
      let centerX = Double(image.width) / 2, centerY = Double(image.height) / 2
      let radius = Double(min(image.width, image.height)) / 4
      let values: [UInt8] = (0..<(image.width * image.height)).map { index in
        let dx = Double(index % image.width) + 0.5 - centerX
        let dy = Double(index / image.width) + 0.5 - centerY
        return hypot(dx, dy) < radius ? 255 : 0
      }
      return try SelectionMask(width: image.width, height: image.height, bytes: values)
    }
  }

  private func artwork(_ color: Pixel = Pixel(0.9, 0.13, 0.07, 1)) throws -> Surface {
    var pixels = try Surface(width: 241, height: 156, fill: .clear)
    for y in 34..<130 {
      for x in 108..<216 where hypot(Double(x - 161), Double(y - 82)) < 48 {
        pixels.setPixel(x: x, y: y, color)
      }
    }
    return pixels
  }

  private func canvas() throws -> CraftDocument {
    var value = try CraftDocument(width: 92, height: 64)
    value.layers[0].content = .raster(try Surface(width: 92, height: 64, fill: Pixel(0.15, 0.25, 0.58, 1)))
    value.selection = IntRect(x: 20, y: 15, width: 48, height: 30)
    return value
  }

  func testObjectReferenceCropsTransparentSubjectAndWholeImageRetainsScene() async throws {
    let input = try artwork()
    let object = try await ReferenceInpainting.normalize(input, scope: .object)
    let whole = try await ReferenceInpainting.normalize(input, scope: .wholeImage)
    XCTAssertEqual(object.count, LocalGenerativeFill.exemplarByteCount)
    XCTAssertEqual(whole.count, LocalGenerativeFill.exemplarByteCount)
    XCTAssertNotEqual(object, whole)
    func colored(_ bytes: Data) -> Int {
      stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 190 && bytes[$0 + 1] < 90 }.count
    }
    XCTAssertGreaterThan(colored(object), colored(whole) * 2)

    if LocalGenerativeFill.supported {
      let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
      let encoder = temp.appending(path: "ImageEncoder.mlmodelc", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: temp) }
      try Data("[]".utf8).write(to: encoder.appending(path: "metadata.json"))
      XCTAssertThrowsError(try LocalGenerativeFill.validateReferenceModel(temp))
    }
  }

  func testSwapAndPlaceKeepMaskedPixelsAndEditableReferencesThroughPSDAndPSB() async throws {
    let original = try canvas()
    let reference = try await ReferenceInpainting.normalize(artwork(), scope: .object)
    let side = LocalGenerativeFill.side
    let red = try Surface(width: side, height: side, fill: Pixel(0.93, 0.2, 0.07, 1))
    let green = try Surface(width: side, height: side, fill: Pixel(0.21, 0.84, 0.10, 1))
    let base = try Renderer.composite(original)
    for intent in ReferenceInpainting.Options.Intent.allCases {
      let options = ReferenceInpainting.Options(scope: intent == .place ? .object : .wholeImage, intent: intent)
      let command = try await LocalReferenceFill.prepare(original, reference: reference, options: options,
        seed: .max, count: 2, detector: RoundedSubject()) { supplied, seeds, image, mask in
        XCTAssertEqual(supplied, reference)
        XCTAssertEqual(seeds, [.max, 0])
        XCTAssertEqual(image.count, side * side * 3)
        XCTAssertTrue(mask.contains(0) && mask.contains(1))
        return [red, green]
      }
      var session = EditorSession(document: original)
      try session.executePrepared(PreparedEdit(command: command, document: original))
      let edited = session.document
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(edited.selection, original.selection)
      XCTAssertEqual(edited.layers.first, original.layers.first)
      try session.undo()
      XCTAssertEqual(session.document, original)
      let output = try Renderer.composite(edited)
      let selection = try XCTUnwrap(original.selection)
      for y in 0..<original.height {
        for x in 0..<original.width where !selection.contains(x, y) {
          XCTAssertEqual(output.pixel(x: x, y: y), base.pixel(x: x, y: y))
        }
      }
      let corner = output.pixel(x: selection.x + 1, y: selection.y + 1)
      if intent == .place { XCTAssertEqual(corner, base.pixel(x: selection.x + 1, y: selection.y + 1)) }
      let center = output.pixel(x: selection.x + selection.width / 2, y: selection.y + selection.height / 2)
      XCTAssertGreaterThan(center.r, 0.8)
      for format in [DocumentIO.Format.native, .psd, .psb] {
        let data = try DocumentIO.encode(edited, format: format)
        let reopened = try DocumentIO.decode(data, native: format == .native, name: "Reference")
        let layer = try XCTUnwrap(reopened.layers.last)
        let record = try XCTUnwrap(GenerativeFillVariations.read(layer))
        XCTAssertEqual(record.referenceOptions, options)
        XCTAssertEqual(record.model, LocalGenerativeFill.referenceModelIdentifier)
        XCTAssertEqual(record.entries.map(\.seed), [.max, 0])
        XCTAssertNotNil(layer.mask)
        let inner = try SmartObjectIO.sourceDocument(XCTUnwrap(layer.smartObject))
        let contextBytes = try XCTUnwrap(inner.layers.first?.sourceTags?[PSDCodec.fillContextTag])
        let (context, _) = try ReferenceInpainting.Context.decode(contextBytes, options: options, source: inner)
        XCTAssertEqual(context.reference, reference)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try output.rgbaData(depth: .u8))
      }
    }
  }

  @MainActor func testReferenceAPIRequiresTransferPermissionAndValidScopeAndIntent() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      shared.store.session = EditorSession(document: try canvas())
      let encoded = Data([0, 1, 2]).base64EncodedString()
      let valid = ["scope": "object", "intent": "place", "dataBase64": encoded]
      var status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["referenceImage": valid, "seed": 47, "variationCount": 2])
      XCTAssertEqual(status, 403)
      service.setDocumentTransfersEnabled(true)
      status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["referenceImage": ["scope": "style", "intent": "place", "dataBase64": encoded]])
      XCTAssertEqual(status, 400)
      status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["referenceImage": valid, "prompt": "an orange"])
      XCTAssertEqual(status, 400)
      status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["referenceImage": valid, "targetLayerID": UUID().uuidString])
      XCTAssertEqual(status, 400)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testRealReferenceFillMatchesEditorAndHTTPAtSameSeed() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["PHOTATO_TEST_REFERENCE_FILL_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional local Paint by Example model.")
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let key = GenerativeFillModelPreference.referenceFillKey
    let old = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: folder), forKey: key)
    defer { UserDefaults.standard.set(old, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var reference = try CraftDocument(width: 241, height: 156)
      reference.layers[0].content = .raster(try artwork())
      let bytes = try DocumentIO.encode(reference, format: .png)
      let original = try canvas()
      let store = shared.store
      store.session = EditorSession(document: original)
      try service.share(shared)
      service.setDocumentTransfersEnabled(true)
      store.beginGenerativeFill()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      draft.imageReference = try ImageGenerationReference.prepare(bytes)
      draft.fillReferenceScope = .object
      draft.fillReferenceIntent = .swap
      draft.seed = 17
      draft.variationCount = 1
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.generativeFillDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let image = try Renderer.composite(store.document)
      let area = try XCTUnwrap(original.selection)
      var redPixels = 0
      for y in (area.y + 4)..<(area.y + area.height - 4) {
        for x in (area.x + 4)..<(area.x + area.width - 4) {
          let color = image.pixel(x: x, y: y)
          if color.r > color.b + 0.18 && color.r > color.g + 0.12 { redPixels += 1 }
        }
      }
      XCTAssertGreaterThan(redPixels, 12, "The red reference needs to affect the selected area, not only the untouched context.")
      let native = try image.rgbaData(depth: .u8)
      await store.undo()
      XCTAssertEqual(store.document, original)
      let status = try await helper.edit(service, shared, GenerativeFillAPI.run,
        ["seed": 17, "referenceImage": ["scope": "object", "intent": "swap", "dataBase64": bytes.base64EncodedString()]],
        timeout: 360)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), native)
      XCTAssertEqual(GenerativeFillVariations.read(try XCTUnwrap(store.activeLayer))?.referenceOptions?.intent, .swap)
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }
}
