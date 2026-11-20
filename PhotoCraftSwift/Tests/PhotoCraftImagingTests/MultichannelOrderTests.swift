import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class MultichannelOrderTests: XCTestCase {
  func testSavedSpotSurvivesBothWaysOfEnteringMultichannelAndEveryContainerCompression() throws {
    var source = try InkModeInputTests().source(.cmyk, depth: .u16)
    var display = PSDWriter()
    for value in [2, 21235, 51500, 39700, 56535, 67] { display.n(value, 2) }
    display.n(2, 1)
    let swatch = try PSDInkChannels.display(display.data)
    var spot = try source.newSpotChannel(name: "Owned Indigo",
      ink: SpotInk(color: swatch.color, solidity: swatch.opacity), density: Float(0x1234) / 65535)
    let last = Float(0xabcd) / 65535
    spot.pixels.setPixel(x: 2, y: 0, Pixel(last, last, last))
    spot.psdDisplay = display.data
    spot.psdIdentifier = 705
    let mask = AlphaChannel(name: "Owned Mask", pixels: try Surface(width: 3, height: 1, depth: .u16, fill: .white))
    source.alphaChannels = [mask, spot]

    let requests = [try InkModeRequest(.multichannel, document: source).command(in: source),
      try InkModeInput.deleteProcess(.init(mode: .cmyk, components: [1], mergeVisible: false), in: source)]
    for request in requests {
      var editor = EditorSession(document: source)
      try editor.execute(request)
      let converted = editor.document
      XCTAssertEqual(converted.alphaChannels, [mask, spot])
      let processNames = try converted.multichannelRaster().plates.map(\.name)
      let native = try NativeArchive.decode(NativeArchive.encodeChunked(converted))
      XCTAssertEqual(native, converted)
      for format in [PSDFileFormat.psd, .psb] {
        for compression in [PSDCompression.raw, .rle, .zip, .zipPrediction] {
          let bytes = try PSDCodec.writeRasterLayers(native, format: format, compositeCompression: compression)
          let reopened = try PSDCodec.read(bytes)
          let plates = try reopened.multichannelRaster().plates
          let ink = try XCTUnwrap(plates.last)
          XCTAssertEqual(plates.map(\.name), processNames + [spot.name])
          XCTAssertEqual(ink.color, swatch.color)
          XCTAssertEqual(ink.solidity, swatch.opacity)
          XCTAssertEqual(ink.samples.rawWord(at: 0), 0x1234)
          XCTAssertEqual(ink.samples.rawWord(at: 2), 0xabcd)
          XCTAssertEqual(reopened.alphaChannels?.count, 1)
          let saved = try XCTUnwrap(reopened.alphaChannels?.first)
          XCTAssertEqual(saved.name, mask.name)
          XCTAssertEqual(reopened.multichannelChannelOrder, plates.dropLast().map(\.id) + [saved.id, ink.id])
          XCTAssertEqual(reopened.sourceMetadata?[PSDInkChannels.key(ink.id)], display.data)
          XCTAssertEqual(reopened.sourceMetadata?[PSDInkChannels.identifierKey(ink.id)], Data([0, 0, 2, 193]))
          if compression == .raw {
            XCTAssertEqual(Array(bytes.suffix(6)), [0xed, 0xcb, 0xed, 0xcb, 0x54, 0x32])
          }
        }
      }
      XCTAssertEqual(editor.document, converted)
      try editor.undo()
      XCTAssertEqual(editor.document, source)
    }
  }

  func testPagedPSBRetainsEditedSpotDisplayAndTerminalDensity() throws {
    let width = 300_000, height = 29
    var document = try CraftDocument(width: width, height: height, depth: .u16)
    var spot = try document.newSpotChannel(name: "Spot Violet",
      ink: SpotInk(color: Pixel(1, 0, 0), solidity: 0.5), density: Float(0xabcd) / 65535)
    var oldDisplay = PSDWriter()
    for value in [0, 65535, 0, 0, 0, 50] { oldDisplay.n(value, 2) }
    oldDisplay.n(2, 1)
    spot.psdDisplay = oldDisplay.data
    spot.spot = SpotInk(color: Pixel(0, 0, 1), solidity: 0.84)
    let terminal = Float(0x3456) / 65535
    spot.pixels.setPixel(x: width - 1, y: height - 1, Pixel(terminal, terminal, terminal))
    let process = InkPlate(name: "Cyan", color: Pixel(0, 1, 1),
      samples: try InkPlane(width: width, height: height, depth: .u16))
    document = try document.replacingInkMode(.multichannel(.init(plates: [process])))
    document.alphaChannels = [spot]
    try document.setMultichannelChannelOrder([spot.id, process.id])

    let bytes = try PSDCodec.writeRasterLayers(document, format: .psb, compositeCompression: .rle)
    let reopened = try PSDCodec.read(bytes)
    let plates = try reopened.multichannelRaster().plates
    XCTAssertEqual(plates.map(\.name), [spot.name, process.name])
    XCTAssertNil(reopened.alphaChannels)
    let ink = try XCTUnwrap(plates.first)
    XCTAssertEqual(ink.color, spot.spot?.color)
    XCTAssertEqual(ink.solidity, spot.spot?.solidity)
    XCTAssertTrue(ink.samples.requiresPagedArchive)
    XCTAssertEqual(ink.samples.rawWord(at: 0), 0xabcd)
    XCTAssertEqual(ink.samples.rawWord(at: width * height - 1), 0x3456)
  }

  func testInterleavedNamesIdentifiersAndSamplesSharePSDAndPSBPlaneOrder() throws {
    var document = try CraftDocument(width: 2, height: 1, depth: .u16)
    let cyan = InkPlate(name: "Cyan", color: Pixel(0, 1, 1),
      samples: try InkPlane(width: 2, height: 1, depth: .u16, value: Float(0xaaaa) / 65535))
    let black = InkPlate(name: "Black", color: .black,
      samples: try InkPlane(width: 2, height: 1, depth: .u16, value: Float(0x5555) / 65535))
    document = try document.replacingInkMode(.multichannel(.init(plates: [cyan, black])))
    let gray = Float(0x1234) / 65535
    var mask = AlphaChannel(name: "Saved Mask", pixels: try Surface(width: 2, height: 1, depth: .u16, fill: Pixel(gray, gray, gray)))
    mask.psdIdentifier = 0x01020304
    document.alphaChannels = [mask]
    try document.setMultichannelChannelOrder([cyan.id, mask.id, black.id])
    for format in [PSDFileFormat.psd, .psb] {
      for compression in [PSDCompression.raw, .rle, .zip, .zipPrediction] {
        let bytes = try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: compression)
        let imported = try PSDCodec.read(bytes)
        let plates = try imported.multichannelRaster().plates
        let names = Dictionary(uniqueKeysWithValues: plates.map { ($0.id, $0.name) }
          + (imported.alphaChannels ?? []).map { ($0.id, $0.name) })
        XCTAssertEqual(imported.multichannelChannelOrder.compactMap { names[$0] }, ["Cyan", "Saved Mask", "Black"])
        XCTAssertEqual(imported.alphaChannels?.first?.psdIdentifier, mask.psdIdentifier)
        XCTAssertEqual(imported.alphaChannels?.first?.pixels.pixel(x: 0, y: 0).r, gray)
        XCTAssertEqual(try imported.inkChannel(imported.inkChannelTargets[0]).rawWord(at: 0), 0xaaaa)
        XCTAssertEqual(try imported.inkChannel(imported.inkChannelTargets[1]).rawWord(at: 0), 0x5555)
        if compression == .raw {
          XCTAssertEqual(Array(bytes.suffix(12)), [0x55,0x55,0x55,0x55,0x12,0x34,0x12,0x34,0xaa,0xaa,0xaa,0xaa])
        }
      }
    }
  }

  func testNativeArchiveUndoAndGroupRelativeOperationsKeepMixedSlots() throws {
    var document = try CraftDocument(width: 2, height: 1)
    let ink = try InkPlane(width: 2, height: 1, depth: .u8, value: 0.5)
    let a = InkPlate(name: "A", color: .black, samples: ink)
    let b = InkPlate(name: "B", color: .black, samples: ink)
    document = try document.replacingInkMode(.multichannel(.init(plates: [a, b])))
    let pixel = try Surface(width: 2, height: 1, fill: .white)
    let x = AlphaChannel(name: "X", pixels: pixel)
    let y = AlphaChannel(name: "Y", pixels: pixel)
    document.alphaChannels = [x, y]
    let baseline = document
    var session = EditorSession(document: document)
    try session.execute(.channel(.moveMultichannel(x.id, 1)))
    XCTAssertEqual(session.document.multichannelChannelOrder, [a.id, x.id, b.id, y.id])
    XCTAssertEqual(session.document.minimumArchiveVersion, 94)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)), session.document)
    try session.execute(.inkChannel(.move(b.id, 0)))
    XCTAssertEqual(session.document.multichannelChannelOrder, [b.id, x.id, a.id, y.id])
    try session.execute(.channel(.move(y.id, 0)))
    XCTAssertEqual(session.document.multichannelChannelOrder, [b.id, y.id, a.id, x.id])
    try session.execute(.inkChannel(.delete(b.id)))
    XCTAssertEqual(session.document.multichannelChannelOrder, [y.id, a.id, x.id])
    try session.execute(.channel(.delete(y.id)))
    XCTAssertEqual(session.document.multichannelChannelOrder, [a.id, x.id])
    XCTAssertFalse(session.document.hasInterleavedMultichannelChannels)
    XCTAssertLessThan(session.document.minimumArchiveVersion, 94)
    XCTAssertThrowsError(try session.execute(.channel(.moveMultichannel(UUID(), 0))))
    XCTAssertEqual(session.undoStack.count, 5)
    for _ in 0..<5 { try session.undo() }
    XCTAssertEqual(session.document, baseline)
  }

  func testPagedPSBReadsAndWritesInterleavedRepeatedRows() throws {
    let width = 300_000, height = 29
    var document = try CraftDocument(width: width, height: height, depth: .u16)
    let cyan = InkPlate(name: "Cyan", color: Pixel(0, 1, 1),
      samples: try InkPlane(width: width, height: height, depth: .u16, value: Float(0xfedc) / 65535))
    let black = InkPlate(name: "Black", color: .black,
      samples: try InkPlane(width: width, height: height, depth: .u16, value: Float(0x1000) / 65535))
    XCTAssertTrue(cyan.samples.requiresPagedArchive)
    document = try document.replacingInkMode(.multichannel(.init(plates: [cyan, black])))
    let gray = Float(0xabcd) / 65535
    let mask = AlphaChannel(name: "Saved", pixels: try Surface(width: width, height: height, depth: .u16,
      fill: Pixel(gray, gray, gray)))
    document.alphaChannels = [mask]
    try document.setMultichannelChannelOrder([cyan.id, mask.id, black.id])
    let psb = try PSDCodec.writeRasterLayers(document, format: .psb, compositeCompression: .rle)
    let reopened = try PSDCodec.read(psb)
    let plates = try reopened.multichannelRaster().plates
    let saved = try XCTUnwrap(reopened.alphaChannels?.first)
    XCTAssertEqual(reopened.multichannelChannelOrder, [plates[0].id, saved.id, plates[1].id])
    XCTAssertEqual(plates[0].samples.rawWord(at: width * height - 1), 0xfedc)
    XCTAssertEqual(plates[1].samples.rawWord(at: width * height - 1), 0x1000)
    XCTAssertEqual(saved.pixels.pixel(x: width - 1, y: height - 1).r, gray)
  }
}
