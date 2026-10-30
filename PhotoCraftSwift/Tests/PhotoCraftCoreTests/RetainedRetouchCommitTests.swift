import XCTest
@testable import PhotoCraftCore

final class RetainedRetouchCommitTests: XCTestCase {
  private func commands(_ document: CraftDocument, _ points: [StrokePoint], mask: Bool) throws -> [Command] {
    let id = document.layers[0].id
    var brush = CloneBrush(); brush.size = 9; brush.opacity = 0.7; brush.flow = 0.25
    let source = CloneSample(surface: try Surface(width: 128, height: 128, depth: document.depth, fill: Pixel(0.7, 0.2, 0.1)))
    var values: [Command] = [.cloneStamp(id, .init(source: source,
      mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: brush, points: points, mask: mask))]
    values += ToningTool.allCases.map { .toning(id, .init(tool: $0, brush: brush, points: points, mask: mask)) }
    var focus = FocusOptions(); focus.protectDetail = false
    values += FocusTool.allCases.map { .focus(id, .init(tool: $0, options: focus, brush: brush, points: points, mask: mask)) }
    return values
  }
  func testFinalPixelsAndHistoryAcrossToolsDepthsMasksAndTransforms() throws {
    for depth in PixelDepth.allCases { for mask in [false, true] {
      var original = try CraftDocument(width: 96, height: 72, depth: depth)
      var pixels = try Surface(width: 128, height: 128, depth: depth)
      pixels.mapPixels { x, y, _ in Pixel(Float(x % 17) / 16, Float(y % 13) / 12, 0.7, Float((x + y) % 7) / 6) }
      original.layers[0].content = .raster(pixels); original.layers[0].x = -20; original.layers[0].y = -25
      original.layers[0].affine = .rotation(6)
      if mask { original.layers[0].mask = pixels }
      original.selection = .init(x: 10, y: 8, width: 70, height: 48)
      let points: [StrokePoint] = (0..<12).map { i in
        let x = 20.0 + Double(i) * 4.0, y = 30.0 + sin(Double(i)) * 8.0
        return .init(x: x, y: y, pressure: 0.7)
      }
      let initial = try commands(original, Array(points.prefix(2)), mask: mask)
      let complete = try commands(original, points, mask: mask)
      for (a, b) in zip(initial, complete) {
        let retained = try DocumentRetouchStrokeSession(document: original, command: a)
        for batch in [Array(points[2..<5]), Array(points[5..<9])] { _ = try retained.append(batch) }
        var session = EditorSession(document: original); try session.startActionRecording(name: "Retouch release")
        try session.executePrepared(retained.prepareEdit(points: points))
        var expected = original; try b.apply(to: &expected)
        XCTAssertTrue(session.document == expected, "\(depth),mask=\(mask),\(b.label)")
        var reference = EditorSession(document: original)
        try reference.startActionRecording(name: "Retouch release"); try reference.execute(b)
        XCTAssertEqual(session.undoStack.count, reference.undoStack.count)
        if case .raster(let a) = session.document.layers[0].content, case .raster(let b) = expected.layers[0].content {
          XCTAssertTrue(try a.rgbaData(depth: .f32) == b.rgbaData(depth: .f32))
        }
        // Retained and complete commands must record identical semantic or unsupported steps.
        XCTAssertEqual(session.actionRecording?.snapshot.steps.first?.operation.unsupportedReason,
          reference.actionRecording?.snapshot.steps.first?.operation.unsupportedReason)
        if expected != original { XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 1) }
        else { XCTAssertTrue(session.actionRecording?.snapshot.steps.isEmpty == true) }
        try session.undo(); XCTAssertTrue(session.document == original)
        try session.redo(); XCTAssertTrue(session.document == expected)
        XCTAssertThrowsError(try retained.append([])); XCTAssertThrowsError(try retained.prepareEdit(points: points))
      }
    } }
  }
  func testAdmissionPrefixesAndStaleCommitCannotBypassValidation() throws {
    let original = try CraftDocument(width: 96, height: 72), id = original.layers[0].id
    let points: [StrokePoint] = [.init(x: 20, y: 30), .init(x: 60, y: 40)]
    for command in try commands(original, [points[0]], mask: false) {
      var locked = original; locked.layers[0].locked = true
      XCTAssertThrowsError(try DocumentRetouchStrokeSession(document: locked, command: command))
      let owner = try DocumentRetouchStrokeSession(document: original, command: command)
      XCTAssertThrowsError(try owner.prepareEdit(points: []))
      XCTAssertThrowsError(try owner.prepareEdit(points: [.init(x: 21, y: 30)]))
      let prepared = try owner.prepareEdit(points: points)
      var changed = EditorSession(document: original); try changed.execute(.opacity(id, 0.5))
      let before = changed.document
      XCTAssertThrowsError(try changed.executePrepared(prepared)); XCTAssertTrue(changed.document == before)
      XCTAssertEqual(changed.undoStack.count, 1)
    }
    XCTAssertFalse(DocumentRetouchStrokeSession.supports(document: original, command: .opacity(id, 0.5)))
  }
  func testCancelledPreparationIsRejected() async throws {
    let original = try CraftDocument(width: 96, height: 72)
    let commands = try commands(original, [.init(x: 20, y: 30)], mask: false)
    for command in commands {
      let task = Task.detached {
        let retained = try DocumentRetouchStrokeSession(document: original, command: command)
        withUnsafeCurrentTask { $0?.cancel() }
        return try retained.prepareEdit(points: [.init(x: 20, y: 30)])
      }
      do { _ = try await task.value; XCTFail("Cancelled preparation returned an edit") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
  }
}
