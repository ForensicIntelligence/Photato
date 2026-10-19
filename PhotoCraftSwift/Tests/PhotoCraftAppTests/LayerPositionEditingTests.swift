import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerPositionEditingTests: XCTestCase {
  @MainActor func testRetainedXBindingUsesEveryTypedAbsoluteValue() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let binding = WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: true)
    binding.wrappedValue = 1
    XCTAssertEqual(store.activeLayerBounds?.x, 1)
    binding.wrappedValue = 17
    XCTAssertEqual(store.activeLayerBounds?.x, 17)
    binding.wrappedValue = 173
    XCTAssertEqual(store.activeLayerBounds?.x, 173)
    XCTAssertEqual(store.activeLayerBounds?.y, 3)
  }

  @MainActor func testRetainedYBindingPreservesCurrentXAndUsesNegativeAbsoluteValue() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let layer = try XCTUnwrap(store.activeLayer)
    let binding = WorkspaceView(store: store).layerPositionBinding(layer, horizontal: false)
    store.perform(.move(layer.id, 27, layer.y))
    binding.wrappedValue = -1
    binding.wrappedValue = -12
    XCTAssertEqual(store.activeLayerBounds?.y, -12)
    XCTAssertEqual(store.activeLayerBounds?.x, 27)
  }

  @MainActor func testAffineBoundsPositionPreservesTransformAndUndoRedo() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    var model = store.document
    model.layers[0].affine = .rotation(30)
    store.session = EditorSession(document: model)
    let layer = try XCTUnwrap(store.activeLayer)
    let originalBounds = try XCTUnwrap(store.activeLayerBounds)
    let binding = WorkspaceView(store: store).layerPositionBinding(layer, horizontal: true)
    binding.wrappedValue = 1
    binding.wrappedValue = 118
    XCTAssertEqual(store.activeLayerBounds?.x, 118)
    XCTAssertEqual(store.activeLayerBounds?.y, originalBounds.y)
    XCTAssertEqual(store.activeLayer?.affine, layer.affine)
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    let result = store.document
    store.undo()
    XCTAssertEqual(store.activeLayerBounds?.x, 1)
    store.undo()
    XCTAssertEqual(store.document, model)
    store.redo()
    store.redo()
    XCTAssertEqual(store.document, result)
  }

  @MainActor func testGroupPositionMovesSubtreeToEachRequestedVisibleOrigin() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    var model = store.document
    let group = Layer(name: "Folder", content: .group(.init()))
    model.layers[0].parentID = group.id
    model.layers.append(group)
    model.activeLayerID = group.id
    store.session = EditorSession(document: model)
    let binding = WorkspaceView(store: store).layerPositionBinding(group, horizontal: true)
    binding.wrappedValue = 2
    binding.wrappedValue = 17
    XCTAssertEqual(store.activeLayerBounds?.x, 17)
    XCTAssertEqual(store.document.layers[0].x, 17)
    XCTAssertEqual(store.document.layers[0].y, 3)
    XCTAssertEqual(store.document.layers[0].parentID, group.id)
    store.undo()
    store.undo()
    XCTAssertEqual(store.document, model)
  }

  @MainActor func testOldFieldCannotMoveNewlySelectedLayerOrItsPreviousTarget() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let binding = WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: true)
    store.perform(.addLayer(Layer(name: "Other", content: .fill(.white))))
    let before = store.document
    let undoCount = store.session.undoStack.count
    binding.wrappedValue = 73
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, undoCount)
  }

  @MainActor func testReadAndCloseInvalidateRetainedPositionField() throws {
    let document = try GroupDisclosureWorkflowTests().fixture()
    defer { document.close() }
    let store = document.store
    let binding = WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: true)
    let saved = try document.data(ofType: CraftNSDocument.nativeType)
    try document.read(from: saved, ofType: CraftNSDocument.nativeType)
    let before = store.document
    binding.wrappedValue = 17
    XCTAssertEqual(store.document, before)
    let closing = WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: false)
    document.close()
    closing.wrappedValue = -12
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testUnchangedAndNonfiniteInputDoNotCreateHistoryAndRangeIsClamped() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let binding = WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: true)
    let before = store.document
    for value in [4, Double.nan, .infinity, -.infinity] { binding.wrappedValue = value }
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    binding.wrappedValue = 999_990
    XCTAssertEqual(store.activeLayerBounds?.x, 999_990)
    binding.wrappedValue = 2_000_000
    XCTAssertEqual(store.activeLayer?.x, 1_000_000)
    // The existing engine permits an origin at its coordinate limit, but its
    // bounds routine rejects the shape's right edge beyond that limit. The
    // position field must still display the stored origin and recover from it.
    XCTAssertThrowsError(try store.layerBounds(XCTUnwrap(store.activeLayer)))
    XCTAssertEqual(binding.wrappedValue, 1_000_000)
    binding.wrappedValue = 17
    XCTAssertEqual(store.activeLayerBounds?.x, 17)
    store.undo()
    store.undo()
    store.undo()
    XCTAssertEqual(store.document, before)
  }

  @MainActor func testLockedPositionInputCannotChangeDocument() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.lock(id, true))
    let before = store.document
    let undoCount = store.session.undoStack.count
    WorkspaceView(store: store).layerPositionBinding(
      try XCTUnwrap(store.activeLayer), horizontal: true
    ).wrappedValue = 17
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, undoCount)
    XCTAssertNotNil(store.error)
  }
}
