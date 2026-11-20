import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDEditableWarpTests: XCTestCase {
  private func document(_ warp: WarpDefinition, linked: Bool = false,
                        projected: Bool = false, masked: Bool = false) throws -> CraftDocument {
    var document = try CraftDocument(width: 90, height: 82, depth: .u16)
    var pixels = try Surface(width: 20, height: 16, depth: .u16)
    for y in 0..<16 {
      for x in 0..<20 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x) / 19, Float(y) / 15, 0.4, 0.8))
      }
    }
    let bytes = try RasterIO.encoded(pixels)
    var layer: Layer
    if linked {
      let reference = try LinkedSmartObjectSource(reference: "/Missing/Artwork.png",
        contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
      layer = try LinkedSmartObjectIO.place(bytes, fileName: "Artwork.png", reference: reference,
                                           in: document, fit: false)
    } else {
      layer = try SmartObjectIO.placed(data: bytes, fileName: "Artwork.png", in: document, fit: false)
    }
    layer.x = 8; layer.y = 6; layer.affine = .scale(2, 2)
    if projected {
      layer.sourceProjection = try SelectionTransform.projection(
        bounds: .init(x: 0, y: 0, width: 20, height: 16),
        corners: [.init(1, 4), .init(26, 0), .init(33, 25), .init(-2, 24)])
    }
    layer.warp = warp
    if masked {
      layer.mask = try Surface(width: 55, height: 44, depth: .u16, fill: .white)
      var properties = MaskProperties()
      properties.linked = !projected
      properties.transform = try layer.coordinateTransform.inverted() * .translation(11, 14)
      layer.maskProperties = properties
    }
    document.layers = [layer]; document.activeLayerID = layer.id
    return document
  }

  private func splitWarp() throws -> WarpDefinition {
    var identity = WarpDefinition()
    identity.sourceBounds = .init(x: 2, y: 2, width: 16, height: 12)
    var value = try identity.custom(width: 20, height: 16)
    try value.mesh?.split(at: 0.25, vertical: true)
    try value.mesh?.split(at: 0.75, vertical: false)
    value.mesh?.points[0] = .init(-3, -2)
    return value
  }

  private func descriptor(_ layer: Layer) throws -> PSDDescriptor {
    try PSDSmartObjects.descriptor(XCTUnwrap(layer.sourceTags?["SoLd"]))
  }

  private func cylinderWarp() throws -> WarpDefinition {
    var warp = WarpDefinition()
    warp.style = .cylinder
    warp.cylinder = try .init(photoshopValues: [2, 14, 18, 3, -0.3, 0.45, 0.375])
    return warp
  }

  func testCylinderDescriptorAndNativeArchiveVersion() throws {
    let warp = try cylinderWarp()
    let settings = try XCTUnwrap(warp.cylinder)
    let items = try PSDWarp.encoded(warp, width: 20, height: 16)
    let placed = PSDDescriptor("null", items: items)
    XCTAssertEqual(try PSDWarp.decode(placed, width: 20, height: 16), warp)
    guard case .object(var alternate) = placed["warp"] else { return XCTFail("Cylinder descriptor is absent.") }
    alternate.items.removeAll { ["uOrder", "vOrder", "warpValues"].contains($0.key.text) }
    let alternatePlaced = PSDDescriptor("null", items: [
      .init("warp", .object(.init("warp", items: alternate.items + [
        .init("warpValues", .units(Data("#Pxl".utf8), settings.photoshopValues.map(\.bitPattern))),
      ]))),
    ])
    XCTAssertEqual(try PSDWarp.decode(alternatePlaced, width: 20, height: 16), warp)
    XCTAssertThrowsError(try PSDWarp.decode(.init("null", items: [.init("warp", .object(alternate))]),
                                           width: 20, height: 16))
    let source = try document(warp)
    XCTAssertEqual(source.minimumArchiveVersion, CylinderWarp.archiveVersion)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(source)), source)
  }

  func testCylinderPSDEmbeddedAndLinkedReopenAndReplaceWithoutFlattening() throws {
    let warp = try cylinderWarp()
    for format in [PSDFileFormat.psd, .psb] {
      for linked in [false, true] {
        let source = try document(warp, linked: linked, projected: format == .psb, masked: true)
        let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: format))
        let layer = try XCTUnwrap(opened.layers.first)
        let preview = try Renderer.composite(source).rgbaData(depth: .u16)
        XCTAssertEqual(try Renderer.composite(opened).rgbaData(depth: .u16), preview)
        let frame = try XCTUnwrap(warp.cylinder).surface.controlBounds
        let savedCorners = try XCTUnwrap(PSDCodec.warpedSmartObjectPlacementCorners(layer))
        let actual = try XCTUnwrap(PSDCodec.warpedSmartObjectPlacementCorners(source.layers[0]))
        XCTAssertEqual(savedCorners, actual)
        if format == .psd {
          XCTAssertEqual(savedCorners[0], .init(8 + 2 * frame.x, 6 + 2 * frame.y))
          XCTAssertEqual(savedCorners[2], .init(8 + 2 * (frame.x + frame.width), 6 + 2 * (frame.y + frame.height)))
        }
        XCTAssertEqual(try layer.linkedSmartObjectPreview()?.warp ?? layer.warp, warp)
        XCTAssertEqual(opened.minimumArchiveVersion, CylinderWarp.archiveVersion)
        let native = try NativeArchive.decodePaged(NativeArchive.encodeChunked(opened))
        XCTAssertEqual(native, opened)
        let intact = try PSDCodec.read(PSDCodec.writeRasterLayers(native, format: format))
        for key in ["warp", "Trnf", "nonAffineTransform"] {
          XCTAssertEqual(try descriptor(intact.layers[0])[key], try descriptor(layer)[key])
        }

        let replacement = try Surface(width: 40, height: 24, depth: .u16, fill: Pixel(0.9, 0.3, 0.1))
        let bytes = try RasterIO.encoded(replacement)
        let reference = try LinkedSmartObjectSource(reference: "/Recovered/New Artwork.png",
          contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
        var current = EditorSession(document: native)
        if linked {
          try current.execute(LinkedSmartObjectIO.replacement(bytes, fileName: "New Artwork.png",
            reference: reference, in: native, layerID: layer.id, preserveSize: true))
        } else {
          let newSource = try SmartObjectIO.decode(bytes, fileName: "New Artwork.png")
          try current.execute(SmartObjectIO.replacement(in: native, layerID: layer.id, source: newSource,
            data: bytes, fileName: "New Artwork.png", preserveSize: true))
        }
        let changed = try XCTUnwrap(current.document.layers.first)
        XCTAssertNil(try changed.linkedSmartObjectPreview())
        XCTAssertEqual(changed.smartObject?.data, bytes)
        let cylinder = try XCTUnwrap(changed.warp?.cylinder)
        XCTAssertEqual(cylinder.left, 4)
        XCTAssertEqual(cylinder.bottom, 21)
        XCTAssertEqual(cylinder.topDepth, -0.225, accuracy: 1e-12)
        XCTAssertEqual(cylinder.wrap, 0.375)
        let rerendered = try Renderer.composite(current.document).rgbaData(depth: .u16)
        XCTAssertNotEqual(rerendered, preview)
        let output = try PSDCodec.read(PSDCodec.writeRasterLayers(current.document, format: format))
        XCTAssertEqual(try output.layers[0].linkedSmartObjectPreview()?.warp ?? output.layers[0].warp, changed.warp)
        XCTAssertEqual(try Renderer.composite(output).rgbaData(depth: .u16), rerendered)
        try current.undo()
        XCTAssertEqual(current.document, native)
      }
    }
  }

  func testClassicWarpPresetsRoundTripWithEditableSourcesAndPreservedPreview() throws {
    for style in WarpStyle.analyticPresets {
      var warp = WarpDefinition()
      warp.style = style; warp.bend = -23; warp.vertical = true
      warp.horizontalDistortion = 7; warp.verticalDistortion = -9
      let source = try document(warp)
      let expected = try Renderer.composite(source).rgbaData(depth: .u16)
      for format in [PSDFileFormat.psd, .psb] {
        let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: format))
        let layer = try XCTUnwrap(opened.layers.first)
        XCTAssertEqual(layer.warp, warp)
        XCTAssertEqual(layer.smartObject?.data, source.layers[0].smartObject?.data)
        XCTAssertNotNil(layer.pristineSmartAppearance)
        XCTAssertEqual(try Renderer.composite(opened).rgbaData(depth: .u16), expected)
      }
    }
  }

  func testSplitWarpKeepsQuiltKnotsRawDescriptorsAndEditablePerspectiveInBothContainers() throws {
    let warp = try splitWarp()
    var original = try document(warp, projected: true, masked: true)
    let generatorSettings = try PSDDescriptor("null", items: [
      .init("generatorSettings", .object(.init("null", items: [
        .init("exportAs", .object(.init("null"))),
      ]))),
    ]).encoded()
    original.sourceMetadata = ["psdGlobal_extn": generatorSettings]
    let preview = try Renderer.composite(original).rgbaData(depth: .u16)
    for format in [PSDFileFormat.psd, .psb] {
      let bytes = try PSDCodec.writeRasterLayers(original, format: format)
      let reopened = try PSDCodec.readPaged(bytes)
      let layer = try XCTUnwrap(reopened.layers.first)
      XCTAssertEqual(layer.warp, warp)
      XCTAssertNotNil(layer.sourceProjection)
      XCTAssertEqual(layer.maskCoordinateTransform, original.layers[0].maskCoordinateTransform)
      XCTAssertEqual(layer.smartObject?.data, original.layers[0].smartObject?.data)
      XCTAssertEqual(reopened.sourceMetadata?["psdGlobal_extn"], generatorSettings)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u16), preview)

      let keys = ["Trnf", "nonAffineTransform", "warp", "quiltWarp"]
      let captured = try descriptor(layer)
      XCTAssertNotNil(captured["quiltWarp"])
      let native = try NativeArchive.decodePaged(NativeArchive.encodeChunked(reopened))
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(native, format: format))
      XCTAssertEqual(saved.sourceMetadata?["psdGlobal_extn"], generatorSettings)
      for key in keys {
        XCTAssertEqual(try descriptor(saved.layers[0])[key], captured[key], key)
      }

      var editedWarp = warp
      editedWarp.mesh?.points[0].x -= 3
      var session = EditorSession(document: reopened)
      let edit = try WarpEdit.prepare(reopened, layerID: layer.id, warp: editedWarp)
      try session.execute(.warp(edit))
      XCTAssertNil(session.document.layers[0].pristineSmartAppearance)
      let edited = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      XCTAssertEqual(edited.layers[0].warp, editedWarp)
      XCTAssertNotEqual(try descriptor(edited.layers[0])["nonAffineTransform"], captured["nonAffineTransform"])
      let changed = try Renderer.composite(edited).rgbaData(depth: .u16)
      XCTAssertNotEqual(changed, preview)
      XCTAssertEqual(changed, try Renderer.composite(session.document).rgbaData(depth: .u16))
      try session.undo()
      XCTAssertEqual(session.document, reopened)
    }
  }

  func testLinkedWarpPreviewRelinksAndKeepsPlacedMaskWithoutWarpingMaskTwice() throws {
    let warp = try splitWarp()
    let source = try document(warp, linked: true, masked: true)
    let cached = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: .psb))
    let layer = try XCTUnwrap(cached.layers.first)
    let pixels = try Renderer.composite(cached).rgbaData(depth: .u16)
    XCTAssertEqual(try Renderer.composite(source).rgbaData(depth: .u16), pixels)
    XCTAssertNil(layer.warp)
    XCTAssertEqual(try layer.linkedSmartObjectPreview()?.warp, warp)
    XCTAssertTrue(try XCTUnwrap(layer.smartObject).data.isEmpty)
    XCTAssertTrue(layer.effectiveMaskProperties.linked)
    XCTAssertEqual(layer.effectiveMaskProperties.storedAfterWarp, true)
    XCTAssertThrowsError(try WarpEdit.target(cached, layerID: layer.id))
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(cached))
    XCTAssertEqual(try descriptor(reopened.layers[0])["quiltWarp"], try descriptor(layer)["quiltWarp"])
    XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u16), pixels)

    let newPixels = try Surface(width: 20, height: 16, depth: .u16, fill: Pixel(0.9, 0.3, 0.4))
    let bytes = try RasterIO.encoded(newPixels)
    let reference = try LinkedSmartObjectSource(reference: "/Recovered/Artwork.png",
      contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
    var session = EditorSession(document: cached)
    try session.execute(LinkedSmartObjectIO.replacement(bytes, fileName: "Artwork.png",
      reference: reference, in: cached, layerID: layer.id, preserveSize: true))
    let resolved = try XCTUnwrap(session.document.layers.first)
    XCTAssertNil(try resolved.linkedSmartObjectPreview())
    XCTAssertEqual(resolved.warp, warp)
    XCTAssertEqual(resolved.mask, layer.mask)
    XCTAssertEqual(resolved.maskCoordinateTransform, layer.maskCoordinateTransform)
    XCTAssertEqual(resolved.smartObject?.data, bytes)
    let derived = try SmartFilterEngine.renderedLayer(resolved, in: session.document)
    XCTAssertEqual(derived.mask, layer.mask)
    XCTAssertEqual(derived.maskCoordinateTransform, layer.maskCoordinateTransform)
    XCTAssertNoThrow(try WarpEdit.target(session.document, layerID: layer.id))
    try session.undo()
    XCTAssertEqual(session.document, cached)

    // Older native saves could attach a pending Warp to an unresolved affine link.
    var deferredSource = try document(WarpDefinition(), linked: true)
    deferredSource.layers[0].warp = nil
    var deferred = try PSDCodec.read(PSDCodec.writeRasterLayers(deferredSource))
    deferred.layers[0].warp = warp
    let olderNative = try NativeArchive.decodePaged(NativeArchive.encodeChunked(deferred))
    XCTAssertEqual(olderNative, deferred)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(olderNative))
    var recovered = olderNative
    let olderLayer = try XCTUnwrap(olderNative.layers.first)
    try LinkedSmartObjectIO.replacement(bytes, fileName: "Artwork.png", reference: reference,
      in: olderNative, layerID: olderLayer.id, preserveSize: true).apply(to: &recovered)
    XCTAssertEqual(recovered.layers[0].warp, warp)
    XCTAssertNil(try recovered.layers[0].linkedSmartObjectPreview())
    XCTAssertNoThrow(try PSDCodec.writeRasterLayers(recovered))
  }

  func testMalformedSplitWarpRecordFailsBeforeSourceCanBeEdited() throws {
    let source = try document(splitWarp())
    let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(source))
    var placed = try descriptor(opened.layers[0])
    let index = try XCTUnwrap(placed.items.firstIndex { $0.key.text == "quiltWarp" })
    guard case .object(var quilt) = placed.items[index].value else { return XCTFail("Missing split mesh") }
    let rows = try XCTUnwrap(quilt.items.firstIndex { $0.key.text == "deformNumRows" })
    quilt.items[rows].value = .integer(4)
    placed.items[index].value = .object(quilt)
    XCTAssertThrowsError(try PSDWarp.decode(placed, width: 20, height: 16))
  }
}
