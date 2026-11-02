import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDGlobalLightTests: XCTestCase {
  func source(_ depth: PixelDepth = .u8, advanced: Bool = false) throws -> CraftDocument {
    var d = try LayerStyleTests().fixture(depth)
    var shared = LayerEffect(.dropShadow); shared.size = 0; shared.distance = 5; shared.angle = 12.5; shared.useGlobalLight = true
    var local = LayerEffect(.innerShadow); local.size = 0; local.distance = 3; local.angle = 73.125; local.useGlobalLight = false
    if advanced { shared.advanced = LayerEffectAdvanced(); local.advanced = LayerEffectAdvanced() }
    d.layers[0].style = LayerStyle(effects: [shared, local]); d.globalLight = GlobalLight(angle: 270, altitude: 45); return d
  }
  func resource(_ id: Int, _ value: Int) -> Data { var w = PSDWriter(); w.n(value, 4); return PSDImageResources.block(id, data: w.data) }
  func testIndependentPublicFilePromotesItsDocumentLightAndRetainsGlobalParticipation() throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    let publicDocument = try PSDCodec.read(Data(contentsOf: fixtures.appendingPathComponent("layer-comps/ag-psd-layer-comps.psd")))
    XCTAssertEqual(publicDocument.globalLight, GlobalLight(angle: 120, altitude: 30))
    let rawStyle = try Data(contentsOf: fixtures.appendingPathComponent("GlobalLight/ag-psd-shadow.lfx2"))
    let style = try PSDLayerStyles.read(rawStyle, globalAngle: 132, globalAltitude: 30)
    XCTAssertEqual(style.effects[0].useGlobalLight, true); XCTAssertEqual(style.effects[0].angle, 120)
    var d = try LayerStyleTests().fixture(); d.layers[0].style = style; d.globalLight = GlobalLight(angle: 132, altitude: 30)
    var changed = d; try Command.globalLight(GlobalLight(angle: 30, altitude: 30)).apply(to: &changed)
    XCTAssertNotEqual(try Renderer.composite(changed).rgbaData(depth: .u8), try Renderer.composite(d).rgbaData(depth: .u8))
    for format in [PSDFileFormat.psd, .psb] {
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(changed, format: format)); XCTAssertEqual(read.globalLight, changed.globalLight)
      XCTAssertEqual(read.layers[0].style?.effects[0].useGlobalLight, true); XCTAssertEqual(read.layers[0].style?.effects[0].angle, 120)
    }
  }

  func testAllDepthPSDPSBResourcesFlagsLocalAnglesAndCompositeWordsRoundTrip() throws {
    for depth in PixelDepth.allCases {
      let d = try source(depth), before = d
      for format in [PSDFileFormat.psd, .psb] {
        let bytes = try PSDCodec.writeRasterLayers(d, format: format), read = try PSDCodec.read(bytes)
        XCTAssertEqual(read.globalLight, d.globalLight)
        XCTAssertEqual(read.layers[0].style?.effects.map(\.useGlobalLight), [true, false]); XCTAssertEqual(read.layers[0].style?.effects.map(\.angle), [12.5, 73.125])
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth: .f32), try Renderer.composite(d).rgbaData(depth: .f32))
        if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let dir = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try bytes.write(to: dir.appendingPathComponent("global-light-\(depth.rawValue).\(format == .psd ? "psd" : "psb")"))
        }
      }
      XCTAssertEqual(d, before)
    }
  }
  func testGlobalDirectionsAreExactlyPeriodicInBothNativeRenderers() throws {
    for advanced in [false, true] {
      for pair in [(-90.0, 270.0), (-360.0, 0.0), (360.0, 0.0)] {
        var a = try source(.f32, advanced: advanced); a.globalLight?.angle = pair.0
        var b = a; b.globalLight?.angle = pair.1
        XCTAssertEqual(try Renderer.composite(a).rgbaData(depth: .f32), try Renderer.composite(b).rgbaData(depth: .f32))
      }
    }
  }
  func testLocalBevelAngleAndAltitudeIgnoreDocumentLightInBothRenderers() throws {
    for advanced in [false, true] {
      var d = try LayerStyleTests().fixture(.f32), effect = LayerEffect(.bevelEmboss)
      effect.useGlobalLight = false; effect.angle = 73; if advanced { effect.advanced = LayerEffectAdvanced(); effect.advanced?.altitude = 25 }
      var style = LayerStyle(effects: [effect]); style.lightAltitude = 25; d.layers[0].style = style
      d.globalLight = GlobalLight(angle: 40, altitude: 10); let local = try Renderer.composite(d).rgbaData(depth: .f32)
      d.globalLight = GlobalLight(angle: 140, altitude: 80); XCTAssertEqual(try Renderer.composite(d).rgbaData(depth: .f32), local)
      d.layers[0].style?.effects[0].useGlobalLight = true
      let shared = try Renderer.composite(d).rgbaData(depth: .f32); d.globalLight?.altitude = 10
      XCTAssertNotEqual(try Renderer.composite(d).rgbaData(depth: .f32), shared)
    }
  }
  func testResourceDefaultsDuplicatesLengthsRangesAndStaleReplacement() throws {
    XCTAssertNil(try PSDGlobalLight.read([]))
    XCTAssertEqual(try PSDGlobalLight.read(PSDImageResources.blocks(resource(1037, 90))), GlobalLight(angle: 90, altitude: 30))
    XCTAssertEqual(try PSDGlobalLight.read(PSDImageResources.blocks(resource(1049, 45))), GlobalLight(angle: 120, altitude: 45))
    for bytes in [resource(1037, 20) + resource(1037, 30), resource(1049, 91), PSDImageResources.block(1037, data: Data([1]))] {
      XCTAssertThrowsError(try PSDGlobalLight.read(PSDImageResources.blocks(bytes)))
    }
    var d = try source(); let unknown = PSDImageResources.block(4000, data: Data([2, 4, 6]))
    d.sourceMetadata = ["psdResources": resource(1037, 10) + resource(1049, 20) + unknown]
    let read = try PSDCodec.read(PSDCodec.writeRasterLayers(d)), blocks = try PSDImageResources.blocks(read.sourceMetadata!["psdResources"]!)
    XCTAssertEqual(read.globalLight, d.globalLight); XCTAssertEqual(blocks.filter { $0.id == 1037 }.count, 1); XCTAssertEqual(blocks.filter { $0.id == 1049 }.count, 1)
    XCTAssertEqual(blocks.first { $0.id == 4000 }?.raw, unknown)
    // An unchanged named light resource must retain every original byte and its order.
    var named = PSDWriter(); named.text("8BIM"); named.n(1037, 2); named.n(3, 1); named.text("Sun"); named.n(4, 4); named.n(270, 4)
    let original = unknown + named.data + resource(1049, 45)
    XCTAssertEqual(try PSDGlobalLight.applying(original, document: d), original)
    d.globalLight?.angle = 90
    let edited = try PSDImageResources.blocks(PSDGlobalLight.applying(original, document: d))
    XCTAssertEqual(edited.map(\.id), [4000, 1037, 1049]); XCTAssertEqual(edited[1].raw.dropLast(4), named.data.dropLast(4)); XCTAssertEqual(edited[1].data, Data([0, 0, 0, 90]))
  }
  func testLegacyFallbackInferenceAndPrecisionGuardsKeepExistingFilesAtomic() throws {
    var d = try source(); d.globalLight = nil; d.layers[0].style?.lightAngle = 90
    let read = try PSDCodec.read(PSDCodec.writeRasterLayers(d)); XCTAssertEqual(read.globalLight, GlobalLight(angle: 90, altitude: 30)); XCTAssertEqual(read.layers[0].style?.effects[0].useGlobalLight, true)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Existing.psd"), original = Data("Existing artwork".utf8); try original.write(to: url)
    var divergent = d; var second = d.layers[0]; second.id = UUID(); second.style?.lightAngle = 45; divergent.layers.append(second)
    var angle = d; angle.globalLight = GlobalLight(angle: 73.375, altitude: 30)
    var altitude = d; altitude.globalLight = GlobalLight(angle: 90, altitude: 31.25)
    for value in [divergent, angle, altitude] { let before = value; XCTAssertThrowsError(try PSDCodec.writeRasterLayers(value, to: url)); XCTAssertEqual(try Data(contentsOf: url), original); XCTAssertEqual(value, before) }
    divergent.globalLight = GlobalLight(angle: 60, altitude: 30); XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(divergent)).globalLight, divergent.globalLight)
  }
  func testIndexedAndMultichannelWritersRetainDocumentLightAndModePlanes() throws {
    var indexed = try CraftDocument(width: 4, height: 3), settings = IndexedColorSettings(); settings.palette = .exact
    try RestrictedModeInput.indexed(settings, in: indexed).apply(to: &indexed)
    var multi = try PSDMultichannelTests().fixture(.u8)
    indexed.globalLight = GlobalLight(angle: 30, altitude: 60); multi.globalLight = indexed.globalLight
    for d in [indexed, multi] { for format in [PSDFileFormat.psd, .psb] {
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(d, format: format)); XCTAssertEqual(read.globalLight, d.globalLight); XCTAssertEqual(read.colorMode, d.colorMode)
      XCTAssertEqual(read.restrictedMode, d.restrictedMode)
      if d.inkMode != nil { try PSDMultichannelTests().assertSamples(read, d) }
    } }
  }
  func testLegacyNativeAdoptionIsConservativeAndLeavesSourceUntouched() throws {
    var d = try source(); d.globalLight = nil; d.layers[0].style?.lightAngle = 90
    d.sourceMetadata = ["psdResources": resource(1037, 90) + resource(1049, 30)]; let before = d
    let adopted = try GlobalLightInput.adoptingLegacyLight(d); XCTAssertEqual(adopted.globalLight, GlobalLight(angle: 90, altitude: 30)); XCTAssertEqual(adopted.layers, d.layers); XCTAssertEqual(adopted.minimumArchiveVersion, 75)
    XCTAssertEqual(d, before)
    d.layers[0].style?.lightAngle = 120; XCTAssertEqual(try GlobalLightInput.adoptingLegacyLight(d), d)
    d.sourceMetadata?["psdResources"] = Data([1, 2, 3]); XCTAssertEqual(try GlobalLightInput.adoptingLegacyLight(d), d)
  }
}
