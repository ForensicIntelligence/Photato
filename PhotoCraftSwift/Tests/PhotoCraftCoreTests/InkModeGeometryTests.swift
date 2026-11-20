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

  func testMaximumMultichannelCanvasReframeCropAndAllGridTurnsRetainExactWords() throws {
    let width = 300_000, height = 299_999
    let plate = try InkPlane(width: width, height: height, depth: .u16, value: 0.375)
      .replacing(offset: 0, values: [Float(1) / 65535])
      .replacing(offset: width * height - 1, values: [Float(65534) / 65535])
    let spot = InkPlate(name: "Exact plate", color: .black, samples: plate)
    var original = try CraftDocument(width: width, height: height, depth: .u16)
      .replacingInkMode(.multichannel(.init(plates: [spot])))
    var mask = try Surface(width: width, height: height, depth: .u16, fill: Pixel(0.25, 0.25, 0.25))
    mask.setPixel(x: 17, y: 20, .white)
    original.alphaChannels = [.init(name: "Coverage", pixels: mask)]
    original.selection = .init(x: 17, y: 20, width: 1, height: 1)
    var session = EditorSession(document: original)
    try session.execute(.canvasSize(width, height + 1, .bottomLeft, nil))
    let expanded = session.document
    let expandedPlate = try XCTUnwrap(planes(expanded).first)
    XCTAssertEqual(expandedPlate.rawWord(at: 0), 0)
    XCTAssertEqual(expandedPlate.rawWord(at: width), 1)
    XCTAssertEqual(expandedPlate.rawWord(at: width * (height + 1) - 1), 65534)
    XCTAssertEqual(expandedPlate.rawWord(at: width + 8), plate.defaultWord)
    XCTAssertEqual(expanded.selection, .init(x: 17, y: 21, width: 1, height: 1))
    XCTAssertEqual(expanded.alphaChannels?[0].pixels.pixel(x: 17, y: 21), .white)
    XCTAssertEqual(expanded.alphaChannels?[0].pixels.pixel(x: 17, y: 0), .black)
    XCTAssertEqual(expanded.alphaChannels?[0].pixels.pixel(x: 18, y: 21), mask.pixel(x: 18, y: 20))
    XCTAssertEqual(expanded.minimumArchiveVersion, 93)

    try session.execute(.crop(.init(x: 0, y: 1, width: width, height: height)))
    XCTAssertEqual(try planes(session.document), [plate])
    XCTAssertEqual(session.document.alphaChannels, original.alphaChannels)
    XCTAssertNil(session.document.selection)
    try session.undo()
    XCTAssertEqual(session.document, expanded)
    try session.undo()
    XCTAssertEqual(session.document, original)

    for turn in CanvasTurn.allCases {
      try session.execute(.rotateCanvas(turn))
      let first: (x: Int, y: Int)
      let last: (x: Int, y: Int)
      switch turn {
      case .clockwise: (first, last) = ((height - 1, 0), (0, width - 1))
      case .counterclockwise: (first, last) = ((0, width - 1), (height - 1, 0))
      case .half: (first, last) = ((width - 1, height - 1), (0, 0))
      case .horizontal: (first, last) = ((width - 1, 0), (0, height - 1))
      case .vertical: (first, last) = ((0, height - 1), (width - 1, 0))
      }
      let result = try XCTUnwrap(planes(session.document).first)
      XCTAssertEqual(result.rawWord(at: first.y * result.width + first.x), 1, turn.rawValue)
      XCTAssertEqual(result.rawWord(at: last.y * result.width + last.x), 65534, turn.rawValue)
      XCTAssertEqual(result.defaultWord, plate.defaultWord)
      XCTAssertLessThanOrEqual(result.retainedSampleBytes, 2 * ComponentPlane.blockSamples * 2)
      try session.undo()
      XCTAssertEqual(session.document, original)
    }
  }

  func testPagedResizeAndRotatedCropMatchDenseSamplesForEveryKernel() throws {
    let side = 300_000
    for depth in [PixelDepth.u8, .u16] {
      let large = try InkPlane(width: side, height: side, depth: depth, value: 0.375)
        .replacing(offset: 0, values: [0.2, 0.9, 0.75, 0.4])
        .replacing(offset: side + 1, values: [1, 0.1, 0.6])
      let control = try InkPlane(width: 32, height: 32, depth: depth, value: 0.375)
        .replacing(offset: 0, values: [0.2, 0.9, 0.75, 0.4])
        .replacing(offset: 33, values: [1, 0.1, 0.6])
      let turn = Transform2D.translation(1.75, 2.5) * .rotation(20)
      for method in Resampling.allCases {
        let reduced = try large.transformed(by: .scale(0.5, 0.5), width: side / 2, height: side / 2,
          method: method, clampEdges: true)
        let resized = try control.transformed(by: .scale(0.5, 0.5), width: 16, height: 16,
          method: method, clampEdges: true)
        for y in 0..<16 {
          for x in 0..<16 {
            XCTAssertEqual(reduced.rawWord(at: y * reduced.width + x), resized.rawWord(at: y * 16 + x), method.rawValue)
          }
        }
        XCTAssertEqual(reduced.rawWord(at: reduced.count - 1), large.defaultWord)
        XCTAssertLessThan(reduced.retainedSampleBytes, 512 * 1024)
        let crop = try large.transformed(by: turn, width: 13, height: 14, method: method, fill: 0.1317)
        let croppedReference = try control.transformed(by: turn, width: 13, height: 14, method: method, fill: 0.1317)
        XCTAssertEqual(try crop.bytes, try croppedReference.bytes, method.rawValue)
      }
    }
    let flat = try InkPlane(width: 3, height: 3, value: 0.5)
    let expanded = try flat.transformed(by: .scale(100_000, 100_000), width: side, height: side,
      method: .bicubic, clampEdges: true)
    XCTAssertEqual(expanded.rawWord(at: expanded.count - 1), 128)
    XCTAssertEqual(expanded.retainedSampleBytes, 0)
  }
}
