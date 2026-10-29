import Foundation
import XCTest

@testable import PhotoCraftCore

final class BucketFillTests: XCTestCase {
  func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func options() -> BucketOptions {
    var o = BucketOptions()
    o.match.antiAlias = false
    o.match.tolerance = 0
    return o
  }
  func testAllDepthsFillOnlyConnectedRegionWithPersistenceAndOneUndo() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 10, height: 6, depth: depth)
      var s = try Surface(width: 10, height: 6, depth: depth, fill: .white)
      for y in 0..<6 { s.setPixel(x: 5, y: y, .black) }
      d.layers[0].content = .raster(s)
      let color = Pixel(0.3, 0.4, 0.8)
      let fill = BucketFill(
        source: .init(surface: s), seed: .init(1, 1), color: color, options: options())
      var session = EditorSession(document: d)
      try session.execute(.paintBucket(d.layers[0].id, fill))
      let output = try pixels(session.document.layers[0])
      for y in 0..<6 {
        for x in 0..<10 {
          XCTAssertTrue(
            output.pixel(x: x, y: y).hasSameBits(
              as:
                x < 5 ? color.quantized(depth) : s.pixel(x: x, y: y)))
        }
      }
      let after = session.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)), after)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo()
      XCTAssertEqual(session.document, d)
      try session.redo()
      XCTAssertEqual(session.document, after)
    }
  }

  func testSelectionOpacityAndBlendAreAppliedOnceAtNativeDepth() throws {
    for depth in PixelDepth.allCases {
      let s = try Surface(width: 4, height: 1, depth: depth, fill: Pixel(0.6, 0.4, 0.2, 0.5))
      let selection = try SelectionMask(width: 4, height: 1, bytes: [0, 64, 128, 255])
      let color = Pixel(0.25, 0.5, 0.75, 0.8)
      for mode in BlendMode.allCases {
        var layer = Layer(name: "Target", content: .raster(s))
        var o = options()
        o.opacity = 0.5
        o.mode = mode
        let fill = BucketFill(
          source: .init(surface: s), seed: .init(0, 0), color: color, options: o)
        try BucketPainter.paint(
          fill, on: &layer, canvasWidth: 4, canvasHeight: 1,
          selection: selection.bounds, selectionMask: selection)
        let output = try pixels(layer)
        for x in 0..<4 {
          let original = s.pixel(x: x, y: 0)
          var expected = original
          if x > 0 {
            let opacity = 0.5 * selection.coverage(x: x, y: 0)
            let blended = mode.composite(
              backdrop: depth == .f32 ? SRGBTransfer.linear(original) : original,
              source: depth == .f32 ? SRGBTransfer.linear(color) : color,
              opacity: opacity, x: x, y: 0)
            expected = (depth == .f32 ? SRGBTransfer.encoded(blended) : blended).quantized(depth)
          }
          XCTAssertTrue(
            output.pixel(x: x, y: 0).hasSameBits(as: expected), "\(depth) \(mode) x=\(x)")
        }
      }
    }
  }

  func testCroppedTargetExpandsWithoutMovingLinkedOrUnlinkedMasks() throws {
    for linked in [false, true] {
      let source = try Surface(width: 8, height: 5, fill: .white)
      var target = Layer(name: "Cropped", content: .raster(try Surface(width: 2, height: 2)))
      target.x = 3
      target.y = 2
      target.mask = try Surface(width: 1, height: 1, fill: .white)
      var props = MaskProperties()
      props.linked = linked
      props.transform = .translation(1, 0)
      target.maskProperties = props
      let originalMaskTransform = target.maskCoordinateTransform
      let fill = BucketFill(
        source: .init(surface: source), seed: .init(0, 0), color: .black, options: options())
      XCTAssertTrue(try BucketPainter.paint(fill, on: &target, canvasWidth: 8, canvasHeight: 5))
      let s = try pixels(target)
      XCTAssertEqual(target.coordinateTransform, .identity)
      XCTAssertEqual(s.width, 8)
      XCTAssertEqual(s.height, 5)
      XCTAssertEqual(s.pixel(x: 0, y: 0), .black)
      XCTAssertEqual(s.pixel(x: 7, y: 4), .black)
      XCTAssertEqual(target.maskCoordinateTransform, originalMaskTransform)
    }
  }

  func testRotatedScaledLayerIsFilledInDocumentCoordinates() throws {
    var s = try Surface(width: 5, height: 5, fill: .white)
    for y in 0..<5 { s.setPixel(x: 4, y: y, .black) }
    var layer = Layer(name: "Rotated", content: .raster(s))
    layer.affine = .translation(15, 1) * .rotation(90) * .scale(2, 2)
    let before = layer
    let fill = BucketFill(
      source: .init(surface: s, transform: layer.coordinateTransform),
      seed: .init(10.5, 4.5), color: Pixel(1, 0, 0), options: options())
    try BucketPainter.paint(fill, on: &layer, canvasWidth: 20, canvasHeight: 14)
    XCTAssertEqual(layer.coordinateTransform, before.coordinateTransform)
    let output = try pixels(layer)
    XCTAssertEqual(output.pixel(x: 1, y: 2), Pixel(1, 0, 0))
    XCTAssertEqual(output.pixel(x: 4, y: 2), .black)
  }

  func testMaskFillUsesScalarCoverageAndExpandsImplicitOutside() throws {
    var layer = Layer(
      name: "Mask target", content: .raster(try Surface(width: 6, height: 3, fill: .white)))
    layer.mask = try Surface(width: 1, height: 1, fill: .black)
    var properties = MaskProperties()
    properties.outside = 1
    properties.transform = .translation(2, 1)
    layer.maskProperties = properties
    let originalContent = layer.content
    let sample = CloneSample(
      surface: try XCTUnwrap(layer.mask), transform: layer.maskCoordinateTransform, outside: .white)
    let fill = BucketFill(
      source: sample, seed: .init(0, 0), color: .black, options: options(), mask: true)
    XCTAssertTrue(try BucketPainter.paint(fill, on: &layer, canvasWidth: 6, canvasHeight: 3))
    XCTAssertEqual(layer.content, originalContent)
    XCTAssertEqual(layer.maskCoordinateTransform, .identity)
    let mask = try XCTUnwrap(layer.mask)
    XCTAssertEqual(mask.width, 6)
    XCTAssertEqual(mask.height, 3)
    for y in 0..<3 { for x in 0..<6 { XCTAssertEqual(mask.pixel(x: x, y: y), .black) } }
    // Canvas filling does not change off-canvas mask semantics.
    XCTAssertEqual(layer.effectiveMaskProperties.outside, 1)
  }

  func testNoOpInvalidLockedAndCancelledEditsAreAtomic() async throws {
    var d = try CraftDocument(width: 4, height: 3)
    d.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: .white))
    let original = d
    let sample = CloneSample(surface: try pixels(d.layers[0]))
    var fill = BucketFill(source: sample, seed: .init(0, 0), color: .white, options: options())
    var session = EditorSession(document: d)
    try session.execute(.paintBucket(d.layers[0].id, fill))
    XCTAssertEqual(session.document, d)
    XCTAssertTrue(session.undoStack.isEmpty)
    fill.color = .black
    fill.options.opacity = .nan
    XCTAssertThrowsError(try Command.paintBucket(d.layers[0].id, fill).apply(to: &d))
    XCTAssertEqual(d, original)
    fill.options.opacity = 1
    d.layers[0].locked = true
    let locked = d
    XCTAssertThrowsError(try Command.paintBucket(d.layers[0].id, fill).apply(to: &d))
    XCTAssertEqual(d, locked)
    let captured = fill
    let task = Task.detached {
      var copy = original
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try Command.paintBucket(original.layers[0].id, captured).apply(to: &copy)
        XCTFail("Expected cancellation")
      } catch is CancellationError {} catch { XCTFail("\(error)") }
      XCTAssertEqual(copy, original)
    }
    await task.value
  }
}
