import Foundation
import XCTest
@testable import PhotoCraftCore

final class LayerStackOrderTests: XCTestCase {
  struct Vectors: Decodable {
    struct Vector: Decodable { let background: Bool; let selected: [String]; let operation: LayerStackOperation; let order: [String] }
    let cases: [Vector]
  }
  func fixture(depth: PixelDepth = .u8, background: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width: 3, height: 2, depth: depth)
    d.layers = try ["A", "B", "C", "D", "E"].enumerated().map { index, name in
      var layer = Layer(name: name, content: .raster(try Surface(width: 3, height: 2, depth: depth, fill: Pixel(Float(index) / 4, 0.25, 0.5))))
      layer.colorLabel = .blue; layer.sourceTags = ["own!": Data([UInt8(index)])]
      return layer
    }
    if background {
      var layer = Layer(name: "BG", content: .raster(try Surface(width: 3, height: 2, depth: depth, fill: .white)))
      layer.background = true; layer.protection = .fullyLocked
      d.layers.insert(layer, at: 0)
    }
    d.activeLayerID = d.layers.first(where: { $0.name == "C" })?.id
    d.selection = .init(x: 0, y: 0, width: 1, height: 1)
    return d
  }
  func testAllIndependentRankVectorsAtEveryDepthAndOneUndo() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "stack-order", withExtension: "json", subdirectory: "Fixtures/LayerStack"))
    let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.cases.count, 310)
    for depth in PixelDepth.allCases { for vector in vectors.cases {
      let source = try fixture(depth: depth, background: vector.background)
      let byName = Dictionary(uniqueKeysWithValues: source.layers.map { ($0.name, $0.id) })
      let selected = try vector.selected.map { try XCTUnwrap(byName[$0]) }
      var session = EditorSession(document: source)
      try session.execute(.stackLayers(.init(layerIDs: selected, operation: vector.operation)))
      XCTAssertEqual(session.document.layers.map(\.name), vector.order, "\(depth)/\(vector.selected)/\(vector.operation)")
      XCTAssertEqual(session.document.activeLayerID, source.activeLayerID)
      XCTAssertEqual(session.document.selection, source.selection)
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: session.document.layers.map { ($0.id, $0) }), Dictionary(uniqueKeysWithValues: source.layers.map { ($0.id, $0) }))
      let changed = vector.order != source.layers.map(\.name), arranged = session.document
      XCTAssertEqual(session.undoStack.count, changed ? 1 : 0)
      if changed { try session.undo(); XCTAssertEqual(session.document, source); try session.redo(); XCTAssertEqual(session.document, arranged) }
    } }
  }
  func testIndependentParentOrdersSubtreeNormalizationAndRichFields() throws {
    var d = try fixture(depth: .f32, background: true)
    var g = Layer(name: "G", content: .group(GroupContent()))
    var h = Layer(name: "H", content: .group(GroupContent()))
    var x = d.layers[1], y = d.layers[2], u = d.layers[3], v = d.layers[4]
    x.name = "X"; y.name = "Y"; u.name = "U"; v.name = "V"
    x.parentID = g.id; y.parentID = g.id; u.parentID = h.id; v.parentID = h.id
    g.colorLabel = .red; h.colorLabel = .green
    x.mask = try Surface(width: 3, height: 2, depth: .f32, fill: Pixel(0.375, 0.375, 0.375))
    x.linkID = UUID(); v.linkID = x.linkID
    d.layers = [d.layers[0], x, y, g, u, v, h, d.layers[5]]; d.activeLayerID = x.id
    let original = d
    try Command.stackLayers(.init(layerIDs: [x.id, u.id], operation: .bringToFront)).apply(to: &d)
    XCTAssertEqual(d.layers.map(\.name), ["BG", "Y", "X", "G", "V", "U", "H", "E"])
    XCTAssertEqual(Dictionary(uniqueKeysWithValues: d.layers.map { ($0.id, $0) }), Dictionary(uniqueKeysWithValues: original.layers.map { ($0.id, $0) }))
    d = original
    try Command.stackLayers(.init(layerIDs: [g.id, x.id, h.id], operation: .reverse)).apply(to: &d)
    XCTAssertEqual(d.layers.map(\.name), ["BG", "U", "V", "H", "X", "Y", "G", "E"])
    XCTAssertEqual(d.activeLayerID, original.activeLayerID)
    XCTAssertEqual(Dictionary(uniqueKeysWithValues: d.layers.map { ($0.id, $0) }), Dictionary(uniqueKeysWithValues: original.layers.map { ($0.id, $0) }))
    try d.validate()
  }
  func testInvalidLockedBackgroundAndCancellationAreAtomic() async throws {
    let source = try fixture(background: true), ids = source.layers.map(\.id)
    for requested in [[], [UUID()], [ids[1], ids[1]], [ids[0]], [ids[1], UUID()]] {
      var d = source
      XCTAssertThrowsError(try Command.stackLayers(.init(layerIDs: requested, operation: .bringToFront)).apply(to: &d))
      XCTAssertEqual(d, source)
    }
    var locked = source; locked.layers[1].locked = true
    let before = locked
    XCTAssertThrowsError(try Command.stackLayers(.init(layerIDs: [ids[1], ids[2]], operation: .sendToBack)).apply(to: &locked))
    XCTAssertEqual(locked, before)
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var d = source
      do { try Command.stackLayers(.init(layerIDs: [ids[1]], operation: .bringToFront)).apply(to: &d); return false }
      catch is CancellationError { return d == source }
      catch { return false }
    }
    let atomic = await task.value; XCTAssertTrue(atomic)
  }
}
