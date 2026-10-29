import Darwin
import Foundation
import XCTest

@testable import PhotoCraftCore

final class AtomicPersistenceFaultTests: XCTestCase {
  func folder() throws -> URL { try AtomicFileWriterTests().directory() }
  func testWritableSearchableDirectoryDoesNotRequireListingPermission() throws {
    let folder = try folder()
    defer {
      chmod(folder.path, 0o700)
      try? FileManager.default.removeItem(at: folder)
    }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    XCTAssertEqual(chmod(folder.path, 0o300), 0)
    let writer = try AtomicFileWriter(to: target)
    try writer.append(Data([1, 2]))
    try writer.commit()
    XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
    XCTAssertEqual(chmod(folder.path, 0o700), 0)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
  }
  func privateName(_ folder: URL) throws -> String {
    try XCTUnwrap(
      FileManager.default.contentsOfDirectory(atPath: folder.path).first {
        $0.hasPrefix(".photato-save-")
      })
  }
  func testShortWritesAndInterruptedWritesProduceExactOutput() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    let bytes = Data((0..<70000).map { UInt8(truncatingIfNeeded: $0) })
    var calls = 0
    var operations = AtomicFileWriter.Operations()
    operations.write = { fd, pointer, count, offset in
      calls += 1
      if calls == 1 {
        errno = EINTR
        return -1
      }
      return Darwin.pwrite(fd, pointer, min(127, count), offset)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(bytes)
    try writer.commit()
    XCTAssertGreaterThan(calls, 500)
    XCTAssertEqual(try Data(contentsOf: target), bytes)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
  }
  func testPartialWriteFailuresAndZeroProgressNeverPublish() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    let old = Data([9, 8, 7])
    for code in [Int32(0), EIO, ENOSPC, EDQUOT] {
      try old.write(to: target)
      var calls = 0
      var operations = AtomicFileWriter.Operations()
      operations.write = { fd, pointer, count, offset in
        calls += 1
        if calls == 1 { return Darwin.pwrite(fd, pointer, min(2, count), offset) }
        errno = code
        return code == 0 ? 0 : -1
      }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      XCTAssertThrowsError(try writer.append(Data(repeating: 4, count: 20)))
      XCTAssertThrowsError(try writer.commit())
      writer.discard()
      XCTAssertEqual(try Data(contentsOf: target), old)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
    }
  }
  func testSynchronizationRetriesInterruptionsBeforePublication() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    var events: [String] = []
    var operations = AtomicFileWriter.Operations()
    operations.synchronize = { fd in
      events.append("sync")
      if events.count == 1 {
        errno = EINTR
        return -1
      }
      return Darwin.fsync(fd)
    }
    operations.fullSynchronize = { fd in
      events.append("full")
      if events.count == 3 {
        errno = EINTR
        return -1
      }
      return Darwin.fcntl(fd, F_FULLFSYNC)
    }
    let rename = operations.rename
    operations.rename = { fd, from, to in
      XCTAssertEqual(try? Data(contentsOf: target), Data([9]))
      events.append("rename")
      return rename(fd, from, to)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2]))
    try writer.commit()
    XCTAssertEqual(events, ["sync", "sync", "full", "full", "rename"])
    XCTAssertNotNil(writer.synchronization)
    XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
  }
  func testUnsupportedFullSyncFallsBackOnlyAfterSuccessfulFileSync() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    for code in [EINVAL, ENOTSUP, ENOSYS] {
      var synced = false
      var operations = AtomicFileWriter.Operations()
      operations.synchronize = { fd in
        synced = true
        return Darwin.fsync(fd)
      }
      operations.fullSynchronize = { _ in
        XCTAssertTrue(synced)
        errno = code
        return -1
      }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      try writer.append(Data([UInt8(truncatingIfNeeded: code)]))
      try writer.commit()
      XCTAssertEqual(writer.synchronization, .file)
      XCTAssertEqual(try Data(contentsOf: target), Data([UInt8(truncatingIfNeeded: code)]))
    }
  }
  func testRealSynchronizationErrorsDoNotFallBackOrPublish() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    let old = Data([9])
    for stage in ["sync", "full"] {
      for code in [EIO, ENOSPC, EDQUOT] {
        try old.write(to: target)
        var fullCalls = 0
        var renameCalls = 0
        var operations = AtomicFileWriter.Operations()
        if stage == "sync" {
          operations.synchronize = { _ in
            errno = code
            return -1
          }
        }
        operations.fullSynchronize = { _ in
          fullCalls += 1
          errno = code
          return -1
        }
        operations.rename = { _, _, _ in
          renameCalls += 1
          return 0
        }
        let writer = try AtomicFileWriter(to: target, operations: operations)
        try writer.append(Data([1, 2]))
        XCTAssertThrowsError(try writer.commit()) {
          XCTAssertEqual(($0 as NSError).code, Int(code))
        }
        XCTAssertThrowsError(try writer.commit())
        writer.discard()
        XCTAssertEqual(fullCalls, stage == "sync" ? 0 : 1)
        XCTAssertEqual(renameCalls, 0)
        XCTAssertEqual(try Data(contentsOf: target), old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
      }
    }
  }
  func testRenameFailurePreservesOriginalAndRemovesOwnedStaging() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    var operations = AtomicFileWriter.Operations()
    operations.rename = { _, _, _ in
      errno = EACCES
      return -1
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2]))
    XCTAssertThrowsError(try writer.commit()) { XCTAssertEqual(($0 as NSError).code, Int(EACCES)) }
    writer.discard()
    XCTAssertEqual(try Data(contentsOf: target), Data([9]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
  }
  func testMovedParentRejectsAndCleanupCannotFollowReplacementDirectory() throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let parent = root.appendingPathComponent("parent")
    let moved = root.appendingPathComponent("moved")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    let target = parent.appendingPathComponent("output")
    try Data([9]).write(to: target)
    let writer = try AtomicFileWriter(to: target)
    try writer.append(Data([1, 2]))
    let temporary = try privateName(parent)
    try FileManager.default.moveItem(at: parent, to: moved)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    try Data([77]).write(to: target)
    try Data([88]).write(to: parent.appendingPathComponent(temporary))
    XCTAssertThrowsError(try writer.commit())
    writer.discard()
    XCTAssertEqual(try Data(contentsOf: target), Data([77]))
    XCTAssertEqual(try Data(contentsOf: parent.appendingPathComponent(temporary)), Data([88]))
    XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("output")), Data([9]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["output"])
  }
  func testReplacedPrivateNameIsNeitherPublishedNorDeleted() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    for symlink in [false, true] {
      let writer = try AtomicFileWriter(to: target)
      try writer.append(Data([1, 2]))
      let temporary = folder.appendingPathComponent(try privateName(folder))
      try FileManager.default.removeItem(at: temporary)
      if symlink {
        try FileManager.default.createSymbolicLink(at: temporary, withDestinationURL: target)
      } else {
        try Data([88]).write(to: temporary)
      }
      XCTAssertThrowsError(try writer.commit())
      writer.discard()
      XCTAssertEqual(try Data(contentsOf: target), Data([9]))
      XCTAssertEqual(try Data(contentsOf: temporary), symlink ? Data([9]) : Data([88]))
      try FileManager.default.removeItem(at: temporary)
    }
  }
  func testCancellationDuringSynchronizationRejectsPublication() async throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    let task = Task {
      var operations = AtomicFileWriter.Operations()
      operations.fullSynchronize = { _ in
        withUnsafeCurrentTask { $0?.cancel() }
        return 0
      }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      defer { writer.discard() }
      try writer.append(Data([1, 2]))
      try writer.commit()
    }
    do {
      try await task.value
      XCTFail("Published cancellation")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(try Data(contentsOf: target), Data([9]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
  }
  func testStreamedNativeArchiveFailurePreservesDecodablePreviousVersion() throws {
    let folder = try folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("recovery")
    let original = try CraftDocument(width: 4, height: 3)
    var changed = original
    changed.name = "Newer edits"
    try NativeArchive.write(original, to: target)
    let bytes = try Data(contentsOf: target)
    for stage in ["write", "full", "rename"] {
      var operations = AtomicFileWriter.Operations()
      if stage == "write" {
        operations.write = { _, _, _, _ in
          errno = ENOSPC
          return -1
        }
      }
      if stage == "full" {
        operations.fullSynchronize = { _ in
          errno = EIO
          return -1
        }
      }
      if stage == "rename" {
        operations.rename = { _, _, _ in
          errno = EACCES
          return -1
        }
      }
      XCTAssertThrowsError(
        try NativeArchive.write(changed, to: target) {
          try AtomicFileWriter(to: $0, maximumBytes: $1, operations: operations)
        })
      XCTAssertEqual(try Data(contentsOf: target), bytes)
      XCTAssertEqual(try NativeArchive.read(target), original)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["recovery"])
    }
    try NativeArchive.write(changed, to: target)
    XCTAssertEqual(try NativeArchive.read(target), changed)
  }
}
