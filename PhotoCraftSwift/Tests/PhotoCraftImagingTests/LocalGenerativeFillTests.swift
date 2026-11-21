import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class LocalGenerativeFillTests: XCTestCase {
  func testEdgeBlendReducesTonalStepAndRetainsTheGeneratedInterior() throws {
    var source = try CraftDocument(width: 74, height: 62)
    let original = Pixel(112.0 / 255, 140.0 / 255, 168.0 / 255)
    let generated = Pixel(124.0 / 255, 150.0 / 255, 178.0 / 255)
    source.layers[0].content = .raster(try Surface(width: source.width, height: source.height, fill: original))
    let area = IntRect(x: 17, y: 15, width: 40, height: 32)
    source.selection = area
    let command = try LocalGenerativeFill.prepare(source) { _, _ in
      try Surface(width: 512, height: 512, depth: .f32, fill: generated)
    }
    var session = EditorSession(document: source)
    try session.executePrepared(PreparedEdit(command: command, document: source))
    let result = try Renderer.composite(session.document)
    let edge = result.pixel(x: area.x, y: area.y + 16)
    XCTAssertLessThan(abs(edge.r - original.r), 0.5 * abs(generated.r - original.r))
    XCTAssertLessThan(abs(edge.b - original.b), 0.5 * abs(generated.b - original.b))
    XCTAssertTrue(result.pixel(x: area.x - 1, y: area.y + 16).hasSameBits(as: original))
    XCTAssertTrue(result.pixel(x: area.x + 20, y: area.y + 16).hasSameBits(as: generated))
    let layer = try XCTUnwrap(session.document.layers.last)
    XCTAssertEqual(layer.mask?.pixel(x: 0, y: 16).r, 1)
  }

  func testTranslucentContextDoesNotTintTheFill() throws {
    var source = try CraftDocument(width: 60, height: 50, depth: .f32)
    let original = Pixel(0.96, 0.14, 0.11, 0.999)
    let generated = Pixel(0.2, 0.45, 0.72)
    source.layers[0].content = .raster(try Surface(
      width: source.width, height: source.height, depth: .f32, fill: SRGBTransfer.linear(original), colorEncoding: .linearRGB))
    source.selection = IntRect(x: 12, y: 10, width: 32, height: 30)
    let command = try LocalGenerativeFill.prepare(source) { _, _ in
      try Surface(width: 512, height: 512, depth: .f32, fill: generated)
    }
    guard case .generativeFill(let layer) = command, case .raster(let patch) = layer.content else {
      return XCTFail("Expected an editable raster patch.")
    }
    let edge = patch.pixel(x: 0, y: 15)
    let interior = patch.pixel(x: 16, y: 15)
    XCTAssertTrue(edge.hasSameBits(as: interior))
    XCTAssertEqual(edge.r, generated.r, accuracy: 0.00001)
    XCTAssertEqual(edge.b, generated.b, accuracy: 0.00001)
    XCTAssertEqual(edge.a, 1)
  }

  func testEdgeCorrectionStaysBoundedOnTheMaximumSparseCanvas() throws {
    var source = try CraftDocument(width: 300_000, height: 300_000)
    let area = IntRect(x: 281_301, y: 294_010, width: 4_096, height: 1_024)
    source.selection = area
    var samples = 0
    let generated = Pixel(0.6, 0.57, 0.45)
    let correction = try XCTUnwrap(GenerativeFillEdgeBlend.prepare(in: source, selection: area, gridLimit: 512,
      context: { _, _ in
        samples += 1
        return Pixel(0.55, 0.53, 0.42)
      }, generated: { _, _ in generated }))
    XCTAssertGreaterThan(samples, 0)
    XCTAssertLessThanOrEqual(samples, 512 * 512)
    let center = Double(area.y) + 512.5
    XCTAssertLessThan(correction.adjusted(generated, x: Double(area.x) + 0.5, y: center).r, generated.r)
    XCTAssertTrue(correction.adjusted(generated, x: Double(area.x) + 2_048.5, y: center).hasSameBits(as: generated))
  }

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
