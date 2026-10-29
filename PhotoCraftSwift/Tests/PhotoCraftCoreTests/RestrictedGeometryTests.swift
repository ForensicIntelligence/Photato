import Foundation
import XCTest
@testable import PhotoCraftCore

final class RestrictedGeometryTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    try CraftDocument(width: 3, height: 2).replacingRestrictedMode(.indexed(IndexedRaster(width: 3, height: 2,
      palette: [.init(0, 0, 0), .init(0, 0, 0), .init(255, 255, 255), .init(255, 0, 0)], indices: Data([0, 1, 2, 3, 2, 1]))))
  }
  func indices(_ document: CraftDocument) throws -> Data {
    guard case .indexed(let raster) = document.restrictedMode else { throw CraftError.invalid("Missing indices") }
    return raster.indices
  }
  func testEveryCanvasTurnPreservesDuplicateEntryIdentityAndHistory() throws {
    let original = try fixture()
    let cases: [(CanvasTurn, [UInt8])] = [(.clockwise, [3, 0, 2, 1, 1, 2]), (.counterclockwise, [2, 1, 1, 2, 0, 3]), (.half, [1, 2, 3, 2, 1, 0]), (.horizontal, [2, 1, 0, 1, 2, 3]), (.vertical, [3, 2, 1, 0, 1, 2])]
    for (turn, expected) in cases {
      var session = EditorSession(document: original)
      try session.execute(.rotateCanvas(turn)); XCTAssertEqual(try indices(session.document), Data(expected))
      XCTAssertEqual(session.document.layers[0].id, original.layers[0].id)
      let changed = session.document
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(changed)) == changed)
      try session.undo(); XCTAssertTrue(session.document == original); try session.redo(); XCTAssertTrue(session.document == changed)
    }
  }
  func testCropAndNearestResizeCopyStoredIndices() throws {
    let original = try fixture(); var cropped = original
    try Command.crop(.init(x: 1, y: 0, width: 2, height: 2)).apply(to: &cropped)
    XCTAssertEqual(try indices(cropped), Data([1, 2, 2, 1]))
    var resized = original
    try Command.imageSize(6, 4, 144, .nearest).apply(to: &resized)
    XCTAssertEqual(try indices(resized), Data([0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2, 2, 3, 3, 2, 2, 1, 1, 3, 3, 2, 2, 1, 1]))
    XCTAssertEqual(resized.resolution, 144)
    for method in Resampling.allCases {
      var same = original; try Command.imageSize(3, 2, 300, method).apply(to: &same)
      XCTAssertEqual(try indices(same), try indices(original), "Identity resizing must preserve duplicate palette entries")
    }
  }
  func testCanvasAnchoringTransparencyAndFill() throws {
    let original = try fixture(); var document = original
    try Command.canvasSize(5, 4, .topLeft, nil).apply(to: &document)
    XCTAssertEqual(try indices(document), Data([0, 1, 2, 2, 2, 3, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))
    document = original; try Command.canvasSize(2, 1, .bottomRight, nil).apply(to: &document)
    XCTAssertEqual(try indices(document), Data([2, 1]))
    document = try original.replacingColorTable([.init(0, 0, 0), .init(0, 0, 0), .init(255, 255, 255), .init(255, 0, 0)], transparentIndex: 2)
    try Command.canvasSize(5, 2, .right, .clear).apply(to: &document)
    XCTAssertEqual(try indices(document), Data([2, 2, 0, 1, 2, 2, 2, 3, 2, 1]))
  }
  func testNonByteAlignedBitmapGeometryAndPadding() throws {
    let raster = try BitmapRaster(width: 9, height: 2, bits: Data([0x81, 0x80, 0x4a, 0]))
    let original = try CraftDocument(width: 9, height: 2).replacingRestrictedMode(.bitmap(raster))
    var rotated = original; try Command.rotateCanvas(.clockwise).apply(to: &rotated)
    guard case .bitmap(let changed) = rotated.restrictedMode else { return XCTFail("Missing bitmap") }
    XCTAssertEqual(changed.bits, Data([0x40, 0x80, 0, 0, 0x80, 0, 0x80, 0x40, 0x40]))
    var expanded = original; try Command.canvasSize(11, 3, .topLeft, .white).apply(to: &expanded)
    guard case .bitmap(let canvas) = expanded.restrictedMode else { return XCTFail() }
    XCTAssertEqual(canvas.bits, Data([0x81, 0x80, 0x4a, 0, 0, 0])); try expanded.validate()
  }
  func testInterpolatedOutputRetainsModeAndInvalidEditsAreAtomic() throws {
    let original = try fixture()
    for method in [Resampling.bilinear, .bicubic] {
      var document = original; try Command.imageSize(7, 5, 72, method).apply(to: &document)
      try document.validate(); XCTAssertEqual(try indices(document).count, 35)
      guard case .indexed(let raster) = document.restrictedMode else { return XCTFail() }
      XCTAssertTrue(raster.indices.allSatisfy { $0 < 4 }); XCTAssertEqual(raster.palette.count, 4)
    }
    var document = original
    for command in [Command.imageSize(0, 2, 72, .nearest), .imageSize(60000, 60000, 72, .nearest), .imageSize(3, 2, .nan, .nearest), .canvasSize(-1, 2, .center, nil), .crop(.init(x: -1, y: 0, width: 1, height: 1))] {
      XCTAssertThrowsError(try command.apply(to: &document)); XCTAssertTrue(document == original)
    }
  }
}
