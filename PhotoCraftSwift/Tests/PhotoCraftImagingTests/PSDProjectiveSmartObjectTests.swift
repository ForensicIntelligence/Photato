import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDProjectiveSmartObjectTests: XCTestCase {
  // Geometry scaled from the Photoshop-authored sample reported in PhotoCraft #579.
  let corners = [PathPoint(6.3, 33.4), .init(49.075, 14.4), .init(93.4125, 55.1), .init(47.35, 79.7625)]

  private func document(linked: Bool = false) throws -> CraftDocument {
    var document = try CraftDocument(width: 100, height: 90, depth: .u16)
    var pixels = try Surface(width: 16, height: 12, depth: .u16)
    for y in 0..<12 {
      for x in 0..<16 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x) / 15, Float(y) / 11, 0.35, 0.75))
      }
    }
    let bytes = try RasterIO.encoded(pixels)
    var layer: Layer
    if linked {
      let link = try LinkedSmartObjectSource(reference: "/Missing/Artwork.png",
        contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count),
        relativePath: "Links/Artwork.png")
      layer = try LinkedSmartObjectIO.place(bytes, fileName: "Artwork.png", reference: link, in: document, fit: false)
    } else {
      layer = try SmartObjectIO.placed(data: bytes, fileName: "Artwork.png", in: document, fit: false)
    }
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
    let source = try XCTUnwrap(layer.smartObject)
    let w = Double(source.width), h = Double(source.height)
    return try [PathPoint(0, 0), .init(w, 0), .init(w, h), .init(0, h)].map { try map.point($0.x, $0.y) }
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

  func testMissingProjectedLinkKeepsBothDescriptorsAndPreviewAcrossPSDPSBAndNative() throws {
    let original = try document(linked: true)
    let expected = try Renderer.composite(original).rgbaData(depth: .u16)
    for format in [PSDFileFormat.psd, .psb] {
      let bytes = try PSDCodec.writeRasterLayers(original, format: format)
      let cached = try PSDCodec.readPaged(bytes)
      let layer = try XCTUnwrap(cached.layers.first)
      let object = try XCTUnwrap(layer.smartObject)
      XCTAssertTrue(object.data.isEmpty)
      XCTAssertNil(object.linkedSource?.authorizationID)
      XCTAssertEqual(object.linkedSource?.reference, "/Missing/Artwork.png")
      XCTAssertEqual(object.linkedSource?.relativePath, "Links/Artwork.png")
      XCTAssertNil(layer.sourceProjection)
      XCTAssertNotNil(try layer.linkedSmartObjectPreview()?.projectiveSourceToCache)
      assertCorners(try corners(of: layer), corners)
      XCTAssertEqual(try Renderer.composite(cached).rgbaData(depth: .u16), expected)
      let originalDescriptor = try PSDSmartObjects.PlacementQuads(PSDSmartObjects.descriptor(XCTUnwrap(layer.sourceTags?["SoLd"])))
      XCTAssertNotEqual(originalDescriptor.base, originalDescriptor.content)

      let native = try NativeArchive.decodePaged(NativeArchive.encodeChunked(cached))
      XCTAssertEqual(native, cached)
      let savedAgain = try PSDCodec.read(PSDCodec.writeRasterLayers(native, format: format))
      let tagged = try PSDSmartObjects.PlacementQuads(PSDSmartObjects.descriptor(XCTUnwrap(savedAgain.layers.first?.sourceTags?["SoLd"])))
      XCTAssertEqual(tagged.base.map(\.bitPattern), originalDescriptor.base.map(\.bitPattern))
      XCTAssertEqual(tagged.content.map(\.bitPattern), originalDescriptor.content.map(\.bitPattern))
      XCTAssertEqual(try Renderer.composite(savedAgain).rgbaData(depth: .u16), expected)
      XCTAssertEqual(savedAgain.layers.first?.maskCoordinateTransform, layer.maskCoordinateTransform)
    }
  }

  func testProjectedLinkedCacheCanMoveAndRelinkSharedInstancesWithoutLosingMasksOrUndo() throws {
    var original = try document(linked: true)
    var stack = SmartFilterStack()
    stack.filters = [.init(filter: RasterFilter(.gaussianBlur))]
    original.layers[0].smartFilters = stack
    var cached = try PSDCodec.read(PSDCodec.writeRasterLayers(original, format: .psb))
    let id = try XCTUnwrap(cached.layers.first?.id)
    let delta = Transform2D.translation(8, -3)
    try Command.duplicateLayer(id).apply(to: &cached)
    let duplicateID = try XCTUnwrap(cached.activeLayerID)
    XCTAssertNotEqual(duplicateID, id)
    try Command.transformLayers(.init(layerIDs: [duplicateID], matrix: delta)).apply(to: &cached)
    let movedCorners = corners.map { point in
      let moved = delta.point(point.x, point.y)
      return PathPoint(moved.x, moved.y)
    }
    cached = try PSDCodec.read(PSDCodec.writeRasterLayers(cached, format: .psb))
    for layer in cached.layers {
      assertCorners(try corners(of: layer), layer.id == id ? corners : movedCorners)
    }
    let newPixels = try Surface(width: 8, height: 18, depth: .u16, fill: Pixel(0.2, 0.9, 0.1))
    let newBytes = try RasterIO.encoded(newPixels)
    let newLink = try LinkedSmartObjectSource(reference: "/New/Artwork.png",
      contentHash: LinkedSmartObjectSource.fingerprint(newBytes), byteLength: UInt64(newBytes.count))
    var session = EditorSession(document: cached)
    try session.execute(LinkedSmartObjectIO.replacement(newBytes, fileName: "Artwork.png",
      reference: newLink, in: cached, layerID: id, preserveSize: true))
    for layer in session.document.layers {
      XCTAssertNil(try layer.linkedSmartObjectPreview())
      XCTAssertEqual(layer.smartObject?.data, newBytes)
      XCTAssertEqual(layer.smartObject?.linkedSource, newLink)
      let prior = try XCTUnwrap(cached.layers.first { $0.id == layer.id })
      XCTAssertEqual(layer.smartObject?.sourceID, prior.smartObject?.sourceID)
      XCTAssertEqual(layer.maskCoordinateTransform, prior.maskCoordinateTransform)
      XCTAssertEqual(layer.smartFilters, prior.smartFilters)
      assertCorners(try corners(of: layer), layer.id == id ? corners : movedCorners)
    }
    let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: .psb))
    XCTAssertEqual(try Renderer.composite(saved).rgbaData(depth: .u16),
                   try Renderer.composite(session.document).rgbaData(depth: .u16))
    try session.undo()
    XCTAssertEqual(session.document, cached)
  }
}
