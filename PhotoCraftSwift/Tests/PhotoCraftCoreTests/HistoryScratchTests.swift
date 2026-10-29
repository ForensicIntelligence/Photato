import Foundation
import XCTest

@testable import PhotoCraftCore

final class HistoryScratchTests: XCTestCase {
  func parent() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "HistoryTest-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func document() throws -> CraftDocument {
    var doc = try CraftDocument(width: 128, height: 65, depth: .f32)
    var pixels = try Surface(width: 128, height: 65, depth: .f32)
      .interpretingSamples(as: .linearRGB)
    let words: [UInt32] = [0x8000_0000, 1, 0x0080_0000, 0x3eaa_aaab, 0xc050_0000, 0x7f7f_ffff]
    for (x, word) in words.enumerated() {
      pixels.setLinearPixel(x: x, y: 0, Pixel(Float(bitPattern: word), -0.0, 4, 1))
      pixels.setLinearPixel(x: x + 64, y: 0, Pixel(Float(bitPattern: word), -0.0, 4, 1))
    }
    doc.layers[0].content = .raster(pixels)
    var mask = try Surface(width: doc.width, height: doc.height, depth: .u8, fill: .white)
    mask.setPixel(x: 64, y: 64, .clear)
    doc.layers[0].mask = mask
    doc.layers[0].sourceTags = ["test": Data([0, 127, 255])]
    doc.patterns = [try RasterPattern(name: "Exact", surface: pixels)]
    doc.selectionMask = try SelectionMask.make(
      .ellipse(.init(x: 2, y: 1, width: 70, height: 60)), width: doc.width, height: doc.height)
    doc.selection = doc.selectionMask?.bounds
    return doc
  }
  func assertSamples(
    _ actual: CraftDocument, _ expected: CraftDocument, file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    XCTAssertEqual(actual, expected, file: file, line: line)
    for (a, b) in zip(actual.layers, expected.layers) {
      if case .raster(let x) = a.content, case .raster(let y) = b.content {
        XCTAssertEqual(
          try x.rgbaData(depth: .f32, colorEncoding: .linearRGB),
          try y.rgbaData(depth: .f32, colorEncoding: .linearRGB), file: file, line: line)
      }
    }
  }
  func testSnapshotsRetainExactBitsMasksPatternsSelectionAndNativeEncoding() throws {
    let source = try document()
    let store = try HistoryScratchStore(parent: parent(), limit: 1_000_000)
    let snapshot = try HistorySnapshot(source, store: store)
    let restored = try snapshot.restore()
    try assertSamples(restored, source)
    XCTAssertEqual(try NativeArchive.encode(restored), try NativeArchive.encode(source))
    XCTAssertLessThan(store.allocatedBytes, source.estimatedBytes)
    let permissions =
      try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions]
      as? Int
    XCTAssertEqual(permissions, 0o700)
    for blob in snapshot.references.values {
      XCTAssertEqual(
        try FileManager.default.attributesOfItem(atPath: blob.url.path)[.posixPermissions] as? Int,
        0o600)
    }
    // Neither raster nor selection references can be decoded as a portable native file.
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: snapshot.metadata.read(), format: nil)
        as? [String: Any])
    let data = try PropertyListSerialization.data(
      fromPropertyList: XCTUnwrap(plist["document"]), format: .binary, options: 0)
    XCTAssertThrowsError(try PropertyListDecoder().decode(CraftDocument.self, from: data))
  }
  func testSpillingPreservesEveryUndoRedoAndIndependentValueBranch() throws {
    let original = try document()
    var session = EditorSession(
      document: original, historyByteLimit: 0, scratchParent: try parent())
    let id = try XCTUnwrap(original.activeLayerID)
    var states = [original]
    for i in 0..<8 {
      try session.execute(.opacity(id, Float(i + 1) / 10))
      states.append(session.document)
      XCTAssertEqual(session.residentHistoryBytes, 0)
    }
    XCTAssertEqual(session.historySpilledStates, 8)
    var branch = session
    for i in (0..<8).reversed() {
      try session.undo()
      try assertSamples(session.document, states[i])
    }
    for i in 1...8 {
      try session.redo()
      try assertSamples(session.document, states[i])
    }
    try branch.undo()
    try branch.execute(.renameLayer(id, "Branch"))
    XCTAssertTrue(branch.redoStack.isEmpty)
    XCTAssertEqual(session.document, states.last)
    XCTAssertEqual(session.undoStack.count, 8)
    XCTAssertEqual(branch.undoStack.count, 8)
  }
  func testPixelEditsSpillWithinPayloadBudgetAndKeepStateLimitAndCoalescing() throws {
    var doc = try CraftDocument(width: 64, height: 64)
    var pixels = try Surface(width: 64, height: 64)
    pixels.setPixel(x: 0, y: 0, .white)
    doc.layers[0].content = .raster(pixels)
    let id = try XCTUnwrap(doc.activeLayerID)
    var session = EditorSession(
      document: doc, historyLimit: 3, historyByteLimit: 70_000, scratchParent: try parent())
    for i in 1...5 {
      pixels.setPixel(x: i, y: 0, .white)
      try session.execute(.replaceContent(id, .raster(pixels)))
      XCTAssertLessThanOrEqual(session.residentHistoryBytes, 70_000)
    }
    XCTAssertEqual(session.undoStack.count, 3)
    XCTAssertGreaterThan(session.historySpilledStates, 0)
    session.beginCoalescing()
    for name in ["A", "B", "C"] { try session.execute(.renameLayer(id, name)) }
    session.endCoalescing()
    XCTAssertEqual(session.undoStack.count, 3)
    try session.undo()
    XCTAssertEqual(session.document.layers[0].name, doc.layers[0].name)
    try session.redo()
    XCTAssertEqual(session.document.layers[0].name, "C")
  }
  func testWriteBudgetAndUnavailableDirectoryRejectEditWithoutHistoryLoss() throws {
    let doc = try document()
    let id = try XCTUnwrap(doc.activeLayerID)
    let parent = try parent()
    for (limit, directory) in [(1, parent), (1_000_000, parent.appendingPathComponent("missing"))] {
      var session = EditorSession(
        document: doc, historyByteLimit: 0, historyDiskByteLimit: limit, scratchParent: directory)
      XCTAssertThrowsError(try session.execute(.renameLayer(id, "Rejected")))
      XCTAssertEqual(session.document, doc)
      XCTAssertTrue(session.undoStack.isEmpty)
      XCTAssertTrue(session.redoStack.isEmpty)
      XCTAssertEqual(session.historyDiskBytes, 0)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
  }
  func testCorruptMissingTruncatedAndSymlinkBlobsRejectRead() throws {
    let store = try HistoryScratchStore(parent: parent(), limit: 100_000)
    for kind in 0..<4 {
      let blob = try store.put(Data([1, 2, UInt8(kind), 4]))
      switch kind {
      case 0: try Data([1, 2, 9, 4]).write(to: blob.url)
      case 1: try Data([1]).write(to: blob.url)
      case 2: try FileManager.default.removeItem(at: blob.url)
      default:
        try FileManager.default.removeItem(at: blob.url)
        try FileManager.default.createSymbolicLink(
          at: blob.url, withDestinationURL: store.directory)
      }
      XCTAssertThrowsError(try blob.read())
    }
    XCTAssertEqual(store.allocatedBytes, 0)
  }
  func testRestoreAndValidationFailuresLeaveStacksAndDocumentUntouched() throws {
    let parent = try parent()
    let doc = try document()
    var session = EditorSession(document: doc, historyByteLimit: 0, scratchParent: parent)
    try session.execute(.opacity(try XCTUnwrap(doc.activeLayerID), 0.5))
    let before = session.document
    let bytes = session.historyDiskBytes
    XCTAssertThrowsError(
      try session.undo { _ in throw CraftError.invalid("Rejected restored state") })
    XCTAssertEqual(session.document, before)
    XCTAssertEqual(session.undoStack.count, 1)
    XCTAssertTrue(session.redoStack.isEmpty)
    let directory = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first)
    for url in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      var data = try Data(contentsOf: url)
      if !data.isEmpty {
        data[0] ^= 1
        try data.write(to: url)
      }
    }
    XCTAssertThrowsError(try session.undo())
    XCTAssertEqual(session.document, before)
    XCTAssertEqual(session.undoStack.count, 1)
    XCTAssertTrue(session.redoStack.isEmpty)
    XCTAssertEqual(session.historyDiskBytes, bytes)
  }
  func testBlobDeduplicationOwnershipAndCleanup() throws {
    let parent = try parent()
    var store: HistoryScratchStore? = try HistoryScratchStore(parent: parent, limit: 6)
    let directory = try XCTUnwrap(store?.directory)
    var first: HistoryScratchBlob? = try store?.put(Data([1, 2, 3]))
    var second: HistoryScratchBlob? = try store?.put(Data([1, 2, 3]))
    XCTAssertTrue(first === second)
    XCTAssertEqual(store?.allocatedBytes, 3)
    first = nil
    XCTAssertEqual(try second?.read(), Data([1, 2, 3]))
    store = nil
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    second = nil
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }
  func testCancellationNeverPublishesEditOrNavigation() async throws {
    let original = try document()
    var ready = EditorSession(document: original, historyByteLimit: 0, scratchParent: try parent())
    try ready.execute(.opacity(try XCTUnwrap(original.activeLayerID), 0.5))
    let source = ready
    let task = Task {
      var session = source
      withUnsafeCurrentTask { $0?.cancel() }
      XCTAssertThrowsError(try session.undo())
      XCTAssertThrowsError(try session.execute(.renameLayer(original.layers[0].id, "Cancelled")))
      XCTAssertEqual(session.document, source.document)
      XCTAssertEqual(session.undoStack.count, source.undoStack.count)
      XCTAssertTrue(session.redoStack.isEmpty)
    }
    try await task.value
  }
  func testConcurrentBlobLifetimesRemainValidAndAccounted() async throws {
    let store = try HistoryScratchStore(parent: parent(), limit: 1_000_000)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for seed in 0..<8 {
        group.addTask {
          for i in 0..<60 {
            let data = Data(repeating: UInt8((seed + i) % 3), count: 4096)
            let blob = try store.put(data)
            XCTAssertEqual(try blob.read(), data)
          }
        }
      }
      try await group.waitForAll()
    }
    XCTAssertEqual(store.allocatedBytes, 0)
    XCTAssertEqual(store.cleanupFailureCount, 0)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
  }
  func testBothActionJobAdaptersSharedEngineCanSpillAndRestore() throws {
    let doc = try CraftDocument(width: 4, height: 4)
    let session = EditorSession(document: doc, historyByteLimit: 0, scratchParent: try parent())
    let actions = """
      [{"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"red"}]},
       {"_obj":"fill","using":{"_enum":"fillContents","_value":"black"},"opacity":{"_unit":"percentUnit","_value":100},"mode":{"_enum":"blendMode","_value":"normal"}}]
      """
    let program = try PhotoshopActionProgram(actionJSON: actions)
    var result = try program.applying(to: session)
    XCTAssertEqual(result.session.historySpilledStates, 1)
    let output = result.session.document
    try result.session.undo()
    XCTAssertEqual(result.session.document, doc)
    try result.session.redo()
    XCTAssertEqual(result.session.document, output)
    XCTAssertEqual(session.document, doc)
  }

  func testAdjacentRestoresShareUnchangedTilesWithoutRetainingUnusedPayload() throws {
    let original = try document()
    let store = try HistoryScratchStore(parent: parent(), limit: 1_000_000)
    let first = try HistorySnapshot(original, store: store).restore(reusing: nil)
    var changed = original
    guard case .raster(var pixels) = changed.layers[0].content else { return XCTFail() }
    pixels.setLinearPixel(x: 0, y: 0, Pixel(7, 5, 4, 1))
    changed.layers[0].content = .raster(pixels)
    let second = try HistorySnapshot(changed, store: store).restore(reusing: first.tiles)
    try assertSamples(second.document, changed)
    var shared: Set<UInt> = []
    _ = first.document.accountHistoryMemory(&shared, includeMetadata: false)
    XCTAssertEqual(
      second.document.accountHistoryMemory(&shared, includeMetadata: false),
      TileArchive.byteCount, "Only the edited tile should need a new raster buffer")
    var current: Set<UInt> = []
    XCTAssertEqual(
      second.tiles.bytes, second.document.accountHistoryMemory(&current, includeMetadata: false),
      "Reuse must own exactly the current document's unique decoded buffers")

    var branch = second.document
    guard case .raster(var branchPixels) = branch.layers[0].content else { return XCTFail() }
    branchPixels.setLinearPixel(x: 64, y: 0, Pixel(9, 8, 7, 1))
    branch.layers[0].content = .raster(branchPixels)
    try assertSamples(first.document, original)
    try assertSamples(second.document, changed)
    let repeated = try HistorySnapshot(changed, store: store).restore(reusing: second.tiles)
    try assertSamples(repeated.document, changed)

    let blank = try CraftDocument(width: 128, height: 65)
    let empty = try HistorySnapshot(blank, store: store).restore(reusing: second.tiles)
    XCTAssertEqual(empty.tiles.bytes, 0, "The new index must discard all unreferenced old buffers")
    XCTAssertEqual(empty.document, blank)
  }

  func testCachedTileStillRejectsMissingOrCorruptScratchBlob() throws {
    for missing in [false, true] {
      let store = try HistoryScratchStore(parent: parent(), limit: 1_000_000)
      let original = try document()
      let snapshot = try HistorySnapshot(original, store: store)
      let restored = try snapshot.restore(reusing: nil)
      let digest = try XCTUnwrap(restored.tiles.tiles.keys.first)
      let blob = try XCTUnwrap(snapshot.references[digest])
      if missing {
        try FileManager.default.removeItem(at: blob.url)
      } else {
        var bytes = try Data(contentsOf: blob.url)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: blob.url)
      }
      XCTAssertThrowsError(try snapshot.restore(reusing: restored.tiles))
      try assertSamples(restored.document, original)
    }
  }

  func testSessionReuseLifetimeAndValidationRollback() throws {
    let original = try document()
    let id = try XCTUnwrap(original.activeLayerID)
    var session = EditorSession(document: original, historyByteLimit: 0, scratchParent: try parent())
    for name in ["First", "Second", "Third"] { try session.execute(.renameLayer(id, name)) }
    XCTAssertEqual(session.historyReusableCurrentRasterBytes, 0)
    try session.undo()
    let first = session.document
    let cached = session.historyReusableCurrentRasterBytes
    XCTAssertGreaterThan(cached, 0)
    XCTAssertThrowsError(try session.undo { _ in throw CraftError.invalid("Rejected") })
    XCTAssertEqual(session.document, first)
    XCTAssertEqual(session.historyReusableCurrentRasterBytes, cached)
    try session.undo()
    var shared: Set<UInt> = []
    _ = first.accountHistoryMemory(&shared, includeMetadata: false)
    XCTAssertEqual(session.document.accountHistoryMemory(&shared, includeMetadata: false), 0)
    XCTAssertEqual(session.historyReusableCurrentRasterBytes, cached)
    var branch = session
    try branch.execute(.renameLayer(id, "First"))  // No-op keeps the current reuse index.
    XCTAssertEqual(branch.historyReusableCurrentRasterBytes, cached)
    try branch.execute(.renameLayer(id, "New branch"))
    XCTAssertEqual(branch.historyReusableCurrentRasterBytes, 0)
    XCTAssertEqual(session.historyReusableCurrentRasterBytes, cached)
    try session.redo()
    XCTAssertEqual(session.document, first)
    XCTAssertEqual(session.residentHistoryBytes, 0)
  }

  func testConcurrentValueBranchesReuseTilesWithoutCrossBranchMutation() async throws {
    let original = try document()
    let id = try XCTUnwrap(original.activeLayerID)
    var ready = EditorSession(document: original, historyByteLimit: 0, scratchParent: try parent())
    for name in ["First", "Second", "Third"] { try ready.execute(.renameLayer(id, name)) }
    try ready.undo()
    let source = ready
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<4 {
        group.addTask {
          var branch = source
          for _ in 0..<6 { try branch.undo(); try branch.redo() }
          guard case .raster(var pixels) = branch.document.layers[0].content else {
            throw CraftError.invalid("Missing raster")
          }
          pixels.setLinearPixel(x: 0, y: 0, Pixel(Float(i + 8), 2, 3, 1))
          try branch.execute(.replaceContent(id, .raster(pixels)))
          XCTAssertEqual(branch.historyReusableCurrentRasterBytes, 0)
          try branch.undo()
          XCTAssertEqual(
            try NativeArchive.encode(branch.document), try NativeArchive.encode(source.document))
        }
      }
      try await group.waitForAll()
    }
    XCTAssertEqual(source.document.layers[0].name, "Second")
    XCTAssertEqual(source.undoStack.count, 2)
    XCTAssertEqual(source.redoStack.count, 1)
  }
}
