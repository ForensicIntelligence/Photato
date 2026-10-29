import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class FrameWorkflowTests: XCTestCase {
  func frame(_ depth: PixelDepth = .u8, shape: FrameDefinition.Shape = .rectangle) throws -> CraftDocument {
    var d = try CraftDocument(width: 30, height: 20, depth: depth)
    d.layers[0].content = .raster(try Surface(width: 30, height: 20, depth: depth, fill: Pixel(1,0,0)))
    try Command.frame(.create(name: "Frame", bounds: .init(x: 5, y: 4, width: 12, height: 10), definition: .init(width: 12, height: 10, shape: shape), children: [d.layers[0].id])).apply(to: &d)
    return d
  }
  func testClipsChildrenForAllDepthsAndShapes() throws {
    for depth in PixelDepth.allCases {
      for shape in [FrameDefinition.Shape.rectangle, .ellipse, .triangle, .polygon] {
        let d = try frame(depth, shape: shape), pixels = try Renderer.composite(d)
        XCTAssertEqual(pixels.pixel(x: 0, y: 0), .clear); XCTAssertEqual(pixels.pixel(x: 11, y: 8), Pixel(1,0,0))
        XCTAssertEqual(pixels.pixel(x: 17, y: 10), .clear)
        if shape == .ellipse { XCTAssertEqual(pixels.pixel(x: 5, y: 4), .clear) }
      }
    }
  }
  func testOriginalRustBoundsGroupingAndSingleHistoryStep() throws {
    var d = try CraftDocument(width: 80, height: 60)
    var a = Layer(name: "A", content: .raster(try Surface(width: 20, height: 20, fill: Pixel(1,0,0)))); a.x = 4; a.y = 4
    var b = Layer(name: "B", content: .raster(try Surface(width: 20, height: 20, fill: Pixel(0,0,1)))); b.x = 30; b.y = 20
    d.layers = [a,b]; d.activeLayerID = b.id
    var session = EditorSession(document: d)
    try session.execute(FrameRenderer.fromLayers([a.id,b.id], name: "Frame 1", in: d))
    XCTAssertEqual(session.document.layers.last?.frameBounds, .init(x: 4, y: 4, width: 46, height: 36))
    let framed = session.document; try session.undo(); XCTAssertEqual(session.document, d); try session.redo(); XCTAssertEqual(session.document, framed)
  }
  func testIndependentGeometryReplacementRetainsSmartObjectAndHistory() throws {
    var d = try frame(); let id = d.layers.last!.id
    var source = try CraftDocument(width: 4, height: 8); source.layers[0].content = .raster(try Surface(width: 4, height: 8, fill: Pixel(0,0,1)))
    let data = try NativeArchive.encodeChunked(source), placed = try SmartObjectIO.placed(data: data, fileName: "Source.photato", in: d)
    try Command.frame(.replace(id, placed, fit: .fill)).apply(to: &d)
    let child = d.children(of: id)[0], original = d
    XCTAssertEqual(child.smartObject?.data, data); XCTAssertEqual(child.affine?.a, 3)
    var session = EditorSession(document: d)
    try session.execute(.frame(.transform(id, .translation(2,1), contents: false)))
    XCTAssertEqual(session.document.children(of: id)[0], child)
    try session.execute(.frame(.transformContents(id, .translation(3,0))))
    XCTAssertEqual(session.document.children(of: id)[0].x, child.x + 3); XCTAssertEqual(session.document.children(of: id)[0].smartObject?.data, data)
    try session.undo(); try session.undo(); XCTAssertEqual(session.document, original)
    try session.execute(.frame(.fit(id, .fit))); XCTAssertEqual(session.document.children(of: id)[0].affine?.a, 1.25)
    try session.execute(.frame(.clear(id))); XCTAssertTrue(session.document.children(of: id).isEmpty); XCTAssertNotNil(session.document.layers.last?.frame)
  }
  func testStrokeOnEmptyFrameAndNative28RoundTrip() throws {
    var d = try frame(); let id = d.layers.last!.id
    try Command.frame(.clear(id)).apply(to: &d)
    var definition = d.layers.last!.frame!; definition.strokeColor = Pixel(0,1,0); definition.strokeWidth = 2
    try Command.frame(.configure(id, definition)).apply(to: &d)
    let rendered = try Renderer.composite(d)
    XCTAssertEqual(rendered.pixel(x: 5, y: 8), Pixel(0,1,0)); XCTAssertEqual(rendered.pixel(x: 11, y: 8), .clear)
    XCTAssertEqual(d.minimumArchiveVersion, 28); XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)), d); XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
    XCTAssertThrowsError(try DocumentIO.encode(d, format: .psd))
  }
  func testTypeAndShapeBecomeEmptyEditableFramesAndInvalidInputRollsBack() throws {
    var d = try CraftDocument(width: 100, height: 80)
    d.layers[0].content = .shape(.init(kind: .ellipse, width: 30, height: 20, color: .black))
    try FrameRenderer.conversion(d.layers[0].id, in: d).apply(to: &d); XCTAssertEqual(d.layers[0].frame?.shape, .ellipse)
    var text = TextContent(text: "O"); text.size = 36
    var layer = Layer(name: "Type", content: .text(text)); layer.x = 10; layer.y = 10; d.layers.append(layer); d.activeLayerID = layer.id
    try FrameRenderer.conversion(layer.id, in: d).apply(to: &d)
    XCTAssertEqual(d.layers.last?.frame?.shape, .custom); XCTAssertGreaterThan(d.layers.last?.frame?.customPath?.knotCount ?? 0, 4)
    var session = EditorSession(document: d), invalid = d.layers.last!.frame!; invalid.width = 0
    XCTAssertThrowsError(try session.execute(.frame(.configure(layer.id, invalid)))); XCTAssertEqual(session.document, d)
  }
}
