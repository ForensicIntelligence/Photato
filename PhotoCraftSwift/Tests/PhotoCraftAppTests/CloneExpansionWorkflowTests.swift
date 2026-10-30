import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class CloneExpansionWorkflowTests: XCTestCase {
  @MainActor func stop(_ store: EditorStore) {
    store.renderTask?.cancel()
    store.clonePrepareTask?.cancel()
    store.cloneOverlayTask?.cancel()
    store.geometryTask?.cancel()
  }
  @MainActor func finish(_ store: EditorStore) async {
    store.finishClone()
    await store.clonePrepareTask?.value
    await store.geometryTask?.value
    await store.retouchPreviewTask?.value; await store.renderTask?.value
  }
  @MainActor func testCroppedLayerPreviewCancelRepeatedSamplingAndUndo() async throws {
    var document = try CraftDocument(width: 100, height: 80, depth: .u16)
    document.layers[0].content = .raster(
      try Surface(width: 6, height: 5, depth: .u16, fill: Pixel(0.3, 0.7, 0.2)))
    document.layers[0].x = 40
    document.layers[0].y = 30
    let state = CloneSources()
    state.brush.size = 5
    state.brush.hardness = 1
    state.aligned = false
    let store = EditorStore(document: document, cloneState: state)
    defer { stop(store) }
    store.chooseTool(WorkspaceCatalog.tool("clone"))
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    store.setCloneSource(at: .init(42.5, 32.5))
    let expected = Pixel(0.3, 0.7, 0.2).quantized(.u16)
    store.beginClone(.init(x: 12.5, y: 12.5))
    await store.clonePrepareTask?.value
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, document)
    XCTAssertEqual(store.surface?.pixel(x: 12, y: 12), expected)
    store.cancelClone()
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.surface?.pixel(x: 12, y: 12), .clear)
    for point in [StrokePoint(x: 12.5, y: 12.5), .init(x: 72.5, y: 62.5)] {
      store.beginClone(point)
      await finish(store)
      XCTAssertNil(store.error)
      XCTAssertEqual(store.surface?.pixel(x: Int(point.x), y: Int(point.y)), expected)
    }
    XCTAssertEqual(store.session.undoStack.count, 2)
    XCTAssertEqual(store.surface?.pixel(x: 42, y: 32), expected)
    XCTAssertLessThan(try XCTUnwrap(store.activeLayer?.x), 40)
    await store.undo()
    await store.undo()
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, document)
    await store.redo()
    await store.redo()
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.surface?.pixel(x: 72, y: 62), expected)
  }

  @MainActor func testMaskOutsideOverlayScalarAlphaAndCrossDocumentExpansion() async throws {
    var sourceDoc = try CraftDocument(width: 100, height: 80)
    sourceDoc.layers[0].mask = try Surface(width: 2, height: 2, fill: Pixel(0.4, 0.9, 0.1, 0))
    var sourceProperties = MaskProperties()
    sourceProperties.outside = 1
    sourceProperties.transform = .translation(40, 30)
    sourceDoc.layers[0].maskProperties = sourceProperties
    var targetDoc = try CraftDocument(width: 100, height: 80)
    targetDoc.layers[0].mask = try Surface(width: 2, height: 2, fill: .black)
    var targetProperties = MaskProperties()
    targetProperties.transform = .translation(40, 30)
    targetDoc.layers[0].maskProperties = targetProperties
    let state = CloneSources()
    state.brush.size = 12
    state.brush.hardness = 1
    state.overlayOpacity = 1
    let source = EditorStore(document: sourceDoc, cloneState: state)
    let target = EditorStore(document: targetDoc, cloneState: state)
    defer {
      stop(source)
      stop(target)
    }
    for store in [source, target] {
      store.chooseTool(WorkspaceCatalog.tool("clone"))
      store.maskEditingLayerID = store.activeLayer?.id
    }
    source.setCloneSource(at: .init(10.5, 10.5))
    target.refreshCloneOverlay()
    await target.cloneOverlayTask?.value
    let overlay = try XCTUnwrap(target.cloneOverlay)
    XCTAssertEqual(overlay.outside, .white)
    let data = try XCTUnwrap(overlay.image.dataProvider?.data) as Data
    XCTAssertEqual(Array(data.prefix(4)), [102, 102, 102, 255])
    let canvas = CraftCanvas(store: target)
    canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
    canvas.cloneHover = CGPoint(x: 20.5, y: 20.5)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 500, height: 400, bitsPerComponent: 8, bytesPerRow: 2000,
        space: RasterIO.colorSpace(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // Match the flipped AppKit canvas coordinate system; raw bitmap contexts start Y-up.
    context.translateBy(x: 0, y: 400)
    context.scaleBy(x: 1, y: -1)
    canvas.drawCloneOverlay(in: context)
    let center = canvas.viewPoint(CGPoint(x: 20.5, y: 20.5))
    let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = (Int(center.y) * 500 + Int(center.x)) * 4
    XCTAssertEqual(pixels[offset], 255)
    XCTAssertEqual(pixels[offset + 3], 255)
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 500, height: 400))
    state.clippedOverlay = false
    state.overlayOpacity = 0.5
    canvas.drawCloneOverlay(in: context)
    let inside = canvas.viewPoint(CGPoint(x: 51, y: 41))
    let insideOffset = (Int(inside.y) * 500 + Int(inside.x)) * 4
    XCTAssertEqual(pixels[offset], 128)
    XCTAssertEqual(pixels[insideOffset], 51, "Outside fill must not double-apply overlay opacity")
    state.invertOverlay = true
    target.refreshCloneOverlay()
    await target.cloneOverlayTask?.value
    XCTAssertEqual(target.cloneOverlay?.outside, .black)
    target.beginClone(.init(x: 20.5, y: 20.5))
    await finish(target)
    XCTAssertNil(target.error)
    let targetLayer = try XCTUnwrap(target.activeLayer)
    XCTAssertEqual(try MaskSampler(layer: targetLayer).coverage(x: 20.5, y: 20.5), 1)
    XCTAssertEqual(targetLayer.content, targetDoc.layers[0].content)
    XCTAssertEqual(source.document, sourceDoc)
    await target.undo()
    XCTAssertEqual(target.document, targetDoc)
  }
}
