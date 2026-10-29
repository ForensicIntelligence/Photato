import Darwin
import Foundation
import XCTest

@testable import PhotoCraftCore

final class AtomicFileWriterTests: XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  func testBoundedWritesPatchesPermissionsAndSymlinkSave() throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("target")
    try Data("original".utf8).write(to: target)
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
    let link = folder.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let writer = try AtomicFileWriter(to: link)
    var expected = Data(repeating: 87, count: 200_000)
    try writer.append(expected)
    try writer.patch(Data([1, 2, 3, 4]), at: 65535)
    expected.replaceSubrange(65535..<65539, with: [1, 2, 3, 4])
    XCTAssertThrowsError(try writer.patch(Data([0]), at: -1))
    XCTAssertThrowsError(try writer.patch(Data([0]), at: Int.max))
    XCTAssertEqual(try Data(contentsOf: target), Data("original".utf8))
    try writer.commit()
    XCTAssertEqual(try Data(contentsOf: link), expected)
    XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    XCTAssertEqual(
      (try FileManager.default.attributesOfItem(atPath: target.path))[.posixPermissions] as? Int,
      0o640)
    XCTAssertEqual(writer.maximumWriteBytes, 65536)
    XCTAssertThrowsError(try writer.append(Data([0])))
    XCTAssertThrowsError(try writer.commit())
  }
  func testFailedOutputAndChangedDestinationNeverReplaceExistingContents() throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("target")
    let original = Data("original".utf8)
    try original.write(to: target)
    do {
      let writer = try AtomicFileWriter(to: target, maximumBytes: 4)
      try writer.append(Data([1, 2, 3]))
      XCTAssertThrowsError(try writer.append(Data([4, 5])))
      XCTAssertThrowsError(try writer.commit())
    }
    XCTAssertEqual(try Data(contentsOf: target), original)
    do {
      let writer = try AtomicFileWriter(to: target)
      try writer.append(Data([1, 2]))
      try Data("new external version".utf8).write(to: target, options: .atomic)
      XCTAssertThrowsError(try writer.commit())
    }
    XCTAssertEqual(try Data(contentsOf: target), Data("new external version".utf8))
    do {
      let missing = folder.appendingPathComponent("new")
      let writer = try AtomicFileWriter(to: missing)
      try writer.append(Data([1, 2]))
      try original.write(to: missing)
      XCTAssertThrowsError(try writer.commit())
      try FileManager.default.removeItem(at: missing)
    }
    XCTAssertThrowsError(try AtomicFileWriter(to: folder))
    XCTAssertThrowsError(try AtomicFileWriter(to: URL(string: "https://example.com")!))
    XCTAssertThrowsError(try AtomicFileWriter(to: folder.appendingPathComponent("missing/file")))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["target"])
  }
  func testCancelledTransactionDiscardsStagedBytes() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("target")
    try Data([9]).write(to: target)
    let task = Task {
      let writer = try AtomicFileWriter(to: target)
      try writer.append(Data(repeating: 4, count: 100000))
      withUnsafeCurrentTask { $0?.cancel() }
      try writer.commit()
    }
    do {
      try await task.value
      XCTFail("Committed cancelled save")
    } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    XCTAssertEqual(try Data(contentsOf: target), Data([9]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["target"])
  }
}
