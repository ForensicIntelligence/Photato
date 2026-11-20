import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDProjectiveSmartObjectTests: XCTestCase {
  // Geometry scaled from the Photoshop-authored sample reported in PhotoCraft #579.
  let corners = [PathPoint(6.3, 33.4), .init(49.075, 14.4), .init(93.4125, 55.1), .init(47.35, 79.7625)]

  private func document() throws -> CraftDocument {
    var document = try CraftDocument(width: 100, height: 90, depth: .u16)
    var pixels = try Surface(width: 16, height: 12, depth: .u16)
    for y in 0..<12 {
      for x in 0..<16 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x) / 15, Float(y) / 11, 0.35, 0.75))
      }
    }
    let bytes = try RasterIO.encoded(pixels)
    var layer = try SmartObjectIO.placed(data: bytes, fileName: "Artwork.png", in: document, fit: false)
    layer.sourceProjection = try SelectionTransform.projection(bounds: .init(x: 0, y: 0, width: 16, height: 12), corners: corners)
    layer.affine = nil; layer.x = 0; layer.y = 0
    layer.warp = WarpDefinition()
    layer.mask = try Surface(width: 72, height: 50, depth: .u16, fill: .white)
    var mask = MaskProperties()
    mask.linked = false
    mask.transform = .translation(9, 13)
    layer.maskProperties = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    return document
  }

  private func corners(of layer: Layer) throws -> [PathPoint] {
    let map = try XCTUnwrap(layer.smartObjectSourceProjection())
    return try [PathPoint(0, 0), .init(16, 0), .init(16, 12), .init(0, 12)].map { try map.point($0.x, $0.y) }
  }

  private func assertCorners(_ actual: [PathPoint], _ expected: [PathPoint], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (p, q) in zip(actual, expected) {
      XCTAssertEqual(p.x, q.x, accuracy: 1e-10, file: file, line: line)
      XCTAssertEqual(p.y, q.y, accuracy: 1e-10, file: file, line: line)
    }
  }

  func testEditableProjectivePSDAndPSBKeepSourceCornersMaskAndRenderedSamples() throws {
    let original = try document()
    let pixels = try Renderer.composite(original).rgbaData(depth: .u16)
    for format in [PSDFileFormat.psd, .psb] {
      let saved = try PSDCodec.writeRasterLayers(original, format: format)
      let reopened = try PSDCodec.readPaged(saved)
      let layer = try XCTUnwrap(reopened.layers.first)
      XCTAssertEqual(layer.smartObject?.data, original.layers[0].smartObject?.data)
      XCTAssertEqual(layer.smartObject?.sourceID, original.layers[0].smartObject?.sourceID)
      XCTAssertEqual(layer.maskCoordinateTransform, original.layers[0].maskCoordinateTransform)
      XCTAssertEqual(layer.effectiveMaskProperties.linked, false)
      XCTAssertNotNil(layer.pristineSmartAppearance)
      assertCorners(try corners(of: layer), corners)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u16), pixels)
      let tags = try XCTUnwrap(layer.sourceTags?["SoLd"])
      let quads = try PSDSmartObjects.PlacementQuads(PSDSmartObjects.descriptor(tags))
      XCTAssertNotEqual(quads.base, quads.content)
      XCTAssertEqual(quads.base[0], corners[0].x, accuracy: 1e-10)
      XCTAssertEqual(quads.base[1], corners[1].y, accuracy: 1e-10)
      XCTAssertEqual(quads.base[4], corners[2].x, accuracy: 1e-10)
      XCTAssertEqual(quads.base[5], corners[3].y, accuracy: 1e-10)
      let resaved = try PSDCodec.read(PSDCodec.writeRasterLayers(reopened, format: format))
      let resavedTag = try XCTUnwrap(resaved.layers.first?.sourceTags?["SoLd"])
      let resavedQuads = try PSDSmartObjects.PlacementQuads(PSDSmartObjects.descriptor(resavedTag))
      XCTAssertEqual(resavedQuads.base, quads.base)
      XCTAssertEqual(resavedQuads.content, quads.content)

      var edited = reopened
      let delta = Transform2D.translation(2, 3) * .rotation(7)
      try Command.transformLayers(.init(layerIDs: [layer.id], matrix: delta)).apply(to: &edited)
      XCTAssertNil(edited.layers[0].pristineSmartAppearance)
      let changed = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: format))
      assertCorners(try corners(of: changed.layers[0]), corners.map { p in
        let q = delta.point(p.x, p.y); return .init(q.x, q.y)
      })
      XCTAssertEqual(changed.layers[0].smartObject?.data, original.layers[0].smartObject?.data)
      XCTAssertEqual(changed.layers[0].maskCoordinateTransform, original.layers[0].maskCoordinateTransform)
    }
  }

  func testSelfCrossingPerspectiveRecordFailsAtEditablePSDEntity() throws {
    let open = try PSDCodec.read(PSDCodec.writeRasterLayers(document()))
    let raw = try XCTUnwrap(open.layers.first?.sourceTags?["SoLd"])
    var descriptor = try PSDSmartObjects.descriptor(raw)
    let index = try XCTUnwrap(descriptor.items.firstIndex { $0.key.text == "nonAffineTransform" })
    let crossed = [corners[0], corners[2], corners[1], corners[3]]
    descriptor.items[index].value = .list(crossed.flatMap { [.number($0.x), .number($0.y)] })
    var rewritten = PSDWriter()
    rewritten.text("soLD"); rewritten.n(4, 4); rewritten.data.append(try descriptor.encoded())
    while rewritten.data.count % 4 != 0 { rewritten.n(0, 1) }
    XCTAssertEqual(rewritten.data.count, raw.count)
    var file = try PSDCodec.writeRasterLayers(open)
    file.replaceSubrange(try XCTUnwrap(file.range(of: raw)), with: rewritten.data)
    XCTAssertThrowsError(try PSDCodec.read(file))
  }
}
