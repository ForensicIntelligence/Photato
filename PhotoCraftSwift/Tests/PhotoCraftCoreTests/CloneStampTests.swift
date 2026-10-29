import Foundation
import XCTest

@testable import PhotoCraftCore

final class CloneStampTests: XCTestCase {
  func testRoundTipAgainstExecutedRustOracle() throws {
    let data = try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "clone-tip-oracle", withExtension: "bin", subdirectory: "Fixtures")))
    XCTAssertEqual(data.count, 6168 * 16)
    func f(_ i: Int) -> Float {
      Float(bitPattern: (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[i + $1]) << ($1 * 8) })
    }
    for i in stride(from: 0, to: data.count, by: 16) {
      XCTAssertEqual(
        ClonePainter.coverage(distance: f(i), radius: f(i + 4), hardness: f(i + 8)), f(i + 12),
        accuracy: 0.00000012)
    }
  }
  func patterned(_ depth: PixelDepth) throws -> Surface {
    var s = try Surface(width: 20, height: 8, depth: depth)
    for y in 0..<8 {
      for x in 0..<20 {
        s.setPixel(x: x, y: y, Pixel(Float(x) / 19, Float(y) / 7, Float((x + y) % 5) / 4))
      }
    }
    return s
  }
  func brush() -> CloneBrush {
    var b = CloneBrush()
    b.size = 3
    b.hardness = 1
    b.pressureSize = false
    return b
  }
  func testExactOpaqueCopyAllDepthsAndImmutableOverlappingSource() throws {
    for depth in PixelDepth.allCases {
      let source = try patterned(depth)
      var output = source
      let stroke = CloneStroke(
        source: .init(surface: source),
        mapping: .init(source: .init(3.5, 3.5), anchor: .init(4.5, 3.5)), brush: brush(),
        points: [.init(x: 4.5, y: 3.5), .init(x: 17.5, y: 3.5)])
      try ClonePainter.paint(stroke, on: &output, transform: .identity)
      for x in 4...17 {
        XCTAssertEqual(output.pixel(x: x, y: 3), source.pixel(x: x - 1, y: 3), "\(depth) x=\(x)")
      }
      XCTAssertEqual(output.pixel(x: 0, y: 0), source.pixel(x: 0, y: 0))
    }
  }
  func testFlowAccumulatesUnderOpacityCeilingAndFractionalSelection() throws {
    var source = try Surface(width: 8, height: 8, depth: .f32, fill: .white)
    source.setPixel(x: 0, y: 0, Pixel(1, 0, 0, 0))
    var output = try Surface(width: 8, height: 8, depth: .u16, fill: .black)
    var b = brush()
    b.size = 8
    b.flow = 0.25
    b.opacity = 0.5
    b.spacing = 0.0625
    let sel = try SelectionMask(width: 8, height: 8, bytes: Array(repeating: 128, count: 64))
    let stroke = CloneStroke(
      source: .init(surface: source),
      mapping: .init(source: .init(4.5, 4.5), anchor: .init(4.5, 4.5)), brush: b,
      points: [.init(x: 4.5, y: 4.5), .init(x: 5.5, y: 4.5)])
    try ClonePainter.paint(stroke, on: &output, transform: .identity, selectionMask: sel)
    let k: Float = (1 - pow(0.75, 3)) * 0.5 * 128 / 255
    XCTAssertEqual(output.pixel(x: 4, y: 4).r, k, accuracy: 1.0 / 65535)
    XCTAssertLessThanOrEqual(output.pixel(x: 4, y: 4).r, 0.5 * 128 / 255)
    XCTAssertEqual(output.pixel(x: 0, y: 0), .black)
  }
  func testTransformsPremultipliedResamplingAndOffsets() throws {
    var mapping = CloneMapping(source: .init(10, 20), anchor: .init(30, 40))
    mapping.width = 200
    mapping.height = 50
    mapping.rotation = 90
    let m = try mapping.transform()
    let p = m.point(31, 40)
    XCTAssertEqual(p.x, 10, accuracy: 1e-10)
    XCTAssertEqual(p.y, 22, accuracy: 1e-10)
    mapping.rotation = 0
    mapping.flipHorizontal = true
    XCTAssertEqual(try mapping.transform().point(32, 40).x, 9, accuracy: 1e-10)
    var source = try Surface(width: 2, height: 1, depth: .f32)
    source.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    source.setPixel(x: 1, y: 0, Pixel(0, 0, 1, 0))
    var result = try Surface(width: 1, height: 1, depth: .f32)
    var map = CloneMapping(source: .init(1, 0.5), anchor: .init(0.5, 0.5))
    map.width = 200
    try ClonePainter.paint(
      .init(
        source: .init(surface: source), mapping: map, brush: brush(),
        points: [.init(x: 0.5, y: 0.5)]), on: &result, transform: .identity)
    XCTAssertEqual(result.pixel(x: 0, y: 0).r, 1, accuracy: 0.000001)
    XCTAssertEqual(result.pixel(x: 0, y: 0).b, 0)
    XCTAssertEqual(result.pixel(x: 0, y: 0).a, 0.5)
  }
  func testFloatTransformedSamplesUseLinearLightAndIntegerSamplesStayEncoded() throws {
    var source = try Surface(width: 2, height: 1, depth: .f32, fill: .black)
    source.setPixel(x: 1, y: 0, .white)
    var map = CloneMapping(source: .init(1, 0.5), anchor: .init(0.5, 0.5))
    map.width = 200
    for depth in PixelDepth.allCases {
      var result = try Surface(width: 1, height: 1, depth: depth)
      try ClonePainter.paint(
        .init(
          source: .init(surface: source), mapping: map, brush: brush(),
          points: [.init(x: 0.5, y: 0.5)]), on: &result, transform: .identity)
      let expected =
        depth == .f32
        ? SRGBTransfer.encoded(Pixel(0.5, 0.5, 0.5)) : Pixel(0.5, 0.5, 0.5).quantized(depth)
      XCTAssertEqual(result.pixel(x: 0, y: 0).r, expected.r, accuracy: 0.000001)
    }
  }
  func testCommandUndoMasksArchiveAndInheritedLock() throws {
    var d = try CraftDocument(width: 20, height: 8, depth: .u16)
    let s = try patterned(.u16)
    d.layers[0].content = .raster(s)
    let id = d.layers[0].id
    let stroke = CloneStroke(
      source: .init(surface: s), mapping: .init(source: .init(2.5, 3.5), anchor: .init(12.5, 3.5)),
      brush: brush(), points: [.init(x: 12.5, y: 3.5)])
    var session = EditorSession(document: d)
    try session.execute(.cloneStamp(id, stroke))
    XCTAssertEqual(session.undoStack.last?.label, "Clone Stamp")
    XCTAssertEqual(
      try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    try session.undo()
    XCTAssertEqual(session.document, d)
    d.layers[0].mask = try Surface(width: 20, height: 8, depth: .u16, fill: .black)
    var maskStroke = stroke
    maskStroke.mask = true
    try Command.cloneStamp(id, maskStroke).apply(to: &d)
    XCTAssertEqual(d.layers[0].mask?.pixel(x: 12, y: 3).r, s.pixel(x: 2, y: 3).r)
    let group = Layer(name: "Locked", content: .group(.init()))
    d.layers[0].parentID = group.id
    d.layers.append(group)
    d.layers[1].locked = true
    session = EditorSession(document: d)
    XCTAssertThrowsError(try session.execute(.cloneStamp(id, stroke)))
    XCTAssertEqual(session.document, d)
  }
  func testInvalidStrokeIsAtomicAndSegmentationDoesNotChangeSpacing() throws {
    let source = try patterned(.u8)
    var a = source
    var b = source
    let mapping = CloneMapping(source: .init(2.5, 3.5), anchor: .init(8.5, 3.5))
    let p = [StrokePoint(x: 8.5, y: 3.5), StrokePoint(x: 15.5, y: 3.5)]
    try ClonePainter.paint(
      .init(source: .init(surface: source), mapping: mapping, brush: brush(), points: p), on: &a,
      transform: .identity)
    try ClonePainter.paint(
      .init(
        source: .init(surface: source), mapping: mapping, brush: brush(),
        points: [p[0], .init(x: 9.0, y: 3.5), .init(x: 13.75, y: 3.5), p[1]]), on: &b,
      transform: .identity)
    XCTAssertEqual(a, b)
    var bad = brush()
    bad.flow = .nan
    XCTAssertThrowsError(
      try ClonePainter.paint(
        .init(source: .init(surface: source), mapping: mapping, brush: bad, points: p), on: &b,
        transform: .identity))
    XCTAssertEqual(b, a)
    XCTAssertThrowsError(
      try ClonePainter.paint(
        .init(
          source: .init(surface: source), mapping: mapping, brush: brush(),
          points: [.init(x: .infinity, y: 1)]), on: &b, transform: .identity))
    XCTAssertEqual(b, a)
  }
}
