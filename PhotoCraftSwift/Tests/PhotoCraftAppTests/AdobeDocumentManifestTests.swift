import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AdobeDocumentManifestTests: XCTestCase {
  private let input = URL(string: "https://example.test/Template.psd?signature=fixture")!
  private let export = URL(string: "https://example.test/manifest.json")!

  private func source() throws -> CraftDocument {
    var doc = try CraftDocument(width: 36, height: 28, depth: .u16)
    var group = Layer(name: "Product group", content: .group(.init()))
    group.x = 1
    let artwork = try RasterIO.encoded(Surface(width: 6, height: 5, fill: Pixel(0.4, 0.6, 0.8)))
    var smart = try SmartObjectIO.placed(data: artwork, fileName: "Artwork.png", in: doc, fit: false)
    smart.name = "Artwork"
    smart.x = 7
    smart.y = 9
    smart.parentID = group.id
    smart.sourceTags = ["lyid": Data([0, 0, 0, 149])]
    smart.opacity = 0.6
    smart.blendMode = .multiply
    smart.clipped = true
    smart.mask = try Surface(width: 4, height: 4, depth: .u16, fill: .white)
    var properties = MaskProperties()
    properties.enabled = false
    properties.linked = false
    properties.transform = .translation(2, -1)
    properties.density = 0.7
    properties.feather = 3
    smart.maskProperties = properties
    var sibling = Layer(name: "Artwork", content: .raster(try Surface(width: 4, height: 4, depth: .u16, fill: .white)))
    sibling.parentID = group.id
    doc.layers += [sibling, smart, group]
    doc.activeLayerID = smart.id
    doc.resolution = 144
    doc.globalLight = GlobalLight(angle: 42, altitude: 47)
    var info = FileInformation()
    info.description = "Owned XMP sample"
    return try FileInfoMetadata.applying(info, fields: ["description"], to: doc)
  }

  private func body(_ destinations: [[String: Any]], xmp: Bool = false, source: URL? = nil) -> [String: Any] {
    [
      "image": ["source": ["url": (source ?? input).absoluteString]], "includeXmp": xmp,
      "outputs": destinations.map { ["destination": $0, "mediaType": "application/json"] },
    ]
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func layer(_ data: [String: Any], id: Int) throws -> [String: Any] {
    func find(_ layers: [[String: Any]]) -> [String: Any]? {
      for layer in layers {
        if layer["id"] as? Int == id { return layer }
        for key in ["children", "layers"] {
          if let children = layer[key] as? [[String: Any]], let match = find(children) { return match }
        }
      }
      return nil
    }
    return try XCTUnwrap(find(try XCTUnwrap(data["layers"] as? [[String: Any]])))
  }

  func testMetadataUsesOriginalIDsAndDocumentCoordinatesWithoutMutatingInput() throws {
    let original = try source()
    let typed = try AdobeLayerIdentifiers.assigning(in: original)
    XCTAssertNil(AdobeLayerIdentifiers.stored(original.layers[1]))
    let data = try object(AdobeDocumentManifest.encode(typed, title: "Template.psd", includeXmp: true))
    let info = try XCTUnwrap(data["document"] as? [String: Any])
    XCTAssertEqual(info["title"] as? String, "Template.psd")
    XCTAssertEqual(info["depth"] as? Int, 16)
    XCTAssertEqual(info["imageMode"] as? String, "rgb")
    XCTAssertEqual(info["resolution"] as? Double, 144)
    XCTAssertEqual(info["globalLightingAngle"] as? Int, 42)
    XCTAssertEqual(info["bounds"] as? [String: Int], ["left": 0, "top": 0, "right": 36, "bottom": 28])
    XCTAssertTrue((info["xmp"] as? String)?.contains("Owned XMP sample") == true)
    let omitted = try object(AdobeDocumentManifest.encode(typed, title: "Template.psd", includeXmp: false))
    XCTAssertNil((omitted["document"] as? [String: Any])?["xmp"])
    let smart = try layer(data, id: 149)
    XCTAssertEqual(smart["type"] as? String, "smart_object_layer")
    let blends = try XCTUnwrap(smart["blendOptions"] as? [String: Any])
    XCTAssertEqual(blends["opacity"] as? Int, 60)
    XCTAssertEqual(blends["blendMode"] as? String, "multiply")
    XCTAssertEqual(blends["clipped"] as? Bool, true)
    let mask = try XCTUnwrap(smart["pixelMask"] as? [String: Any])
    XCTAssertEqual(mask["enabled"] as? Bool, false)
    XCTAssertEqual(mask["linked"] as? Bool, false)
    XCTAssertEqual(mask["offset"] as? [String: Double], ["horizontal": 2, "vertical": -1])
    XCTAssertEqual(mask["bounds"] as? [String: Int], ["left": 9, "top": 8, "right": 13, "bottom": 12])
    XCTAssertEqual((smart["userMask"] as? [String: Double])?["density"], 70)
    XCTAssertEqual((smart["userMask"] as? [String: Double])?["feather"], 3)
    let object = try XCTUnwrap(smart["smartObject"] as? [String: Any])
    let artwork = try XCTUnwrap(object["smartObjectData"] as? [String: Any])
    let file = try XCTUnwrap(artwork["fileInfo"] as? [String: Any])
    XCTAssertEqual(object["isLinked"] as? Bool, false)
    XCTAssertEqual(file["name"] as? String, "Artwork.png")
    XCTAssertEqual(file["path"] as? String, "Artwork.png")
    XCTAssertEqual(file["fileType"] as? String, "png")
    XCTAssertEqual(file["linked"] as? Bool, false)
    XCTAssertEqual(artwork["transform"] as? [Double], [7, 9, 13, 9, 13, 14, 7, 14])
    XCTAssertEqual((try layer(data, id: 2))["name"] as? String, "Artwork")
  }

  func testIdentifiersReserveStoredAndRejectDuplicateRecords() throws {
    var original = try source()
    original.layers[1].sourceTags = ["lyid": Data([0, 0, 0, 1])]
    let withIDs = try AdobeLayerIdentifiers.assigning(in: original)
    XCTAssertEqual(withIDs.layers.compactMap(AdobeLayerIdentifiers.stored), [5, 1, 149, 4])
    let data = try PSDCodec.writeRasterLayers(withIDs)
    let reopened = try PSDCodec.read(data)
    XCTAssertEqual(reopened.layers.compactMap(AdobeLayerIdentifiers.stored), [5, 1, 149, 4])
    original.layers[0].sourceTags = ["lyid": Data([0, 0, 0, 1])]
    XCTAssertThrowsError(try AdobeLayerIdentifiers.assigning(in: original))
    var background = try source()
    background.layers[0].background = true
    background.layers[0].sourceTags = ["lyid": Data([0, 0, 0, 56])]
    let backgroundPSD = try PSDCodec.writeRasterLayers(AdobeLayerIdentifiers.assigning(in: background))
    XCTAssertEqual(try PSDCodec.read(backgroundPSD).layers.first.flatMap(AdobeLayerIdentifiers.stored), 56)
  }

  func testManifestRequestRejectsUnsupportedOptionsAndMixedDestinations() throws {
    for invalid in [
      body([["embedded": "unknown"]]), body([["embedded": "json", "validityPeriod": 60]]),
      body([["url": "http://example.test/out.json"]]), body([["validityPeriod": 2]]), body([]),
      body([["embedded": "json"]]).merging(["includeLayerThumbnails": true]) { _, new in new },
      body([["embedded": "json"]]).merging(["extractSmartObjectData": true]) { _, new in new },
      body([["embedded": "json"]]).merging(["includeXmp": "true"]) { _, new in new },
    ] {
      XCTAssertThrowsError(try AdobeManifestRequest(data: JSONSerialization.data(withJSONObject: invalid)))
    }
  }

  @MainActor func testHTTPManifestIDsWorkInAnEditAndTheNextPSD() async throws {
    let doc = try source()
    let bytes = try PSDCodec.writeRasterLayers(doc)
    let transport = ManifestTestTransport()
    await transport.set(bytes, at: input)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let retained = shared.store.document
      let denied = try await helper.request(service, path: AdobeManifestRequest.route, body: self.body([["embedded": "json"]]))
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setResourceJobsEnabled(true)
      let first = try await self.results(service, body: self.body([["embedded": "json"]], xmp: true))
      let manifest = try XCTUnwrap((first.first?["destination"] as? [String: Any])?["content"] as? [String: Any])
      let target = try self.layer(manifest, id: 149)
      XCTAssertEqual(target["type"] as? String, "smart_object_layer")
      let unchangedOrder: [String: Any] = [
        "image": ["source": ["url": self.input.absoluteString]],
        "edits": ["layers": [["operation": ["type": "edit"], "type": "smart_object_layer", "id": 149,
                             "blendOptions": ["opacity": 25]]]],
        "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]],
      ]
      let noReorder = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite", payload: unchangedOrder)
      let sameStack = try PSDCodec.read(noReorder.2)
      XCTAssertNil(AdobeLayerIdentifiers.stored(sameStack.layers[1]))
      XCTAssertEqual(AdobeLayerIdentifiers.stored(sameStack.layers[2]), 149)

      let edits: [String: Any] = [
        "image": ["source": ["url": self.input.absoluteString]], "edits": ["layers": [
          ["operation": ["type": "edit"], "type": "smart_object_layer", "id": 149,
           "blendOptions": ["opacity": 25], "pixelMask": ["isEnabled": true]],
          ["operation": ["type": "move", "placement": ["type": "top"]], "id": 2],
        ]],
        "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]],
      ]
      let result = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite", payload: edits)
      let rebound = try PSDCodec.read(result.2)
      XCTAssertEqual(rebound.layers.last.flatMap(AdobeLayerIdentifiers.stored), 2)
      await transport.set(result.2, at: self.input)
      let changed = try await self.results(service, body: self.body([["embedded": "json"]]))
      let details = try XCTUnwrap((changed.first?["destination"] as? [String: Any])?["content"] as? [String: Any])
      let updated = try self.layer(details, id: 149)
      XCTAssertEqual((updated["blendOptions"] as? [String: Any])?["opacity"] as? Int, 25)
      XCTAssertEqual((updated["pixelMask"] as? [String: Any])?["enabled"] as? Bool, true)
      XCTAssertEqual((try self.layer(details, id: 2))["type"] as? String, "pixel_layer")
      XCTAssertEqual(shared.store.document, retained)
    }
  }

  @MainActor func testAllManifestOutputDestinationsShareTheSameJSON() async throws {
    let doc = try source()
    let psb = URL(string: "https://example.test/Template.psb")!
    let transport = ManifestTestTransport()
    await transport.set(try PSDCodec.writeRasterLayers(doc, format: .psb), at: psb)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, _ in
      service.setResourceJobsEnabled(true)
      let reply = try await self.results(service, body: self.body([["embedded": "string"], ["embedded": "base64"],
        ["validityPeriod": 60], ["url": self.export.absoluteString]], source: psb))
      XCTAssertEqual(reply.count, 4)
      let destinations = try reply.map { try XCTUnwrap($0["destination"] as? [String: Any]) }
      let json = Data(try XCTUnwrap(destinations[0]["content"] as? String).utf8)
      XCTAssertEqual((try self.object(json)["document"] as? [String: Any])?["title"] as? String, "Template.psb")
      XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(destinations[1]["content"] as? String)), json)
      let hosted = try XCTUnwrap(URL(string: try XCTUnwrap(destinations[2]["url"] as? String)))
      let unauthorized = try await helper.request(service, path: hosted.path, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let authorized = try await helper.request(service, path: hosted.path)
      XCTAssertEqual(authorized.0.statusCode, 200)
      XCTAssertEqual(authorized.1, json)
      XCTAssertEqual(destinations[3]["url"] as? String, self.export.absoluteString)
      let uploaded = await transport.uploaded(self.export)
      XCTAssertEqual(uploaded, json)
    }
  }

  @MainActor private func results(_ service: AutomationService, body: [String: Any]) async throws -> [[String: Any]] {
    let helper = AutomationTests()
    let started = try await helper.request(service, path: AdobeManifestRequest.route, body: body)
    XCTAssertEqual(started.0.statusCode, 202)
    let accepted = try object(started.1)
    let path = try XCTUnwrap(URL(string: try XCTUnwrap(accepted["statusUrl"] as? String))).path
    for _ in 0..<200 {
      let poll = try await helper.request(service, path: path)
      let snapshot = try object(poll.1)
      if snapshot["status"] as? String == "succeeded" {
        let result = try XCTUnwrap(snapshot["result"] as? [String: Any])
        return try XCTUnwrap(result["outputs"] as? [[String: Any]])
      }
      if snapshot["status"] as? String == "failed" {
        XCTFail("Manifest job failed: \(snapshot)")
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw AdobeAPIError.invalid("Manifest did not complete.")
  }
}

private actor ManifestTestTransport: AdobeResourceTransport {
  var resources: [URL: Data] = [:]
  var uploads: [URL: Data] = [:]
  func set(_ data: Data, at url: URL) { resources[url] = data }
  func uploaded(_ url: URL) -> Data? { uploads[url] }
  func fetch(_ url: URL) async throws -> Data {
    guard let data = resources[url] else { throw AdobeAPIError.invalid("Missing owned fixture.") }
    return data
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    guard case .external(let url, _) = output.destination else { throw AdobeAPIError.invalid("Expected an external mock destination.") }
    uploads[url] = data
  }
}
