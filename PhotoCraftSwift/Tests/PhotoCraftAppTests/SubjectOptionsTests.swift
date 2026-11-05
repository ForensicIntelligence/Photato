import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct SampledSubject: ForegroundDetecting {
  func mask(for image: Surface) async throws -> SelectionMask {
    try await Task.sleep(for: .milliseconds(20))
    let pixel = image.pixel(x: 2, y: 2)
    let x = pixel.r > pixel.g ? 1 : 4
    return try .make(.rectangle(.init(x: x, y: 1, width: 2, height: 3)),
      width: image.width, height: image.height, antiAlias: false)
  }
}

final class SubjectOptionsTests: XCTestCase {
  @MainActor func testOptionsCaptureSamplingAndMatchHTTPSelectionHistoryAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), brushes: BrushLibrary(),
      pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 8, height: 6, depth: .u16)
      original.layers[0].content = .raster(try Surface(width: 8, height: 6, depth: .u16, fill: Pixel(0.9, 0.1, 0.1)))
      original.layers[0].locked = true
      original.layers.append(Layer(name: "Visible green", content:
        .raster(try Surface(width: 8, height: 6, depth: .u16, fill: Pixel(0.1, 0.9, 0.1)))))
      original.selection = .init(x: 0, y: 0, width: 1, height: 1)
      let id = original.layers[0].id
      original.activeLayerID = id
      shared.store.foregroundDetector = SampledSubject()
      try service.share(shared)

      for tool in [EditorTool.objectSelection, .quickSelection] {
        for all in [false, true] {
          shared.store.session = EditorSession(document: original)
          shared.store.selectedLayerIDs = [id]
          let native = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
          defer { native.cancelBrush(); native.renderTask?.cancel() }
          native.tool = tool
          native.foregroundDetector = SampledSubject()
          native.selectionMode = .subtract; native.selectionPaintMode = .intersect
          native.selectionSampleAllLayers = all
          native.subjectSampleAllLayers = !all
          XCTAssertTrue(native.canSelectSubjectFromToolOptions, "Locked pixels remain readable.")
          native.selectSubjectFromToolOptions()
          XCTAssertTrue(native.geometryBusy)
          XCTAssertFalse(native.canSelectSubjectFromToolOptions)
          native.selectionSampleAllLayers = !all // Must not change the captured detector input.
          native.selectSubjectFromToolOptions() // Busy click must not launch a second edit.
          await native.geometryTask?.value
          XCTAssertNil(native.error)
          XCTAssertEqual(native.document.selection, .init(x: all ? 4 : 1, y: 1, width: 2, height: 3))
          XCTAssertEqual(native.document.layers, original.layers)
          XCTAssertEqual(native.subjectSampleAllLayers, !all)
          XCTAssertEqual(native.session.undoStack.count, 1)

          let parameters: [String: Any] = ["layerID": id.uuidString,
            "sampleAllLayers": all, "mode": "replace"]
          var status = try await helper.edit(service, shared, "selection.subject", parameters)
          XCTAssertEqual(status, 200)
          XCTAssertEqual(shared.store.document, native.document)
          XCTAssertEqual(try NativeArchive.encodeChunked(shared.store.document),
            try NativeArchive.encodeChunked(native.document))
          XCTAssertEqual(shared.store.session.undoStack.count, 1)
          let result = native.document
          await native.undo()
          status = try await helper.edit(service, shared, "history.undo")
          XCTAssertEqual(status, 200); XCTAssertEqual(native.document, original)
          XCTAssertEqual(shared.store.document, original)
          await native.redo()
          status = try await helper.edit(service, shared, "history.redo")
          XCTAssertEqual(status, 200); XCTAssertEqual(native.document, result)
          XCTAssertEqual(shared.store.document, result)

          native.aiBusy = true
          XCTAssertFalse(native.canSelectSubjectFromToolOptions)
          native.selectSubjectFromToolOptions()
          XCTAssertEqual(native.document, result); native.aiBusy = false
          native.tool = .selectionBrush
          XCTAssertFalse(native.canSelectSubjectFromToolOptions)
          native.selectSubjectFromToolOptions(); XCTAssertEqual(native.document, result)
          native.tool = tool
          let state = try JSONDecoder().decode(AutomationValue.self,
            from: JSONSerialization.data(withJSONObject: native.selectionToolsState))
          XCTAssertNoThrow(try BrushAPI.merge(state, schema: SelectionToolAPI.stateSchema))
          XCTAssertEqual(native.selectionToolsState["canSelectSubject"] as? Bool, true)
        }
      }
      let mapping = SelectionToolAPI.subjectSelectionCapability
      XCTAssertEqual(mapping["command"] as? String, "selection.subject")
      XCTAssertEqual(mapping["tools"] as? [String], ["objectSelection", "quickSelection"])
      XCTAssertEqual(mapping["sampleAllLayersField"] as? String, "selectionTools.sampleAllLayers")
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: SelectionToolAPI.capabilities))
    }
  }
}
