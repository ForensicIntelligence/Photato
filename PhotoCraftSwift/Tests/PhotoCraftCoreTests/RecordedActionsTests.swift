import XCTest
@testable import PhotoCraftCore

final class RecordedActionsTests: XCTestCase {
  func fixture() throws -> CraftDocument { try CraftDocument(width: 9, height: 7) }
  func testRecordingReplayOnDifferentDocumentAndOneHistoryStep() throws {
    let original = try fixture(); var recording = EditorSession(document: original)
    try recording.startActionRecording(name: "Blue print")
    let id = original.activeLayerID!
    try recording.execute(.fill(id, Pixel(0.1, 0.2, 0.8)))
    try recording.execute(.applyFilter(id, RasterFilter(.highPass)))
    try recording.execute(.imageSize(6, 4, 120, .bilinear))
    let action = try XCTUnwrap(recording.actionRecording?.snapshot)
    XCTAssertEqual(action.steps.count, 3)
    let decoded = try JSONDecoder().decode(RecordedAction.self, from: JSONEncoder().encode(action))
    let target = try fixture(); XCTAssertNotEqual(target.activeLayerID, id)
    var replay = EditorSession(document: target); try replay.execute(.action(decoded))
    XCTAssertEqual(replay.document.layers.map(\.content), recording.document.layers.map(\.content))
    XCTAssertEqual(replay.document.resolution, recording.document.resolution)
    XCTAssertEqual(replay.undoStack.count, 1)
    let result = replay.document; try replay.undo(); XCTAssertEqual(replay.document, target)
    try replay.redo(); XCTAssertEqual(replay.document, result)
  }
  func testRecordingTracksUndoRedoBranchingAndCoalescing() throws {
    var session = EditorSession(document: try fixture()); let id = session.document.activeLayerID!
    try session.startActionRecording(name: "History")
    session.beginCoalescing()
    try session.execute(.opacity(id, 0.5)); try session.execute(.opacity(id, 0.25)); session.endCoalescing()
    XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 2)
    try session.undo(); XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 0)
    try session.redo(); XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 2)
    try session.undo(); try session.execute(.renameLayer(id, "Renamed"))
    XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 1); XCTAssertTrue(session.redoStack.isEmpty)
    XCTAssertThrowsError(try session.startActionRecording(name: "Again"))
    session.stopActionRecording(); XCTAssertNil(session.actionRecording)
  }
  func testNewLayerAndNamedSelectionPortableTargets() throws {
    let original = try fixture(); var session = EditorSession(document: original)
    try session.startActionRecording(name: "Layers")
    try session.execute(.newPixelLayer(.init(name: "Overlay")))
    try session.execute(.fill(session.document.activeLayerID!, Pixel(1, 0, 0, 0.5)))
    session.selectLayer(original.activeLayerID!)
    try session.execute(.renameLayer(original.activeLayerID!, "Base"))
    let action = try XCTUnwrap(session.actionRecording?.snapshot)
    var replay = try fixture(); try action.apply(to: &replay)
    XCTAssertEqual(replay.layers.map(\.name), session.document.layers.map(\.name))
    XCTAssertEqual(replay.layers.map(\.content), session.document.layers.map(\.content))
    XCTAssertEqual(replay.layers.first { $0.id == replay.activeLayerID }?.name, "Base")
  }
  func testFailureDisabledStepsAndUnsupportedRecordingAreAtomic() throws {
    let original = try fixture(); var result = original
    var action = RecordedAction(name: "Failure", steps: [
      .init(name: "Fill", operation: .fill(.active, .black)),
      .init(name: "Unavailable", operation: .unsupported("Unavailable test operation"))])
    XCTAssertThrowsError(try action.apply(to: &result)) { XCTAssertTrue($0.localizedDescription.contains("step 2")) }
    XCTAssertEqual(result, original)
    action.steps[1].enabled = false; try action.apply(to: &result); XCTAssertNotEqual(result, original)
    var session = EditorSession(document: original); try session.startActionRecording(name: "Unsupported")
    try session.execute(.protection([original.activeLayerID!: .all]))
    XCTAssertNotNil(session.actionRecording?.snapshot.steps.first?.operation.unsupportedReason)
  }
  func testMovementIsRelativeAndInvalidTargetDoesNotMutate() throws {
    var source = try fixture(); source.layers[0].x = 3
    let op = ActionOperation(recording: .move(source.activeLayerID!, 8, 4), in: source)
    var target = try fixture(); target.layers[0].x = 20
    try op.command(in: target)?.apply(to: &target); XCTAssertEqual(target.layers[0].x, 25); XCTAssertEqual(target.layers[0].y, 4)
    let before = target
    let action = RecordedAction(name: "Missing", steps: [.init(name: "Select", operation: .select(.named("Missing", occurrence: 0)))])
    XCTAssertThrowsError(try action.apply(to: &target)); XCTAssertEqual(target, before)
  }
  func testPreparedEditsRecordOnlySuccessfulCommitsAndRespectLocks() throws {
    let original = try fixture(); var session = EditorSession(document: original)
    try session.startActionRecording(name: "Prepared")
    let prepared = try PreparedEdit(command: .fill(original.activeLayerID!, .black), document: original)
    try session.executePrepared(prepared); XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 1)
    XCTAssertThrowsError(try session.executePrepared(prepared)); XCTAssertEqual(session.actionRecording?.snapshot.steps.count, 1)
    var locked = original; locked.layers[0].locked = true
    let action = try XCTUnwrap(session.actionRecording?.snapshot); let before = locked
    XCTAssertThrowsError(try action.apply(to: &locked)); XCTAssertEqual(locked, before)
  }
  func testInvalidFormatBoundsAndCancelledPlayback() async throws {
    var action = RecordedAction(name: " "); XCTAssertThrowsError(try action.validate())
    action.name = "Valid"; action.steps = Array(repeating: .init(name: "Fill", operation: .fill(.active, .black)), count: 513)
    XCTAssertThrowsError(try action.validate())
    let source = try fixture()
    let worker = Task { var document = source; withUnsafeCurrentTask { $0?.cancel() }; try RecordedAction(name: "Cancel", steps: [.init(name: "Fill", operation: .fill(.active, .black))]).apply(to: &document) }
    do { try await worker.value; XCTFail("Cancellation must propagate") } catch { XCTAssertTrue(error is CancellationError) }
  }
}
