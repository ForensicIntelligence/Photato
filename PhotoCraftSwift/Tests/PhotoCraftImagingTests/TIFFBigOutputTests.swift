import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFBigOutputTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  func testBigTIFFFileAndDataKeepEditableLayersSelectionsAndPyramids() throws {
    let original = try RasterIO.read(fixtures.appendingPathComponent("tiff-layers/photoshop-transparent-be-fixture.tiff"))
    let expected = try XCTUnwrap(original.alphaChannels?.first)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    for order in RasterEncodingOptions.TIFFByteOrder.allCases {
      let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: order, tiffPixelOrder: .perChannel,
        tiffLayers: true, tiffTransparency: true, tiffImagePyramid: true, tiffBigTIFF: true, tiffLayerCompression: .rle)
      let data = try RasterIO.encoded(original, type: .tiff, options: options)
      try RasterIO.write(original, to: url, type: .tiff, options: options)
      XCTAssertEqual(try Data(contentsOf: url), data)
      let file = try TIFFContainer(data, metadata: true)
      XCTAssertTrue(file.isBigTIFF)
      XCTAssertEqual(file.order, order == .bigEndian ? .big : .little)
      XCTAssertEqual(file.root.fields[273]?.type, 16)
      XCTAssertEqual(file.root.fields[279]?.type, 16)
      let pyramid = try XCTUnwrap(file.root.fields[330])
      XCTAssertEqual(pyramid.type, 18)
      var next = pyramid.children.first
      for _ in 0..<3 {
        let level = try XCTUnwrap(next)
        XCTAssertEqual(level.fields[273]?.type, 16)
        XCTAssertEqual(level.fields[279]?.type, 16)
        next = level.next
      }
      XCTAssertNil(next)
      let reopened = try RasterIO.read(url)
      XCTAssertEqual(reopened.layers.map(\.name), original.layers.map(\.name))
      XCTAssertEqual(reopened.layers.map(\.mask), original.layers.map(\.mask))
      XCTAssertEqual(reopened.alphaChannels?.first?.pixels, expected.pixels)
      XCTAssertEqual(reopened.resolution, original.resolution)
      XCTAssertEqual(reopened.profileIsUntagged, original.profileIsUntagged)
      XCTAssertNil(file.root.fields[34675])
    }
    let tagged = try RasterIO.encoded(original, type: .tiff, options: .init(tiffBigTIFF: true, tiffEmbedProfile: true))
    let taggedFile = try TIFFContainer(tagged, metadata: true)
    let embedded = try XCTUnwrap(taggedFile.root.fields[34675]?.data)
    XCTAssertEqual(embedded, try original.workingICC ?? NativeModeProfile.standard(.rgb, depth: original.depth))
    XCTAssertEqual(try RasterIO.read(tagged).sourceICC, embedded)
  }

  func testBigTIFFWorksForFlatSurfaceAndRestrictedStorage() throws {
    let shape = try Surface(width: 19, height: 13, depth: .u8, fill: Pixel(0.25, 0.5, 0.75, 1))
    let size = RasterEncodingOptions(tiffCompression: .lzw, tiffByteOrder: .littleEndian, tiffBigTIFF: true)
    let raw = try RasterIO.encoded(shape, type: .tiff, options: size)
    let tiff = try TIFFContainer(raw, metadata: false)
    XCTAssertTrue(tiff.isBigTIFF)
    XCTAssertEqual(try tiff.scalar(259), 5)
    let opened = try RasterIO.read(raw)
    guard case .raster(let pixels) = opened.layers[0].content else { return XCTFail("Expected RGB pixels") }
    XCTAssertEqual(try pixels.rgbaData(depth: .u8), try shape.rgbaData(depth: .u8))

    for name in ["bitmap-le.tif", "indexed-be.tif"] {
      let original = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/" + name))
      let bytes = try RasterIO.encoded(original, type: .tiff, options: size)
      XCTAssertTrue(TIFFContainer.isBigTIFF(bytes))
      let reopened = try RasterIO.read(bytes)
      XCTAssertEqual(reopened.restrictedMode, original.restrictedMode)
      XCTAssertEqual(reopened.resolution, original.resolution)
    }

    let classic = try RasterIO.encoded(shape, type: .tiff, options: .init(tiffBigTIFF: false))
    XCTAssertTrue(TIFFContainer.isClassic(classic))
    XCTAssertThrowsError(try RasterIO.encoded(shape, type: .png, options: size))
  }

  func testBigTIFFWritesAFirstIFDAndStripAboveFourGiB() throws {
    let document = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/gray8-stripped-le.tif"))
    let data = try RasterIO.encoded(document, type: .tiff,
      options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none, tiffTransparency: false))
    let container = try TIFFContainer(data, metadata: true)
    let length = try XCTUnwrap(container.numbers(279).first)
    let strip = try container.bytes(at: XCTUnwrap(container.numbers(273).first), count: length)
    let layout = TIFFContainer.Layout(bigTIFF: true)
    let order = container.order
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: destination) }
    try layout.header(order: order).write(to: destination)
    let file = try FileHandle(forWritingTo: destination)
    let highStrip = 4_295_032_832
    var extent = highStrip
    func append(_ bytes: Data) throws {
      try file.seek(toOffset: UInt64(extent))
      try file.write(contentsOf: bytes)
      extent += bytes.count
    }
    func patch(_ bytes: Data, _ offset: Int) throws {
      try file.seek(toOffset: UInt64(offset))
      try file.write(contentsOf: bytes)
    }
    do {
      try append(strip)
      container.set(273, [highStrip], type: layout.offsetFieldType)
      container.set(279, [length], type: layout.offsetFieldType)
      let pointer = try container.writeDirectories(order: order, maximumOutput: layout.maximumFileBytes, layout: layout,
        extent: { extent }, emit: append, patch: patch)
      XCTAssertGreaterThan(order.number(pointer, 0, 8), Int(UInt32.max))
      try patch(pointer, layout.headerPointerOffset)
      try file.close()
    } catch {
      try? file.close()
      throw error
    }
    let reopened = try RasterIO.read(destination)
    XCTAssertEqual(reopened.colorMode, .grayscale)
    XCTAssertEqual(reopened.resolution, 225)
    let exported = try XCTUnwrap(reopened.layers.first?.nativeMode)
    let control = try XCTUnwrap(document.layers.first?.nativeMode)
    let range = 0..<(document.width * document.height)
    XCTAssertEqual(range.map { exported.rawWord(component: 0, index: $0) },
      range.map { control.rawWord(component: 0, index: $0) })
  }

  func testTIFFKeepsAllAdobeAlphaAndSpotSamplesAtEachRGBDepth() throws {
    struct Fixture: Decodable {
      let fixtureSHA256: String
      let names: [String]
      let identifiers: [UInt32]
      let sampleSHA256: [String]
    }
    struct Provenance: Decodable { let fixtures: [String: Fixture] }
    func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    let folder = fixtures.appendingPathComponent("tiff-aux")
    let provenance = try JSONDecoder().decode(Provenance.self,
      from: Data(contentsOf: folder.appendingPathComponent("provenance.json")))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
    defer { try? FileManager.default.removeItem(at: url) }
    for bits in [8, 16, 32] {
      let filename = "photoshop-rgb\(bits)-alpha-spot.tiff"
      let reference = folder.appendingPathComponent(filename)
      let oracle = try XCTUnwrap(provenance.fixtures[filename])
      XCTAssertEqual(hex(try Data(contentsOf: reference)), oracle.fixtureSHA256)
      let original = try RasterIO.read(reference)
      func check(_ restored: CraftDocument) throws {
        XCTAssertEqual(restored.colorMode, .rgb)
        XCTAssertEqual(restored.resolution, 144)
        XCTAssertEqual(restored.layers.map(\.name), ["Base", "Coating"])
        XCTAssertEqual(restored.layers.map(\.x), [0, 8])
        XCTAssertEqual(restored.layers.map(\.y), [0, 10])
        let channels = try XCTUnwrap(restored.alphaChannels)
        XCTAssertEqual(channels.map(\.name), oracle.names)
        XCTAssertEqual(channels.compactMap(\.psdIdentifier), oracle.identifiers)
        XCTAssertEqual(channels.first?.spot?.solidity, 0.63)
        XCTAssertNil(channels.last?.spot)
        for (channel, expected) in zip(channels, oracle.sampleSHA256) {
          let raw = try (0..<restored.height).flatMap { try PSDAuxiliaryChannels.row(channel, y: $0, depth: bits) }
          XCTAssertEqual(hex(Data(raw)), expected)
        }
      }
      try check(original)
      for big in [false, true] {
        let options = RasterEncodingOptions(tiffCompression: .zip,
          tiffByteOrder: big ? .littleEndian : .bigEndian,
          tiffPixelOrder: big ? .perChannel : .interleaved,
          tiffPredictor: bits == 32, tiffLayers: true, tiffTransparency: big, tiffBigTIFF: big,
          tiffLayerCompression: .zip)
        let data = try RasterIO.encoded(original, type: .tiff, options: options)
        try RasterIO.write(original, to: url, type: .tiff, options: options)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let tiff = try TIFFContainer(data, metadata: false)
        XCTAssertEqual(tiff.isBigTIFF, big)
        XCTAssertEqual(try tiff.scalar(277), big ? 6 : 5)
        XCTAssertEqual(Array(try tiff.numbers(338).suffix(2)), [0, 0])
        let layerFile = try TIFFContainer(data, metadata: false, additionalTags: [37724])
        var layers = try layerFile.reader(for: XCTUnwrap(layerFile.root.fields[37724]))
        _ = try layers.bytes(TIFFLayers.signature.count)
        let tag = try layers.bytes(8)
        if big {
          XCTAssertEqual(String(decoding: tag.suffix(4).reversed(), as: UTF8.self), "MTrn")
          XCTAssertEqual(layerFile.order.number(try layers.bytes(4), 0, 4), 0)
          _ = try layers.bytes(8)
        }
        _ = try layers.bytes(4)
        XCTAssertEqual(layerFile.order.number(try layers.bytes(2), 0, 2), 2)
        try check(RasterIO.read(url))
      }
    }
  }

  func testComponentModeTIFFRetainsSavedChannelsAndNativeColor() throws {
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let profile = try NativeModeProfile.standard(mode, depth: .u16)
      var document = try CraftDocument(width: 39, height: 21, depth: .u16)
      document.modeDescriptor = try .init(mode: mode, depth: .u16, profile: profile)
      let baseBuilder = try NativeModeRaster.RowBuilder(width: 39, height: 21, mode: mode, depth: .u16, profile: profile)
      let color: [UInt32] = mode == .lab ? [39321, 32896, 32896] : Array(repeating: 13107, count: mode.componentCount)
      for (component, word) in (color + [65535]).enumerated() { try baseBuilder.fill(component: component, word: word) }
      let base = try baseBuilder.finish()
      var layer = Layer(name: "Native color", content: .raster(try base.surface()))
      layer.nativeMode = base
      document.layers = [layer]
      document.activeLayerID = layer.id
      var mask = try Surface(width: 39, height: 21, depth: .u16, fill: .white)
      mask.setPixel(x: 4, y: 6, Pixel(0.21, 0.21, 0.21))
      document.alphaChannels = [AlphaChannel(name: "Saved mask", pixels: mask),
        AlphaChannel(name: "Plate", pixels: mask, spot: .init(color: .black, solidity: 0.25))]
      let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .littleEndian,
        tiffPixelOrder: .perChannel, tiffLayers: true, tiffTransparency: false, tiffBigTIFF: true,
        tiffLayerCompression: .zip)
      let data = try RasterIO.encoded(document, type: .tiff, options: options)
      let restored = try RasterIO.read(data)
      XCTAssertEqual(restored.colorMode, mode)
      XCTAssertEqual(restored.layers.first?.name, layer.name)
      XCTAssertEqual(restored.layers.first?.nativeMode?.profile, profile)
      XCTAssertEqual(restored.alphaChannels?.map(\.name), ["Saved mask", "Plate"])
      XCTAssertEqual(restored.alphaChannels?.last?.spot?.solidity, 0.25)
      XCTAssertEqual(try restored.alphaChannels?.first?.pixels.rgbaData(depth: .u16), try mask.rgbaData(depth: .u16))
      XCTAssertEqual(try restored.alphaChannels?.last?.pixels.rgbaData(depth: .u16), try mask.rgbaData(depth: .u16))
      if mode != .lab {
        let kept = try XCTUnwrap(restored.layers.first?.nativeMode)
        for component in 0...mode.componentCount {
          XCTAssertEqual(kept.rawWord(component: component, index: 124), base.rawWord(component: component, index: 124))
        }
      }
    }
  }


  func testFlatTIFFPreservesAdobeAlphaAndSpotPlanesIndependentlyOfLayers() throws {
    struct Fixture: Decodable {
      let fixtureSHA256: String
      let names: [String]
      let identifiers: [UInt32]
      let sampleSHA256: [String]
      let depth: Int
    }
    struct Provenance: Decodable { let fixtures: [String: Fixture] }
    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    let folder = fixtures.appendingPathComponent("tiff-flat-aux")
    let provenance = try JSONDecoder().decode(Provenance.self,
      from: Data(contentsOf: folder.appendingPathComponent("provenance.json")))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
    defer { try? FileManager.default.removeItem(at: url) }
    for (name, evidence) in provenance.fixtures.sorted(by: { $0.key < $1.key }) {
      let reference = folder.appendingPathComponent(name)
      XCTAssertEqual(digest(try Data(contentsOf: reference)), evidence.fixtureSHA256)
      let original = try RasterIO.read(reference)
      func check(_ document: CraftDocument, expecting names: Set<String>) throws {
        XCTAssertEqual(document.colorMode, .rgb)
        XCTAssertEqual(document.bitsPerChannel, evidence.depth)
        XCTAssertEqual(document.width, 67)
        XCTAssertEqual(document.height, 43)
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(document.alphaChannels?.map(\.name) ?? [], evidence.names.filter(names.contains))
        for channel in document.alphaChannels ?? [] {
          let index = try XCTUnwrap(evidence.names.firstIndex(of: channel.name))
          XCTAssertEqual(channel.psdIdentifier, evidence.identifiers[index])
          let bytes = try (0..<document.height).flatMap { try PSDAuxiliaryChannels.row(channel, y: $0, depth: evidence.depth) }
          XCTAssertEqual(digest(Data(bytes)), evidence.sampleSHA256[index])
        }
      }
      try check(original, expecting: Set(evidence.names))
      let flat = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .littleEndian,
        tiffPixelOrder: .perChannel, tiffPredictor: evidence.depth == 32,
        tiffLayers: false, tiffTransparency: true, tiffBigTIFF: true,
        tiffAlphaChannels: true, tiffSpotColors: true)
      let encoded = try RasterIO.encoded(original, type: .tiff, options: flat)
      try RasterIO.write(original, to: url, type: .tiff, options: flat)
      XCTAssertEqual(try Data(contentsOf: url), encoded)
      let tiff = try TIFFContainer(encoded, metadata: false, additionalTags: [34377, 37724])
      XCTAssertNil(tiff.root.fields[37724])
      XCTAssertNotNil(tiff.root.fields[34377])
      XCTAssertEqual(try tiff.numbers(338).count, evidence.names.count + 1)
      try check(RasterIO.read(url), expecting: Set(evidence.names))
      var select = flat
      select.tiffAlphaChannels = false
      select.tiffTransparency = false
      select.tiffBigTIFF = false
      try check(RasterIO.read(RasterIO.encoded(original, type: .tiff, options: select)), expecting: ["Proof ink"])
      select.tiffAlphaChannels = true
      select.tiffSpotColors = false
      try check(RasterIO.read(RasterIO.encoded(original, type: .tiff, options: select)), expecting: ["Alpha 2"])
      try check(RasterIO.read(RasterIO.encoded(original, type: .tiff)), expecting: [])
    }
  }

}
