import Foundation
import XCTest

@testable import PhotoCraftCore

final class LayerMergeTests: XCTestCase {
  func test262144IndependentPhotoshopNormalCompositePixels() throws {
    for (bits, depth, variant, opacity) in [
      (8, PixelDepth.u8, "normal", Float(1)), (16, .u16, "normal", 1),
      (32, .f32, "normal", 1), (8, .u8, "opacity", Float(153) / 255),
    ] {
      let data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(
            forResource: "\(variant)-rgb\(bits)", withExtension: "rgba",
            subdirectory: "Fixtures/layer-merge")))
      let size = bits / 8
      XCTAssertEqual(data.count, 65536 * 12 * size)
      func sample(_ index: Int) -> Float {
        let offset = index * size
        let value = data[offset..<offset + size].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return bits == 32 ? Float(bitPattern: value) : Float(value) / Float(bits == 8 ? 255 : 65535)
      }
      func pixel(_ offset: Int) -> Pixel {
        Pixel(sample(offset), sample(offset + 1), sample(offset + 2), sample(offset + 3))
      }
      var errors = [Int](repeating: 0, count: 4)
      for index in 0..<65536 {
        let actual = NormalLayerComposite.composite(
          backdrop: pixel(index * 12), source: pixel(index * 12 + 4), opacity: opacity, depth: depth
        )
        let expected = pixel(index * 12 + 8)
        for (c, pair) in zip(
          [actual.r, actual.g, actual.b, actual.a],
          [expected.r, expected.g, expected.b, expected.a]
        ).enumerated() {
          if pair.0.bitPattern != pair.1.bitPattern { errors[c] += 1 }
        }
      }
      XCTAssertEqual(errors, [0, 0, 0, 0], "\(variant) RGB/\(bits)")
    }
  }

  func document(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 5, depth: depth)
    d.layers[0] = Layer(
      name: "Bottom",
      content: .raster(
        try Surface(width: 5, height: 4, depth: depth, fill: Pixel(0.2, 0.4, 0.6, 0.7))))
    d.layers[0].x = -2
    var top = Layer(
      name: "Top",
      content: .raster(
        try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0.7, 0.2, 0.9, 0.6))))
    top.x = 4
    top.y = 3
    d.layers.append(top)
    d.activeLayerID = top.id
    d.selection = IntRect(x: 1, y: 1, width: 2, height: 2)
    return d
  }

  func testAtomicMergeBoundsNamesSelectionAndUndoAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      for operation in LayerMergeOperation.allCases {
        let d = try document(depth)
        var session = EditorSession(document: d)
        try session.execute(
          .mergeLayers(Set(d.layers.map(\.id)), operation == .down ? .selected : operation))
        session.undo()
        XCTAssertEqual(session.document, d)
        let ids = operation == .down ? Set([d.layers[1].id]) : Set(d.layers.map(\.id))
        try session.execute(.mergeLayers(ids, operation))
        let result = session.document
        XCTAssertEqual(result.layers.count, 1)
        let layer = result.layers[0]
        XCTAssertEqual(layer.name, operation == .down ? "Bottom" : "Top")
        XCTAssertEqual(layer.id, operation == .down ? d.layers[0].id : d.layers[1].id)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertEqual(layer.x, operation == .visible ? 0 : -2)
        XCTAssertEqual(result.selection, d.selection)
        XCTAssertEqual(session.undoStack.count, 1)
        XCTAssertEqual(session.undoStack.last?.label, operation.rawValue)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
        session.undo()
        XCTAssertEqual(session.document, d)
        session.redo()
        XCTAssertEqual(session.document, result)
      }
    }
  }

  func testHiddenLayersAndActiveVisiblePlacement() throws {
    var d = try document()
    var hidden = Layer(
      name: "Hidden", content: .raster(try Surface(width: 1, height: 1, fill: .white)))
    hidden.visible = false
    d.layers.insert(hidden, at: 1)
    XCTAssertFalse(LayerMerge.canApply(.down, layerIDs: [d.layers[2].id], in: d))
    for active in [d.layers[0].id, d.layers[2].id] {
      var candidate = d
      candidate.activeLayerID = active
      try Command.mergeLayers([], .visible).apply(to: &candidate)
      XCTAssertEqual(candidate.layers.count, 2)
      XCTAssertEqual(
        candidate.layers.firstIndex(where: { $0.id == active }), active == d.layers[0].id ? 0 : 1)
      XCTAssertEqual(candidate.layers.first(where: { $0.id == hidden.id }), hidden)
    }
    try Command.mergeLayers(Set(d.layers.map(\.id)), .selected).apply(to: &d)
    XCTAssertEqual(d.layers.map(\.name), ["Top"])
  }

  func testUnsupportedInputsAndOversizedUnionRejectAtomically() throws {
    for variant in 0..<9 {
      var d = try document()
      switch variant {
      case 0: d.layers[1].locked = true
      case 1: d.layers[1].blendMode = .multiply
      case 2: d.layers[1].mask = try Surface(width: 4, height: 3, fill: .white)
      case 3: d.layers[1].affine = .scale(2, 1)
      case 4: d.layers[1].content = .fill(.white)
      case 5: d.layers[1].clipped = true
      case 6: d.layers[1].x = 100_000
      case 7: d.layers[1].visible = false
      default: d.layers[1].parentID = UUID()
      }
      let original = d
      XCTAssertThrowsError(try Command.mergeLayers([d.layers[1].id], .down).apply(to: &d))
      XCTAssertEqual(d, original)
    }
    var empty = try document()
    for i in empty.layers.indices {
      empty.layers[i].content = .raster(try Surface(width: 1, height: 1))
    }
    let original = empty
    XCTAssertThrowsError(
      try Command.mergeLayers(Set(empty.layers.map(\.id)), .selected).apply(to: &empty))
    XCTAssertEqual(empty, original)
  }

  func testCancelledAndStaleMergesCannotCommit() async throws {
    let d = try document()
    let command = Command.mergeLayers([d.layers[1].id], .down)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PreparedEdit(command: command, document: d)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled merge completed")
    } catch is CancellationError {}
    let prepared = try PreparedEdit(command: command, document: d)
    var session = EditorSession(document: d)
    try session.execute(.renameLayer(d.layers[0].id, "Changed"))
    let changed = session.document
    XCTAssertThrowsError(try session.executePrepared(prepared))
    XCTAssertEqual(session.document, changed)
  }
}
