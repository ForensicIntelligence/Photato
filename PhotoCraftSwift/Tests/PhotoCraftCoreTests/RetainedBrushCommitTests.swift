import XCTest
@testable import PhotoCraftCore

final class RetainedBrushCommitTests: XCTestCase {
  func testHeldPrefixesFinalPixelsActionsAndHistoryAcrossDepthAndDynamics() throws {
    for depth in PixelDepth.allCases {
      for variant in 0..<8 {
        var original = try CraftDocument(width: 96, height: 72, depth: depth)
        original.layers[0].content = .raster(try Surface(width: 96, height: 72, depth: depth, fill: Pixel(0.2, 0.4, 0.6, 0.7)))
        original.layers[0].affine = .translation(2, 3) * .rotation(5)
        original.selection = .init(x: 8, y: 8, width: 72, height: 56)
        let id = original.layers[0].id
        var brush = Brush(); brush.settings = .init(); brush.size = 12; brush.opacity = 0.6
        brush.color = Pixel(0.8, 0.1, 0.3); brush.settings!.flow = 0.35; brush.settings!.seed = 42
        brush.settings!.smoothing.amount = 0.8
        switch variant {
        case 1: brush.settings!.smoothing.catchUpOnEnd = false
        case 2: brush.settings!.scattering.enabled = true; brush.settings!.scattering.amount.jitter = 1.2
        case 3: brush.settings!.colorDynamics.enabled = true; brush.settings!.colorDynamics.perTip = true; brush.settings!.colorDynamics.hue = 0.5
        case 4: brush.settings!.texture.enabled = true; brush.settings!.wetEdges = true
        case 5: brush.erase = true
        case 6: brush.settings!.mode = .multiply; original.layers[0].protection = .transparency
        case 7: brush.settings!.shape.enabled = true; brush.settings!.shape.size.control = .penPressure; brush.settings!.buildUp = true
        default: break
        }
        let retained = try DocumentBrushStrokeSession(document: original, layerID: id, brush: brush)
        let points: [StrokePoint] = (0..<12).map { i in
          let x = 15.0 + Double(i) * 5.0
          let y = 30.0 + sin(Double(i)) * 12.0
          let pressure = Float(i % 4 + 1) / 4.0
          return StrokePoint(x: x, y: y, pressure: pressure, time: Double(i) * 16.0)
        }
        for i in 0..<11 {
          let actual = try retained.append([points[i]], includingReleaseTail: false)
          var held = brush; held.settings!.smoothing.catchUpOnEnd = false
          var expected = original; try Command.stroke(id, Array(points.prefix(i + 1)), held).apply(to: &expected)
          XCTAssertTrue(actual == expected, "depth=\(depth), variant=\(variant), prefix=\(i)")
        }
        let prepared = try retained.prepareEdit(points: points)
        var session = EditorSession(document: original); try session.startActionRecording(name: "Retained stroke")
        try session.executePrepared(prepared)
        var expected = original; try Command.stroke(id, points, brush).apply(to: &expected)
        XCTAssertTrue(session.document == expected)
        if case .raster(let a) = session.document.layers[0].content, case .raster(let b) = expected.layers[0].content {
          XCTAssertTrue(try a.rgbaData(depth: .f32) == b.rgbaData(depth: .f32))
        } else { XCTFail("Raster target lost") }
        XCTAssertEqual(session.undoStack.count, 1)
        let action = try XCTUnwrap(session.actionRecording?.snapshot); XCTAssertEqual(action.steps.count, 1)
        var replay = original; try action.apply(to: &replay); XCTAssertTrue(replay == expected)
        try session.undo(); XCTAssertTrue(session.document == original)
        try session.redo(); XCTAssertTrue(session.document == expected)
        XCTAssertThrowsError(try retained.append([])); XCTAssertThrowsError(try retained.prepareEdit(points: points))
      }
    }
  }

  func testChangedInputLockedTargetAndStaleCommitAreRejected() throws {
    let original = try CraftDocument(width: 64, height: 48), id = original.layers[0].id
    var brush = Brush(); brush.settings = .init()
    let retained = try DocumentBrushStrokeSession(document: original, layerID: id, brush: brush)
    let points: [StrokePoint] = [.init(x: 10, y: 20, time: 0), .init(x: 40, y: 25, time: 20)]
    _ = try retained.append([points[0]], includingReleaseTail: false)
    XCTAssertThrowsError(try retained.prepareEdit(points: []))
    XCTAssertThrowsError(try retained.prepareEdit(points: [.init(x: 11, y: 20, time: 0)]))
    let edit = try retained.prepareEdit(points: points)
    var changed = EditorSession(document: original); try changed.execute(.opacity(id, 0.5))
    let before = changed.document
    XCTAssertThrowsError(try changed.executePrepared(edit)); XCTAssertTrue(changed.document == before)
    XCTAssertEqual(changed.undoStack.count, 1)
    var locked = original; locked.layers[0].locked = true
    XCTAssertThrowsError(try DocumentBrushStrokeSession(document: locked, layerID: id, brush: brush))
    brush.settings!.dual.enabled = true
    XCTAssertThrowsError(try DocumentBrushStrokeSession(document: original, layerID: id, brush: brush))
  }

  func testCancelledPreparationCannotBeCommitted() async throws {
    let original = try CraftDocument(width: 64, height: 48)
    let task = Task.detached {
      var brush = Brush(); brush.settings = .init()
      let retained = try DocumentBrushStrokeSession(document: original, layerID: original.layers[0].id, brush: brush)
      _ = try retained.append([.init(x: 10, y: 20, time: 0)])
      withUnsafeCurrentTask { $0?.cancel() }
      return try retained.prepareEdit(points: [.init(x: 10, y: 20, time: 0)])
    }
    do { _ = try await task.value; XCTFail("Cancelled stroke produced a prepared edit") }
    catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
  }
}
