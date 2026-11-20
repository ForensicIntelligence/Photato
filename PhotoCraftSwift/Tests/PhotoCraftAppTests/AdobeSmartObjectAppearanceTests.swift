import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraft

final class AdobeSmartObjectAppearanceTests: XCTestCase {
  private let input = URL(string: "https://example.test/template.psd")!
  private let artwork = URL(string: "https://example.test/artwork.png")!
  private let mask = URL(string: "https://example.test/matte.png")!

  private func grayscale(_ samples: [UInt16], width: Int, kind: UTType = .png, wide: Bool = false) throws -> Data {
    let height = samples.count / width
    let bytes = Data(samples.flatMap { value -> [UInt8] in
      wide ? [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)] : [UInt8(value)]
    })
    let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
    let bitmap = CGBitmapInfo(rawValue: wide ? CGBitmapInfo.byteOrder16Big.rawValue : 0)
    let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: wide ? 16 : 8,
      bitsPerPixel: wide ? 16 : 8, bytesPerRow: width * (wide ? 2 : 1), space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: bitmap, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let result = NSMutableData()
    let writer = try XCTUnwrap(CGImageDestinationCreateWithData(result, kind.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(writer))
    return result as Data
  }

  private func source(_ url: URL) -> [String: String] { ["url": url.absoluteString] }

  private func addition(linked: Bool = false) -> [String: Any] {
    [
      "name": "Template Artwork", "type": "smart_object_layer",
      "operation": ["type": "add", "placement": ["type": "top"]],
      "smartObject": ["isLinked": linked, "smartObjectFile": ["source": source(artwork)]],
    ]
  }

  private func edit(_ values: [String: Any]) -> [String: Any] {
    values.merging(["name": "Template Artwork", "type": "smart_object_layer", "operation": ["type": "edit"]]) {
      existing, _ in existing
    }
  }

