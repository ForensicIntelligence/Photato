import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RetainedMaskPreviewTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run { _ = PhotatoApp.makeDelegate(isolatedSession: true); _ = NSApplication.shared }
  }
  private let points: [StrokePoint] = [.init(x: 12, y: 20, pressure: 0.5, time: 0),
    .init(x: 27, y: 25, pressure: 0.8, time: 12), .init(x: 42, y: 18, time: 24),
    .init(x: 59, y: 31, pressure: 0.6, time: 36)]
  private func source(_ target: Int, _ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 72, height: 48, depth: depth)
    var pixels = try Surface(width: 72, height: 48, depth: depth)
    pixels.mapPixels { x, y, _ in Pixel(Float(x + 1) / 74, Float(y + 1) / 50, 0.4, 0.8) }
    d.layers[0].content = .raster(pixels)
    if target == 1 {
      let layer = Layer(name: "Colour", content: .adjustment(AdjustmentBrushKind.colorVibrance.initial))
      d.layers.append(layer); d.activeLayerID = layer.id
    }
    if target != 2 { d.layers[d.layers.count - 1].mask = try Surface(width: 72, height: 48, depth: depth, fill: target == 0 ? .white : .black) }
    return d
  }
  private func brush() -> Brush {
    var b = Brush(); b.settings = .init(); b.settings?.seed = 523
    b.settings?.flow = 0.63; b.settings?.smoothing.amount = 0.9
    b.size = 7; b.opacity = 0.8; b.color = .black
    return b
  }
  private func command(_ target: Int, _ d: CraftDocument, _ newID: UUID, _ points: [StrokePoint], held: Bool = false) -> Command {
    var b = brush()
    if target == 0 {
      if held { b.settings?.smoothing.catchUpOnEnd = false }
      return .maskStroke(d.layers.last!.id, points, b)
    }
    return .adjustmentBrush(.init(layerID: target == 1 ? d.layers.last!.id : nil, newLayerID: newID,
      adjustment: AdjustmentBrushKind.colorVibrance.initial, points: points, brush: b))
  }
  func testWorkerPrefixesUseNativeTailPoliciesAndRejectOlderOrChangedInput() async throws {
    for depth in PixelDepth.allCases { for target in 0..<3 {
      let original = try source(target, depth), id = UUID()
      let worker = try XCTUnwrap(InteractiveBrushPreview(document: original, command: command(target, original, id, [])))
      var previous: RenderSnapshot?
      for count in 1...points.count {
        let values = Array(points.prefix(count))
        let next = try await worker.snapshot(base: original, points: values, previous: previous)
        let snapshot = try XCTUnwrap(next)
        var expected = original; try command(target, original, id, values, held: true).apply(to: &expected)
        XCTAssertEqual(snapshot.document, expected); XCTAssertEqual(snapshot.surface, try Renderer.composite(expected))
        previous = snapshot
      }
      do { _ = try await worker.snapshot(base: original, points: [points[0]], previous: previous); XCTFail("Older prefix accepted") }
      catch is CancellationError {} catch { XCTFail("\(error)") }
      do { _ = try await worker.snapshot(base: original, points: [.init(x: 1, y: 1)], previous: previous); XCTFail("Changed prefix accepted") }
      catch is CancellationError { XCTFail("Changed input was silently cancelled") } catch {}
      let result = try await worker.prepareCommit(base: original, points: points)
      let prepared = try XCTUnwrap(result)
      var expected = original; try command(target, original, id, points).apply(to: &expected)
      var session = EditorSession(document: original); try session.executePrepared(prepared)
      XCTAssertEqual(session.document, expected); XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, expected)
      do { _ = try await worker.snapshot(base: original, points: points, previous: previous); XCTFail("Finished preview accepted") }
      catch is CancellationError {} catch { XCTFail("\(error)") }
      do { _ = try await worker.prepareCommit(base: original, points: points); XCTFail("Finished commit accepted") } catch {}
    } }
  }
  @MainActor private func store(_ original: CraftDocument, _ target: Int) -> EditorStore {
    let s = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary(), paintPalette: PaintPalette())
    s.tool = target == 0 ? .brush : .adjustmentBrush
    if target == 0 { s.selectMask(original.layers.last!.id); s.brush.color = .black }
    s.adjustmentBrushKind = .colorVibrance
    s.brush.size = 7; s.brush.opacity = 0.8; s.brush.hardness = 0.7
    s.brushOptions.flow = 0.63; s.brushOptions.smoothing.amount = 0.9
    s.brushOptions.pressureSize = false; s.brushOptions.pressureOpacity = false
    return s
  }
  @MainActor private func begin(_ s: EditorStore) throws -> Command {
    s.beginBrush(points[0], zoom: 1)
    for point in points.dropFirst() { s.extendBrush(point) }
    XCTAssertNotNil(s.interactiveBrushPreview)
    let gesture = try XCTUnwrap(s.brushGesture)
    return gesture.adjustmentRequest.map(Command.adjustmentBrush) ?? gesture.command
  }
  @MainActor func testNativePreviewCancelCommitRecordingArchiveAndHistoryRetainFullCommand() async throws {
    for depth in [PixelDepth.u8, .u16] { for target in 0..<3 {
      let original = try source(target, depth), s = store(original, target)
      defer { s.cancelBrush(); s.renderTask?.cancel() }
      _ = try begin(s)
      let gesture = try XCTUnwrap(s.brushGesture)
      var held = original
      try (gesture.adjustmentRequest.map(Command.adjustmentBrush) ?? gesture.heldCommand).apply(to: &held)
      await s.brushPreviewTask?.value; await s.renderTask?.value
      XCTAssertNil(s.error); XCTAssertEqual(s.surface, try Renderer.composite(held))
      XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
      s.cancelBrush(); await s.renderTask?.value
      XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
      try s.session.startActionRecording(name: "Mask stroke")
      let full = try begin(s)
      var expected = original; try full.apply(to: &expected)
      s.finishBrush(); await s.geometryTask?.value; await s.renderTask?.value
      XCTAssertNil(s.error); XCTAssertEqual(s.document, expected); XCTAssertEqual(s.session.undoStack.count, 1)
      if target != 0 {
        XCTAssertEqual(s.adjustmentBrushLayer?.id, expected.activeLayerID)
        XCTAssertEqual(s.selectedLayerIDs, Set(expected.activeLayerID.map { [$0] } ?? []))
      }
      let action = try XCTUnwrap(s.session.actionRecording?.snapshot)
      XCTAssertEqual(action.steps.count, 1)
      let file = try ActionLibraryFile.decode(ActionLibraryFile(actions: [action]).encoded())
      if target != 0 { XCTAssertEqual(file.version, 61) }
      var replay = original; try file.actions[0].apply(to: &replay)
      XCTAssertEqual(replay.layers.map(\.mask), expected.layers.map(\.mask))
      XCTAssertEqual(replay.layers.map(\.content), expected.layers.map(\.content))
      XCTAssertEqual(try Renderer.composite(replay), try Renderer.composite(expected))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(expected)), expected)
      _ = await s.requestHistory(redo: false).value; XCTAssertEqual(s.document, original)
      _ = await s.requestHistory(redo: true).value; XCTAssertEqual(s.document, expected)
    } }
  }
  @MainActor func testNativeRetainedCommitsEqualExistingHTTPRoutesAndAdvertisedCapabilities() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, document in
      for target in 0..<3 {
        let original = try self.source(target), native = self.store(original, target)
        defer { native.cancelBrush(); native.renderTask?.cancel() }
        document.store.session = EditorSession(document: original); try service.share(document)
        let full = try self.begin(native), gesture = try XCTUnwrap(native.brushGesture)
        var parameters: [String: Any] = ["points": BrushAPI.json(gesture.points), "brush": BrushAPI.json(gesture.brush)]
        let name: String
        if case .adjustmentBrush(let request) = full {
          name = "adjustmentBrush.stroke"; parameters["kind"] = "colorVibrance"
          parameters["settings"] = AdjustmentBrushAPI.settings(request.adjustment)
          parameters["subtract"] = request.subtract; parameters["newLayer"] = request.layerID == nil
          if let id = request.layerID { parameters["layerID"] = id.uuidString }
          else { parameters["newLayerID"] = request.newLayerID.uuidString }
        } else {
          name = "paint.stroke"; parameters["target"] = "layerMask"; parameters["layerID"] = gesture.layerID.uuidString
        }
        native.finishBrush(); await native.geometryTask?.value
        let status = try await helper.edit(service, document, name, parameters)
        XCTAssertEqual(status, 200); XCTAssertNil(native.error); XCTAssertEqual(document.store.document, native.document)
        XCTAssertEqual(native.session.undoStack.count, 1); XCTAssertEqual(document.store.session.undoStack.count, 1)
        _ = await document.store.requestHistory(redo: false).value
        XCTAssertEqual(document.store.document, original)
      }
    }
    let preview = try XCTUnwrap(BrushAPI.capabilities["interactivePreview"] as? [String: Any])
    XCTAssertNotNil(preview["maskBrush"]); XCTAssertEqual(preview["performanceGuarantee"] as? Bool, false)
    let adjustment = try XCTUnwrap(AdjustmentBrushAPI.capabilities["interactivePreview"] as? [String: Any])
    XCTAssertEqual(adjustment["performanceGuarantee"] as? Bool, false)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: AdjustmentBrushAPI.capabilities))
  }
  func testWorkerPreservesMaskLightPauseAndUnpausedAdjustmentPreview() async throws {
    for adjustment in [false, true] {
      var original = try source(adjustment ? 1 : 0)
      var light = ModernAdjustment(.light); light.values["shadows"] = 45; light.values["exposure"] = 0.7
      original.layers.append(try light.layer(in: original))
      let id = original.layers[adjustment ? 1 : 0].id, b = brush()
      let command: Command = adjustment
        ? .adjustmentBrush(.init(layerID: id, adjustment: AdjustmentBrushKind.colorVibrance.initial, points: points, brush: b))
        : .maskStroke(id, points, b)
      let worker = try XCTUnwrap(InteractiveBrushPreview(document: original, command: command))
      let value = try await worker.snapshot(base: original, points: points, previous: nil)
      let snapshot = try XCTUnwrap(value)
      var expected = original
      if adjustment { try command.apply(to: &expected) }
      else {
        var held = b; held.settings?.smoothing.catchUpOnEnd = false
        try Command.maskStroke(id, points, held).apply(to: &expected)
        expected = LightEditingPreview(document: original, editingLayers: [id]).project(expected)
      }
      XCTAssertEqual(snapshot.document, expected); XCTAssertEqual(snapshot.surface, try Renderer.composite(expected))
      let result = try await worker.prepareCommit(base: original, points: points)
      var session = EditorSession(document: original); try session.executePrepared(try XCTUnwrap(result))
      var committed = original; try command.apply(to: &committed)
      XCTAssertEqual(session.document, committed)
    }
  }

  func testStaleSourcesCancellationAndUnsupportedTargetsKeepCompleteFallback() async throws {
    let original = try source(0), id = UUID(), initial = command(0, original, id, [])
    let worker = try XCTUnwrap(InteractiveBrushPreview(document: original, command: initial))
    _ = try await worker.snapshot(base: original, points: Array(points.prefix(2)), previous: nil)
    var changed = original; changed.name = "Changed source"
    let stalePreview = try await worker.snapshot(base: changed, points: points, previous: nil)
    let staleCommit = try await worker.prepareCommit(base: changed, points: points)
    XCTAssertNil(stalePreview); XCTAssertNil(staleCommit)
    let samples = points
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await worker.snapshot(base: original, points: samples, previous: nil)
    }
    do { _ = try await cancelled.value; XCTFail("Cancelled preview accepted") } catch is CancellationError {}
    let result = try await worker.prepareCommit(base: original, points: points)
    var session = EditorSession(document: original); try session.executePrepared(try XCTUnwrap(result))
    var expected = original; try command(0, original, id, points).apply(to: &expected)
    XCTAssertEqual(session.document, expected)
    var b = brush(); b.settings?.dual.enabled = true
    XCTAssertNil(InteractiveBrushPreview(document: original, command: .maskStroke(original.layers[0].id, points, b)))
    b = brush(); b.settings?.symmetry.mode = .vertical
    XCTAssertNil(InteractiveBrushPreview(document: original, command: .maskStroke(original.layers[0].id, points, b)))
    var request = AdjustmentBrushRequest(layerID: nil, adjustment: AdjustmentBrushKind.colorVibrance.initial, points: points, brush: brush())
    request.objectMask = try .make(.rectangle(.init(x: 0, y: 0, width: 20, height: 20)), width: 72, height: 48, antiAlias: false)
    XCTAssertNil(InteractiveBrushPreview(document: original, command: .adjustmentBrush(request)))
    var noMask = original; noMask.layers[0].mask = nil
    XCTAssertNil(InteractiveBrushPreview(document: noMask, command: initial))
  }
}
