import Foundation
import XCTest
@testable import PhotoCraftCore

final class ComponentPlaneTests: XCTestCase {
  func testMaximumGeometryAndSparseEditsAtEveryDepth() throws {
    for (depth, fill): (PixelDepth, UInt32) in [(.u8, 203), (.u16, 60001), (.f32, Float(-3.5).bitPattern)] {
      let source = try ComponentPlane(width: 300000, height: 300000, depth: depth, defaultWord: fill)
      XCTAssertEqual(source.count, 90_000_000_000); XCTAssertEqual(source.residentEditBytes, 0)
      XCTAssertEqual(source.word(at: 0), fill); XCTAssertEqual(source.word(at: source.count - 1), fill)
      var edited = source
      try edited.setWord(0, at: source.count - 1)
      XCTAssertEqual(source.word(at: source.count - 1), fill); XCTAssertEqual(edited.word(at: source.count - 1), 0)
      XCTAssertEqual(edited.storedBlockCount, 1); XCTAssertLessThan(edited.residentEditBytes, 20000)
      XCTAssertEqual(edited.word(at: source.count - 2), fill)
      XCTAssertThrowsError(try edited.setWord(0, at: source.count)); XCTAssertThrowsError(try edited.setWord(0, at: -1))
      XCTAssertEqual(edited.word(at: source.count - 2), fill)
    }
    XCTAssertThrowsError(try ComponentPlane(width: 300001, height: 1, depth: .u8))
    XCTAssertThrowsError(try ComponentPlane(width: Int.max, height: Int.max, depth: .f32))
    XCTAssertThrowsError(try ComponentPlane(width: 0, height: 10, depth: .u16))
  }
  func testRawRowsKeepLiteralIntegerAndFloatBitsAcrossBlocks() throws {
    let words: [UInt32] = [0, 1, 0x7fffff, 0x80000000, 0x3f800001, 0xc2fa0000, 0x7f7fffff]
    var plane = try ComponentPlane(width: 8201, height: 2, depth: .f32)
    let bytes = words.reduce(into: Data()) { data, value in
      for shift in [0, 8, 16, 24] { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    try plane.writeRow(0, x: 4093, bytes: bytes)
    XCTAssertEqual(try plane.row(0, x: 4093, count: words.count), bytes)
    for (i, word) in words.enumerated() { XCTAssertEqual(plane.word(at: 4093 + i), word) }
    XCTAssertEqual(plane.word(at: 4092), 0); XCTAssertEqual(plane.word(at: 4100), 0)
    var sixteen = try ComponentPlane(width: 8201, height: 1, depth: .u16, defaultWord: 9)
    let source = Data([42, 0x34, 0x12, 0xff, 0xff, 0x00, 0x80, 42])
    try sixteen.writeRow(0, x: 4095, bytes: source[1..<7])
    XCTAssertEqual(try sixteen.row(0, x: 4094, count: 5), Data([9, 0, 0x34, 0x12, 0xff, 0xff, 0, 0x80, 9, 0]))
    try capture("raw-float-row", bytes)
    try capture("raw-u16-row", sixteen.row(0, x: 4094, count: 5))
  }
  func testInvalidRowsAreAtomicAndPreserveSignedZero() throws {
    var p = try ComponentPlane(width: 10000, height: 1, depth: .f32, defaultWord: 0x80000000)
    let old = p
    XCTAssertThrowsError(try p.writeRow(0, bytes: Data([0, 0, 128, 63, 0, 0, 128, 127])))
    XCTAssertEqual(p, old); XCTAssertEqual(p.residentEditBytes, 0)
    XCTAssertThrowsError(try p.writeRow(0, x: 9999, bytes: Data(count: 8)))
    XCTAssertThrowsError(try p.writeRow(-1, bytes: Data()))
    XCTAssertThrowsError(try p.writeRow(0, bytes: Data([0])))
    XCTAssertEqual(p, old)
    try p.setWord(0, at: 3)
    XCTAssertNotEqual(p, old); XCTAssertEqual(old.word(at: 3), 0x80000000)
    XCTAssertEqual(p.word(at: 3), 0)
    XCTAssertThrowsError(try ComponentPlane(width: 1, height: 1, depth: .f32, defaultWord: Float.nan.bitPattern))
    XCTAssertThrowsError(try ComponentPlane(width: 1, height: 1, depth: .u8, defaultWord: 256))
    XCTAssertThrowsError(try ComponentPlane(width: 1, height: 1, depth: .u16, defaultWord: 65536))
    XCTAssertEqual(try p.row(0, x: 10000, count: 0), Data())
  }
  func testEqualityComparesLogicalBitsDespiteDifferentDefaultsAndPadding() throws {
    let a = try ComponentPlane(width: 5, height: 1, depth: .u16, defaultWord: 23)
    var b = try ComponentPlane(width: 5, height: 1, depth: .u16, defaultWord: 2)
    for i in 0..<5 { try b.setWord(23, at: i) }
    XCTAssertEqual(a, b)
    var partial = try ComponentPlane(width: 10000, height: 1, depth: .u16, defaultWord: 2)
    try partial.setWord(23, at: 0)
    XCTAssertNotEqual(try ComponentPlane(width: 10000, height: 1, depth: .u16, defaultWord: 23), partial)
    try b.setWord(24, at: 4); XCTAssertNotEqual(a, b)
  }
  func testMaximumFloatPlaneSpillRetainsBitsAndOnlyPromotesTouchedBlock() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("component-test-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    var source = try ComponentPlane(width: 300000, height: 300000, depth: .f32, defaultWord: Float(-2).bitPattern)
    try source.setWord(0x80000000, at: 0); try source.setWord(1, at: source.count - 1)
    let snapshot = try source.spilling(maximumBytes: 3_000_000, directory: folder)
    XCTAssertEqual(snapshot, source); XCTAssertEqual(snapshot.residentEditBytes, 0)
    XCTAssertGreaterThanOrEqual(snapshot.mappedVirtualBytes, 360_000_000_000)
    XCTAssertLessThan(snapshot.referencedScratchBytes, 3_000_000)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    source = try ComponentPlane(width: 1, height: 1, depth: .u8)
    XCTAssertEqual(snapshot.word(at: 0), 0x80000000); XCTAssertEqual(snapshot.word(at: snapshot.count - 1), 1)
    XCTAssertEqual(snapshot.word(at: snapshot.count - 2), Float(-2).bitPattern)
    var edited = snapshot; try edited.setWord(Float(10).bitPattern, at: snapshot.count - 2)
    XCTAssertEqual(snapshot.word(at: snapshot.count - 2), Float(-2).bitPattern)
    XCTAssertEqual(edited.word(at: edited.count - 2), Float(10).bitPattern)
    XCTAssertLessThan(edited.residentEditBytes, 20000)
    let again = try edited.spilling(maximumBytes: 3_000_000, directory: folder)
    XCTAssertEqual(again, edited); XCTAssertEqual(again.residentEditBytes, 0)
    try capture("max-plane-last-row", again.row(299999, x: 299996, count: 4))
  }
  func testScratchAdmissionIOFailureAndPublicationLifecycle() throws {
    var source = try ComponentPlane(width: 8192, height: 1, depth: .u8, defaultWord: 3)
    try source.setWord(4, at: 0); try source.setWord(5, at: 8191)
    let before = source
    XCTAssertThrowsError(try source.spilling(maximumBytes: 0)); XCTAssertEqual(source, before)
    XCTAssertThrowsError(try source.spilling(maximumBytes: Int(getpagesize()) + 4096)); XCTAssertEqual(source, before)
    XCTAssertThrowsError(try source.spilling(directory: URL(string: "https://example.invalid/scratch")!))
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertThrowsError(try source.spilling(directory: missing)); XCTAssertEqual(source, before)
    let writer = try ComponentPlaneWriter(plane: source, maximumBytes: Int(getpagesize()), directory: nil)
    XCTAssertThrowsError(try writer.write(key: 0, block: ComponentBlock(fill: 2, stride: 1)))
    XCTAssertThrowsError(try writer.finish())
    let done = try ComponentPlaneWriter(plane: source, maximumBytes: Int(getpagesize()), directory: nil)
    let mapping = try done.finish()
    XCTAssertFalse(mapping.contains(0)); XCTAssertFalse(mapping.contains(-1)); XCTAssertFalse(mapping.contains(2))
    XCTAssertThrowsError(try done.finish())
    XCTAssertThrowsError(try done.write(key: 0, block: ComponentBlock(fill: 2, stride: 1)))
  }
  func testCancellationDoesNotPublishOrMutate() async throws {
    let source = try ComponentPlane(width: 8192, height: 1, depth: .u16, defaultWord: 7)
    let task = Task.detached { () -> Bool in
      while !Task.isCancelled { await Task.yield() }
      var edited = source
      do { try edited.writeRow(0, bytes: Data(count: 16384)); return false } catch is CancellationError {} catch { return false }
      do { _ = try source.spilling(); return false } catch is CancellationError {} catch { return false }
      return edited == source && edited.residentEditBytes == 0
    }
    task.cancel(); let passed = await task.value; XCTAssertTrue(passed)
  }
  func testIndependentConcurrentBranchesRetainOriginalBlocks() async throws {
    var plane = try ComponentPlane(width: 300000, height: 300000, depth: .u16, defaultWord: 9)
    try plane.setWord(99, at: 0)
    let source = try plane.spilling(maximumBytes: 3_000_000)
    let outputs = try await withThrowingTaskGroup(of: (Int, ComponentPlane).self) { group in
      for i in 0..<32 { group.addTask { var copy = source; try copy.setWord(UInt32(i + 100), at: source.count - 1); return (i, copy) } }
      var values: [(Int, ComponentPlane)] = []; for try await value in group { values.append(value) }; return values
    }
    XCTAssertEqual(source.word(at: source.count - 1), 9); XCTAssertEqual(source.word(at: 0), 99)
    for (i, value) in outputs { XCTAssertEqual(value.word(at: value.count - 1), UInt32(i + 100)); XCTAssertEqual(value.word(at: 0), 99); XCTAssertLessThan(value.residentEditBytes, 12000) }
  }
  func testInkIntegrationKeepsLegacyBytesLimitsAndCheapUniformHistory() throws {
    let source = try InkPlane(width: 4096, height: 2048, depth: .u16, value: 0.5)
    XCTAssertEqual(source.residentSampleBytes, 0)
    let edited = try source.replacing(offset: 4095, values: [0, 1])
    XCTAssertLessThan(edited.residentSampleBytes, 20000)
    XCTAssertEqual(source.rawWord(at: 4095), 32768); XCTAssertEqual(source.rawWord(at: 4096), 32768)
    XCTAssertEqual(edited.rawWord(at: 4095), 0); XCTAssertEqual(edited.rawWord(at: 4096), 65535)
    XCTAssertThrowsError(try InkPlane(width: 4096, height: 2049, depth: .u16))
    let data = (0..<10007).reduce(into: Data()) { bytes, i in let v = UInt16(truncatingIfNeeded: i * 511); bytes.append(UInt8(truncatingIfNeeded: v)); bytes.append(UInt8(v >> 8)) }
    let exact = try InkPlane(width: 10007, height: 1, depth: .u16, bytes: data)
    XCTAssertEqual(exact.bytes, data)
    XCTAssertEqual(try JSONDecoder().decode(InkPlane.self, from: JSONEncoder().encode(exact)), exact)
    XCTAssertEqual(try exact.mapped { _, _, value in value }.bytes, data)
    try capture("ink-legacy-u16", exact.bytes)
  }
  private func capture(_ name: String, _ data: Data) throws {
    guard let folder = ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] else { return }
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".bin"), options: .withoutOverwriting)
  }
}
