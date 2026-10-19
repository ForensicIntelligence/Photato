import Foundation
import XCTest

@testable import PhotoCraftCore

final class LayerViaTests: XCTestCase {
  func test196608IndependentPhotoshopAlphaPairsAtAllDepths() throws {
    for (bits, depth) in [(8, PixelDepth.u8), (16, .u16), (32, .f32)] {
      let data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(
            forResource: "photoshop-rgb\(bits)", withExtension: "alpha",
            subdirectory: "Fixtures/layer-via")))
      let bytes = bits / 8
      let count = 256 * 256
      XCTAssertEqual(data.count, count * bytes * 3)
      func sample(_ index: Int) -> Float {
        let offset = index * bytes
        let v = data[offset..<offset + bytes].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return bits == 32 ? Float(bitPattern: v) : Float(v) / Float(bits == 8 ? 255 : 65535)
      }
      var copyErrors = 0
      var cutErrors = 0
      for i in 0..<count {
        let result = LayerVia.alpha(source: sample(i), selection: UInt8(i % 256), depth: depth)
        if result.copied.bitPattern != sample(count + i).bitPattern { copyErrors += 1 }
        if result.remaining.bitPattern != sample(2 * count + i).bitPattern { cutErrors += 1 }
      }
      XCTAssertEqual(copyErrors, 0, "RGB/\(bits) copied alpha")
      XCTAssertEqual(cutErrors, 0, "RGB/\(bits) remaining source alpha")
    }
  }

  func selected(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 7, height: 6, depth: depth)
    d.layers[0].content = .raster(
      try Surface(width: 5, height: 4, depth: depth, fill: Pixel(0.2, 0.4, 0.8, 0.6)))
    d.layers[0].x = -1
    d.layers[0].y = 1
    d.selection = IntRect(x: 0, y: 2, width: 3, height: 2)
    return d
  }

  func testOffsetCutPreservesMaskFramePropertiesAndAtomicUndo() throws {
    for depth in PixelDepth.allCases {
      var d = try selected(depth)
      d.layers[0].visible = false
      d.layers[0].opacity = 0.6
      d.layers[0].blendMode = .multiply
      d.layers[0].mask = try Surface(width: 5, height: 4, depth: depth, fill: .white)
      var props = MaskProperties()
      props.transform = .translation(2, -3)
      props.linked = false
      d.layers[0].maskProperties = props
      let oldMaskTransform = d.layers[0].maskCoordinateTransform
      var session = EditorSession(document: d)
      try session.execute(.layerVia(d.layers[0].id, .cut))
      let result = session.document
      XCTAssertEqual(result.layers.count, 2)
      let new = result.layers[1]
      XCTAssertEqual(new.name, "Layer 1")
      XCTAssertEqual(new.x, 0)
      XCTAssertEqual(new.y, 2)
      XCTAssertTrue(new.visible)
      XCTAssertFalse(new.locked)
      XCTAssertEqual(new.opacity, 0.6)
      XCTAssertEqual(new.blendMode, .multiply)
      XCTAssertNil(new.mask)
      XCTAssertNil(new.vectorMask)
      XCTAssertNil(new.sourceTags)
      XCTAssertEqual(result.layers[0].maskCoordinateTransform, oldMaskTransform)
      XCTAssertFalse(result.layers[0].visible)
      XCTAssertNil(result.selection)
      XCTAssertNil(result.selectionMask)
      XCTAssertEqual(result.activeLayerID, new.id)
      XCTAssertEqual(session.undoStack.count, 1)
      guard case .raster(let pixels) = result.layers[0].content else { return XCTFail() }
      XCTAssertEqual(pixels.pixel(x: 1, y: 1), Pixel(1, 1, 1, 0))
      session.undo()
      XCTAssertEqual(session.document, d)
      session.redo()
      XCTAssertEqual(session.document, result)
    }
  }

  func testCopyLeavesSourceUnchangedAndStaysInParentGroup() throws {
    var d = try selected(.f32)
    let group = Layer(name: "Group", content: .group(GroupContent()))
    d.layers[0].parentID = group.id
    d.layers[0].name = "Layer 1"
    d.layers.append(group)
    let old = d
    try Command.layerVia(d.layers[0].id, .copy).apply(to: &d)
    XCTAssertEqual(d.layers[0], old.layers[0])
    XCTAssertEqual(d.layers[1].parentID, group.id)
    XCTAssertEqual(d.layers[1].name, "Layer 2")
    XCTAssertEqual(d.layers[2], group)
    try d.validate()
  }

  func testUnsupportedLockedEmptyAndLayerLimitRejectAtomically() throws {
    for variant in 0..<7 {
      var d = try selected()
      switch variant {
      case 0: d.layers[0].locked = true
      case 1: d.layers[0].affine = .scale(2, 1)
      case 2: d.layers[0].clipped = true
      case 3: d.layers[0].content = .fill(.white)
      case 4: d.selection = nil
      case 5: d.layers[0].content = .raster(try Surface(width: 5, height: 4))
      default:
        for i in 1..<512 {
          d.layers.append(
            Layer(name: "Empty \(i)", content: .raster(try Surface(width: 1, height: 1))))
        }
      }
      let before = d
      for operation in LayerViaOperation.allCases {
        XCTAssertThrowsError(try Command.layerVia(d.layers[0].id, operation).apply(to: &d))
        XCTAssertEqual(d, before)
      }
    }
  }

  func testCancelledAndStaleEditsCannotReplaceDocument() async throws {
    let d = try selected(.u16)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PreparedEdit(command: .layerVia(d.layers[0].id, .cut), document: d)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled edit completed")
    } catch is CancellationError {}
    let prepared = try PreparedEdit(command: .layerVia(d.layers[0].id, .cut), document: d)
    var session = EditorSession(document: d)
    try session.execute(.renameLayer(d.layers[0].id, "Changed"))
    let changed = session.document
    XCTAssertThrowsError(try session.executePrepared(prepared))
    XCTAssertEqual(session.document, changed)
  }
}
