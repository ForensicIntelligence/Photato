import XCTest

@testable import PhotoCraftCore

final class GeometryTests: XCTestCase {
  func asymmetric(_ depth: PixelDepth = .f32) throws -> CraftDocument {
    var doc = try CraftDocument(width: 4, height: 3, depth: depth)
    var surface = try Surface(width: 3, height: 2, depth: depth)
    for y in 0..<2 {
      for x in 0..<3 {
        surface.setPixel(x: x, y: y, Pixel(Float(x + 1) / 4, Float(y + 1) / 3, 0.25))
      }
    }
    var layer = Layer(name: "Pixels", content: .raster(surface))
    layer.x = 1
    layer.y = 1
    var mask = try Surface(width: 3, height: 2, depth: depth, fill: .white)
    mask.setPixel(x: 0, y: 1, .black)
    layer.mask = mask
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    return doc
  }
  func testAffineCompositionInverseAndInvalidNumbers() throws {
    let t = Transform2D.translation(5, -3) * .rotation(32) * .scale(2, 0.5)
    let p = t.point(4, 8)
    let round = try t.inverted().point(p.x, p.y)
    XCTAssertEqual(round.x, 4, accuracy: 1e-10)
    XCTAssertEqual(round.y, 8, accuracy: 1e-10)
    for t in [Transform2D.scale(0, 1), Transform2D(tx: .infinity), Transform2D(a: .nan)] {
      XCTAssertThrowsError(try t.inverted())
    }
    XCTAssertEqual(try Transform2D.scale(1000, 1000).bounds(width: 100, height: 100), .init(x:0,y:0,width:100_000,height:100_000))
    XCTAssertThrowsError(try Transform2D.scale(4000, 4000).bounds(width: 100, height: 100))
  }
  func testPixelAndMaskFlipStayLinkedAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let original = try asymmetric(depth)
      var session = EditorSession(document: original)
      let id = try XCTUnwrap(original.activeLayerID)
      try session.execute(.flip(id, true))
      guard case .raster(let before) = original.layers[0].content,
        case .raster(let after) = session.document.layers[0].content
      else { return XCTFail() }
      for y in 0..<2 {
        for x in 0..<3 {
          XCTAssertEqual(after.pixel(x: x, y: y), before.pixel(x: 2 - x, y: y))
          XCTAssertEqual(
            session.document.layers[0].mask?.pixel(x: x, y: y),
            original.layers[0].mask?.pixel(x: 2 - x, y: y))
        }
      }
      try session.undo()
      XCTAssertEqual(session.document, original)
    }
  }
  func testCanvasAnchorsPreservePixelsAndUndo() throws {
    for anchor in CanvasAnchor.allCases {
      let original = try asymmetric()
      var s = EditorSession(document: original)
      try s.execute(.canvasSize(8, 7, anchor, nil))
      XCTAssertEqual(s.document.layers[0].content, original.layers[0].content)
      XCTAssertEqual(s.document.layers[0].x, 1 + Int(anchor.fractions.0 * 4))
      XCTAssertEqual(s.document.layers[0].y, 1 + Int(anchor.fractions.1 * 4))
      XCTAssertEqual(s.document.layers[0].mask, original.layers[0].mask)
      try s.undo()
      XCTAssertEqual(s.document, original)
    }
  }
  func testCanvasExtensionColorOnlyFillsNewArea() throws {
    var s = EditorSession(document: try asymmetric())
    try s.execute(.canvasSize(6, 5, .center, Pixel(0, 1, 0)))
    guard case .raster(let extensionPixels) = s.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(extensionPixels.pixel(x: 0, y: 0), Pixel(0, 1, 0))
    XCTAssertEqual(extensionPixels.pixel(x: 1, y: 1), .clear)
    XCTAssertEqual(s.document.layers[1].x, 2)
  }
  func testImageResizeMapsOffsetsMasksAndSelection() throws {
    var d = try asymmetric(.u16)
    d.selection = IntRect(x: 1, y: 1, width: 2, height: 1)
    var s = EditorSession(document: d)
    try s.execute(.imageSize(8, 6, 300, .nearest))
    XCTAssertEqual(s.document.layers[0].x, 2)
    XCTAssertEqual(s.document.layers[0].y, 2)
    XCTAssertEqual(s.document.selection, IntRect(x: 2, y: 2, width: 4, height: 2))
    guard case .raster(let output) = s.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(output.width, 6)
    XCTAssertEqual(output.height, 4)
    XCTAssertEqual(output.depth, .u16)
    XCTAssertEqual(s.document.layers[0].mask?.pixel(x: 0, y: 2), .black)
    XCTAssertEqual(s.document.pixelsPerInch, 300)
    try s.undo()
    XCTAssertEqual(s.document, d)
    try s.redo()
    XCTAssertEqual(s.document.width, 8)
  }
  func testResolutionOnlyDoesNotResamplePixels() throws {
    let d = try asymmetric()
    var s = EditorSession(document: d)
    try s.execute(.resolution(300))
    XCTAssertEqual(s.document.layers, d.layers)
    XCTAssertEqual(s.document.width, d.width)
    XCTAssertEqual(s.document.pixelsPerInch, 300)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(s.document)), s.document)
    try s.undo()
    XCTAssertEqual(s.document, d)
  }
  func testOldNativeArchiveDecodesWithoutNewGeometryFields() throws {
    let d = try asymmetric()
    let data = try NativeArchive.encode(d)
    var plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    plist["version"] = 1
    var document = try XCTUnwrap(plist["document"] as? [String: Any])
    document.removeValue(forKey: "resolution")
    var layers = try XCTUnwrap(document["layers"] as? [[String: Any]])
    for i in layers.indices { layers[i].removeValue(forKey: "affine") }
    document["layers"] = layers
    plist["document"] = document
    let old = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .binary, options: 0)
    XCTAssertEqual(try NativeArchive.decode(old), d)
  }
  func testInvalidTransformsAndSizesFailAtomically() throws {
    var d = try asymmetric()
    d.layers[0].locked = true
    var s = EditorSession(document: d)
    let id = try XCTUnwrap(d.activeLayerID)
    for cmd: Command in [
      .transform(id, .scale(2, 2), .bilinear), .imageSize(Int.max, 3, 72, .bilinear),
      .canvasSize(-1, 3, .center, nil), .resolution(.nan),
    ] {
      XCTAssertThrowsError(try s.execute(cmd))
      XCTAssertEqual(s.document, d)
      XCTAssertTrue(s.undoStack.isEmpty)
    }
    d.layers[0].locked = false
    s = EditorSession(document: d)
    XCTAssertThrowsError(try s.execute(.transform(id, .scale(0, 2), .bicubic)))
    XCTAssertEqual(s.document, d)
  }
  func testBilinearPremultipliedAlphaAvoidsTransparentColorBleed() throws {
    var s = try Surface(width: 2, height: 1, depth: .f32)
    s.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    s.setPixel(x: 1, y: 0, Pixel(0, 0, 1, 0))
    let p = RasterGeometry.sample(s, x: 1, y: 0.5, method: .bilinear)
    XCTAssertEqual(p.r, 1, accuracy: 1e-6)
    XCTAssertEqual(p.b, 0, accuracy: 1e-6)
    XCTAssertEqual(p.a, 0.5, accuracy: 1e-6)
  }
}
