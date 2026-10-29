import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PcraftContainerTests: XCTestCase {
  private func fixture(_ name: String) throws -> Data {
    let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: root.appendingPathComponent("Pcraft").appendingPathComponent(name))
  }
  private func manifest() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("manifest.json")) as? [String: Any])
  }
  private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  func testOfficialBLAKE3VectorsAcrossChunkAndTreeBoundaries() throws {
    let vectors = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("blake3-vectors.json")) as? [[String: Any]])
    for vector in vectors {
      let length = try XCTUnwrap(vector["length"] as? Int)
      let input = Data((0..<length).map { UInt8($0 % 251) })
      XCTAssertEqual(try PcraftBLAKE3.hex(input), vector["hash"] as? String, "length \(length)")
      let slice = (Data([99]) + input).dropFirst()
      XCTAssertEqual(try PcraftBLAKE3.hash(slice), try PcraftBLAKE3.hash(input))
    }
  }
  func testOriginalRustBlobsMatchEveryByteAndBLAKE3Address() throws {
    let source = try XCTUnwrap(try manifest()["source"] as? [String: Any])
    let blobs = try XCTUnwrap(source["blobs"] as? [[String: Any]])
    XCTAssertEqual(blobs.count, 42)
    for blob in blobs {
      let name = try XCTUnwrap(blob["name"] as? String), length = try XCTUnwrap(blob["length"] as? Int)
      let pattern = try XCTUnwrap(Int(name.split(separator: "-").last!))
      let input = Data((0..<length).map { i -> UInt8 in
        if pattern == 0 { return 0 }
        if pattern == 1 { return UInt8(i % 251) }
        let value = UInt64(i) &* 0x9e3779b97f4a7c15 &+ 17, shift = i % 31
        let rotated = shift == 0 ? value : (value << shift) | (value >> (64 - shift))
        return UInt8(truncatingIfNeeded: rotated >> 43)
      })
      let decoded = try PcraftZstd.decode(fixture(name + ".zst"), limit: length, expectedBytes: length)
      XCTAssertEqual(decoded, input, name)
      XCTAssertEqual(try PcraftBLAKE3.hex(decoded), blob["blake3"] as? String, name)
    }
  }
  func testIndependentZstandardCLILevelsAndUnknownSizes() throws {
    let cases = try XCTUnwrap(try manifest()["cli"] as? [[String: Any]])
    XCTAssertEqual(cases.count, 48)
    for value in cases {
      let name = try XCTUnwrap(value["file"] as? String), count = try XCTUnwrap(value["bytes"] as? Int)
      do {
        let compressed = try fixture(name)
        XCTAssertEqual(sha(compressed), value["compressed_sha256"] as? String)
        let decoded = try PcraftZstd.decode(compressed, limit: count, expectedBytes: count)
        XCTAssertEqual(sha(decoded), value["sha256"] as? String, name)
      } catch { XCTFail("\(name): \(error)") }
    }
  }
  func testOriginalEditableProjectContainersAndTileAddresses() throws {
    for depth in ["u8", "u16", "f32"] {
      let archive = try PcraftZIP(fixture("source-\(depth).pcraft"))
      let manifest = try JSONSerialization.jsonObject(with: archive.read("manifest.json")) as? [String: Any]
      XCTAssertNotNil(manifest)
      let tiles = archive.entries.keys.filter { $0.hasPrefix("tiles/") && $0.hasSuffix(".zst") }
      XCTAssertGreaterThan(tiles.count, 3)
      for name in tiles {
        let decoded = try PcraftZstd.decode(archive.read(name), limit: 2 * 1024 * 1024)
        XCTAssertEqual(try PcraftBLAKE3.hex(decoded), String(name.dropFirst(6).dropLast(4)), name)
      }
    }
  }
  func testIndependentStoredDeflateAndDescriptorZIPs() throws {
    let cases = try XCTUnwrap(try manifest()["zip"] as? [String])
    for name in cases {
      let archive = try PcraftZIP(fixture(name))
      XCTAssertEqual(Set(archive.entries.keys), ["manifest.json", "tiles/Ω.bin", "empty/"])
      XCTAssertEqual(try archive.read("manifest.json"), Data("{\"version\":1}".utf8))
      XCTAssertEqual(try archive.read("tiles/Ω.bin"), Data((0..<(256 * 333)).map { UInt8($0 % 256) }))
      XCTAssertEqual(try archive.read("empty/"), Data())
      XCTAssertEqual(try PcraftZIP((Data([99]) + fixture(name)).dropFirst()).read("manifest.json"),
        try archive.read("manifest.json"))
      XCTAssertThrowsError(try archive.read("missing"))
      XCTAssertThrowsError(try archive.read("manifest.json", limit: 1))
      XCTAssertThrowsError(try archive.read("empty/", limit: -1))
    }
  }
  func testRawRLEAndHuffmanReuseFrames() throws {
    let magic: [UInt8] = [0x28,0xB5,0x2F,0xFD]
    let raw = Data(magic + [0x20,3,25,0,0,97,98,99])
    let rle = Data(magic + [0x20,3,27,0,0,97])
    XCTAssertEqual(try PcraftZstd.decode(raw, limit: 3), Data("abc".utf8))
    XCTAssertEqual(try PcraftZstd.decode(rle, limit: 3), Data("aaa".utf8))
    // Two symbols of weight 1, one stream; second block repeats the Huffman tree.
    let huffman = Data(magic + [0,0,60,0,0,0x22,0xC0,0,128,0x10,5,0,
      45,0,0,0x23,0x40,0,6,0])
    XCTAssertEqual(try PcraftZstd.decode(huffman, limit: 4), Data([0,1,1,0]))
    var smallWindow = huffman; smallWindow[4] = 0x20; smallWindow[5] = 4
    XCTAssertThrowsError(try PcraftZstd.decode(smallWindow, limit: 4))
    var reserved = raw; reserved[4] |= 8
    XCTAssertThrowsError(try PcraftZstd.decode(reserved, limit: 3))
    var unused = raw; unused[4] |= 16
    XCTAssertEqual(try PcraftZstd.decode(unused, limit: 3), Data("abc".utf8))
    var invalidMatch = huffman; invalidMatch[9] |= 1
    XCTAssertThrowsError(try PcraftZstd.decode(invalidMatch, limit: 4))
    XCTAssertThrowsError(try PcraftZstd.decode(raw + raw, limit: 6))
    XCTAssertThrowsError(try PcraftZstd.decode(raw, limit: 2))
    XCTAssertThrowsError(try PcraftZstd.decode(raw, limit: 4, expectedBytes: 4))
    XCTAssertThrowsError(try PcraftZstd.decode(raw, limit: -1))
    XCTAssertThrowsError(try PcraftZstd.decode(raw, limit: Int.max))
    for end in 0..<raw.count { XCTAssertThrowsError(try PcraftZstd.decode(raw.prefix(end), limit: 3)) }
  }
  func testZstandardChecksumTruncationAndAllocationGuards() throws {
    let compressed = try fixture("cli-text-19-known.zst")
    var damaged = compressed; damaged[damaged.count - 1] ^= 1
    XCTAssertThrowsError(try PcraftZstd.decode(damaged, limit: 256 * 1024))
    for end in 0..<compressed.count {
      XCTAssertThrowsError(try PcraftZstd.decode(compressed.prefix(end), limit: 256 * 1024), "prefix \(end)")
    }
    let magic: [UInt8] = [0x28,0xB5,0x2F,0xFD]
    XCTAssertThrowsError(try PcraftZstd.decode(Data(magic + [0xE0] + Array(repeating: 255, count: 8)), limit: 1))
    XCTAssertThrowsError(try PcraftZstd.decode(Data(magic + [0,255]), limit: 1))
    XCTAssertThrowsError(try PcraftZstd.decode(Data(magic + [0x21,1,0,1,0,0]), limit: 1))
    // Stable mutation corpus must fail cleanly or produce bounded data, never trap.
    for index in 0..<min(64, compressed.count) {
      for mask: UInt8 in [1, 128, 255] {
        var changed = compressed; changed[index] ^= mask
        if let decoded = try? PcraftZstd.decode(changed, limit: 256 * 1024) {
          XCTAssertLessThanOrEqual(decoded.count, 256 * 1024)
        }
      }
    }
  }
  func testZIPCorruptionTruncationAndPathGuards() throws {
    let data = try fixture("zip-0-0.zip"), archive = try PcraftZIP(data)
    var crc = data
    let payload = try XCTUnwrap(archive.entries["manifest.json"]?.range.lowerBound)
    crc[payload] ^= 1
    XCTAssertThrowsError(try PcraftZIP(crc).read("manifest.json"))
    for count in [0,1,21,22,data.count / 2,data.count - 1] {
      XCTAssertThrowsError(try PcraftZIP(data.prefix(count)))
    }
    // Equal-length traversal names in both headers, otherwise structurally valid.
    var traversal = data
    let original = Data("manifest.json".utf8), bad = Data("../ifest.json".utf8)
    var search = traversal.startIndex
    while let range = traversal.range(of: original, in: search..<traversal.endIndex) {
      traversal.replaceSubrange(range, with: bad); search = range.upperBound
    }
    XCTAssertThrowsError(try PcraftZIP(traversal))
    var localFlags = data; localFlags[6] ^= 1
    XCTAssertThrowsError(try PcraftZIP(localFlags))
    let deflated = try fixture("zip-8-0.zip")
    var stream = deflated
    let streamOffset = try XCTUnwrap(PcraftZIP(deflated).entries["tiles/Ω.bin"]?.range.lowerBound)
    stream[streamOffset] ^= 255
    XCTAssertThrowsError(try PcraftZIP(stream).read("tiles/Ω.bin"))
  }
  func testXXHashKnownVectors() throws {
    XCTAssertEqual(try PcraftXXHash64.hash([]), 0xEF46DB3751D8E999)
    XCTAssertEqual(try PcraftXXHash64.hash(Array("a".utf8)), 0xD24EC4F1A98C6E5B)
    XCTAssertEqual(try PcraftXXHash64.hash(Array("abc".utf8)), 0x44BC2CF5AD770999)
  }
  func testCancellationPropagatesBeforeAllocation() async throws {
    let compressed = try fixture("cli-text-19-known.zst"), zip = try fixture("zip-0-0.zip")
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      for operation in [
        { _ = try PcraftBLAKE3.hash(Data()) },
        { _ = try PcraftZstd.decode(compressed, limit: 256 * 1024) },
        { _ = try PcraftZIP(zip) },
      ] {
        do { try operation(); XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
      }
    }
    await task.value
  }
}
