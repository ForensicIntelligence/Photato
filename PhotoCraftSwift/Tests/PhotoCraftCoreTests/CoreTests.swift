import XCTest

@testable import PhotoCraftCore

final class CoreTests: XCTestCase {
  func testSparseAndCopyOnWriteAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var a = try Surface(width: 130, height: 90, depth: depth)
      XCTAssertEqual(a.tileCount, 0)
      a.setPixel(x: 64, y: 64, Pixel(0.3, 0.7, 0.9))
      var b = a
      b.setPixel(x: 64, y: 64, .white)
      XCTAssertEqual(a.pixel(x: 64, y: 64).r, depth.quantize(0.3))
      XCTAssertEqual(b.pixel(x: 64, y: 64), .white)
      XCTAssertEqual(a.tileCount, 1)
      XCTAssertEqual(a.pixel(x: -1, y: 100), .clear)
    }
  }
  func testInvalidDimensions() {
    for (w, h) in [(0, 10), (-1, 5), (Int.max, Int.max), (32768, 32768)] {
      XCTAssertThrowsError(try Surface(width: w, height: h))
    }
  }
  func testHDRIsRetainedAtFloatDepth() throws {
    var s = try Surface(width: 1, height: 1, depth: .f32)
    s.setPixel(x: 0, y: 0, Pixel(4, -0.2, 2))
    XCTAssertEqual(s.pixel(x: 0, y: 0).r, 4)
  }
  func testAlphaCompositing() {
    let p = BlendMode.normal.composite(backdrop: Pixel(0, 0, 1, 0.5), source: Pixel(1, 0, 0, 0.5))
    XCTAssertEqual(p.a, 0.75, accuracy: 1e-6)
    XCTAssertEqual(p.r, 2 / 3, accuracy: 1e-6)
    XCTAssertEqual(p.b, 1 / 3, accuracy: 1e-6)
  }
  func testBlendIdentitiesAndAllModesFinite() {
    XCTAssertEqual(BlendMode.allCases.count, 27)
    XCTAssertEqual(BlendMode.multiply.channel(0.3, 1), 0.3)
    XCTAssertEqual(BlendMode.screen.channel(0.3, 0), 0.3)
    XCTAssertEqual(BlendMode.difference.channel(0.3, 0.3), 0)
    for m in BlendMode.allCases {
      for b: Float in [0, 0.2, 0.5, 1] {
        for s: Float in [0, 0.2, 0.5, 1] {
          let p = m.composite(backdrop: Pixel(b, 1 - b, b), source: Pixel(s, s, 1 - s))
          XCTAssertTrue(p.isFinite, "\(m)")
        }
      }
    }
  }
  func testDissolveDeterministicCoverage() {
    var total = 0
    for x in 0..<10000 {
      let a = BlendMode.dissolve.composite(
        backdrop: .clear, source: Pixel(1, 0, 0, 0.25), x: x, y: 9)
      XCTAssertTrue(a.a == 0 || a.a == 1)
      total += Int(a.a)
    }
    XCTAssertTrue((2250...2750).contains(total))
  }
  func testArchiveRoundTrip() throws {
    var d = try CraftDocument(width: 8, height: 8, depth: .f32)
    var s = try Surface(width: 8, height: 8, depth: .f32)
    s.setPixel(x: 2, y: 5, Pixel(3, 0.2, 0.9, 0.7))
    d.layers.append(Layer(name: "paint", content: .raster(s)))
    d.layers[1].mask = try Surface(width: 8, height: 8, fill: Pixel(0.5, 0.5, 0.5))
    d.sourceICC = Data([1, 2, 3])
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
  }
  func testCorruptArchivesAndVersionRejected() throws {
    XCTAssertThrowsError(try NativeArchive.decode(Data("bad".utf8)))
    let d = try CraftDocument(width: 2, height: 2)
    let data = try NativeArchive.encode(d)
    for n in [0, 1, data.count / 2, data.count - 1] {
      XCTAssertThrowsError(try NativeArchive.decode(data.prefix(n)))
    }
    var p = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    p["version"] = 99
    XCTAssertThrowsError(
      try NativeArchive.decode(
        PropertyListSerialization.data(fromPropertyList: p, format: .binary, options: 0)))
  }
  func testTransactionsUndoRedoAndBranching() throws {
    var s = EditorSession(document: try CraftDocument(width: 16, height: 16))
    let before = s.document
    let l = Layer(name: "Ink", content: .raster(try Surface(width: 16, height: 16)))
    try s.execute(.addLayer(l))
    try s.execute(.opacity(l.id, 0.5))
    s.undo()
    XCTAssertEqual(s.document.layers.last?.opacity, 1)
    s.undo()
    XCTAssertEqual(s.document, before)
    s.redo()
    XCTAssertEqual(s.document.layers.count, 2)
    try s.execute(.renameLayer(l.id, "Renamed"))
    XCTAssertTrue(s.redoStack.isEmpty)
    let valid = s.document
    XCTAssertThrowsError(try s.execute(.opacity(l.id, .nan)))
    XCTAssertEqual(s.document, valid)
  }
  func testLocksAndHistoryBound() throws {
    var s = EditorSession(document: try CraftDocument(width: 2, height: 2), historyLimit: 2)
    let id = try XCTUnwrap(s.document.activeLayerID)
    try s.execute(.renameLayer(id, "1"))
    try s.execute(.renameLayer(id, "2"))
    try s.execute(.lock(id, true))
    XCTAssertEqual(s.undoStack.count, 2)
    XCTAssertThrowsError(try s.execute(.deleteLayer(id)))
    try s.execute(.visibility(id, false))
    XCTAssertFalse(s.document.layers[0].visible)
  }
  func testBrushSelectionOpacityAndEraser() throws {
    var s = try Surface(width: 20, height: 20, depth: .f32)
    var b = Brush()
    b.color = Pixel(1, 0, 0)
    b.size = 12
    b.opacity = 0.5
    let p = StrokePoint(x: 10, y: 10)
    let selection = IntRect(x: 10, y: 0, width: 10, height: 20)
    try Painter.stroke(surface: &s, points: [p, p, p], brush: b, selection: selection)
    XCTAssertEqual(s.pixel(x: 9, y: 10), .clear)
    XCTAssertEqual(s.pixel(x: 10, y: 10).a, 0.5, accuracy: 0.001)
    b.erase = true
    b.opacity = 1
    try Painter.stroke(surface: &s, points: [p], brush: b)
    XCTAssertEqual(s.pixel(x: 10, y: 10).a, 0, accuracy: 0.001)
  }
  func testInvalidStrokeRollsBack() throws {
    var s = EditorSession(document: try CraftDocument(width: 5, height: 5))
    let l = Layer(name: "x", content: .raster(try Surface(width: 5, height: 5)))
    try s.execute(.addLayer(l))
    let before = s.document
    XCTAssertThrowsError(try s.execute(.stroke(l.id, [StrokePoint(x: .nan, y: 2)], Brush())))
    XCTAssertEqual(s.document, before)
  }
  func testCropPreservesPixelsAndUndo() throws {
    var s = EditorSession(document: try CraftDocument(width: 20, height: 20))
    let before = s.document
    try s.execute(.crop(IntRect(x: 2, y: 3, width: 10, height: 8)))
    XCTAssertEqual(s.document.width, 10)
    XCTAssertEqual(s.document.layers[0].x, -2)
    s.undo()
    XCTAssertEqual(s.document, before)
  }
  func testSelectionOutsideCanvasRejectedAtomically() throws {
    var s = EditorSession(document: try CraftDocument(width: 4, height: 4))
    let before = s.document
    XCTAssertThrowsError(try s.execute(.selection(IntRect(x: 0, y: 0, width: Int.max, height: 4))))
    XCTAssertEqual(s.document, before)
  }
}
extension CoreTests {
  func testCorruptTileLengthRejectedDuringDecode() throws {
    var payload: [String: Any] = [
      "width": 2, "height": 2, "depth": PixelDepth.u8.rawValue,
      "defaultPixel": ["r": 0, "g": 0, "b": 0, "a": 0],
      "tiles": ["0": []],
    ]
    XCTAssertThrowsError(
      try JSONDecoder().decode(Surface.self, from: JSONSerialization.data(withJSONObject: payload)))
    payload["width"] = Int.max
    XCTAssertThrowsError(
      try JSONDecoder().decode(Surface.self, from: JSONSerialization.data(withJSONObject: payload)))
  }
}
