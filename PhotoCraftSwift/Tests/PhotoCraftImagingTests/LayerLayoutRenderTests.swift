import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerLayoutRenderTests: XCTestCase {
  struct Reference: Decodable {
    var name: String, kind: String, edge: String, input: String, reference: String
    var target: [Int]?, canvas: Bool, expected: [[Int]]
  }
  func file(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/layout")))
  }
  func merged(_ data: Data) throws -> Data {
    func u16(_ i: Int) -> Int { Int(data[i]) << 8 | Int(data[i + 1]) }
    func u32(_ i: Int) -> Int { u16(i) << 16 | u16(i + 2) }
    let channels = u16(12)
    let height = u32(14)
    let width = u32(18)
    XCTAssertEqual(u16(22), 8)
    var reader = PSDReader(data: data, offset: 26)
    for _ in 0..<3 { _ = try reader.section() }
    var raw = try PSDChannelCodec.decode(
      reader.bytes(reader.remaining), width: width, height: height, depth: 8, channels: channels)
    if channels == 3 { raw.append(contentsOf: repeatElement(UInt8(255), count: width * height)) }
    return Data(raw)
  }
  func packed(_ surface: Surface) -> Data {
    let n = surface.width * surface.height
    var raw = [UInt8](repeating: 0, count: n * 4)
    for y in 0..<surface.height {
      for x in 0..<surface.width {
        let p = PSDMergedSample.encode(surface.pixel(x: x, y: y), depth: 8)
        for (c, value) in [p.r, p.g, p.b, p.a].enumerated() {
          raw[c * n + y * surface.width + x] = UInt8((value * 255).rounded())
        }
      }
    }
    return Data(raw)
  }
  func testIndependentPhotoshopLayoutCompositionPersistenceAndPSDExport() throws {
    let cases = try JSONDecoder().decode([Reference].self, from: file("cases.json"))
    XCTAssertEqual(cases.count, 26)
    let names = [
      "top": "Top Edges", "bottom": "Bottom Edges", "vcenter": "Vertical Centers",
      "left": "Left Edges", "right": "Right Edges", "hcenter": "Horizontal Centers",
      "hspace": "Horizontally", "vspace": "Vertically",
    ]
    var results: [[String: Any]] = []
    for row in cases {
      var document = try PSDCodec.read(file(row.input))
      if let r = row.target, !row.canvas {
        try Command.selection(IntRect(x: r[0], y: r[1], width: r[2], height: r[3])).apply(
          to: &document)
      }
      let original = document
      let operation: LayerLayoutOperation =
        row.kind == "align"
        ? .align(try XCTUnwrap(LayerAlignment(rawValue: names[row.edge]!)))
        : .distribute(try XCTUnwrap(LayerDistribution(rawValue: names[row.edge]!)))
      let command = try Renderer.layoutCommand(
        in: document, selected: Set(document.layers.map(\.id)), operation: operation,
        target: row.canvas ? .canvas : .selection)
      try command.apply(to: &document)
      XCTAssertEqual(document.selection, original.selection, row.name)
      let photoshop = try PSDCodec.read(file(row.reference))
      for i in document.layers.indices {
        let stored = try Renderer.layoutBounds(document.layers[i], in: document, stored: true)
        let referenceStored = try Renderer.layoutBounds(
          photoshop.layers[i], in: photoshop, stored: true)
        XCTAssertEqual(stored, referenceStored, row.name)
        if case .raster(let actualPixels) = document.layers[i].content,
          case .raster(let originalPixels) = original.layers[i].content
        {
          let expectedPixels =
            actualPixels.width == originalPixels.width
              && actualPixels.height == originalPixels.height
            ? originalPixels
            : try originalPixels.cropped(to: XCTUnwrap(originalPixels.contentBounds()))
          XCTAssertEqual(actualPixels, expectedPixels, row.name)
        }
        let b = try XCTUnwrap(
          Renderer.layoutBounds(document.layers[i], in: document, stored: false))
        XCTAssertEqual([b.x, b.y, b.width, b.height], row.expected[i], row.name)
      }
      let reference = try merged(file(row.reference))
      let pixels = try Renderer.composite(document)
      let actual = packed(pixels)
      XCTAssertTrue(actual == reference, "\(row.name): rendered bytes differ")
      let native = try NativeArchive.decode(NativeArchive.encode(document))
      XCTAssertEqual(native, document)
      let exported = try PSDCodec.writeRasterLayers(native)
      XCTAssertTrue(try merged(exported) == reference, "\(row.name): PSD merged bytes differ")
      let restored = try PSDCodec.read(exported)
      XCTAssertTrue(
        try packed(Renderer.composite(restored)) == reference,
        "\(row.name): PSD reopened bytes differ")
      results.append([
        "name": row.name, "pixels": document.width * document.height,
        "composition_exact": actual == reference, "export_exact": try merged(exported) == reference,
      ])
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/layer-layout-reference.json"))
  }
  func testGroupsEditableTypesDepthsAndEmptyLayers() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 120, height: 80, depth: depth)
      let group = Layer(name: "Group", content: .group(GroupContent()))
      var shape = Layer(
        name: "Shape",
        content: .shape(ShapeContent(kind: .rectangle, width: 8, height: 7, color: .white)))
      shape.x = 17
      shape.y = 9
      shape.parentID = group.id
      var text = Layer(name: "Type", content: .text(TextContent(text: "Hi", size: 16)))
      text.x = 41
      text.y = 21
      text.parentID = group.id
      var pixel = Layer(
        name: "Pixels",
        content: .raster(try Surface(width: 7, height: 5, depth: depth, fill: .white)))
      pixel.x = 88
      pixel.y = 55
      let empty = Layer(
        name: "Empty", content: .raster(try Surface(width: 1, height: 1, depth: depth)))
      d.layers = [shape, text, group, empty, pixel]
      d.activeLayerID = pixel.id
      let original = d
      let command = try Renderer.layoutCommand(
        in: d, selected: Set(d.layers.map(\.id)), operation: .align(.right))
      try command.apply(to: &d)
      XCTAssertEqual(d.layers[4], original.layers[4])
      XCTAssertEqual(d.layers[3], empty)
      XCTAssertEqual(d.layers[0].content, shape.content)
      XCTAssertEqual(d.layers[1].content, text.content)
      XCTAssertEqual(d.layers[0].x - shape.x, d.layers[1].x - text.x)
      let bounds = try XCTUnwrap(Renderer.layoutBounds(d.layers[2], in: d, stored: false))
      XCTAssertEqual(bounds.x + bounds.width, 95)
    }
  }
  func testUnboundedFillIsExplicitlyRejected() throws {
    var d = try CraftDocument(width: 10, height: 10)
    let fill = Layer(name: "Fill", content: .fill(.white))
    d.layers = [fill]
    d.activeLayerID = fill.id
    XCTAssertThrowsError(
      try Renderer.layoutCommand(
        in: d, selected: [fill.id], operation: .align(.left), target: .canvas))
  }
  func testConsecutiveAlignmentsUsePhotoshopsUpdatedStorageBounds() throws {
    var d = try PSDCodec.read(file("00-input.psd"))
    let selected = Set(d.layers.map(\.id))
    try Renderer.layoutCommand(in: d, selected: selected, operation: .align(.horizontalCenter))
      .apply(to: &d)
    try Command.selection(IntRect(x: 0, y: 0, width: d.width, height: d.height)).apply(to: &d)
    try Renderer.layoutCommand(in: d, selected: selected, operation: .align(.left)).apply(to: &d)
    let expected = try merged(file("sequence-hcenter-selection-left.psd"))
    XCTAssertTrue(
      try packed(Renderer.composite(d)) == expected, "Consecutive alignment differs from Photoshop")
    XCTAssertTrue(try merged(PSDCodec.writeRasterLayers(d)) == expected)
    let result: [String: Any] = [
      "pixels": d.width * d.height,
      "composition_exact": try packed(Renderer.composite(d)) == expected,
      "export_exact": try merged(PSDCodec.writeRasterLayers(d)) == expected,
    ]
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/layer-layout-sequence-reference.json"))
  }
}
