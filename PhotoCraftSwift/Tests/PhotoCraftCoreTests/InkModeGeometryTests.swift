import Foundation
import XCTest
@testable import PhotoCraftCore

final class InkModeGeometryTests: XCTestCase {
  func fixture(_ duotone: Bool, depth: PixelDepth = .u16) throws -> CraftDocument {
    let values: [UInt16] = [1, 257, 4097, 32768, 65534, 65535]
    let bytes = duotone ? Data([1, 2, 3, 4, 5, 6]) : Data(values.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
    let plane = try InkPlane(width: 3, height: 2, depth: duotone ? .u8 : depth, bytes: bytes)
    let raster: InkModeRaster = duotone
      ? .duotone(try .init(gray: plane, settings: .init(inks: [.init(name: "Blue", color: Pixel(0, 0, 1))]), sourceModeData: Data([9])))
      : .multichannel(try .init(plates: [.init(name: "Blue", color: Pixel(0, 0, 1), samples: plane), .init(name: "Gold", color: Pixel(1, 0.8, 0), solidity: 0.3, samples: plane.converted(to: depth, inverted: true))]))
    var document = try CraftDocument(width: 3, height: 2).replacingInkMode(raster)
    var mask = try Surface(width: 3, height: 2, depth: document.depth, fill: .black)
    mask.setPixel(x: 1, y: 0, .white)
    document.alphaChannels = [.init(name: "Mask", pixels: mask)]
    document.selection = .init(x: 1, y: 0, width: 1, height: 1)
    try document.validate(); return document
  }
  func planes(_ document: CraftDocument) throws -> [InkPlane] {
    switch try XCTUnwrap(document.inkMode) {
    case .duotone(let r): [r.gray]
    case .multichannel(let r): r.plates.map(\.samples)
    }
  }
  func testQuarterTurnAndFlipMoveExactSamplesMasksAndSelection() throws {
    for duo in [true, false] {
      let original = try fixture(duo), before = try planes(original)
      var session = EditorSession(document: original)
      try session.execute(.rotateCanvas(.clockwise))
      XCTAssertEqual(session.document.width, 2); XCTAssertEqual(session.document.height, 3)
      let indices = [3, 0, 4, 1, 5, 2]
      for (a, b) in zip(try planes(session.document), before) {
        for i in indices.indices { XCTAssertEqual(a.value(at: i), b.value(at: indices[i])) }
      }
      XCTAssertEqual(session.document.selection, .init(x: 1, y: 1, width: 1, height: 1))
      XCTAssertEqual(session.document.alphaChannels?[0].pixels.pixel(x: 1, y: 1), .white)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)) == session.document)
      try session.undo(); XCTAssertTrue(session.document == original)
      try session.execute(.rotateCanvas(.horizontal))
      for (a, b) in zip(try planes(session.document), before) {
        for (i, j) in [2, 1, 0, 5, 4, 3].enumerated() { XCTAssertEqual(a.value(at: i), b.value(at: j)) }
      }
      try session.undo(); XCTAssertTrue(session.document == original)
    }
  }
  func testCanvasExpansionUsesPaperAndCropRestoresAllSamplesAndMetadata() throws {
    for duo in [true, false] {
      let original = try fixture(duo)
      var session = EditorSession(document: original)
      try session.execute(.canvasSize(5, 2, .topLeft, nil))
      let expanded = session.document
      for (a, b) in zip(try planes(expanded), try planes(original)) {
        XCTAssertEqual(a.value(at: 3), duo ? 1 : 0)
        XCTAssertEqual(a.value(at: 4), duo ? 1 : 0)
        for y in 0..<2 { for x in 0..<3 { XCTAssertEqual(a.value(at: y * 5 + x), b.value(at: y * 3 + x)) } }
      }
      try session.execute(.crop(.init(x: 0, y: 0, width: 3, height: 2)))
      XCTAssertEqual(session.document.inkMode, original.inkMode)
      XCTAssertEqual(session.document.alphaChannels, original.alphaChannels); XCTAssertNil(session.document.selection)
      try session.undo(); XCTAssertTrue(session.document == expanded)
      try session.undo(); XCTAssertTrue(session.document == original)
    }
  }
  func testImageSizeResamplesEachPlateWithoutColorConversion() throws {
    let original = try fixture(false), before = try planes(original)
    var session = EditorSession(document: original)
    try session.execute(.imageSize(6, 4, 300, .nearest))
    XCTAssertEqual(session.document.pixelsPerInch, 300)
    for (a, b) in zip(try planes(session.document), before) {
      for y in 0..<4 { for x in 0..<6 { XCTAssertEqual(a.value(at: y * 6 + x), b.value(at: y / 2 * 3 + x / 2)) } }
    }
    try session.undo(); XCTAssertTrue(session.document == original)
    try session.execute(.imageSize(6, 4, 150, .bilinear))
    let after = try planes(session.document)
    XCTAssertEqual(after[0].value(at: 0), before[0].value(at: 0))
    XCTAssertEqual(after[1].value(at: 0), before[1].value(at: 0))
    try session.document.validate()
  }
  func testMalformedGeometryIsAtomicAndRotatedCropRetainsInkMode() throws {
    let original = try fixture(false)
    for command in [Command.canvasSize(Int.min, 3, .center, nil), .imageSize(0, 4, 72, .nearest),
      .canvasSize(4, 3, .center, Pixel(1, 0, 0)), .imageSize(3, 2, .nan, .bilinear)] {
      var candidate = original
      XCTAssertThrowsError(try command.apply(to: &candidate)); XCTAssertTrue(candidate == original)
    }
    var request = CropRequest(x: 0, y: 0, width: 3, height: 2); request.angle = 20
    let cropped = try CropGeometry.applying(request, to: original)
    XCTAssertEqual(cropped.colorMode, .multichannel); XCTAssertEqual(try planes(cropped).count, 2)
    request.deleteCroppedPixels = false
    XCTAssertThrowsError(try CropGeometry.applying(request, to: original))
    request.deleteCroppedPixels = true; request.fill = .contentAware
    XCTAssertThrowsError(try CropGeometry.applying(request, to: original))
  }
}
