import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class PatternWorkflowTests: XCTestCase {
  func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "photato-pattern-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor func testInstallRenameDeleteAndLibraryReloadPreservePixelsAndSelection() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Patterns.pclibrary")
    let library = PatternLibrary(persistenceURL: url)
    let tile = try RasterPattern(
      name: "Custom",
      surface: Surface(width: 3, height: 2, depth: .f32, fill: Pixel(0.12345679, 1.5, -0.1, 0.75)))
    try await library.install([tile])
    XCTAssertEqual(library.selected, tile)
    try await library.rename(tile.id, to: "Renamed")
    XCTAssertEqual(library.selected?.id, tile.id)
    let restored = PatternLibrary(persistenceURL: url)
    await restored.loadTask?.value
    XCTAssertNil(restored.error)
    XCTAssertEqual(restored.items, library.items)
    XCTAssertEqual(restored.selectedID, tile.id)
    XCTAssertEqual(restored.selected?.surface, tile.surface)
    try await library.remove(tile.id)
    XCTAssertFalse(library.items.contains { $0.id == tile.id })
    XCTAssertEqual(try PatternArchive.decode(Data(contentsOf: url)), library.items)
  }
  @MainActor func testCorruptAndUnwritablePersistenceNeverReplaceLibrary() async throws {
    let folder = try temporary()
    defer { try? FileManager.default.removeItem(at: folder) }
    let corrupt = folder.appendingPathComponent("Corrupt.pclibrary")
    let data = Data([1, 2, 3, 4])
    try data.write(to: corrupt)
    let library = PatternLibrary(persistenceURL: corrupt)
    await library.loadTask?.value
    XCTAssertNotNil(library.error)
    let before = library.items
    do {
      try await library.remove(before[0].id)
      XCTFail("Expected preserved corrupt file")
    } catch {}
    XCTAssertEqual(library.items, before)
    XCTAssertEqual(try Data(contentsOf: corrupt), data)
    let blocked = PatternLibrary(persistenceURL: corrupt.appendingPathComponent("Nested.pclibrary"))
    let original = blocked.items
    do {
      try await blocked.rename(original[0].id, to: "Failed write")
      XCTFail("Expected write failure")
    } catch {}
    XCTAssertEqual(blocked.items, original)
    XCTAssertFalse(blocked.busy)
  }
  @MainActor func testDefinePatternIsGlobalPresetOperationAndCancellationLeavesDocumentAlone()
    async throws
  {
    let library = PatternLibrary()
    var doc = try CraftDocument(width: 12, height: 8, depth: .u16)
    doc.layers[0].content = .raster(
      try Surface(width: 12, height: 8, depth: .u16, fill: Pixel(0.2, 0.4, 0.6)))
    doc.selection = .init(x: 2, y: 1, width: 4, height: 3)
    let store = EditorStore(document: doc, patterns: library)
    defer { store.renderTask?.cancel() }
    let count = library.items.count
    store.definePattern(name: "From selection")
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertFalse(store.geometryBusy)
    XCTAssertEqual(library.items.count, count + 1)
    XCTAssertEqual(library.selected?.surface.width, 4)
    XCTAssertEqual(library.selected?.surface.height, 3)
    XCTAssertEqual(store.document, doc)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertTrue(store.bucketUsesPattern)
    store.definePattern(name: "Cancelled")
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(library.items.count, count + 1)
    XCTAssertEqual(store.document, doc)
  }
  @MainActor func testBucketCapturesSelectedPatternAndFilledDocumentDoesNotDependOnLibrary()
    async throws
  {
    let library = PatternLibrary()
    var tile = try Surface(width: 2, height: 1, fill: Pixel(1, 0, 0))
    tile.setPixel(x: 1, y: 0, Pixel(0, 0, 1))
    let pattern = try RasterPattern(name: "Red Blue", surface: tile)
    try await library.install([pattern])
    var doc = try CraftDocument(width: 12, height: 8)
    doc.layers[0].content = .raster(try Surface(width: 12, height: 8, fill: .white))
    let store = EditorStore(document: doc, patterns: library)
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    store.bucketUsesPattern = true
    store.bucketOptions.match.antiAlias = false
    store.colorRegionClick(at: .init(2, 2))
    library.selectedID = library.items[0].id
    store.bucketUsesPattern = false
    try await library.remove(pattern.id)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count, 1)
    guard case .raster(let pixels) = store.activeLayer?.content else {
      return XCTFail("Expected raster")
    }
    for x in 0..<12 {
      XCTAssertEqual(pixels.pixel(x: x, y: 4), x % 2 == 0 ? Pixel(1, 0, 0) : Pixel(0, 0, 1))
    }
    let filled = store.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(filled)), filled)
    await store.undo()
    XCTAssertEqual(store.document, doc)
    await store.redo()
    XCTAssertEqual(store.document, filled)
  }
  @MainActor func testEmptyLibraryDoesNotFallThroughToForegroundAndCancelledSaveIsAtomic()
    async throws
  {
    let library = PatternLibrary()
    for pattern in library.items { try await library.remove(pattern.id) }
    let doc = try CraftDocument(width: 4, height: 4)
    let store = EditorStore(document: doc, patterns: library)
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    store.bucketUsesPattern = true
    store.colorRegionClick(at: .init(1, 1))
    XCTAssertNotNil(store.error)
    XCTAssertEqual(store.document, doc)
    XCTAssertFalse(store.geometryBusy)
    let pattern = try PatternPresets.make()[0]
    let task = Task { @MainActor in
      do {
        try await library.install([pattern])
        XCTFail("Expected cancellation")
      } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
    task.cancel()
    await task.value
    XCTAssertTrue(library.items.isEmpty)
  }
}
