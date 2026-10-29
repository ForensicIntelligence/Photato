import Foundation
import XCTest

@testable import PhotoCraftCore

final class RGBComponentFillTests: XCTestCase {
  private struct References: Decodable {
    struct Sample: Decodable {
      let name: String
      let width: Int
      let height: Int
      let value: Float
      let opacity: Float
      let offset: Int
    }
    let byteCount: Int
    let cases: [Sample]
  }

  private func fixture(_ ext: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-component-fill-rgb8", withExtension: ext,
          subdirectory: "Fixtures")))
  }

  func test122880IndependentPhotoshopLayerChannelBytesAndUndo() throws {
    let references = try JSONDecoder().decode(References.self, from: fixture("json"))
    let bytes = try fixture("bin")
    XCTAssertEqual(bytes.count, references.byteCount)
    XCTAssertEqual(references.cases.count, 5)
    var compared = 0
    for reference in references.cases {
      let count = reference.width * reference.height * 4
      let input = bytes.subdata(in: reference.offset..<reference.offset + count)
      let expected = bytes.subdata(in: reference.offset + count..<reference.offset + count * 2)
      var pixels = try Surface(width: reference.width, height: reference.height)
      for y in 0..<reference.height {
        for x in 0..<reference.width {
          let at = (y * reference.width + x) * 4
          pixels.setPixel(
            x: x, y: y,
            Pixel(
              Float(input[at]) / 255, Float(input[at + 1]) / 255,
              Float(input[at + 2]) / 255, Float(input[at + 3]) / 255))
        }
      }
      var document = try CraftDocument(width: reference.width, height: reference.height)
      document.layers[0].content = .raster(pixels)
      var session = EditorSession(document: document)
      try session.execute(
        .fillComponents(
          document.layers[0].id,
          .init(
            components: .red, value: reference.value, opacity: reference.opacity)))
      guard case .raster(let actual) = session.document.layers[0].content else {
        return XCTFail("Lost raster content")
      }
      XCTAssertEqual(try actual.rgbaData(depth: .u8), expected, reference.name)
      XCTAssertEqual(actual.width, pixels.width)
      XCTAssertEqual(actual.height, pixels.height)
      let edited = session.document
      XCTAssertEqual(session.undoStack.map(\.label), ["Fill"])
      try session.undo()
      XCTAssertEqual(session.document, document)
      try session.redo()
      XCTAssertEqual(session.document, edited)
      compared += count
    }
    XCTAssertEqual(compared, 122_880)
  }

  func testAllComponentCombinationsPreserveUntargetedStoredBitsAndMetadata() throws {
    let source = Pixel(Float(bitPattern: 0x8000_0000), 0.12345679, 0.7, 0.23456789)
    for bits: UInt8 in 1...7 {
      var pixels = try Surface(width: 2, height: 2)
      try pixels.mapStoredPixels { _, _, _ in source }
      var document = try CraftDocument(width: 8, height: 7)
      document.layers[0].content = .raster(pixels)
      document.layers[0].x = 2
      document.layers[0].y = 3
      document.layers[0].name = "Cropped layer"
      document.layers[0].opacity = 0.3
      document.layers[0].blendMode = .multiply
      document.layers[0].mask = try Surface(width: 2, height: 2, fill: .black)
      let before = document
      let components = RGBComponents(rawValue: bits)
      try Command.fillComponents(
        document.layers[0].id,
        .init(
          components: components, value: 1)
      ).apply(to: &document)
      guard case .raster(let result) = document.layers[0].content else { return XCTFail() }
      let sample = result.pixel(x: 0, y: 0)
      XCTAssertEqual(
        sample.r.bitPattern, components.contains(.red) ? Float(1).bitPattern : source.r.bitPattern)
      XCTAssertEqual(
        sample.g.bitPattern, components.contains(.green) ? Float(1).bitPattern : source.g.bitPattern
      )
      XCTAssertEqual(
        sample.b.bitPattern, components.contains(.blue) ? Float(1).bitPattern : source.b.bitPattern)
      XCTAssertEqual(sample.a.bitPattern, source.a.bitPattern)
      document.layers[0].content = before.layers[0].content
      XCTAssertEqual(document, before, "Only targeted stored samples may change")
    }
  }

  func testDocumentSpaceSelectionAndFractionalCoverage() throws {
    var document = try CraftDocument(width: 8, height: 5)
    document.layers[0].content = .raster(
      try Surface(width: 3, height: 2, fill: Pixel(0, 0.2, 0.4, 0)))
    document.layers[0].x = 2
    document.layers[0].y = 1
    document.layers[0].affine = .scale(2, 1)
    // Local centers map to (3,1), (5,1), (7,1), then the same columns at y2.
    var coverage = [UInt8](repeating: 0, count: 40)
    coverage[1 * 8 + 3] = 255
    coverage[1 * 8 + 5] = 128
    document.setCoverageSelection(try SelectionMask(width: 8, height: 5, bytes: coverage))
    let before = document
    try Command.fillComponents(
      document.layers[0].id,
      .init(
        components: [.red, .blue], value: 1, opacity: 0.5)
    ).apply(to: &document)
    guard case .raster(let result) = document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(result.pixel(x: 0, y: 0).r, Float(128) / 255)
    XCTAssertEqual(result.pixel(x: 1, y: 0).r, Float(64) / 255)
    XCTAssertEqual(result.pixel(x: 2, y: 0), Pixel(0, 0.2, 0.4, 0).quantized(.u8))
    XCTAssertEqual(result.pixel(x: 0, y: 1), Pixel(0, 0.2, 0.4, 0).quantized(.u8))
    XCTAssertEqual(result.pixel(x: 0, y: 0).a, 0)
    XCTAssertEqual(result.pixel(x: 1, y: 0).g, PixelDepth.u8.quantize(0.2))
    XCTAssertEqual(document.selectionMask, before.selectionMask)
    XCTAssertEqual(document.selection, before.selection)
  }

  func testInvalidTargetsDepthsLocksAndParametersRejectAtomically() throws {
    for variant in 0..<14 {
      var document = try CraftDocument(width: 4, height: 3)
      var id = document.layers[0].id
      var fill = RGBComponentFill(components: .red, value: 1)
      switch variant {
      case 0: fill.components = []
      case 1: fill.components = .init(rawValue: 8)
      case 2: fill.value = .nan
      case 3: fill.opacity = .infinity
      case 4: fill.value = -0.01
      case 5: fill.opacity = 1.01
      case 6: document.layers[0].locked = true
      case 7:
        var group = Layer(name: "Locked parent", content: .group(GroupContent()))
        group.locked = true
        document.layers[0].parentID = group.id
        document.layers.append(group)
      case 8: document.layers[0].content = .fill(.white)
      case 9: id = UUID()
      case 10: document.layers[0].affine = .scale(0, 0)
      case 11, 12:
        document = try CraftDocument(width: 4, height: 3, depth: variant == 11 ? .u16 : .f32)
        id = document.layers[0].id
      default: document.layers[0].content = .raster(try Surface(width: 4, height: 3, depth: .u16))
      }
      let before = document
      XCTAssertThrowsError(
        try Command.fillComponents(id, fill).apply(to: &document), "variant \(variant)")
      XCTAssertEqual(document, before)
      var session = EditorSession(document: before)
      XCTAssertThrowsError(try session.execute(.fillComponents(id, fill)))
      XCTAssertEqual(session.document, before)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
  }

  func testNoOpDoesNotAllocateTilesOrChangeHistory() throws {
    var document = try CraftDocument(width: 4, height: 3)
    document.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: .black))
    var session = EditorSession(document: document)
    for fill in [
      RGBComponentFill(components: .red, value: 0),
      RGBComponentFill(components: .all, value: 1, opacity: 0),
    ] {
      try session.execute(.fillComponents(document.layers[0].id, fill))
      XCTAssertEqual(session.document, document)
      XCTAssertTrue(session.undoStack.isEmpty)
      guard case .raster(let pixels) = session.document.layers[0].content else { return XCTFail() }
      XCTAssertEqual(pixels.tileCount, 0)
    }
  }

  func testCancellationStaleEditAndFailedStoredMapAreAtomic() async throws {
    let document = try CraftDocument(width: 64, height: 64)
    let command = Command.fillComponents(document.layers[0].id, .init(components: .green, value: 1))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PreparedEdit(command: command, document: document)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled edit completed")
    } catch is CancellationError {}
    let prepared = try PreparedEdit(command: command, document: document)
    var session = EditorSession(document: document)
    try session.execute(.renameLayer(document.layers[0].id, "Changed"))
    let changed = session.document
    XCTAssertThrowsError(try session.executePrepared(prepared))
    XCTAssertEqual(session.document, changed)
    XCTAssertEqual(session.undoStack.count, 1)
    var surface = try Surface(width: 2, height: 2)
    let original = surface
    XCTAssertThrowsError(
      try surface.mapStoredPixels { x, y, _ in
        x == 1 && y == 1 ? Pixel(.nan, 1, 1) : .white
      })
    XCTAssertEqual(surface, original)
  }
}
