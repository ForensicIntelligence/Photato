import Darwin
import Foundation
import XCTest

@testable import PhotoCraftCore

final class NativeArchiveReadRetryTests: XCTestCase {
  private func file() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("input.photato")
    try NativeArchive.write(CraftDocument(width: 3, height: 2), to: url)
    return url
  }
  private func changeAttributes(_ url: URL, attempt: Int) throws {
    let result = url.withUnsafeFileSystemRepresentation {
      chmod($0!, mode_t(attempt.isMultiple(of: 2) ? 0o600 : 0o640))
    }
    guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }
  func testAttributeChangeRestartsWholeReadWithFreshDescriptor() throws {
    let url = try file()
    let expected = try NativeArchive.read(url)
    let originalBytes = try Data(contentsOf: url)
    var attempts = 0
    let decoded = try NativeArchiveFileSource.withStableMetadata {
      attempts += 1
      let source = try NativeArchiveFileSource(url)
      let bytes = try source.read(at: 0, count: source.count)
      if attempts == 1 { try changeAttributes(url, attempt: attempts) }
      try source.validateUnchanged()
      return try NativeArchive.decode(bytes)
    }
    XCTAssertEqual(attempts, 2)
    XCTAssertEqual(decoded, expected)
    XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    XCTAssertEqual(try NativeArchive.read(url), expected)
  }
  func testRepeatedAttributeChangesStopAfterOneRetry() throws {
    let url = try file()
    var attempts = 0
    XCTAssertThrowsError(
      try NativeArchiveFileSource.withStableMetadata {
        attempts += 1
        let source = try NativeArchiveFileSource(url)
        _ = try source.read(at: 0, count: source.count)
        try changeAttributes(url, attempt: attempts)
        try source.validateUnchanged()
      }
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("changed while reading"))
    }
    XCTAssertEqual(attempts, 2)
  }
  func testReplacementAndContentChangesDoNotRetry() throws {
    for replacement in [false, true] {
      let url = try file()
      var attempts = 0
      XCTAssertThrowsError(
        try NativeArchiveFileSource.withStableMetadata {
          attempts += 1
          let source = try NativeArchiveFileSource(url)
          _ = try source.read(at: 0, count: source.count)
          if replacement {
            try Data(contentsOf: url).write(to: url, options: .atomic)
          } else {
            let file = try FileHandle(forWritingTo: url)
            try file.seekToEnd()
            try file.write(contentsOf: Data([42]))
            try file.close()
          }
          try source.validateUnchanged()
        })
      XCTAssertEqual(attempts, 1)
    }
  }
  func testIntegrityFailureIsNotRetried() throws {
    let url = try file()
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count - 1] ^= 1
    try bytes.write(to: url)
    var attempts = 0
    XCTAssertThrowsError(
      try NativeArchiveFileSource.withStableMetadata {
        attempts += 1
        return try NativeArchive.read(url)
      })
    XCTAssertEqual(attempts, 1)
  }
}
