import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class LocalGenerativeFillTests: XCTestCase {
  func testMaskedPlacementPreservesProtectedSamplesAndUndoAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth)
      let command = try LocalGenerativeFill.prepare(source) { image, mask in
        XCTAssertEqual(image.count, 512 * 512 * 3)
        XCTAssertTrue(mask.contains(0))
        XCTAssertTrue(mask.contains(1))
        return try Surface(width: 512, height: 512, depth: .f32, fill: Pixel(0.1, 0.9, 0.33))
      }
      try verify(command, in: source)
    }
  }

  func testPinnedCoreMLModelGeneratesAnEditableFill() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_LAMA_MODEL"] else {
      throw XCTSkip("Set PHOTATO_TEST_LAMA_MODEL to qualify local inference.")
    }
    guard LocalGenerativeFill.supported else { throw XCTSkip("Requires Apple Silicon and macOS 26 or later.") }
    let source = try fixture(.u8)
    let command = try LocalGenerativeFill.prepare(source, model: URL(fileURLWithPath: path))
    try verify(command, in: source)
  }

  private func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var source = try CraftDocument(width: 79, height: 62, depth: depth)
    let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
    var pixels = try Surface(width: source.width, height: source.height, depth: depth, colorEncoding: encoding)
    for y in 0..<source.height { for x in 0..<source.width {
      let value = Float((13 * x + 7 * y) % 41) / 40
      let pixel = x >= 32 && x < 43 && y >= 23 && y < 38
        ? Pixel(0.98, 0.05, 0.03) : Pixel(0.14 + 0.09 * value, 0.62 + 0.18 * value, 0.87)
      if depth == .f32 { pixels.setLinearPixel(x: x, y: y, pixel) }
      else { pixels.setPixel(x: x, y: y, pixel) }
    } }
    source.layers[0].content = .raster(pixels)
    let area = IntRect(x: 30, y: 21, width: 15, height: 19)
    source.setCoverageSelection(try SelectionMask.sampledCoverage(width: source.width, height: source.height, regions: [area]) { x, y in
      guard area.contains(x, y) else { return 0 }
      if x == 30 && y == 21 { return 0 }
      return x == 30 || y == 21 ? 127 : 255
    })
    return source
  }

  private func verify(_ command: Command, in source: CraftDocument) throws {
    let old = try Renderer.composite(source)
    var session = EditorSession(document: source)
    try session.executePrepared(PreparedEdit(command: command, document: source))
    let edited = session.document
    XCTAssertEqual(edited.layers.dropLast(), source.layers[...])
    XCTAssertEqual(edited.selectionMask, source.selectionMask)
    let layer = try XCTUnwrap(edited.layers.last)
    XCTAssertEqual(layer.id, edited.activeLayerID)
    XCTAssertEqual(try XCTUnwrap(layer.mask).pixel(x: 0, y: 0).r, 0)
    XCTAssertEqual(try XCTUnwrap(layer.mask).pixel(x: 0, y: 1).r, Float(127) / 255)
    let output = try Renderer.composite(edited)
    let mask = try MaskSampler(layer: layer)
    for y in 0..<source.height { for x in 0..<source.width {
      let coverage = source.selectionCoverage(x: x, y: y)
      XCTAssertEqual(mask.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5), coverage)
      if coverage == 0 {
        XCTAssertTrue(old.linearPixel(x: x, y: y).hasSameBits(as: output.linearPixel(x: x, y: y)), "\(source.depth) \(x),\(y)")
      }
    } }
    XCTAssertNotEqual(old.pixel(x: 37, y: 29), output.pixel(x: 37, y: 29))
    try session.undo()
    XCTAssertEqual(session.document, source)
    try session.redo()
    XCTAssertEqual(session.document, edited)
  }
}
