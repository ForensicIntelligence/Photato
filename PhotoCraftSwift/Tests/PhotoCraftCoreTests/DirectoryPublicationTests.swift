import Darwin
import Foundation
import XCTest
@testable import PhotoCraftCore

final class DirectoryPublicationTests: XCTestCase {
  func testCommitFlushesTheRetainedDirectoryAfterRenameIncludingSearchOnlyFolders() throws {
    for permissions: mode_t in [0o700, 0o300] {
      let folder = try AtomicFileWriterTests().directory()
      defer { chmod(folder.path, 0o700); try? FileManager.default.removeItem(at: folder) }
      let target = folder.appendingPathComponent("owned-output")
      try Data([9]).write(to: target)
      XCTAssertEqual(chmod(folder.path, permissions), 0)
      var events: [String] = [], publishedDirectory: Int32?
      var operations = AtomicFileWriter.Operations()
      operations.synchronize = { fd in
        var value = stat(); XCTAssertEqual(fstat(fd, &value), 0)
        XCTAssertEqual(value.st_mode & S_IFMT, S_IFREG)
        events.append("file"); return Darwin.fsync(fd)
      }
      operations.fullSynchronize = { fd in events.append("full"); return Darwin.fcntl(fd, F_FULLFSYNC) }
      let rename = operations.rename
      operations.rename = { fd, from, to in
        events.append("rename"); publishedDirectory = fd
        return rename(fd, from, to)
      }
      operations.synchronizeDirectory = { fd in
        XCTAssertEqual(fd, publishedDirectory)
        var value = stat(); XCTAssertEqual(fstat(fd, &value), 0)
        XCTAssertEqual(value.st_mode & S_IFMT, S_IFDIR)
        XCTAssertEqual(try? Data(contentsOf: target), Data([1, 2, 3]))
        events.append("directory"); return Darwin.fsync(fd)
      }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      try writer.append(Data([1, 2, 3])); try writer.commit()
      XCTAssertEqual(events, ["file", "full", "rename", "directory"])
      XCTAssertTrue(writer.isPublished)
      XCTAssertTrue(writer.directorySynchronized)
      XCTAssertEqual(try Data(contentsOf: target), Data([1, 2, 3]))
    }
  }

