import Foundation
import PhotoCraftCore
import XCTest

final class GradientFillTests: XCTestCase {
  func testCreationCapturesSelectionNativeArchiveUndoAndInvalidCommandsAreAtomic() throws {
    var doc = try CraftDocument(width: 100, height: 80, depth: .u16)
    doc.selection = .init(x: 10, y: 20, width: 40, height: 30)
    let gradient = try GradientDefinition.foregroundToBackground.resolved(
      foreground: Pixel(0.2, 0.4, 0.7), background: .white)
    let fill = GradientFill(gradient: gradient)
    let layer = Layer(name: "Gradient Fill", content: .gradientFill(fill))
    var session = EditorSession(document: doc)
    try session.execute(.addGradientFill(layer, true))
    let added = session.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(added)), added)
    XCTAssertEqual(
      try fill.frame(for: added.layers.last!, width: 100, height: 80),
      .init(x: 10, y: 20, width: 40, height: 30))
    XCTAssertEqual(added.selection, doc.selection)
    XCTAssertEqual(try MaskSampler(layer: added.layers.last!).coverage(x: 11, y: 21), 1)
    try session.undo()
    XCTAssertEqual(session.document, doc)
    try session.redo()
    XCTAssertEqual(session.document, added)
    var changed = fill
    changed.placement.style = .diamond
    try session.execute(.setGradientFill(layer.id, changed))
    XCTAssertEqual(session.undoStack.count, 2)
    try session.undo()
    XCTAssertEqual(session.document, added)
    changed.placement.scale = .nan
    XCTAssertThrowsError(try session.execute(.setGradientFill(layer.id, changed)))
    XCTAssertEqual(session.document, added)
    XCTAssertThrowsError(try session.execute(.setGradientFill(doc.layers[0].id, fill)))
    XCTAssertThrowsError(
      try session.execute(
        .addGradientFill(
          .init(name: "Invalid", content: .gradientFill(.init(gradient: .foregroundToTransparent))))
      ))
    XCTAssertEqual(session.document, added)
    try session.execute(.lock(layer.id, true))
    XCTAssertThrowsError(try session.execute(.setGradientFill(layer.id, fill)))
  }
  func testMaskFrameEnabledOutsideVectorIntersectionAndMove() throws {
    let fill = GradientFill()
    var layer = Layer(name: "Fill", content: .gradientFill(fill))
    layer.mask = try Surface(width: 20, height: 15, fill: .white)
    var p = MaskProperties()
    p.transform = .translation(12, 9)
    p.outside = 0
    layer.maskProperties = p
    let canvas = IntRect(x: 0, y: 0, width: 80, height: 60)
    XCTAssertEqual(
      try layer.fillFrame(width: 80, height: 60), .init(x: 12, y: 9, width: 20, height: 15))
    layer.maskProperties?.density = 0.2
    layer.maskProperties?.feather = 10
    XCTAssertEqual(
      try layer.fillFrame(width: 80, height: 60), .init(x: 12, y: 9, width: 20, height: 15))
    layer.maskProperties?.enabled = false
    XCTAssertEqual(try layer.fillFrame(width: 80, height: 60), canvas)
    layer.maskProperties?.enabled = true
    layer.maskProperties?.outside = 1
    XCTAssertEqual(try layer.fillFrame(width: 80, height: 60), canvas)
    layer.maskProperties?.outside = 0
    layer.vectorMask = VectorMask(
      path: VectorPath(components: [
        PathComponent(knots: [.init(.init(20, 15)), .init(.init(40, 30))])
      ]))
    XCTAssertEqual(
      try layer.fillFrame(width: 80, height: 60), .init(x: 20, y: 15, width: 12, height: 9))
    layer.vectorMask?.path.inverted = true
    var unaligned = fill
    unaligned.aligned = false
    XCTAssertEqual(try unaligned.frame(for: layer, width: 80, height: 60), canvas)
    var doc = try CraftDocument(width: 80, height: 60)
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    try Command.move(layer.id, 4, 3).apply(to: &doc)
    XCTAssertEqual(
      try doc.layers[0].fillFrame(width: 80, height: 60), .init(x: 16, y: 12, width: 20, height: 15)
    )
    doc.layers[0].mask = try Surface(width: 20, height: 15)
    XCTAssertEqual(try doc.layers[0].fillFrame(width: 80, height: 60), canvas)
  }
  func testClipboardRetainsEditableStopsAtEveryDepth() throws {
    var source = try CraftDocument(width: 20, height: 12)
    source.layers = [Layer(name: "Fill", content: .gradientFill(.init()))]
    source.activeLayerID = source.layers[0].id
    let clipboard = try ClipboardContent(
      kind: .layers, document: source, bounds: .init(x: 0, y: 0, width: 20, height: 12))
    let decoded = try ClipboardContent.decode(clipboard.encoded())
    for depth in PixelDepth.allCases {
      var target = try CraftDocument(width: 40, height: 30, depth: depth)
      try Command.paste(decoded, .centered, nil).apply(to: &target)
      XCTAssertEqual(target.layers.last?.content, source.layers[0].content)
      XCTAssertNotEqual(target.layers.last?.id, source.layers[0].id)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(target)), target)
    }
  }
  func testCanvasTurnAndResizeRetainRelativeControls() throws {
    var fill = GradientFill()
    fill.placement.angle = 0
    fill.placement.offsetX = 0.2
    fill.placement.offsetY = -0.1
    try fill.transform(by: .scale(2, 3))
    XCTAssertEqual(fill.placement.offsetX, 0.2)
    XCTAssertEqual(fill.placement.offsetY, -0.1)
    try fill.transform(by: .init(a: 0, b: 1, c: -1, d: 0, tx: 60))
    XCTAssertEqual(fill.placement.angle, -90)
    XCTAssertEqual(fill.placement.offsetX, 0.1)
    XCTAssertEqual(fill.placement.offsetY, 0.2)
    try fill.transform(by: .translation(9, -3))
    XCTAssertEqual(fill.placement.angle, -90)
    XCTAssertEqual(fill.placement.offsetX, 0.1)
  }
}
