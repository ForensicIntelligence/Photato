import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct FixedForeground: ForegroundDetecting {
  var delay: Duration = .zero
  func mask(for image: Surface) async throws -> SelectionMask {
    if delay > .zero { try await Task.sleep(for: delay) }
    return try .make(.rectangle(.init(x: 1, y: 1, width: max(1, image.width - 2), height: max(1, image.height - 2))),
      width: image.width, height: image.height, antiAlias: false)
  }
}

final class ForegroundWorkflowTests: XCTestCase {
  func testCoreMaskCoordinatesPixelsSelectionPersistenceAndHistoryAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      var original = try CraftDocument(width: 8, height: 6, depth: depth)
      original.layers[0].x = 1
      original.layers[0].affine = .scale(0.8, 0.8)
      original.selection = .init(x: 0, y: 0, width: 2, height: 2)
      let id = original.layers[0].id
      let command = try await ForegroundSelection.command(document: original, layerID: id,
        removeBackground: true, detector: FixedForeground())
      var session = EditorSession(document: original)
      try session.execute(command)
      let result = session.document
      XCTAssertEqual(result.layers[0].content, original.layers[0].content)
      XCTAssertEqual(result.selection, original.selection)
      XCTAssertEqual(result.layers[0].maskProperties?.transform, try original.layers[0].coordinateTransform.inverted())
      XCTAssertEqual(result.layers[0].mask?.pixel(x: 2, y: 2).r, 1)
      XCTAssertEqual(result.layers[0].mask?.pixel(x: 0, y: 0).r, 0)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
      let image = try Renderer.composite(result)
      XCTAssertEqual(image.pixel(x: 0, y: 0).a, 0)
      XCTAssertEqual(image.pixel(x: 2, y: 2).a, 1, accuracy: 0.001)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, result)
      XCTAssertThrowsError(try session.execute(command))
      XCTAssertEqual(session.document, result)
    }
  }
  func testSubjectModesNoSubjectDimensionsAndLockGuards() async throws {
    var original = try CraftDocument(width: 8, height: 6)
    original.layers[0].locked = true
    let id = original.layers[0].id
    let selection = try await ForegroundSelection.command(document: original, layerID: id,
      removeBackground: false, detector: FixedForeground())
    var session = EditorSession(document: original)
    try session.execute(selection)
    let mask = try XCTUnwrap(session.document.selectionMask)
    try session.execute(.selectSubject(mask, .subtract)); XCTAssertNil(session.document.selection)
    try session.execute(.selectSubject(mask, .add)); XCTAssertNotNil(session.document.selection)
    do { _ = try await ForegroundSelection.command(document: original, layerID: id, removeBackground: true, detector: FixedForeground()); XCTFail("Locked removal") } catch {}
    XCTAssertThrowsError(try session.execute(.selectSubject(SelectionMask(width: 8, height: 6, bytes: .init(repeating: 0, count: 48)), .replace)))
    XCTAssertThrowsError(try session.execute(.removeBackground(id, SelectionMask(width: 1, height: 1, bytes: [255]))))
    XCTAssertThrowsError(try ForegroundSelection.checkSize(6001, 1))
    XCTAssertThrowsError(try ForegroundSelection.checkSize(4096, 4096))
  }
  @MainActor func testDesktopSelectRemoveUndoRedoAndCancel() async throws {
    let original = try CraftDocument(width: 8, height: 6)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    store.foregroundDetector = FixedForeground()
    store.detectSubject(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertNotNil(store.document.selectionMask)
    await store.undo(); XCTAssertEqual(store.document, original)
    store.detectSubject(removeBackground: true); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertTrue(store.editingMask)
    let result = store.document
    await store.undo(); XCTAssertEqual(store.document, original)
    await store.redo(); XCTAssertEqual(store.document, result)
    await store.undo()
    store.select(original.layers[0].id)
    store.foregroundDetector = FixedForeground(delay: .seconds(5))
    store.detectSubject(); XCTAssertTrue(store.geometryBusy)
    store.cancelActiveOperation(); await store.geometryTask?.value
    XCTAssertEqual(store.document, original); XCTAssertFalse(store.geometryBusy)
  }
  @MainActor func testPhotatoHTTPMatchesDesktopAndValidatesBusyStaleAndParameters() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store, original = shared.store.document
      store.foregroundDetector = FixedForeground()
      try service.share(shared)
      let parameters: [String: Any] = ["layerID": original.layers[0].id.uuidString]
      let reply = try await helper.edit(service, shared, "layer.removeBackground", parameters)
      XCTAssertEqual(reply, 200)
      let command = try await ForegroundSelection.command(document: original, layerID: original.layers[0].id, removeBackground: true, detector: FixedForeground())
      var expected = original; try command.apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      let stale = try await helper.edit(service, shared, "selection.subject", parameters, revision: "stale")
      XCTAssertEqual(stale, 409)
      let undo = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertEqual(store.document, original)
      var invalid = parameters; invalid["sampleAllLayers"] = 1
      let bad = try await helper.edit(service, shared, "selection.subject", invalid); XCTAssertEqual(bad, 400)
      invalid = parameters; invalid["mode"] = "bogus"
      let badMode = try await helper.edit(service, shared, "selection.subject", invalid); XCTAssertEqual(badMode, 400)
      store.geometryBusy = true
      let busy = try await helper.edit(service, shared, "selection.subject", parameters); XCTAssertEqual(busy, 409)
      store.geometryBusy = false
      let selected = try await helper.edit(service, shared, "selection.subject", parameters); XCTAssertEqual(selected, 200)
      XCTAssertNotNil(store.document.selectionMask)
    }
  }
  @MainActor func testPhotatoNativeCancelPreventsLateCommit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let original = shared.store.document
      shared.store.foregroundDetector = FixedForeground(delay: .seconds(5))
      try service.share(shared)
      let pending = Task { try await helper.edit(service, shared, "selection.subject", ["layerID": original.layers[0].id.uuidString]) }
      for _ in 0..<100 where !shared.store.geometryBusy { try await Task.sleep(for: .milliseconds(10)) }
      XCTAssertTrue(shared.store.geometryBusy)
      shared.store.cancelActiveOperation()
      let reply = try await pending.value
      XCTAssertEqual(reply, 409); XCTAssertEqual(shared.store.document, original)
      XCTAssertFalse(shared.store.geometryBusy)
    }
  }
  @MainActor func testRevokingShareDiscardsPreparedSubjectResult() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let before = shared.store.document
      shared.store.foregroundDetector = FixedForeground(delay: .milliseconds(200))
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first?.id)
      let request = Task { try await helper.edit(service, shared, "selection.subject", ["layerID": before.layers[0].id.uuidString]) }
      for _ in 0..<100 where !shared.store.geometryBusy { try await Task.sleep(for: .milliseconds(5)) }
      XCTAssertTrue(shared.store.geometryBusy)
      service.revoke(share)
      let reply = try await request.value
      XCTAssertEqual(reply, 409); XCTAssertEqual(shared.store.document, before)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  func testBackgroundRouteFramingAndSchemas() throws {
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method: "POST", path: "/v2/remove-background"), 4 * 1_024 * 1_024)
    let names = Set(AutomationCommand.definitions.map(\.name))
    XCTAssertTrue(names.isSuperset(of: ["selection.subject", "layer.removeBackground"]))
    let request = try payload(["output": ["mediaType": "image/png"]])
    XCTAssertEqual(request.mediaType, .png)
  }
  func payload(_ fields: [String: Any] = [:]) throws -> AdobeRemoveBackgroundRequest {
    var data: [String: Any] = ["image": ["source": ["url": "https://example.test/input.png"]]]
    data.merge(fields) { _, new in new }
    return try .init(data: JSONSerialization.data(withJSONObject: data))
  }
  func testPublishedEnvelopeStrictDefaultsAndInvalidOptions() throws {
    let defaults = try payload()
    XCTAssertEqual(defaults.mode, .cutout); XCTAssertFalse(defaults.trim)
    XCTAssertEqual(defaults.decontamination, 1); XCTAssertNil(defaults.mediaType)
    XCTAssertNil(try payload(["output": [:]]).mediaType)
    for fields: [String: Any] in [
      ["mode": "wrong"], ["trim": 1], ["colorDecontamination": true], ["colorDecontamination": -1],
      ["backgroundColor": ["red": 2, "green": 3, "blue": 4]], ["output": ["mediaType": "image/tiff"]],
      ["output": ["mediaType": "image/webp"]], ["outputs": []], ["options": [:]],
      ["image": ["source": ["url": "file:///tmp/image.png"]]],
      ["mode": "psd", "output": ["mediaType": "image/png"]]
    ] { XCTAssertThrowsError(try payload(fields), "\(fields)") }
  }
  func testAdobeCutoutMaskPSDTrimBackgroundAndPixelEquivalence() async throws {
    let original = try CraftDocument(width: 8, height: 6)
    let input = try RasterIO.encoded(original)
    for mode in ["cutout", "mask", "psd"] {
      for trim in [false, true] {
        let request = try payload(["mode": mode, "trim": trim, "colorDecontamination": 0])
        let encoded = try await request.execute(input: input, detector: FixedForeground())
        let decoded = try RasterIO.read(XCTUnwrap(encoded.first).data)
        XCTAssertEqual(decoded.width, trim ? 6 : 8); XCTAssertEqual(decoded.height, trim ? 4 : 6)
        if mode == "psd" { XCTAssertNotNil(decoded.layers.first?.mask) }
        let image = try Renderer.composite(decoded)
        if !trim {
          XCTAssertEqual(image.pixel(x: 0, y: 0).a, mode == "mask" ? 1 : 0)
          XCTAssertEqual(image.pixel(x: 2, y: 2), .white)
          if mode == "mask" { XCTAssertEqual(image.pixel(x: 0, y: 0), .black) }
        }
      }
    }
    let background = try payload(["backgroundColor": ["red": 255, "green": 0, "blue": 0, "alpha": 1], "colorDecontamination": 0])
    let encoded = try await background.execute(input: input, detector: FixedForeground())
    XCTAssertEqual(try Renderer.composite(RasterIO.read(encoded[0].data)).pixel(x: 0, y: 0), Pixel(1,0,0))
    let jpeg = try payload(["output": ["mediaType": "image/jpeg"]])
    let jpegData = try await jpeg.execute(input: input, detector: FixedForeground())[0].data
    XCTAssertTrue(jpegData.starts(with: [255,216]))
  }
  func testLocalDecontaminationDoesNotChangeOpaquePixelsOrAlpha() throws {
    var surface = try Surface(width: 3, height: 1, fill: Pixel(0,0,1))
    surface.setPixel(x: 1, y: 0, Pixel(0.5,0,0.5)); surface.setPixel(x: 2, y: 0, Pixel(1,0,0))
    let mask = try SelectionMask(width: 3, height: 1, bytes: [0,128,255])
    XCTAssertEqual(try AdobeRemoveBackgroundRequest.decontaminate(surface, mask: mask, amount: 0), surface)
    let result = try AdobeRemoveBackgroundRequest.decontaminate(surface, mask: mask, amount: 1)
    XCTAssertEqual(result.pixel(x: 2, y: 0), surface.pixel(x: 2, y: 0))
    XCTAssertGreaterThan(result.pixel(x: 1, y: 0).r, 0.99)
    XCTAssertLessThan(result.pixel(x: 1, y: 0).b, 0.01)
    XCTAssertEqual(result.pixel(x: 1, y: 0).a, 1)
  }
  @MainActor func testAdobeActualHTTPJobResultAndHostedMask() async throws {
    let helper = AutomationTests(), jobs = AutomationActionJobsTests()
    let transport = AutomationActionJobsTests.Transport()
    await transport.set(try RasterIO.encoded(CraftDocument(width: 8, height: 6)))
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport,
      foregroundDetector: FixedForeground()) { service, shared in
      let before = shared.store.document
      let body: [String: Any] = ["image": ["source": ["url": "https://example.test/input.png"]], "mode": "mask", "trim": true]
      let disabled = try await helper.request(service, path: "/v2/remove-background", body: body)
      XCTAssertEqual(disabled.0.statusCode, 403)
      service.setResourceJobsEnabled(true)
      let result = try await jobs.output(service, submit: "/v2/remove-background", payload: body, expectedMediaType: "image/png")
      let image = try RasterIO.read(result.2)
      XCTAssertEqual(image.width, 6); XCTAssertEqual(image.height, 4)
      XCTAssertEqual(shared.store.document, before)
    }
  }
  @MainActor func testFactorySubjectMenuBinding() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      func find(_ menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
          if item.identifier?.rawValue == "Select > Subject" { return item }
          if let sub = item.submenu, let result = find(sub) { return result }
        }
        return nil
      }
      XCTAssertEqual(try XCTUnwrap(find(menu)).action, #selector(AppDelegate.selectSubject))
    }
  }
}