  func testDirectoryErrorsReportPublishedBytesWithoutRollbackOrUnsupportedFallback() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for existing in [false, true] {
      for code in [EIO, ENOSPC, EDQUOT, EACCES, EINVAL, ENOTSUP, ENOSYS] {
        let target = folder.appendingPathComponent("output-\(existing)-\(code)")
        if existing { try Data([9]).write(to: target) }
        var directoryFD: Int32 = -1, calls = 0
        var operations = AtomicFileWriter.Operations()
        operations.synchronizeDirectory = { fd in
          directoryFD = fd; calls += 1; errno = code; return -1
        }
        var writer: AtomicFileWriter? = try AtomicFileWriter(to: target, operations: operations)
        try writer!.append(Data([1, 2, 3]))
        XCTAssertThrowsError(try writer!.commit()) { error in
          guard let failure = error as? AtomicFileWriter.PublicationFailure else {
            return XCTFail("Unexpected error: \(error)")
          }
          XCTAssertTrue(failure.filePublished)
          XCTAssertEqual(failure.posixCode, code)
          let value = error as NSError
          XCTAssertEqual(value.domain, AtomicFileWriter.PublicationFailure.errorDomain)
          XCTAssertEqual(value.code, Int(code))
          XCTAssertEqual(value.userInfo["PhotatoFilePublished"] as? Bool, true)
          XCTAssertEqual(value.userInfo["PhotatoDirectorySynchronized"] as? Bool, false)
          XCTAssertEqual((value.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain, NSPOSIXErrorDomain)
          XCTAssertEqual((value.userInfo[NSUnderlyingErrorKey] as? NSError)?.code, Int(code))
          XCTAssertTrue(value.localizedDescription.contains("unconfirmed"))
        }
        XCTAssertTrue(writer!.isPublished)
        XCTAssertFalse(writer!.directorySynchronized)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fcntl(directoryFD, F_GETFD), -1)
        XCTAssertEqual(errno, EBADF)
        XCTAssertThrowsError(try writer!.commit())
        writer!.discard(); writer = nil
        XCTAssertEqual(try Data(contentsOf: target), Data([1, 2, 3]))
      }
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 14)
  }

  func testDirectorySynchronizationRetriesInterruptionsAndClosesDescriptor() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    var calls = 0, directoryFD: Int32 = -1
    var operations = AtomicFileWriter.Operations()
    operations.synchronizeDirectory = { fd in
      calls += 1; directoryFD = fd
      if calls < 3 { errno = EINTR; return -1 }
      return Darwin.fsync(fd)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2])); try writer.commit()
    XCTAssertEqual(calls, 3)
    XCTAssertTrue(writer.isPublished)
    XCTAssertTrue(writer.directorySynchronized)
    XCTAssertEqual(fcntl(directoryFD, F_GETFD), -1)
    XCTAssertEqual(errno, EBADF)
    XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
  }

  func testCancellationAfterRenameStillFinishesInterruptedDirectorySynchronization() async throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output")
    try Data([9]).write(to: target)
    let task = Task {
      var calls = 0
      var operations = AtomicFileWriter.Operations()
      operations.synchronizeDirectory = { fd in
        calls += 1
        if calls == 1 {
          withUnsafeCurrentTask { $0?.cancel() }
          errno = EINTR; return -1
        }
        return Darwin.fsync(fd)
      }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      defer { writer.discard() }
      try writer.append(Data([1, 2])); try writer.commit()
      return (calls, Task.isCancelled, writer.isPublished, writer.directorySynchronized)
    }
    let result = try await task.value
    XCTAssertEqual(result.0, 2)
    XCTAssertTrue(result.1)
    XCTAssertTrue(result.2)
    XCTAssertTrue(result.3)
    XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output"])
  }

  func testPublicationSynchronizesRetainedDirectoryWhenItsPathMovesAfterValidation() throws {
    let root = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let parent = root.appendingPathComponent("parent"), moved = root.appendingPathComponent("moved")
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    let target = parent.appendingPathComponent("output")
    try Data([9]).write(to: target)
    var original = stat(); XCTAssertEqual(stat(parent.path, &original), 0)
    var operations = AtomicFileWriter.Operations()
    let rename = operations.rename
    operations.rename = { fd, from, to in
      let result = rename(fd, from, to)
      guard result == 0 else { return result }
      do {
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try Data([77]).write(to: target)
      } catch { XCTFail("Owned path move failed: \(error)") }
      return 0
    }
    var synchronized = false
    operations.synchronizeDirectory = { fd in
      var current = stat(); XCTAssertEqual(fstat(fd, &current), 0)
      XCTAssertEqual(current.st_dev, original.st_dev)
      XCTAssertEqual(current.st_ino, original.st_ino)
      XCTAssertEqual(try? Data(contentsOf: moved.appendingPathComponent("output")), Data([1, 2]))
      XCTAssertEqual(try? Data(contentsOf: target), Data([77]))
      synchronized = true; return Darwin.fsync(fd)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2])); try writer.commit()
    XCTAssertTrue(synchronized)
    XCTAssertTrue(writer.directorySynchronized)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["output"])
    XCTAssertEqual(try Data(contentsOf: target), Data([77]))
  }

  func testStreamedArchiveDirectoryFailureRetainsDecodablePublishedVersionAndCanRetry() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("recovery")
    let original = try CraftDocument(width: 4, height: 3)
    var changed = original; changed.name = "Newer edits"
    try NativeArchive.write(original, to: target)
    var operations = AtomicFileWriter.Operations()
    operations.synchronizeDirectory = { _ in errno = EIO; return -1 }
    XCTAssertThrowsError(try NativeArchive.write(changed, to: target) {
      try AtomicFileWriter(to: $0, maximumBytes: $1, operations: operations)
    }) { XCTAssertTrue($0 is AtomicFileWriter.PublicationFailure) }
    XCTAssertEqual(try NativeArchive.read(target), changed)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["recovery"])
    try NativeArchive.write(changed, to: target)
    XCTAssertEqual(try NativeArchive.read(target), changed)
  }
}
