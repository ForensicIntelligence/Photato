import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDMultichannelTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var plates: [InkPlate] = []
    for c in 0..<3 {
      var bytes = Data()
      for i in 0..<12 {
        let n = depth == .u8 ? (i * 31 + c * 17) % 256 : (i * 5957 + c * 971) % 65536
        bytes.append(UInt8(n & 255)); if depth == .u16 { bytes.append(UInt8(n >> 8)) }
      }
      plates.append(.init(name: ["Black", "Orange 🟠", "青"][c], color: [Pixel.black, Pixel(1,0.5,0), Pixel(0,1,1)][c], solidity: [0,0.37,1][c],
        samples: try InkPlane(width: 4, height: 3, depth: depth, bytes: bytes)))
    }
    var document = try CraftDocument(width: 4, height: 3, depth: depth).replacingInkMode(.multichannel(MultichannelRaster(plates: plates)))
    document.resolution = 300
    document.alphaChannels = [.init(name: "Saved coverage", pixels: try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0.4,0.4,0.4)))]
    return document
  }
  func assertSamples(_ read: CraftDocument, _ original: CraftDocument, file: StaticString = #filePath, line: UInt = #line) throws {
    guard case .multichannel(let a) = read.inkMode, case .multichannel(let b) = original.inkMode else { return XCTFail("Missing Multichannel", file: file, line: line) }
    XCTAssertEqual(a.plates.map(\.samples), b.plates.map(\.samples), file: file, line: line)
    XCTAssertEqual(a.plates.map(\.name), b.plates.map(\.name), file: file, line: line)
    XCTAssertEqual(a.plates.map(\.solidity), b.plates.map(\.solidity), file: file, line: line)
    XCTAssertEqual(try read.alphaChannels?.map { try $0.pixels.rgbaData(depth: read.depth) }, try original.alphaChannels?.map { try $0.pixels.rgbaData(depth: original.depth) }, file: file, line: line)
    XCTAssertEqual(read.alphaChannels?.map(\.options), original.alphaChannels?.map(\.options), file: file, line: line)
    XCTAssertTrue(read.layers.isEmpty); XCTAssertEqual(read.pixelsPerInch, original.pixelsPerInch)
  }
  func testIndependentFilesDecodeExactInkAndMaskSamplesAtBothDepthsAndAllCompressions() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "provenance", withExtension: "json", subdirectory: "Fixtures/MultichannelFormats"))
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let names = try XCTUnwrap(manifest["names"] as? [String]), fixtures = try XCTUnwrap(manifest["fixtures"] as? [[String: Any]])
    XCTAssertEqual(fixtures.count, 16)
    for entry in fixtures {
      let name = try XCTUnwrap(entry["file"] as? String), depth = try XCTUnwrap(entry["depth"] as? Int)
      let fileSamples = try XCTUnwrap(entry["fileSamples"] as? [[Int]])
      let document = try PSDCodec.read(Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(name)))
      guard case .multichannel(let raster) = document.inkMode else { return XCTFail(name) }
      XCTAssertEqual(raster.plates.map(\.name), Array(names.prefix(5))); XCTAssertEqual(document.alphaChannels?.map(\.name), Array(names.suffix(2)))
      XCTAssertEqual(document.alphaChannels?.map(\.options.indicates), [.maskedAreas,.selectedAreas])
      let max = depth == 8 ? 255 : 65535
      for c in 0..<7 { for i in 0..<12 {
        let value: Float
        let inverted: Bool
        if c < raster.plates.count {
          value = raster.plates[c].samples.value(at: i)
          inverted = true
        } else {
          let alpha = document.alphaChannels![c - raster.plates.count]
          value = alpha.pixels.pixel(x: i % 4, y: i / 4).r
          // The fixture contains Photoshop editing gray. Selected Areas
          // stores the complement of Photato's normalized selection coverage.
          inverted = alpha.options.indicates == .selectedAreas
        }
        let expected = inverted ? max - fileSamples[c][i] : fileSamples[c][i]
        XCTAssertEqual(Int((value * Float(max)).rounded()), expected, "\(name) plane \(c) sample \(i)")
      } }
      let data = try PSDCodec.writeRasterLayers(document, compositeCompression: .zipPrediction)
      try assertSamples(PSDCodec.read(data), document)
      var reader = PSDReader(data: data); _ = try reader.bytes(26); _ = try reader.section()
      let blocks = try PSDImageResources.blocks(reader.section().data)
      let original = try PSDImageResources.blocks(try XCTUnwrap(document.sourceMetadata?["psdResources"]))
      XCTAssertEqual(blocks.first { $0.id == 1077 }?.data, original.first { $0.id == 1077 }?.data, "Unchanged RGB/HSB/CMYK/Lab/Gray metadata must survive exactly")
    }
  }
  func testAllCompressionContainersAndFileBackedWritesPreserveSamplesAndNativeHistory() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for depth in [PixelDepth.u8,.u16] { for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases {
      let source = try fixture(depth), url = folder.appendingPathComponent("ink.psd")
      let data = try PSDCodec.writeRasterLayers(source, format: format, compositeCompression: compression)
      try PSDCodec.writeRasterLayers(source, to: url, format: format, compositeCompression: compression)
      XCTAssertEqual(try Data(contentsOf: url), data)
      let restored = try PSDCodec.read(url); try assertSamples(restored, source)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(restored)), restored)
      var session = EditorSession(document: restored)
      guard case .multichannel(let ink) = restored.inkMode else { return XCTFail() }
      try session.execute(.inkChannel(.write(.plate(ink.plates[0].id), 0, [1])))
      try session.undo(); XCTAssertEqual(session.document, restored)
    } } }
  }
  func testModernDisplayFramingAndInvalidInputsRejectWithoutAcceptingTruncation() throws {
    let source = try fixture(.u8), data = try PSDCodec.writeRasterLayers(source)
    for n in 0..<data.count { XCTAssertThrowsError(try PSDCodec.read(data.prefix(n)), "Truncation at \(n)") }
    var file = PSDReader(data: data); _ = try file.bytes(26); _ = try file.section()
    let blocks = try PSDImageResources.blocks(file.section().data), display = try XCTUnwrap(blocks.first { $0.id == 1077 })
    XCTAssertEqual(display.data.count, 4 + 4*13)
    XCTAssertThrowsError(try PSDInkChannels.displays([.init(id: 1077, data: display.data + Data([0]), raw: Data())], count: 4))
    XCTAssertThrowsError(try PSDInkChannels.names([.init(id: 1045, data: Data([255,255,255,255]), raw: Data())], count: 4))
    var bad = data; bad[25] = 8; XCTAssertThrowsError(try PSDCodec.read(bad))
    bad = data; bad[23] = 32; XCTAssertThrowsError(try PSDCodec.read(bad))
    bad = data; bad[13] = 57; XCTAssertThrowsError(try PSDCodec.read(bad))
    var quick = source; quick.quickMask = quick.alphaChannels?.first
    // Use a distinct temporary channel identity to keep the source document valid.
    quick.quickMask?.id = UUID();XCTAssertNotNil(try PSDCodec.read(PSDCodec.writeRasterLayers(quick)).quickMask)
    XCTAssertThrowsError(try PSDInkChannels.display(Data([0,3])+Data(repeating:0,count:11)))
  }
  func testLegacyDisplayAndDefaultNamesAndOptionsEditsReplaceStaleResources() throws {
    let source = try fixture(.u8), data = try PSDCodec.writeRasterLayers(source)
    var r = PSDReader(data: data); let header = try r.bytes(26); _ = try r.section()
    let blocks = try PSDImageResources.blocks(r.section().data), tail = try r.bytes(r.remaining)
    let modern = try XCTUnwrap(blocks.first { $0.id == 1077 }?.data)
    var legacy = Data()
    for i in 0..<4 { legacy.append(modern.subdata(in: (4+i*13)..<(4+(i+1)*13))); legacy.append(0) }
    var file = PSDWriter(); file.data = header; file.n(0,4); file.section(PSDImageResources.block(1007,data:legacy)); file.data += tail
    let old = try PSDCodec.read(file.data)
    XCTAssertEqual(old.colorChannelNames, ["Channel 1","Channel 2","Channel 3"])
    var edited = old
    guard case .multichannel(var ink) = old.inkMode else { return XCTFail() }
    ink.plates[0].name = "Changed"; ink.plates[0].color = Pixel(0,1,0); ink.plates[0].solidity = 0.61
    edited.inkMode = .multichannel(ink)
    let read = try PSDCodec.read(PSDCodec.writeRasterLayers(edited))
    guard case .multichannel(let revised) = read.inkMode else { return XCTFail() }
    XCTAssertEqual(revised.plates[0].name,"Changed"); XCTAssertEqual(revised.plates[0].color,Pixel(0,1,0)); XCTAssertEqual(revised.plates[0].solidity,0.61)
    XCTAssertEqual(revised.plates[0].samples,ink.plates[0].samples)
  }
  func testMaximumChannelCountAndMissingDisplayMetadata() throws {
    let plates = try (0..<56).map { i in InkPlate(name: "Ink \(i)", color: .black,
      samples: try InkPlane(width: 1, height: 1, bytes: Data([UInt8(i)]))) }
    let document = try CraftDocument(width: 1, height: 1).replacingInkMode(.multichannel(MultichannelRaster(plates: plates)))
    for compression in PSDCompression.allCases {
      let data = try PSDCodec.writeRasterLayers(document, compositeCompression: compression)
      let restored = try PSDCodec.read(data); try assertSamples(restored, document)
      var r = PSDReader(data: data); let header = try r.bytes(26); _ = try r.section(); _ = try r.section()
      var writer = PSDWriter(); writer.data = header; writer.n(0,4); writer.n(0,4); writer.data += try r.bytes(r.remaining)
      let noNames = try PSDCodec.read(writer.data)
      XCTAssertEqual(noNames.colorChannelNames.count,56); XCTAssertEqual(noNames.colorChannelNames.last,"Channel 56")
      XCTAssertEqual(try noNames.multichannelRaster().plates.map(\.samples),plates.map(\.samples))
    }
    XCTAssertThrowsError(try PSDChannelCodec.byteCount(width:1,height:1,depth:8,channels:57))
    XCTAssertThrowsError(try PSDChannelCodec.byteCount(width:8192,height:8192,depth:16,channels:56))
  }

  func testMaximumWidthPrintPlateKeepsNumericWordsAcrossAllPSBCompressions() throws {
    let width = 300_000, height = 29, depth = PixelDepth.u16
    let center = width / 2, last = width * height - 1
    let plate = try InkPlane(width: width, height: height, depth: depth, value: 0.25)
      .replacing(offset: center, values: [0.5]).replacing(offset: last, values: [0.75])
    let ink = InkPlate(name: "Print black", color: .black, solidity: 1, samples: plate)
    var document = try CraftDocument(width: width, height: height, depth: depth)
      .replacingInkMode(.multichannel(MultichannelRaster(plates: [ink])))
    var alpha = try Surface(width: width, height: height, depth: depth, fill: Pixel(0.5, 0.5, 0.5))
    alpha.setPixel(x: 0, y: height - 1, .white)
    var options = ChannelDisplayOptions()
    options.indicates = .selectedAreas
    document.alphaChannels = [AlphaChannel(name: "Saved coverage", pixels: alpha, options: options)]
    let folder = try PSDFileOutputTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    XCTAssertEqual(document.minimumArchiveVersion, 93)
    XCTAssertThrowsError(try plate.bytes)
    for compression in PSDCompression.allCases {
      let target = folder.appendingPathComponent("plates-\(compression.rawValue).psb")
      try PSDCodec.writeRasterLayers(document, to: target, format: .psb, compositeCompression: compression)
      let reopened = try PSDCodec.read(target)
      let loaded = try XCTUnwrap(reopened.multichannelRaster().plates.first?.samples)
      XCTAssertEqual(loaded, plate)
      XCTAssertEqual(loaded.rawWord(at: 0), 16_384)
      XCTAssertEqual(loaded.rawWord(at: center), 32_768)
      XCTAssertEqual(loaded.rawWord(at: last), 49_151)
      XCTAssertLessThanOrEqual(loaded.retainedSampleBytes, 2 * 4096 * 2)
      let saved = try XCTUnwrap(reopened.alphaChannels?.first)
      XCTAssertEqual(saved.name, "Saved coverage")
      XCTAssertEqual(saved.options.indicates, .selectedAreas)
      XCTAssertEqual(saved.pixels.pixel(x: 0, y: height - 1), .white)
      XCTAssertEqual(saved.pixels.pixel(x: 1, y: height - 1), alpha.pixel(x: 1, y: height - 1))
      XCTAssertThrowsError(try PSDCodec.read(Data(contentsOf: target).dropLast()))
    }
    let native = folder.appendingPathComponent("plates.photato")
    try NativeArchive.write(document, to: native)
    XCTAssertEqual(try NativeArchive.read(native), document)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)

    let preview = try Renderer.composite(document)
    XCTAssertEqual(preview.pixel(x: 0, y: 0).r, (1 - plate.value(at: 0)) * (1 - plate.value(at: 0)))
    XCTAssertEqual(preview.pixel(x: width - 1, y: height - 1).r, (1 - plate.value(at: last)) * (1 - plate.value(at: last)))
    var session = EditorSession(document: document)
    try session.execute(.inkChannel(.edit([.plate(ink.id)], .invert)))
    let inverted = try XCTUnwrap(session.document.multichannelRaster().plates.first?.samples)
    XCTAssertEqual(inverted.rawWord(at: 0), 49_151)
    XCTAssertEqual(inverted.rawWord(at: last), 16_384)
    try session.undo()
    XCTAssertEqual(session.document, document)
  }

  func testMaximumSizeInkPreviewAndViewportUpdateAfterEditAndUndo() throws {
    let side = 300_000
    let last = side * side - 1
    let plate = InkPlate(name: "Black", color: .black, solidity: 1,
      samples: try InkPlane(width: side, height: side, depth: .u16, value: 0.25))
    let document = try CraftDocument(width: side, height: side, depth: .u16)
      .replacingInkMode(.multichannel(MultichannelRaster(plates: [plate])))
    var session = EditorSession(document: document)
    let initial = try Renderer.render(document)
    let corner = side - 1
    let defaultPixel = initial.surface.pixel(x: corner, y: corner)
    XCTAssertEqual(defaultPixel, initial.surface.pixel(x: 0, y: 0))
    XCTAssertNil(initial.surface.storedTileKeys.first { _ in true })

    try session.execute(.inkChannel(.write(.plate(plate.id), last, [0.75])))
    let edited = try Renderer.render(session.document, reusing: initial)
    XCTAssertEqual(edited.update, .full)
    XCTAssertEqual(edited.surface.pixel(x: 0, y: 0), defaultPixel)
    let newPixel = edited.surface.pixel(x: corner, y: corner)
    let sample = try session.document.multichannelRaster().plates[0].samples.value(at: last)
    XCTAssertEqual(newPixel.r, (1 - sample) * (1 - sample))
    XCTAssertNotEqual(newPixel, defaultPixel)
    XCTAssertEqual(edited.surface.storedTileKeys.reduce(0) { count, _ in count + 1 }, 1)

    let region = IntRect(x: corner - 1, y: corner - 1, width: 2, height: 2)
    let viewport = try Renderer.composite(session.document, region: region)
    XCTAssertEqual(viewport.pixel(x: corner, y: corner), newPixel)
    XCTAssertEqual(viewport.pixel(x: corner - 1, y: corner - 1), defaultPixel)
    XCTAssertEqual(viewport.pixel(x: corner - 2, y: corner), .clear)

    try session.undo()
    let undone = try Renderer.render(session.document, reusing: edited)
    XCTAssertEqual(undone.surface.pixel(x: corner, y: corner), defaultPixel)
  }
  func testEmitOutputsForIndependentDecoderWhenRequested() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_INK_PSD_OUTPUT_DIR"] else { return }
    let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var expected: [[String: Any]] = []
    for depth in [PixelDepth.u8,.u16] { for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases {
      let source = try fixture(depth), bits = source.bitsPerChannel
      let name = "ink-\(bits)-\(compression.rawValue).\(format == .psd ? "psd":"psb")"
      try PSDCodec.writeRasterLayers(source, to: folder.appendingPathComponent(name), format: format, compositeCompression: compression)
      guard case .multichannel(let ink) = source.inkMode else { return XCTFail() }
      let max = bits == 8 ? 255 : 65535
      var samples = ink.plates.map { p in (0..<12).map { max-Int((p.samples.value(at:$0)*Float(max)).rounded()) } }
      samples.append((0..<12).map { i in Int((source.alphaChannels![0].pixels.pixel(x:i%4,y:i/4).r*Float(max)).rounded()) })
      expected.append(["file":name,"samples":samples,"names":ink.plates.map(\.name)+["Saved coverage"],"depth":bits])
    } } }
    try JSONSerialization.data(withJSONObject: expected,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("expected.json"))
  }
}
