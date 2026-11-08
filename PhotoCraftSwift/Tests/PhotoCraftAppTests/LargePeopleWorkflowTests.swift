import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor LargeWorkflowPeople: PeopleDetecting {
  let delay: Duration
  init(delay: Duration = .zero) { self.delay = delay }
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    if delay > .zero { try await Task.sleep(for: delay) }
    return [.init(instanceID: 1, mask: try .make(.rectangle(.init(x: 0, y: 0, width: image.width, height: image.height)),
      width: image.width, height: image.height, antiAlias: false))]
  }
}

final class LargePeopleWorkflowTests: XCTestCase {
  func fixture(_ width: Int = 300000, _ height: Int = 300000) throws -> CraftDocument {
    try CraftDocument(width: width, height: height)
  }
  @MainActor func stop(_ store: EditorStore) {
    store.peopleWorkspace.close(); store.objectFinder.cancel(); store.geometryTask?.cancel(); store.renderTask?.cancel()
  }
  @MainActor func testNativeLargePeopleDetectionHoverSelectionAndHistoryAreBounded() async throws {
    let store = EditorStore(document: try fixture(), actions: ActionLibrary(), brushes: BrushLibrary(), skies: SkyLibrary())
    defer { stop(store) }
    store.peopleDetector = LargeWorkflowPeople(); store.peopleFeaturesDetector = nil
    store.objectFinderEnabled = false; store.tool = .objectSelection
    XCTAssertTrue(store.canSelectPeople); XCTAssertFalse(store.canFindObjects); XCTAssertFalse(store.canUseSelectionTools)
    let original = store.document
    store.openPeoplePicker(); await store.peopleWorkspace.task?.value
    XCTAssertTrue(store.peopleWorkspace.presented)
    XCTAssertEqual(store.peopleWorkspace.scene?.analysisWidth, 1024)
    XCTAssertTrue(store.peopleWorkspace.scene?.reducedAnalysis == true)
    store.hoverPerson(1); await store.peopleWorkspace.overlayTask?.value
    let image = try XCTUnwrap(store.peopleWorkspace.image)
    XCTAssertEqual(image.width, 1024); XCTAssertEqual(image.height, 1024)
    XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    await store.selectPeople([1])?.value
    let selected = store.document
    XCTAssertEqual(selected.selection, .init(x: 0, y: 0, width: 300000, height: 300000))
    XCTAssertEqual(selected.layers, original.layers); XCTAssertEqual(store.session.undoStack.count, 1)
    _ = await store.requestHistory(redo: false).value; XCTAssertEqual(store.document, original)
    _ = await store.requestHistory(redo: true).value; XCTAssertEqual(store.document, selected)
  }
  @MainActor func testRealHTTPLargePeopleStateSelectionAndOversizedMaskRejection() async throws {
    let harness = AutomationTests()
    try await harness.withService(actions: ActionLibrary(), skies: SkyLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let store = document.store; defer { self.stop(store) }
      store.session = EditorSession(document: try self.fixture())
      store.peopleDetector = LargeWorkflowPeople(); store.peopleFeaturesDetector = nil
      let original = store.document; try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await harness.request(service, path: "/v1/documents/\(share)/commands", body: ["command":"selection.findPeople","revision":service.revision(store),"parameters":["includeThumbnails":true]])
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      let fields = json.filter { ["revision","peopleSelection","peopleThumbnails"].contains($0.key) }
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: fields))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: PeopleAPI.resultSchema))
      let state = try XCTUnwrap(json["peopleSelection"] as? [String:Any])
      XCTAssertEqual(state["analysisWidth"] as? Int, 1024); XCTAssertEqual(state["reducedAnalysis"] as? Bool, true)
      let tooLarge = try await harness.edit(service, document, "selection.findPeople", ["includeMasks":true])
      XCTAssertEqual(tooLarge, 413); XCTAssertEqual(store.document, original)
      let selected = try await harness.edit(service, document, "selection.selectPeople", ["cacheID":store.peopleWorkspace.cacheID.uuidString,"instanceIDs":[1]])
      XCTAssertEqual(selected, 200); XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertEqual(store.document.selection, .init(x: 0, y: 0, width: 300000, height: 300000))
      XCTAssertEqual(store.session.undoStack.count, 1)
      let undone = try await harness.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200); XCTAssertEqual(store.document, original)
    }
  }
  @MainActor func testLargeDetectionCancelAndChangedSourceCannotPublishLateResults() async throws {
    let store = EditorStore(document: try fixture(8192, 2), actions: ActionLibrary(), brushes: BrushLibrary(), skies: SkyLibrary())
    defer { stop(store) }
    store.peopleDetector = LargeWorkflowPeople(delay: .milliseconds(80)); store.peopleFeaturesDetector = nil
    store.tool = .objectSelection; store.objectFinderEnabled = false
    let original = store.document
    store.requestPeople(); let pending = store.peopleWorkspace.task
    store.stopPeopleDetection(); await pending?.value
    XCTAssertNil(store.peopleWorkspace.scene); XCTAssertFalse(store.peopleWorkspace.busy); XCTAssertEqual(store.document, original)
    store.requestPeople(force: true); let stale = store.peopleWorkspace.task
    var changed = store.document; changed.layers[0].x = 1; store.session = EditorSession(document: changed)
    await stale?.value
    XCTAssertNil(store.peopleWorkspace.scene); XCTAssertEqual(store.document, changed); XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPFullResolutionMaskBytesAndNativeSelectionAgreeForLongCanvas() async throws {
    let harness = AutomationTests()
    try await harness.withService(actions: ActionLibrary(), skies: SkyLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let store = document.store; defer { self.stop(store) }
      store.session = EditorSession(document: try self.fixture(8192, 2))
      store.peopleDetector = LargeWorkflowPeople(); store.peopleFeaturesDetector = nil
      let original = store.document; try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await harness.request(service, path: "/v1/documents/\(share)/commands", body: ["command":"selection.findPeople","revision":service.revision(store),"parameters":["includeMasks":true]])
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      let masks = try XCTUnwrap(json["peopleMasks"] as? [[String:Any]])
      let mask = try XCTUnwrap(masks.first)
      XCTAssertEqual(mask["width"] as? Int, 8192); XCTAssertEqual(mask["height"] as? Int, 2)
      let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(mask["coverageBase64"] as? String)))
      XCTAssertEqual(bytes, Data(repeating: 255, count: 8192 * 2))
      let fields = json.filter { ["revision","peopleSelection","peopleMasks"].contains($0.key) }
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: fields))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: PeopleAPI.resultSchema))
      XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
      let selected = try await harness.edit(service, document, "selection.selectPeople", ["cacheID":store.peopleWorkspace.cacheID.uuidString,"instanceIDs":[1]])
      XCTAssertEqual(selected, 200)
      let native = try XCTUnwrap(store.peopleWorkspace.scene).coverage(instanceIDs: [1], hardEdge: false)
      XCTAssertEqual(Data(try native.bytes), bytes)
      XCTAssertEqual(store.document.layers, original.layers); XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
}
