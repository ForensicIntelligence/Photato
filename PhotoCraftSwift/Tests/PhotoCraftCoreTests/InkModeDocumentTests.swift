import Foundation
import XCTest
@testable import PhotoCraftCore

final class InkModeDocumentTests: XCTestCase {
  private func duotone() throws -> CraftDocument {
    let gray = try InkPlane(width: 3, height: 1, bytes: Data([0, 128, 255]))
    let settings = DuotoneSettings(inks: [.init(name: "Cyan", color: Pixel(0, 1, 1)), .init(name: "Magenta", color: Pixel(1, 0, 1))])
    return try CraftDocument(width: 3, height: 1).replacingInkMode(.duotone(.init(gray: gray, settings: settings, sourceModeData: Data([3, 1, 4]))))
  }
  private func multichannel(depth: PixelDepth = .u16) throws -> CraftDocument {
    let data = depth == .u16 ? Data([0, 0, 0, 128, 255, 255]) : Data([0, 128, 255])
    let plane = try InkPlane(width: 3, height: 1, depth: depth, bytes: data)
    let plates = [InkPlate(name: "Cyan", color: Pixel(0, 1, 1), samples: plane),
      InkPlate(name: "Magenta", color: Pixel(1, 0, 1), samples: try plane.converted(to: depth, inverted: true)),
      InkPlate(name: "Yellow", color: Pixel(1, 1, 0), samples: plane)]
    return try CraftDocument(width: 3, height: 1).replacingInkMode(.multichannel(.init(plates: plates)))
  }
  func testNative48RestoresAuthoritativeGrayAndExactIndependentInkBytes() throws {
    for original in [try duotone(), try multichannel(), try multichannel(depth: .u8)] {
      XCTAssertEqual(original.minimumArchiveVersion, 48)
      XCTAssertTrue(original.hasAuthoritativeModeStorage); XCTAssertFalse(original.hasNativeModeStorage)
      for bytes in [try NativeArchive.encode(original), try NativeArchive.encodeChunked(original)] {
        XCTAssertTrue(try NativeArchive.decode(bytes) == original, "Ink data and document identity must round-trip")
        XCTAssertThrowsError(try NativeArchive.decode(bytes, rasterByteLimit: 0))
      }
    }
    let original = try duotone()
    var poisoned = original; poisoned.layers[0].content = .raster(try Surface(width: 3, height: 1, fill: Pixel(1, 0, 0)))
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(poisoned)) == original, "Gray data, not serialized RGB cache, is authoritative")
    var plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: NativeArchive.encode(original), format: nil) as? [String: Any])
    plist["version"] = 47
    XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)))
  }
  func testPreparedInkChangesAreSourceCheckedAndFullyUndoable() throws {
    let initial = try CraftDocument(width: 3, height: 1), prepared = try duotone()
    let converted = try initial.replacingInkMode(XCTUnwrap(prepared.inkMode))
    var session = EditorSession(document: initial)
    let command = Command.preparedDocumentMode(.init(source: initial, result: converted, title: "Duotone"))
    try session.execute(command); XCTAssertTrue(session.document == converted)
    guard case .duotone(let old) = converted.inkMode else { return XCTFail() }
    var settings = old.settings; settings.inks[0].color = Pixel(0.1, 0.2, 0.6)
    let edited = try converted.replacingDuotoneSettings(settings)
    try session.execute(.preparedDocumentMode(.init(source: converted, result: edited, title: "Duotone Options")))
    guard case .duotone(let changed) = session.document.inkMode else { return XCTFail() }
    XCTAssertEqual(changed.gray, old.gray); XCTAssertNil(changed.sourceModeData)
    try session.undo(); XCTAssertTrue(session.document == converted)
    try session.undo(); XCTAssertTrue(session.document == initial)
    try session.redo(); try session.redo(); XCTAssertTrue(session.document == edited)
    XCTAssertThrowsError(try session.execute(command)); XCTAssertTrue(session.document == edited)
  }
  func testSelectedPaintingUpdatesOnlyGraySourceAndPreservesInkSettings() throws {
    let original = try duotone(); var session = EditorSession(document: original)
    let id = try XCTUnwrap(original.activeLayerID)
    try session.execute(.selection(.init(x: 2, y: 0, width: 1, height: 1)))
    let selected = session.document
    try session.execute(.fill(id, Pixel(1, 0, 0)))
    guard case .duotone(let ink) = session.document.inkMode,
      case .duotone(let old) = original.inkMode,
      case .raster(let cache) = session.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(ink.gray.bytes, Data([0, 128, 54])); XCTAssertEqual(ink.settings, old.settings)
    XCTAssertEqual(ink.sourceModeData, old.sourceModeData)
    XCTAssertEqual(cache.pixel(x: 2, y: 0).r, cache.pixel(x: 2, y: 0).g)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)) == session.document)
    try session.undo(); XCTAssertTrue(session.document == selected)
  }
  func testInvalidLayerAndMixedStorageEditsCannotPartiallyMutateInkDocument() throws {
    let original = try duotone(), id = try XCTUnwrap(original.activeLayerID)
    for command in [Command.move(id, 1, 0), .opacity(id, 0.5), .addLayer(Layer(name: "Extra", content: .fill(.white)))] {
      var candidate = original
      XCTAssertThrowsError(try command.apply(to: &candidate)); XCTAssertTrue(candidate == original)
    }
    var mixed = original; mixed.modeDescriptor = try .init(mode: .rgb, depth: .u8)
    XCTAssertThrowsError(try mixed.validate())
    var multi = try multichannel(), unchanged = multi
    XCTAssertTrue(multi.layers.isEmpty); XCTAssertNil(multi.activeLayerID)
    XCTAssertEqual(multi.colorChannelNames, ["Cyan", "Magenta", "Yellow"])
    XCTAssertThrowsError(try Command.addLayer(Layer(name: "No layers", content: .fill(.black))).apply(to: &multi))
    XCTAssertTrue(multi == unchanged)
    unchanged.layers = [Layer(name: "Invalid", content: .fill(.black))]
    XCTAssertThrowsError(try unchanged.validate())
    for mode in [DocumentColorMode.duotone, .multichannel] {
      XCTAssertThrowsError(try NativeModeRaster(width: 1, height: 1, mode: mode, depth: .u8))
      XCTAssertThrowsError(try DocumentModeDescriptor(mode: mode, depth: .u8))
    }
  }
  func testInkPlateEditsKeepOtherPlatesAndAuxiliaryMasksSeparate() throws {
    var original = try multichannel()
    let alpha = AlphaChannel(name: "Saved mask", pixels: try Surface(width: 3, height: 1, depth: .u16, fill: .white))
    original.alphaChannels = [alpha]; try original.validate()
    guard case .multichannel(let before) = original.inkMode else { return XCTFail() }
    var plate = before.plates[1]; plate.samples = try plate.samples.replacing(offset: 1, values: [0.25]); plate.solidity = 0.8
    let edited = try original.replacingInkPlate(plate)
    guard case .multichannel(let after) = edited.inkMode else { return XCTFail() }
    XCTAssertEqual(after.plates[0], before.plates[0]); XCTAssertEqual(after.plates[2], before.plates[2])
    XCTAssertEqual(edited.alphaChannels, original.alphaChannels)
    var session = EditorSession(document: original)
    try session.execute(.preparedDocumentMode(.init(source: original, result: edited, title: "Ink Channel")))
    try session.undo(); XCTAssertTrue(session.document == original)
    try session.redo(); XCTAssertTrue(session.document == edited)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(edited)) == edited)
    var collision = original; collision.alphaChannels?[0].id = before.plates[0].id
    XCTAssertThrowsError(try collision.validate())
  }
  func testConvertingInkModesRecoversGrayOrMatchingComponents() throws {
    let duo = try duotone(), gray = try duo.convertingMode(.init(mode: .grayscale, depth: .u8))
    XCTAssertEqual(try gray.layers[0].nativeMode?.planes[0], Data([0, 128, 255])); XCTAssertNil(gray.inkMode)
    let multi = try multichannel(), rgb = try multi.convertingMode(.init(mode: .rgb, depth: .u16))
    XCTAssertEqual(try rgb.layers[0].nativeMode?.planes[0], Data([255, 255, 255, 127, 0, 0]))
    XCTAssertEqual(try rgb.layers[0].nativeMode?.planes[1], Data([0, 0, 0, 128, 255, 255]))
    XCTAssertEqual(try rgb.layers[0].nativeMode?.planes[3], Data(repeating: 255, count: 6))
    let linear = try multi.convertingMode(.init(mode: .rgb, depth: .f32))
    let half = try XCTUnwrap(linear.layers[0].nativeMode?.value(component: 0, index: 1))
    XCTAssertEqual(half, 0.214, accuracy: 0.002, "Integer RGB samples must be linearized for32-bit storage")
    for mode in DocumentColorMode.componentModes {
      let converted = try duo.convertingMode(.init(mode: mode, depth: .u8))
      try converted.validate(); XCTAssertEqual(converted.colorMode, mode); XCTAssertNil(converted.inkMode)
    }
  }
  func testScratchSpilledHistoryRestoresInkPlanesAndMetadata() throws {
    let original = try multichannel()
    var session = EditorSession(document: original, historyByteLimit: 0)
    guard case .multichannel(let raster) = original.inkMode else { return XCTFail() }
    var plate = raster.plates[0]; plate.samples = try plate.samples.replacing(offset: 1, values: [0.12345])
    let edited = try original.replacingInkPlate(plate)
    try session.execute(.preparedDocumentMode(.init(source: original, result: edited, title: "Ink samples")))
    XCTAssertEqual(session.residentHistoryBytes, 0); XCTAssertGreaterThan(session.historySpilledStates, 0)
    try session.undo(); XCTAssertTrue(session.document == original)
    try session.redo(); XCTAssertTrue(session.document == edited)
  }
}
