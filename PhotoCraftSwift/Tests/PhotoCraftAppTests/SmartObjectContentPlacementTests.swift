import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SmartObjectContentPlacementTests: XCTestCase {
  private let inputURL = URL(string: "https://example.test/template.psd")!
  private let ingredientURL = URL(string: "https://example.test/ingredient.png")!

  private func baseline() throws -> (document: CraftDocument, layer: Layer) {
    var document = try CraftDocument(width: 16, height: 12)
    document.layers[0].content = .raster(try Surface(width: 16, height: 12))
    let frame = try RasterIO.encoded(Surface(width: 6, height: 4, fill: Pixel(0.5, 0.5, 0.5)))
    var layer = try SmartObjectIO.placed(data: frame, fileName: "Frame.png", in: document, fit: false)
    layer.name = "Artwork Frame"
    layer.x = 2
    layer.y = 3
    layer.opacity = 0.8
    layer.smartObject?.resolution = 144
    document.layers.append(layer)
    document.activeLayerID = layer.id
    return (document, layer)
  }

  private func ingredient() throws -> Data {
    var pixels = try Surface(width: 6, height: 2, fill: Pixel(1, 0, 0))
    for y in 0..<2 {
      for x in 2..<6 { pixels.setPixel(x: x, y: y, x < 4 ? Pixel(0, 1, 0) : Pixel(0, 0, 1)) }
    }
    return try RasterIO.encoded(pixels)
  }

  private func field(_ placement: [String: Any], extras: [String: Any] = [:]) -> [String: Any] {
    var fields: [String: Any] = [
      "smartObjectFile": ["source": ["url": ingredientURL.absoluteString]], "contentPlacement": placement,
    ]
    fields.merge(extras) { _, value in value }
    return fields
  }

  private func edit(_ fields: [String: Any]) -> [String: Any] {
    ["name": "Artwork Frame", "type": "smart_object_layer", "operation": ["type": "edit"], "smartObject": fields]
  }

  private func payload(_ entry: [String: Any]) -> [String: Any] {
    [
      "image": ["source": ["url": inputURL.absoluteString]], "edits": ["layers": [entry]],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]],
    ]
  }

  private func contents(of layer: Layer) throws -> (frame: CraftDocument, nested: Layer, original: SmartObject) {
    let object = try XCTUnwrap(layer.smartObject)
    let frame = try SmartObjectIO.sourceDocument(object)
    XCTAssertEqual(frame.layers.count, 1)
    let nested = try XCTUnwrap(frame.layers.first)
    return (frame, nested, try XCTUnwrap(nested.smartObject))
  }

  func testFitFillAlignAndClipInsideTheFrameWhileRetainingFullIngredient() throws {
    let (document, original) = try baseline()
    let data = try ingredient()
    let alignments: [(FrameFit, CanvasAnchor, Transform2D)] = [
      (.fit, .topLeft, .identity), (.fit, .center, .translation(0, 1)), (.fit, .bottomRight, .translation(0, 2)),
      (.fill, .topLeft, .scale(2, 2)), (.fill, .center, .init(a: 2, d: 2, tx: -3)),
      (.fill, .bottomRight, .init(a: 2, d: 2, tx: -6)),
    ]
    for (mode, anchor, expected) in alignments {
      let command = try SmartObjectContentPlacement(mode: mode, anchor: anchor)
        .replacement(in: document, layerID: original.id, data: data, fileName: "ingredient.png")
      var session = EditorSession(document: document)
      try session.execute(command)
      let outer = try XCTUnwrap(session.document.layers.last)
      let (frame, nested, object) = try contents(of: outer)
      XCTAssertEqual(outer.id, original.id)
      XCTAssertEqual(outer.coordinateTransform, original.coordinateTransform)
      XCTAssertEqual(outer.opacity, original.opacity)
      XCTAssertEqual(frame.width, 6)
      XCTAssertEqual(frame.height, 4)
      XCTAssertEqual(frame.pixelsPerInch, 144)
      XCTAssertEqual(nested.coordinateTransform, expected)
      XCTAssertEqual(object.data, data)
      XCTAssertEqual(object.width, 6)
      XCTAssertEqual(object.height, 2)
      let preview = try Renderer.composite(session.document)
      XCTAssertEqual(preview.pixel(x: 1, y: 4).a, 0, "Outside left edge")
      XCTAssertEqual(preview.pixel(x: 8, y: 4).a, 0, "Outside right edge")
      if mode == .fit && anchor == .bottomRight {
        XCTAssertEqual(preview.pixel(x: 3, y: 3).a, 0)
        XCTAssertEqual(preview.pixel(x: 3, y: 5).a, original.opacity)
      } else if mode == .fill {
        XCTAssertEqual(preview.pixel(x: 4, y: 4).a, original.opacity)
      }
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo()
      XCTAssertEqual(session.document, document)
    }

    let portrait = try RasterIO.encoded(Surface(width: 2, height: 6, fill: .white))
    let verticalAlignments: [(CanvasAnchor, Double)] = [(.top, 0), (.center, -7), (.bottom, -14)]
    for (anchor, y) in verticalAlignments {
      var session = EditorSession(document: document)
      try session.execute(SmartObjectContentPlacement(mode: .fill, anchor: anchor)
        .replacement(in: document, layerID: original.id, data: portrait, fileName: "portrait.png"))
      let nested = try contents(of: XCTUnwrap(session.document.layers.last)).nested
      XCTAssertEqual(nested.coordinateTransform, .init(a: 3, d: 3, ty: y))
    }
  }

  func testNativeAndPhotoshopRoundTripsKeepRotatedFrameAndOriginalPSB() throws {
    let (original, layer) = try baseline()
    var document = original
    document.layers[1].affine = .rotation(30) * .scale(1.25, 0.8)
    var source = try CraftDocument(width: 6, height: 2, depth: .u16)
    source.resolution = 96
    source.layers[0].content = .raster(try Surface(width: 6, height: 2, depth: .u16, fill: Pixel(0.2, 0.5, 0.75)))
    let asset = try PSDCodec.writeRasterLayers(source, format: .psb)
    var session = EditorSession(document: document)
    try session.execute(SmartObjectContentPlacement(mode: .fill, anchor: .right)
      .replacement(in: document, layerID: layer.id, data: asset, fileName: "ingredient.psb"))
    let outer = try XCTUnwrap(session.document.layers.last)
    XCTAssertEqual(outer.coordinateTransform, document.layers[1].coordinateTransform)
    XCTAssertEqual(try contents(of: outer).original.data, asset)
    let native = try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document))
    XCTAssertEqual(native, session.document)
    for format in [PSDFileFormat.psd, .psb] {
      let bytes = try PSDCodec.writeRasterLayers(session.document, format: format)
      let reopened = try PSDCodec.read(bytes)
      let restored = try XCTUnwrap(reopened.layers.last)
      let t = restored.coordinateTransform
      for (actual, expected) in zip([t.a, t.b, t.c, t.d, t.tx, t.ty],
                                    [outer.coordinateTransform.a, outer.coordinateTransform.b, outer.coordinateTransform.c,
                                     outer.coordinateTransform.d, outer.coordinateTransform.tx, outer.coordinateTransform.ty]) {
        XCTAssertEqual(actual, expected, accuracy: 1e-10)
      }
      let (frame, nested, retained) = try contents(of: restored)
      XCTAssertEqual(frame.height, 4)
      XCTAssertEqual(frame.width, 6)
      XCTAssertEqual(frame.pixelsPerInch, 144)
      XCTAssertEqual(nested.coordinateTransform, .init(a: 2, d: 2, tx: -6))
      XCTAssertEqual(retained.data, asset)
      XCTAssertEqual(retained.resolution, 96)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8),
                     try Renderer.composite(session.document).rgbaData(depth: .u8))
    }
  }

  func testJPEGAndTIFFSourcesRetainOriginalFileBytesThroughPSDExport() throws {
    let (document, target) = try baseline()
    let source = try CraftDocument(width: 3, height: 5)
    let encoded = [
      ("nested.jpg", try RasterIO.encoded(source, type: .jpeg), "image/jpeg"),
      ("nested.tiff", try RasterIO.encoded(source, type: .tiff), "image/tiff"),
      ("nested.psd", try PSDCodec.writeRasterLayers(source), "image/vnd.adobe.photoshop"),
    ]
    for (name, data, mediaType) in encoded {
      var session = EditorSession(document: document)
      try session.execute(SmartObjectContentPlacement(mode: .fit, anchor: .center)
        .replacement(in: document, layerID: target.id, data: data, fileName: name))
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
      let object = try contents(of: XCTUnwrap(reopened.layers.last)).original
      XCTAssertEqual(object.mediaType, mediaType)
      XCTAssertEqual(object.fileName, name)
      XCTAssertEqual(object.data, data)
      XCTAssertEqual(object.width, 3)
      XCTAssertEqual(object.height, 5)
    }
  }

  func testRejectsConflictingOptionsAndUnsupportedFramesBeforeMutation() throws {
    let (document, layer) = try baseline()
    let good = field(["mode": "fit"])
    let valid = try AdobeSmartObjectEdit(edit(good), path: "layer")
    XCTAssertNotNil(valid.url)
    for invalid in [field(["mode": "original"]), field(["mode": "fit", "verticalAlign": "left"]),
                    field(["mode": "fill", "extra": true]), field(["mode": "fit"], extras: ["isLinked": true]),
                    field(["mode": "fit"], extras: ["autoResize": false]), ["contentPlacement": ["mode": "fit"]]] {
      XCTAssertThrowsError(try AdobeSmartObjectEdit(edit(invalid), path: "layer"))
    }
    for key in ["transformMode", "transform"] {
      var request = edit(good)
      request[key] = key == "transformMode" ? "none" as Any : [String: Any]() as Any
      XCTAssertThrowsError(try AdobeSmartObjectEdit(request, path: "layer"))
    }
    var add = edit(good)
    add["operation"] = ["type": "add", "placement": ["type": "top"]]
    XCTAssertThrowsError(try AdobeSmartObjectEdit(add, path: "layer"))
    let fixture = try ingredient()
    let placement = SmartObjectContentPlacement(mode: .fill, anchor: .center)

    var skewed = document
    skewed.layers[1].affine = .init(c: 0.25)
    var perspective = document
    perspective.layers[1].sourceProjection = .init(.identity)
    var maskedRotation = document
    maskedRotation.layers[1].affine = .rotation(30)
    maskedRotation.layers[1].mask = try Surface(width: 6, height: 4, fill: .white)
    var locked = document
    locked.layers[1].locked = true
    var linked = document
    let object = try XCTUnwrap(layer.smartObject)
    linked.layers[1].smartObject = try object.linked(to: .remote(ingredientURL, data: object.data))
    for invalid in [skewed, perspective, maskedRotation, locked, linked] {
      var session = EditorSession(document: invalid)
      XCTAssertThrowsError(try session.execute(placement.replacement(in: invalid, layerID: layer.id, data: fixture, fileName: "ingredient.png")))
      XCTAssertEqual(session.document, invalid)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
  }

  @MainActor func testAdobeHTTPTemplateJobReturnsEditableNestedPSD() async throws {
    let (document, _) = try baseline()
    let png = try ingredient()
    let input = try PSDCodec.writeRasterLayers(document)
    let resources = FramePlacementTransport(files: [inputURL: input, ingredientURL: png])
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: resources) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      let reply = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite",
        payload: self.payload(self.edit(self.field(["mode": "fill", "horizontalAlign": "right"]))))
      let result = try PSDCodec.read(reply.2)
      let target = try XCTUnwrap(result.layers.last)
      XCTAssertEqual(target.coordinateTransform, .translation(2, 3))
      XCTAssertEqual(target.opacity, 0.8)
      let (frame, nested, retained) = try self.contents(of: target)
      XCTAssertEqual(frame.width, 6)
      XCTAssertEqual(frame.height, 4)
      XCTAssertEqual(nested.coordinateTransform, .init(a: 2, d: 2, tx: -6))
      XCTAssertEqual(retained.data, png)
      let pixels = try Renderer.composite(result)
      XCTAssertEqual(pixels.pixel(x: 1, y: 5).a, 0)
      XCTAssertEqual(pixels.pixel(x: 8, y: 5).a, 0)
      XCTAssertEqual(pixels.pixel(x: 6, y: 5).b, 1)
      XCTAssertEqual(shared.store.document, untouched)
    }
  }

  @MainActor func testPhotatoHTTPRespectsRevisionReplacesSharedInstancesAndKeepsMasks() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let response = try await helper.request(service, path: "/v1/capabilities")
      let root = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let smartObjects = try XCTUnwrap(root["smartObjects"] as? [String: Any])
      let photato = try XCTUnwrap(smartObjects["contentPlacement"] as? [String: Any])
      XCTAssertEqual(photato["photatoCommand"] as? String, "smartObject.replace")
      let jobs = try XCTUnwrap(root["actionJobs"] as? [String: Any])
      let adobe = try XCTUnwrap(jobs["smartObjectContentPlacement"] as? [String: Any])
      XCTAssertEqual(adobe["adobeRoute"] as? String, "POST /v2/create-composite")
      let source = CraftNSDocument(model: try CraftDocument(width: 4, height: 2))
      service.controller.addDocument(source)
      defer { source.store.renderTask?.cancel(); service.controller.removeDocument(source) }
      try service.share(shared)
      try service.share(source)
      let sourceID = try XCTUnwrap(service.shares.first { $0.document === source }?.id)
      var params: [String: Any] = ["sourceDocumentID": sourceID.uuidString, "sourceRevision": service.revision(source.store)]
      let placed = try await helper.edit(service, shared, "smartObject.place", params)
      XCTAssertEqual(placed, 200)
      let frame = try XCTUnwrap(shared.store.activeLayer)
      shared.store.perform(.mask(frame.id, try Surface(width: 4, height: 2, fill: .white)))
      var mask = MaskProperties()
      mask.transform = .translation(0.25, 0.5)
      mask.density = 0.6
      shared.store.perform(.maskProperties(frame.id, mask))
      var clone = Layer(name: "Peer", content: frame.content)
      clone.smartObject = frame.smartObject
      shared.store.perform(.addLayer(clone))
      let before = shared.store.document
      source.store.perform(.fill(source.store.document.layers[0].id, .white))
      params["layerID"] = frame.id.uuidString
      params["contentPlacement"] = ["mode": "fit", "verticalAlign": "bottom"]

      let stale = try await helper.edit(service, shared, "smartObject.replace", params)
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(shared.store.document, before)
      params["sourceRevision"] = service.revision(source.store)
      let incompatible = try await helper.edit(service, shared, "smartObject.replace",
        params.merging(["preserveSize": false]) { current, _ in current })
      XCTAssertEqual(incompatible, 400)
      let updated = try await helper.edit(service, shared, "smartObject.replace", params)
      XCTAssertEqual(updated, 200)
      let target = try XCTUnwrap(shared.store.document.layers.first { $0.id == frame.id })
      let sibling = try XCTUnwrap(shared.store.document.layers.first { $0.id == clone.id })
      XCTAssertEqual(target.coordinateTransform, frame.coordinateTransform)
      XCTAssertEqual(target.maskProperties, mask)
      XCTAssertEqual(sibling.smartObject?.sourceID, target.smartObject?.sourceID)
      XCTAssertEqual(try self.contents(of: target).frame.width, 4)
      XCTAssertEqual(try self.contents(of: sibling).original.width, 4)
      let undone = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undone, 200)
      XCTAssertEqual(shared.store.document, before)
    }
  }
}

private struct FramePlacementTransport: AdobeResourceTransport {
  let files: [URL: Data]

  func fetch(_ url: URL) async throws -> Data {
    guard let data = files[url] else { throw AdobeAPIError.invalid("Missing owned content placement fixture.") }
    return data
  }

  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    throw AdobeAPIError.unsupported("The fixture uses hosted output.")
  }
}