  private func payload(_ edits: [[String: Any]]) -> [String: Any] {
    [
      "image": ["source": source(input)], "edits": ["layers": edits],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]],
    ]
  }

  private func request(_ edits: [[String: Any]]) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: payload(edits)), createComposite: true)
  }

  private func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var doc = try CraftDocument(width: 12, height: 8, depth: depth)
    doc.layers[0].content = .raster(try Surface(width: 12, height: 8, depth: depth, fill: Pixel(0.8, 0.6, 0.4)))
    return doc
  }

  private func artBytes() throws -> Data {
    try RasterIO.encoded(Surface(width: 5, height: 4, fill: Pixel(0.4, 0.6, 0.8)))
  }

  func testAppearanceOnlyEditAcceptsPublishedBlendModesAndValidatesRanges() throws {
    let doc = try request([addition()]).applying(to: fixture(), resources: [artwork: artBytes()]).session.document
    let expected: [(String, BlendMode)] = [
      ("normal", .normal), ("dissolve", .dissolve), ("darken", .darken), ("multiply", .multiply),
      ("color_burn", .colorBurn), ("linear_burn", .linearBurn), ("darker_color", .darkerColor),
      ("lighten", .lighten), ("screen", .screen), ("color_dodge", .colorDodge), ("linear_dodge", .linearDodge),
      ("lighter_color", .lighterColor), ("overlay", .overlay), ("soft_light", .softLight), ("hard_light", .hardLight),
      ("vivid_light", .vividLight), ("pin_light", .pinLight), ("hard_mix", .hardMix), ("difference", .difference),
      ("exclusion", .exclusion), ("divide", .divide), ("hue", .hue), ("saturation", .saturation),
      ("color", .color), ("luminosity", .luminosity),
    ]
    for (spelling, mode) in expected {
      let layer = try request([edit(["blendOptions": ["blendMode": spelling, "opacity": 43]])])
        .applying(to: doc).session.document.layers.last
      XCTAssertEqual(layer?.blendMode, mode, spelling)
      XCTAssertEqual(layer?.opacity, 0.43, spelling)
      XCTAssertEqual(layer?.smartObject, doc.layers.last?.smartObject)
    }
    for invalid: [String: Any] in [["opacity": -1], ["opacity": 101], ["opacity": true],
      ["opacity": 0.5], ["blendMode": "linear_light"], ["blendMode": "MULTIPLY"],
      ["fillOpacity": 70]] {
      XCTAssertThrowsError(try request([edit(["blendOptions": invalid])]))
    }
  }

  func testGrayPNG16GrayPSDAndGrayJPEGSupplyNumericMaskSamples() throws {
    var add = addition()
    add["pixelMask"] = ["source": source(mask)]
    let doc = try fixture(depth: .u16)
    let artworkBytes = try artBytes()
    func coverage(_ data: Data) throws -> Surface {
      let edited = try request([add]).applying(to: doc, resources: [artwork: artworkBytes, mask: data])
      return try XCTUnwrap(edited.session.document.layers.last?.mask)
    }

    let png = try grayscale([0x1234, 0xabcd, 0x4321, 0xffff], width: 2, wide: true)
    let samples = try coverage(png)
    XCTAssertEqual(samples.depth, .u16)
    XCTAssertEqual(samples.pixel(x: 0, y: 0).r, Float(0x1234) / 65_535)
    XCTAssertEqual(samples.pixel(x: 1, y: 0).r, Float(0xabcd) / 65_535)
    XCTAssertEqual(samples.pixel(x: 0, y: 1).r, Float(0x4321) / 65_535)

    var grayDocument = try CraftDocument(width: 2, height: 2, depth: .u16)
    var nativeGray = try NativeModeRaster(width: 2, height: 2, mode: .grayscale, depth: .u16)
    grayDocument.modeDescriptor = try .init(mode: .grayscale, depth: .u16, profile: nativeGray.profile)
    for index in 0..<4 {
      try nativeGray.set(1, component: 0, index: index)
      try nativeGray.set(1, component: 1, index: index)
    }
    try nativeGray.set(Float(0x7312) / 65_535, component: 0, index: 0)
    grayDocument.layers[0].nativeMode = nativeGray
    grayDocument.layers[0].content = .raster(try nativeGray.surface())
    let psdCoverage = try coverage(PSDCodec.writeRasterLayers(grayDocument))
    XCTAssertEqual(psdCoverage.pixel(x: 0, y: 0).r, Float(0x7312) / 65_535)
    XCTAssertEqual(psdCoverage.pixel(x: 1, y: 1), .white)

    let jpeg = try grayscale([UInt16](repeating: 91, count: 16 * 16), width: 16, kind: .jpeg)
    XCTAssertEqual(try coverage(jpeg).pixel(x: 8, y: 8).r, Float(91) / 255, accuracy: 1 / 255)
    XCTAssertThrowsError(try coverage(artworkBytes))
    XCTAssertThrowsError(try coverage(Data([1, 2, 3])))
  }

  func testMaskPropertyPatchPreservesPlacementAndRemovesOnlyTheMask() throws {
    var add = addition()
    let doc = try fixture()
    let sourceData = try artBytes()
    let maskData = try grayscale([0, 64, 128, 255], width: 2)
    add["transformMode"] = "custom"
    add["transform"] = ["offset": ["horizontal": 2, "vertical": 1], "angle": 30]
    add["pixelMask"] = ["source": source(mask), "offset": ["horizontal": 1, "vertical": 2], "isLinked": false]
    let created = try request([add]).applying(to: doc, resources: [artwork: sourceData, mask: maskData]).session.document
    let before = try XCTUnwrap(created.layers.last)
    XCTAssertEqual(before.maskCoordinateTransform.tx, before.coordinateTransform.tx + 1, accuracy: 1e-10)
    XCTAssertEqual(before.maskCoordinateTransform.ty, before.coordinateTransform.ty + 2, accuracy: 1e-10)
    XCTAssertEqual(before.maskCoordinateTransform.a, 1, accuracy: 1e-10)
    XCTAssertEqual(before.maskCoordinateTransform.b, 0, accuracy: 1e-10)
    XCTAssertEqual(before.mask?.pixel(x: 0, y: 1).r, Float(128) / 255)
    XCTAssertFalse(before.effectiveMaskProperties.linked)

    let toggled = try request([edit(["pixelMask": ["isEnabled": false]])])
      .applying(to: created).session.document
    XCTAssertEqual(toggled.layers.last?.effectiveMaskProperties.transform, before.effectiveMaskProperties.transform)
    let replacement = try grayscale([10, 20, 30, 40], width: 2)
    let reloaded = try request([edit(["pixelMask": ["source": source(mask)]])])
      .applying(to: toggled, resources: [mask: replacement]).session.document
    XCTAssertEqual(reloaded.layers.last?.effectiveMaskProperties, toggled.layers.last?.effectiveMaskProperties)
    XCTAssertEqual(reloaded.layers.last?.mask?.pixel(x: 0, y: 1).r, Float(30) / 255)

    let patch = edit(["pixelMask": ["isEnabled": false, "offset": ["horizontal": -1]]])
    let patched = try request([patch]).applying(to: created).session.document
    let updated = try XCTUnwrap(patched.layers.last)
    XCTAssertEqual(updated.mask, before.mask)
    XCTAssertEqual(updated.maskCoordinateTransform.tx, updated.coordinateTransform.tx - 1, accuracy: 1e-10)
    XCTAssertEqual(updated.maskCoordinateTransform.ty, before.maskCoordinateTransform.ty, accuracy: 1e-10)
    XCTAssertFalse(updated.effectiveMaskProperties.enabled)
    XCTAssertFalse(updated.effectiveMaskProperties.linked)

    let remove = edit(["blendOptions": ["opacity": 18], "pixelMask": [
      "delete": true, "source": ["url": "ignored"], "isEnabled": "ignored", "offset": "ignored",
    ]])
    let removal = try request([remove])
    XCTAssertEqual(removal.layerEdits?.flatMap(\.resources), [])
    let removed = try XCTUnwrap(removal.applying(to: patched).session.document.layers.last)
    XCTAssertNil(removed.mask)
    XCTAssertNil(removed.maskProperties)
    XCTAssertEqual(removed.smartObject, updated.smartObject)
    XCTAssertEqual(removed.coordinateTransform, updated.coordinateTransform)
    XCTAssertEqual(removed.opacity, 0.18)
  }

  func testInvalidMaskRequestsAndLaterJobFailureLeaveTheInputUnchanged() throws {
    let doc = try fixture()
    for maskSettings: [String: Any] in [["delete": false], ["isLinked": 1], ["offset": ["horizontal": true]],
      ["offset": ["vertical": Double(Int32.max) + 1]], ["source": ["url": "file:///tmp/mask.png"]],
      ["source": ["content": "not a URL"]]] {
      var add = addition()
      add["pixelMask"] = maskSettings
      XCTAssertThrowsError(try request([add]))
    }
    let original = try PSDCodec.writeRasterLayers(doc)
    let badEdit = edit(["pixelMask": ["isEnabled": false]])
    XCTAssertThrowsError(try request([addition(), badEdit]).applying(to: doc, resources: [artwork: artBytes()]))
    XCTAssertEqual(try PSDCodec.writeRasterLayers(doc), original)
  }

  @MainActor func testHTTPPlacementFetchesBothAssetsAndMatchesNativeMaskComposite() async throws {
    let transport = AppearanceTransport()
    let fixtureBytes = try PSDCodec.writeRasterLayers(fixture())
    let artworkBytes = try artBytes()
    let matteBytes = try grayscale([255, 128, 0, 255, 64, 0], width: 3)
    await transport.set(fixtureBytes, at: input)
    await transport.set(artworkBytes, at: artwork)
    await transport.set(matteBytes, at: mask)

    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      let caps = try await AutomationTests().request(service, path: "/v1/capabilities")
      let contents = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      let jobs = try XCTUnwrap(contents["actionJobs"] as? [String: Any])
      let appearance = try XCTUnwrap(jobs["smartObjectTemplateAppearance"] as? [String: Any])
      XCTAssertEqual(appearance["route"] as? String, "POST /v2/create-composite")
      let blends = try XCTUnwrap(appearance["blendOptions"] as? [String: Any])
      XCTAssertEqual((blends["blendModes"] as? [String])?.count, 25)
      let maskCapability = try XCTUnwrap(appearance["pixelMask"] as? [String: Any])
      XCTAssertEqual(maskCapability["deleteOnEditOnly"] as? Bool, true)

      var add = self.addition(linked: true)
      add["transformMode"] = "custom"
      add["transform"] = ["offset": ["horizontal": 2, "vertical": 1]]
      add["blendOptions"] = ["blendMode": "multiply", "opacity": 60]
      add["pixelMask"] = ["source": self.source(self.mask), "offset": ["horizontal": 1], "isLinked": false]
      let response = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite", payload: self.payload([add]))
      let actual = try PSDCodec.read(response.2)
      let layer = try XCTUnwrap(actual.layers.last)
      XCTAssertEqual(layer.smartObject?.linkedSource?.reference, self.artwork.absoluteString)
      XCTAssertEqual(layer.blendMode, .multiply)
      XCTAssertEqual(layer.opacity, 0.6)
      XCTAssertEqual(layer.maskCoordinateTransform, .translation(3, 1))
      XCTAssertTrue(layer.effectiveMaskProperties.enabled)
      XCTAssertFalse(layer.effectiveMaskProperties.linked)
      XCTAssertEqual(layer.mask?.pixel(x: 1, y: 0).r, Float(128) / 255)
      let fetched = await transport.requests()
      XCTAssertEqual(Set(fetched), [self.input, self.artwork, self.mask])
      XCTAssertEqual(fetched.count, 3)

      let base = try PSDCodec.read(fixtureBytes)
      var expected = EditorSession(document: base)
      var object = try SmartObjectIO.placed(data: artworkBytes, fileName: "artwork.png", in: base, fit: false)
      object.x = 2
      object.y = 1
      let id = object.id
      try expected.execute(.addLayer(object))
      try expected.execute(.blend(id, .multiply))
      try expected.execute(.opacity(id, 0.6))
      var nativeMask = try Surface(width: 3, height: 2, fill: .black)
      for (index, byte) in [255, 128, 0, 255, 64, 0].enumerated() {
        let value = Float(byte) / 255
        nativeMask.setPixel(x: index % 3, y: index / 3, Pixel(value, value, value))
      }
      try expected.execute(.mask(id, nativeMask))
      var placement = MaskProperties()
      placement.transform = .translation(1, 0)
      placement.linked = false
      try expected.execute(.maskProperties(id, placement))
      XCTAssertEqual(try Renderer.composite(actual).rgbaData(depth: .u8),
        try Renderer.composite(expected.document).rgbaData(depth: .u8))
      XCTAssertEqual(shared.store.document, untouched)
    }
  }
}

private actor AppearanceTransport: AdobeResourceTransport {
  private var files: [URL: Data] = [:]
  private var fetched: [URL] = []
  func set(_ bytes: Data, at url: URL) { files[url] = bytes }
  func requests() -> [URL] { fetched }
  func fetch(_ url: URL) async throws -> Data {
    fetched.append(url)
    guard let data = files[url] else { throw AdobeAPIError.invalid("Missing owned fixture.") }
    return data
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    throw AdobeAPIError.unsupported("The fixture uses hosted output.")
  }
}
