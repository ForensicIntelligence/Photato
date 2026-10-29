import Foundation
import XCTest
@testable import PhotoCraftCore

final class RestrictedModeDocumentTests: XCTestCase {
  private func indexed() throws -> CraftDocument {
    let raster = try IndexedRaster(width: 3, height: 1, palette: [.init(255, 0, 0), .init(255, 0, 0), .init(0, 0, 255)], indices: Data([1, 0, 2]))
    return try CraftDocument(width: 3, height: 1).replacingRestrictedMode(.indexed(raster))
  }
  func testNative47AndHistoryRetainPaletteIdentity() throws {
    let original = try CraftDocument(width: 3, height: 1)
    let raster = try IndexedRaster(width: 3, height: 1, palette: [.init(255, 0, 0), .init(255, 0, 0), .init(0, 0, 255)], indices: Data([1, 0, 2]))
    let converted = try original.replacingRestrictedMode(.indexed(raster))
    var session = EditorSession(document: original)
    try session.execute(.preparedDocumentMode(.init(source: original, result: converted)))
    XCTAssertEqual(session.document, converted); XCTAssertEqual(converted.colorMode, .indexed)
    XCTAssertEqual(converted.bitsPerChannel, 8); XCTAssertEqual(converted.minimumArchiveVersion, 47)
    for encoded in [try NativeArchive.encode(converted), try NativeArchive.encodeChunked(converted)] {
      XCTAssertEqual(try NativeArchive.decode(encoded), converted)
    }
    let table = try converted.replacingColorTable([.init(255, 0, 0), .init(0, 255, 0), .init(0, 0, 255)], transparentIndex: nil)
    let command = Command.preparedDocumentMode(.init(source: converted, result: table, title: "Color Table"))
    XCTAssertEqual(command.label, "Color Table"); try session.execute(command)
    guard case .indexed(let updated) = session.document.restrictedMode else { return XCTFail("Palette storage missing") }
    XCTAssertEqual(updated.indices, Data([1, 0, 2])); XCTAssertEqual(try updated.surface().pixel(x: 0, y: 0), Pixel(0, 1, 0))
    try session.undo(); XCTAssertEqual(session.document, converted)
    try session.undo(); XCTAssertEqual(session.document, original)
    try session.redo(); try session.redo(); XCTAssertEqual(session.document, table)
    XCTAssertThrowsError(try session.execute(command)); XCTAssertEqual(session.document, table)
  }
  func testNativeBitmapBitsRestoreCacheAndRejectDowngrade() throws {
    let raster = try BitmapRaster(width: 9, height: 1, bits: Data([0x81, 0x80]))
    let document = try CraftDocument(width: 9, height: 1).replacingRestrictedMode(.bitmap(raster))
    XCTAssertEqual(document.colorMode, .bitmap); XCTAssertEqual(document.bitsPerChannel, 1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)), document)
    var cacheChanged = document; cacheChanged.layers[0].content = .raster(try Surface(width: 9, height: 1, fill: .white))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(cacheChanged)), document)
    var plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: NativeArchive.encode(document), format: nil) as? [String: Any])
    plist["version"] = 46
    let downgraded = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    XCTAssertThrowsError(try NativeArchive.decode(downgraded))
  }
  func testRestrictedPixelEditingQuantizesAndUndoKeepsUnchangedIndices() throws {
    let document = try indexed(); var session = EditorSession(document: document)
    let id = try XCTUnwrap(document.activeLayerID)
    try session.execute(.selection(.init(x: 2, y: 0, width: 1, height: 1)))
    let selected = session.document
    try session.execute(.fill(id, Pixel(0.95, 0.05, 0.05)))
    guard case .indexed(let changed) = session.document.restrictedMode else { return XCTFail() }
    XCTAssertEqual(changed.indices, Data([1, 0, 0]))
    try session.undo(); XCTAssertEqual(session.document, selected)
    let bitmap = try CraftDocument(width: 3, height: 1).replacingRestrictedMode(.bitmap(BitmapRaster(width: 3, height: 1, bits: Data([0]))))
    var binary = EditorSession(document: bitmap)
    try binary.execute(.fill(try XCTUnwrap(bitmap.activeLayerID), Pixel(0.3, 0.3, 0.3)))
    guard case .bitmap(let filled) = binary.document.restrictedMode else { return XCTFail() }
    XCTAssertEqual(filled.bits, Data([0xe0])); try binary.undo(); XCTAssertEqual(binary.document, bitmap)
  }
  func testInvalidLayerEditsAreAtomicAndComponentConversionExitsRestrictedMode() throws {
    let original = try indexed(), id = try XCTUnwrap(original.activeLayerID)
    var malformed = original; malformed.layers = []; malformed.activeLayerID = nil
    XCTAssertThrowsError(try malformed.replacingColorTable([.init(0, 0, 0)], transparentIndex: nil))
    var document = original
    for command in [Command.opacity(id, 0.5), .move(id, 1, 0), .addLayer(Layer(name: "Extra", content: .raster(try Surface(width: 3, height: 1))))] {
      XCTAssertThrowsError(try command.apply(to: &document)); XCTAssertEqual(document, original)
    }
    for mode in DocumentColorMode.componentModes {
      var session = EditorSession(document: original)
      try session.execute(.documentMode(.init(mode: mode, depth: .u8)))
      XCTAssertNil(session.document.restrictedMode); XCTAssertEqual(session.document.colorMode, mode)
      try session.document.validate(); try session.undo(); XCTAssertEqual(session.document, original)
    }
    XCTAssertThrowsError(try original.convertingMode(.init(mode: .indexed, depth: .u8)))
    XCTAssertThrowsError(try NativeModeRaster(width: 1, height: 1, mode: .bitmap, depth: .u8))
    XCTAssertThrowsError(try NativeModeRaster(width: 1, height: 1, mode: .indexed, depth: .u8))
  }
}
