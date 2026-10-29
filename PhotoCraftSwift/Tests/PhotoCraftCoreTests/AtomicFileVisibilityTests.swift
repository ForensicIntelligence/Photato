import Darwin
import Foundation
import XCTest

@testable import PhotoCraftCore

final class AtomicFileVisibilityTests: XCTestCase {
  func flags(_ url: URL) throws -> UInt32 {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return value.st_flags
  }

  func testPrivateStagingVisibilityDoesNotHidePublishedDocument() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("visible.psd")
    let writer = try AtomicFileWriter(to: target)
    let bytes = Data([56, 66, 80, 83, 1, 2, 3])
    try writer.append(bytes)
    let staged = folder.appendingPathComponent(
      try AtomicPersistenceFaultTests().privateName(folder))
    // Reproduce the flag observed on File Provider's dot-prefixed staging file.
    XCTAssertEqual(chflags(staged.path, UInt32(UF_HIDDEN | UF_NODUMP)), 0)
    try writer.commit()
    XCTAssertEqual(try Data(contentsOf: target), bytes)
    XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
    XCTAssertNotEqual(try flags(target) & UInt32(UF_NODUMP), 0)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["visible.psd"])
  }

  func testReplacementPreservesDestinationVisibilityThroughSymlink() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for hidden in [false, true] {
      let target = folder.appendingPathComponent(hidden ? "hidden.psd" : "visible.psd")
      try Data([9]).write(to: target)
      XCTAssertEqual(chflags(target.path, hidden ? UInt32(UF_HIDDEN) : 0), 0)
      let link = folder.appendingPathComponent(target.lastPathComponent + "-link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      let writer = try AtomicFileWriter(to: link)
      try writer.append(Data([1, 2]))
      let staged = folder.appendingPathComponent(
        try AtomicPersistenceFaultTests().privateName(folder))
      XCTAssertEqual(chflags(staged.path, hidden ? 0 : UInt32(UF_HIDDEN)), 0)
      try writer.commit()
      XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
      XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), hidden ? UInt32(UF_HIDDEN) : 0)
      XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
  }

  func testVisibilityRetriesInterruptionsBeforeSynchronizationAndPublication() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output.psd")
    var events: [String] = []
    var operations = AtomicFileWriter.Operations()
    operations.setFlags = { fd, flags in
      events.append("flags")
      if events.count == 1 { errno = EINTR; return -1 }
      return Darwin.fchflags(fd, flags)
    }
    operations.synchronize = { fd in
      events.append("sync")
      return Darwin.fsync(fd)
    }
    operations.fullSynchronize = { fd in
      events.append("full")
      return Darwin.fcntl(fd, F_FULLFSYNC)
    }
    let rename = operations.rename
    operations.rename = { fd, from, to in
      events.append("rename")
      return rename(fd, from, to)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2]))
    let staged = folder.appendingPathComponent(try AtomicPersistenceFaultTests().privateName(folder))
    XCTAssertEqual(chflags(staged.path, UInt32(UF_HIDDEN)), 0)
    try writer.commit()
    XCTAssertEqual(events, ["flags", "flags", "sync", "full", "rename"])
    XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
    XCTAssertEqual(try Data(contentsOf: target), Data([1, 2]))
  }

  func testVisibilityErrorsPreserveOriginalAndCleanUpStaging() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output.psd")
    for code in [EIO, EACCES, ENOTSUP] {
      try Data([9]).write(to: target)
      XCTAssertEqual(chflags(target.path, 0), 0)
      var operations = AtomicFileWriter.Operations()
      operations.setFlags = { _, _ in errno = code; return -1 }
      operations.synchronize = { _ in XCTFail("Synchronized after flag failure"); return 0 }
      operations.rename = { _, _, _ in XCTFail("Published after flag failure"); return 0 }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      try writer.append(Data([1, 2]))
      let staged = folder.appendingPathComponent(try AtomicPersistenceFaultTests().privateName(folder))
      XCTAssertEqual(chflags(staged.path, UInt32(UF_HIDDEN)), 0)
      XCTAssertThrowsError(try writer.commit()) {
        XCTAssertEqual(($0 as NSError).domain, NSPOSIXErrorDomain)
        XCTAssertEqual(($0 as NSError).code, Int(code))
      }
      XCTAssertThrowsError(try writer.commit())
      writer.discard()
      XCTAssertEqual(try Data(contentsOf: target), Data([9]))
      XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output.psd"])
    }
  }

  func testMatchingVisibilityDoesNotRequireFlagSupportAndDotNamesRemainHidden() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["visible.psd", ".hidden-by-name.psd"] {
      let target = folder.appendingPathComponent(name)
      var operations = AtomicFileWriter.Operations()
      operations.setFlags = { _, _ in XCTFail("Unnecessary flag mutation"); errno = ENOTSUP; return -1 }
      let writer = try AtomicFileWriter(to: target, operations: operations)
      try writer.append(Data([1, 2]))
      let staged = folder.appendingPathComponent(try AtomicPersistenceFaultTests().privateName(folder))
      XCTAssertEqual(chflags(staged.path, 0), 0)
      try writer.commit()
      XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
      XCTAssertEqual(try target.resourceValues(forKeys: [.isHiddenKey]).isHidden, name.hasPrefix("."))
    }
  }

  func testConcurrentDestinationVisibilityChangeRejectsReplacement() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output.psd")
    try Data([9]).write(to: target)
    XCTAssertEqual(chflags(target.path, 0), 0)
    let writer = try AtomicFileWriter(to: target)
    try writer.append(Data([1, 2]))
    XCTAssertEqual(chflags(target.path, UInt32(UF_HIDDEN)), 0)
    XCTAssertThrowsError(try writer.commit())
    writer.discard()
    XCTAssertEqual(try Data(contentsOf: target), Data([9]))
    XCTAssertNotEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output.psd"])
  }

  func testStagingVisibilityChangedDuringSynchronizationRejectsPublication() throws {
    let folder = try AtomicFileWriterTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("output.psd")
    try Data([9]).write(to: target)
    XCTAssertEqual(chflags(target.path, 0), 0)
    var operations = AtomicFileWriter.Operations()
    operations.synchronize = { fd in
      XCTAssertEqual(Darwin.fchflags(fd, UInt32(UF_HIDDEN)), 0)
      return Darwin.fsync(fd)
    }
    let writer = try AtomicFileWriter(to: target, operations: operations)
    try writer.append(Data([1, 2]))
    XCTAssertThrowsError(try writer.commit())
    writer.discard()
    XCTAssertEqual(try Data(contentsOf: target), Data([9]))
    XCTAssertEqual(try flags(target) & UInt32(UF_HIDDEN), 0)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["output.psd"])
  }
}
