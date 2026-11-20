import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ProjectiveSmartObjectWorkflowTests: XCTestCase {
  private let corners = [PathPoint(14, 20), .init(66, 13), .init(90, 66), .init(10, 74)]

  private func reopened() throws -> CraftDocument {
    var doc = try CraftDocument(width: 108, height: 92)
    let surface = try Surface(width: 20, height: 16, fill: Pixel(0.8, 0.3, 0.2))
    var layer = try SmartObjectIO.placed(data: RasterIO.encoded(surface), fileName: "Owned Artwork.png", in: doc, fit: false)
    layer.x = 0; layer.y = 0; layer.affine = nil
    layer.sourceProjection = try SelectionTransform.projection(bounds: .init(x: 0, y: 0, width: 20, height: 16), corners: corners)
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    return try PSDCodec.read(PSDCodec.writeRasterLayers(doc, format: .psb))
  }

  @MainActor func testReopenedProjectiveFrameUsesActualCornersPivotAndExactAffineDelta() async throws {
    let document = try reopened()
    let store = EditorStore(document: document)
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.beginTransform()
    let draft = try XCTUnwrap(store.transformDraft)
    let frame = try XCTUnwrap(draft.projectiveArtworkFrame)
    XCTAssertEqual(try draft.selectionProjection, .identity)
    _ = NSApplication.shared
    store.zoom = 4
    let canvas = CraftCanvas(store: store)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 480, height: 400), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = canvas
    canvas.frame = try XCTUnwrap(window.contentView).bounds
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close() }
    XCTAssertGreaterThanOrEqual(canvas.scale, 1)
    for (index, pair) in zip([0, 2, 4, 6], zip(draft.selectionCorners, corners)) {
      XCTAssertEqual(pair.0.x, pair.1.x, accuracy: 1e-10)
      XCTAssertEqual(pair.0.y, pair.1.y, accuracy: 1e-10)
      let p = try XCTUnwrap(draft.handles.indices.contains(index) ? draft.handles[index] : nil)
      XCTAssertEqual(canvas.selectionTransformHit(p, draft: draft), index)
    }
    let center = try frame.point(0.5, 0.5)
    XCTAssertEqual(draft.transformReferencePoint, center)
    XCTAssertEqual(canvas.selectionTransformHit(CGPoint(x: center.x, y: center.y), draft: draft), -1)
    XCTAssertEqual(canvas.selectionTransformHit(CGPoint(x: 89, y: 15), draft: draft), 8)
    XCTAssertEqual(draft.displayedAngle, atan2(-7.0, 52.0) * 180 / .pi, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(store.layerRotation(document.layers[0])), draft.displayedAngle, accuracy: 1e-10)
    let carried = draft.selectionApplying(.translation(6, -3))
    XCTAssertEqual(try carried.selectionProjection.affineValue(), .translation(6, -3))
    let angled = carried.transformNumeric(\.angle, 12 - carried.displayedAngle + carried.angle)
    XCTAssertEqual(angled.displayedAngle, 12, accuracy: 1e-10)
    XCTAssertNotNil(try angled.selectionProjection.affineValue())
    XCTAssertEqual(angled.transformReferencePoint.x, center.x + 6, accuracy: 1e-10)
    XCTAssertEqual(angled.transformReferencePoint.y, center.y - 3, accuracy: 1e-10)
    store.updateTransform(angled)
    let state = try XCTUnwrap(store.transformReferenceState["projectiveArtworkFrame"] as? [String: Any])
    XCTAssertEqual(state["delta"] as? [Double], try angled.selectionProjection.values)
    XCTAssertEqual(state["angleDegrees"] as? Double, angled.displayedAngle)
    let decoded = try JSONDecoder().decode(AutomationValue.self,
      from: JSONSerialization.data(withJSONObject: store.transformReferenceState))
    XCTAssertNoThrow(try BrushAPI.merge(decoded, schema: TransformReferenceAPI.stateSchema))
    let session = try XCTUnwrap(store.selectionTransform)
    store.commitTransform()
    await session.commitTask?.value
    XCTAssertNil(session.error)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.layers[0].smartObject?.data, document.layers[0].smartObject?.data)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, document)
  }

  @MainActor func testSecondDistortSaveReopenFeedsManifestTheComposedCorners() async throws {
    let document = try reopened()
    let store = EditorStore(document: document)
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.beginTransform()
    let draft = try XCTUnwrap(store.transformDraft)
    let start = draft.handles[0], end = CGPoint(x: start.x + 5, y: start.y - 1)
    let next = draft.selectionDragging(handle: 0, from: start, to: end, mode: .distort, shift: false, option: false)
    XCTAssertEqual(Array(next.selectionCorners.dropFirst()), Array(draft.selectionCorners.dropFirst()))
    XCTAssertNil(try next.selectionProjection.affineValue())
    store.updateTransform(next)
    let session = try XCTUnwrap(store.selectionTransform)
    store.commitTransform()
    await session.commitTask?.value
    XCTAssertNil(session.error)
    let reloaded = try PSDCodec.read(PSDCodec.writeRasterLayers(store.document))
    let layer = try XCTUnwrap(reloaded.layers.first)
    let committed = try XCTUnwrap(ProjectiveArtworkFrame(layer))
    XCTAssertEqual(layer.smartObject?.data, document.layers[0].smartObject?.data)
    for (p, q) in zip(committed.corners, next.selectionCorners) {
      XCTAssertEqual(p.x, q.x, accuracy: 1e-10)
      XCTAssertEqual(p.y, q.y, accuracy: 1e-10)
    }
    var translated = reloaded
    try Command.transformLayers(.init(layerIDs: [layer.id], matrix: .translation(2, 3))).apply(to: &translated)
    let frame = try XCTUnwrap(ProjectiveArtworkFrame(translated.layers[0]))
    let state = try XCTUnwrap(translated.layers[0].smartObjectAPIState?["projectiveSourceGeometry"] as? [String: Any])
    XCTAssertEqual(state["transform"] as? [Double], frame.placement.values)
    let identified = try AdobeLayerIdentifiers.assigning(in: translated)
    let data = try AdobeDocumentManifest.encode(identified, title: "Mockup.psd", includeXmp: false)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
    let smart = try XCTUnwrap(layers.first?["smartObject"] as? [String: Any])
    let fields = try XCTUnwrap(smart["smartObjectData"] as? [String: Any])
    XCTAssertEqual(fields["transform"] as? [Double], frame.corners.flatMap { [$0.x, $0.y] })
  }
}
