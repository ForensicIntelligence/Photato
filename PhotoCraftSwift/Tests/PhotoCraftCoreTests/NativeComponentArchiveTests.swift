import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeComponentArchiveTests: XCTestCase {
  func fixture(_ depth: PixelDepth, _ mode: DocumentColorMode = .rgb) throws -> CraftDocument {
    var d = try CraftDocument(width: 65, height: 65, depth: depth)
    var surface = try Surface(width: 65, height: 65, depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    if depth == .f32 { surface.setLinearPixel(x: 64, y: 64, Pixel(Float(bitPattern: 1), -0.0, -3.5, 0.5)) }
    else { surface.setPixel(x: 64, y: 64, Pixel(0.25, 0.75, 0.5, 0.5)) }
    d.layers[0].content = .raster(surface)
    return try d.convertingMode(.init(mode: mode, depth: depth))
  }
  func testNative86AndLegacyLayoutsPreserveEveryModeDepthAndProfile() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let d = try fixture(depth, mode)
      for version in [46, 85, 86] {
        let bytes = try NativeArchive.encodeChunked(d, minimumVersion: version)
        XCTAssertEqual(try NativeArchive.decode(bytes), d)
        XCTAssertEqual(try NativeArchive.decodePaged(bytes), d)
        XCTAssertEqual(try NativeArchive.dimensions(bytes).width, 65)
        if version == 86 {
          let (metadata, _) = try NativeChunkedArchive.manifest(count: bytes.count) { bytes.subdata(in: $0..<$0 + $1) }
          let object = String(describing: try PropertyListSerialization.propertyList(from: metadata, format: nil))
          XCTAssertTrue(object.contains("componentPages")); XCTAssertFalse(object.contains("planeBlobs"))
        }
      }
    } }
  }
  func testFileAndRecoveryReopenRetainMappedWordsAfterFileRemoval() throws {
    let d = try fixture(.f32), folder = try NativeIndexedArchiveTests().temporary(), url = folder.appendingPathComponent("component.photato")
    defer { try? FileManager.default.removeItem(at: folder) }
    try NativeArchive.write(d, to: url)
    let bytes = try Data(contentsOf: url)
    XCTAssertTrue(bytes.starts(with: NativeIndexedArchive.containerHeader(86)))
    let reopened = try NativeArchive.readPaged(url)
    XCTAssertEqual(reopened, d)
    let file = try AtomicFileWriter(to: url)
    try NativeIndexedArchive.write(d, output: .init(file: file, maximumBytes: NativeArchive.maximumBytes), recoveryContext: Data("owned context".utf8), minimumVersion: 86)
    try file.commit()
    let recovery = try NativeArchive.readRecoveryPaged(url)
    XCTAssertEqual(recovery.document, d); XCTAssertEqual(recovery.context, Data("owned context".utf8))
    try FileManager.default.removeItem(at: url)
    XCTAssertEqual(reopened.layers[0].nativeMode, d.layers[0].nativeMode)
    XCTAssertEqual(reopened.layers[0].nativeMode?.rawWord(component: 0, index: 4224), 1)
  }
  func testHistorySnapshotAndUndoKeepOwnedRawComponents() throws {
    let folder = try NativeIndexedArchiveTests().temporary(); defer { try? FileManager.default.removeItem(at: folder) }
    let d = try fixture(.u16, .cmyk), store = try HistoryScratchStore(parent: folder, limit: 2_000_000)
    let snapshot = try HistorySnapshot(d, store: store)
    let metadata = String(describing: try PropertyListSerialization.propertyList(from: snapshot.metadata.read(), format: nil))
    XCTAssertTrue(metadata.contains("componentPages")); XCTAssertFalse(metadata.contains("planeBlobs"))
    XCTAssertEqual(try snapshot.restore(), d)
    var session = EditorSession(document: try snapshot.restore())
    let id = try XCTUnwrap(d.activeLayerID)
    try session.execute(.opacity(id, 0.5)); try session.undo(); XCTAssertEqual(session.document, d)
    try session.redo(); XCTAssertEqual(session.document.layers[0].nativeMode, d.layers[0].nativeMode)
  }
  func testPagedScratchAndOwnedHeapBudgetsRejectWithoutChangingSource() throws {
    let d = try fixture(.f32), bytes = try NativeArchive.encodeChunked(d, minimumVersion: 86)
    XCTAssertThrowsError(try NativeArchive.decodePaged(bytes, heapByteLimit: 1))
    XCTAssertThrowsError(try NativeArchive.decodePaged(bytes, scratchByteLimit: 1))
    XCTAssertThrowsError(try NativeArchive.decode(bytes, rasterByteLimit: 1))
    XCTAssertEqual(try NativeArchive.decodePaged(bytes), d)
  }
  func testMixedLegacyPagesAndWrongContextsReject() throws {
    let raster = try XCTUnwrap(fixture(.f32).layers[0].nativeMode), context = ComponentArchiveTestContext()
    let encoder = PropertyListEncoder(); encoder.userInfo[.historyTileEncoder] = context
    let data = try encoder.encode(raster)
    XCTAssertThrowsError(try PropertyListDecoder().decode(NativeModeRaster.self, from: data))
    let decoder = PropertyListDecoder(); decoder.userInfo[.historyTileDecoder] = context
    var object = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    object["planes"] = try raster.planes
    XCTAssertThrowsError(try decoder.decode(NativeModeRaster.self, from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)))
    object.removeValue(forKey: "planes"); object["planeBlobs"] = ["b0"]
    XCTAssertThrowsError(try decoder.decode(NativeModeRaster.self, from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)))
    object.removeValue(forKey: "planeBlobs"); var pages = try XCTUnwrap(object["componentPages"] as? [[String: Any]])
    pages[0]["width"] = 64; object["componentPages"] = pages
    XCTAssertThrowsError(try decoder.decode(NativeModeRaster.self, from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)))
    context.supportsComponentPages = false
    XCTAssertThrowsError(try decoder.decode(NativeModeRaster.self, from: data))
  }
}
