import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import PhotoCraftImaging

final class PcraftProjectTests: XCTestCase {
  private func fixture(_ name: String, rich: Bool = false) throws -> Data {
    let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: root.appendingPathComponent(rich ? "PcraftProjects" : "Pcraft").appendingPathComponent(name))
  }
  private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func objects(_ name: String = "source-u8.pcraft", rich: Bool = false) throws -> [String: Data] {
    let zip = try PcraftZIP(fixture(name, rich: rich))
    return try Dictionary(uniqueKeysWithValues: zip.entries.keys.map { ($0, try zip.read($0)) })
  }
  private func read(_ entries: [String: Data], limits: PcraftProject.Limits = .init()) throws -> PcraftProject {
    try PcraftProject.read(limits: limits) { name, limit in
      let data = try XCTUnwrap(entries[name], name)
      guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
      return data
    }
  }
  private func changed(_ entries: [String: Data], _ body: (inout [String: Any]) -> Void) throws -> [String: Data] {
    var copy = entries
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(copy["manifest.json"])) as? [String: Any])
    body(&json)
    copy["manifest.json"] = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    return copy
  }
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("photato-pcraft-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: url) }
    return url
  }
  private func write(_ entries: [String: Data], at root: URL) throws {
    for (name, data) in entries {
      let file = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file)
    }
  }
  func testOriginalProjectsKeepExactManifestDefaultsAndAllTiles() throws {
    for depth in ["u8", "u16", "f32"] {
      let entries = try objects("source-\(depth).pcraft")
      let project = try read(entries)
      XCTAssertEqual(project.rawManifest, entries["manifest.json"])
      XCTAssertEqual(project.layerIDs.count, 3)
      XCTAssertEqual(project.surfaces.count, 3)
      XCTAssertTrue(project.blobs.isEmpty)
      let background = try XCTUnwrap(project.surfaces["/document/layers/0/content/surface"])
      XCTAssertEqual(background.pixel(x: 0, y: 0).count, background.bytesPerPixel)
      XCTAssertEqual(background.pixel(x: Int64.min, y: Int64.max), background.defaultPixel)
      XCTAssertEqual(project.manifest["document"]?["layers"]?.array?[0]["locks"]?["position"], .bool(true))
      XCTAssertEqual(project.manifest["document"]?["layers"]?.array?[0]["locks"]?["pixels"], .bool(false))
    }
  }
  func testRichSourceGraphMatchesIndependentPayloadAndSurfaceInventory() throws {
    let inventory = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("manifest.json", rich: true)) as? [String: Any])
    for entry in try XCTUnwrap(inventory["cases"] as? [[String: Any]]) {
      let file = try XCTUnwrap(entry["file"] as? String)
      let bytes = try fixture(file, rich: true)
      XCTAssertEqual(sha(bytes), entry["sha256"] as? String)
      let project = try PcraftProject.read(bytes)
      XCTAssertEqual(sha(project.rawManifest), entry["manifest_sha256"] as? String)
      XCTAssertEqual(project.manifest["document"]?["id"]?.uint, 9007199254740993)
      XCTAssertEqual(project.layerIDs.first, 9007199254740995)
      XCTAssertEqual(project.manifest["document"]?["text_styles"]?["psd_raw"]?["largeID"]?.uint, 9007199254740997)
      let surfaces = try XCTUnwrap(entry["surfaces"] as? [String: [String: Any]])
      let payloads = try XCTUnwrap(entry["payloads"] as? [String: [String: Any]])
      XCTAssertEqual(Set(project.surfaces.keys), Set(surfaces.keys))
      var seen = Set<String>()
      for (path, reference) in surfaces {
        let surface = try XCTUnwrap(project.surfaces[path])
        let tiles = try XCTUnwrap(reference["tiles"] as? [[String: Any]])
        XCTAssertEqual(tiles.count, surface.tiles.count)
        for tile in tiles {
          let hash = try XCTUnwrap(tile["hash"] as? String)
          let x = try XCTUnwrap(tile["tx"] as? Int32), y = try XCTUnwrap(tile["ty"] as? Int32)
          let data = try XCTUnwrap(surface.tiles[.init(x: x, y: y)])
          let name = "tiles/\(hash).zst"; seen.insert(name)
          XCTAssertEqual(sha(data), payloads[name]?["sha256"] as? String)
          XCTAssertEqual(data.count, payloads[name]?["bytes"] as? Int)
          XCTAssertEqual(surface.pixel(x: Int64(x) * 256, y: Int64(y) * 256), data.prefix(surface.bytesPerPixel))
          XCTAssertEqual(surface.pixel(x: Int64(x) * 256 + 255, y: Int64(y) * 256 + 255), data.suffix(surface.bytesPerPixel))
        }
      }
      for (hash, data) in project.blobs {
        let name = "blobs/\(hash).zst"; seen.insert(name)
        XCTAssertEqual(sha(data), payloads[name]?["sha256"] as? String)
        XCTAssertEqual(data.count, payloads[name]?["bytes"] as? Int)
      }
      XCTAssertEqual(seen, Set(payloads.keys), "Every stored editing payload is reached, including comp appearance.")
      XCTAssertEqual(project.layerIDs.count, 12)
    }
  }
  func testJSONPreservesNumbersUnicodeAndRejectsAmbiguity() throws {
    let source = #"{"id":18446744073709551615,"negative":-9223372036854775808,"zero":-0.0e+0,"text":"\uD83E\uDD54","future":{"precise":0.123456789012345678901}}"#
    let value = try PcraftJSON.parse(Data(source.utf8))
    XCTAssertEqual(value["id"]?.uint, UInt64.max)
    XCTAssertEqual(value["negative"]?.int, Int64.min)
    XCTAssertEqual(value["zero"], .number("-0.0e+0"))
    XCTAssertEqual(value["text"]?.string, "🥔")
    XCTAssertEqual(value["future"]?["precise"], .number("0.123456789012345678901"))
    for bad in ["", "01", "-01", "+1", "1.", ".5", "1e", "1e9999", "NaN", "[1,]", "{\"a\":1,}",
      "{\"a\":1,\"\\u0061\":2}", "{\"a\":null,\"a\":3}", "\"\\uD800\"", "\"\\x20\"", "{}{}"] {
      XCTAssertThrowsError(try PcraftJSON.parse(Data(bad.utf8)), bad)
    }
    XCTAssertThrowsError(try PcraftJSON.parse(Data([34,255,34])))
    XCTAssertThrowsError(try PcraftJSON.parse(Data("[0,1]".utf8), maximumNodes: 2))
    XCTAssertThrowsError(try PcraftJSON.parse(Data((String(repeating: "[", count: 368) + "0" + String(repeating: "]", count: 368)).utf8)))
  }
  func testAllSourcePixelFormatsKeepUnboundedEncodedDefaults() throws {
    let original = try objects()
    for (mode, channels) in ["Bitmap":1, "Grayscale":1, "Duotone":1, "Indexed":3, "Rgb":3, "Lab":3, "Cmyk":4, "Multichannel":3] {
      for (sample, bytes) in ["U8":1, "U16":2, "F32":4] {
        for alpha in [false, true] {
          let encoded = Data((0..<((channels + (alpha ? 1 : 0)) * bytes)).map { UInt8($0 * 7) })
          let changed = try changed(original) { root in
            var doc = root["document"] as! [String: Any]
            var layer = (doc["layers"] as! [[String: Any]])[0]
            layer["content"] = ["kind":"raster", "surface":["format":["mode":mode,"sample":sample,"alpha":alpha],
              "default":encoded.map { String(format:"%02x",$0) }.joined(),"tiles":[]]]
            doc["layers"] = [layer]; root["document"] = doc
          }
          let surface = try XCTUnwrap(try read(changed).surfaces.values.first)
          XCTAssertEqual(surface.pixel(x: -65537, y: 1_000_000), encoded)
        }
      }
    }
  }
  func testUnknownMetadataAndInlineStyleBytesStayInGraph() throws {
    let entries = try changed(objects()) { root in root["future_metadata"] = ["text":"Ω","bytes":[0,255],"enabled":true] }
    let project = try read(entries)
    XCTAssertEqual(project.manifest["future_metadata"]?["bytes"], .array([.number("0"),.number("255")]))
    XCTAssertEqual(project.rawManifest, entries["manifest.json"])
  }
  func testSourceGroupDepthBoundaryAllowsEmptyChildrenOnly() throws {
    let original = try objects()
    func nested(_ count: Int) throws -> [String: Data] {
      try changed(original) { root in
        var doc = root["document"] as! [String: Any]
        let template = (doc["layers"] as! [[String: Any]])[0]
        var children: [[String: Any]] = []
        for index in (0..<count).reversed() {
          var group = template
          group["id"] = index + 1
          group["content"] = ["kind":"group", "children":children, "expanded":true]
          children = [group]
        }
        doc["layers"] = children; root["document"] = doc
      }
    }
    XCTAssertEqual(try read(nested(101)).layerIDs.count, 101)
    XCTAssertThrowsError(try read(nested(102)))
  }
  func testCorruptOrMissingPayloadsRejectWithoutPreviewFallback() throws {
    var entries = try objects()
    let name = try XCTUnwrap(entries.keys.first { $0.hasPrefix("tiles/") })
    let saved = entries[name]!
    entries[name] = Data([0,1,2])
    XCTAssertThrowsError(try read(entries))
    entries[name] = try fixture("blob-0-0.zst")
    XCTAssertThrowsError(try read(entries))
    entries[name] = saved
    let second = try XCTUnwrap(entries.keys.first { $0.hasPrefix("tiles/") && $0 != name })
    entries[name] = entries[second] // Valid Zstd and size but wrong content address.
    XCTAssertThrowsError(try read(entries))
    entries.removeValue(forKey: name)
    XCTAssertThrowsError(try PcraftProject.read { key, _ in
      guard let value = entries[key] else { throw CocoaError(.fileNoSuchFile) }; return value
    })
  }
  func testInvalidVersionIDsKindsCoordinatesAndTileDefaultsReject() throws {
    let original = try objects()
    for mutation in 0..<9 {
      let entries = try changed(original) { root in
        if mutation == 0 { root["format_version"] = 2; return }
        var doc = root["document"] as! [String: Any]
        var layers = doc["layers"] as! [[String: Any]]
        if mutation == 1 { layers[1]["id"] = layers[0]["id"] }
        var content = layers[0]["content"] as! [String: Any]
        if mutation == 2 { content["kind"] = "unrecognized" }
        var surface = content["surface"] as! [String: Any]
        var tiles = surface["tiles"] as! [[String: Any]]
        if mutation == 3 { tiles.append(tiles[0]) }
        if mutation == 4 { tiles[0]["tx"] = Int64(Int32.max) + 1 }
        if mutation == 5 { tiles[0]["hash"] = "../escape" }
        if mutation == 6 { surface["default"] = "+0000000" }
        if mutation == 7 { surface["default"] = "00" }
        if mutation == 8 { layers[0]["id"] = 1.5 }
        surface["tiles"] = tiles; content["surface"] = surface; layers[0]["content"] = content
        doc["layers"] = layers; root["document"] = doc
      }
      XCTAssertThrowsError(try read(entries), "mutation \(mutation)")
    }
  }
  func testBudgetsCountLogicalTileUsesAndManifestBeforeAllocation() throws {
    let entries = try objects()
    let project = try read(entries)
    var limits = PcraftProject.Limits()
    limits.totalBytes = project.accountedBytes - 1
    XCTAssertThrowsError(try read(entries, limits: limits))
    limits.totalBytes = project.accountedBytes
    XCTAssertEqual(try read(entries, limits: limits).accountedBytes, project.accountedBytes)
    limits.manifestBytes = 10
    XCTAssertThrowsError(try read(entries, limits: limits))
    limits = .init(); limits.layers = 2
    XCTAssertThrowsError(try read(entries, limits: limits))
    limits = .init(); limits.surfaces = 2
    XCTAssertThrowsError(try read(entries, limits: limits))
    limits = .init(); limits.blobBytes = 1
    XCTAssertThrowsError(try read(objects("rich-u8.pcraft", rich: true), limits: limits))
    limits = .init(); limits.totalBytes = -1
    XCTAssertThrowsError(try read(entries, limits: limits))
  }
  func testDirectoryAndZIPFilesHaveIdenticalGraphAndSamples() throws {
    let root = try temporaryDirectory()
    let folder = root.appendingPathComponent("project.pcraft")
    let entries = try objects()
    try write(entries, at: folder)
    let file = root.appendingPathComponent("archive.pcraft")
    try fixture("source-u8.pcraft").write(to: file)
    let a = try PcraftProject.read(folder), b = try PcraftProject.read(file)
    XCTAssertEqual(a.manifest, b.manifest)
    XCTAssertEqual(a.layerIDs, b.layerIDs)
    XCTAssertEqual(a.accountedBytes, b.accountedBytes)
    for (path, surface) in a.surfaces { XCTAssertEqual(surface.tiles, b.surfaces[path]?.tiles) }
  }
  func testDirectoryRejectsLinksTraversalSpecialFilesAndReplacement() throws {
    let root = try temporaryDirectory(), folder = root.appendingPathComponent("project")
    let entries = try objects(); try write(entries, at: folder)
    let source = try PcraftDirectory(folder)
    _ = try source.read("manifest.json", limit: 1_000_000)
    XCTAssertThrowsError(try source.read("../manifest.json", limit: 1_000_000))
    XCTAssertThrowsError(try source.read("tiles/../manifest.json", limit: 1_000_000))
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
    XCTAssertThrowsError(try PcraftDirectory(link))
    let manifest = folder.appendingPathComponent("manifest.json")
    try FileManager.default.moveItem(at: manifest, to: root.appendingPathComponent("original.json"))
    try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: root.appendingPathComponent("original.json"))
    XCTAssertThrowsError(try source.validateUnchanged())
    XCTAssertThrowsError(try PcraftProject.read(folder))
    try FileManager.default.removeItem(at: manifest)
    XCTAssertEqual(mkfifo(manifest.path, 0o600), 0)
    XCTAssertThrowsError(try PcraftProject.read(folder))
    try FileManager.default.removeItem(at: manifest)
    try entries["manifest.json"]!.write(to: manifest)
    let tileFolder = folder.appendingPathComponent("tiles")
    try FileManager.default.moveItem(at: tileFolder, to: root.appendingPathComponent("outside"))
    try FileManager.default.createSymbolicLink(at: tileFolder, withDestinationURL: root.appendingPathComponent("outside"))
    XCTAssertThrowsError(try PcraftProject.read(folder))
  }
  func testDirectoryRevalidatesFilesAfterReadAndRootIdentity() throws {
    let root = try temporaryDirectory(), folder = root.appendingPathComponent("project")
    try write(objects(), at: folder)
    let source = try PcraftDirectory(folder)
    let manifest = folder.appendingPathComponent("manifest.json")
    _ = try source.read("manifest.json", limit: 1_000_000)
    let handle = try FileHandle(forWritingTo: manifest)
    try handle.write(contentsOf: Data("xxxx".utf8)); try handle.close()
    XCTAssertThrowsError(try source.validateUnchanged())
    let next = try PcraftDirectory(folder)
    try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("moved"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    XCTAssertThrowsError(try next.validateUnchanged())
  }
  func testLinkedSmartObjectPathsAreNeverFollowed() throws {
    let entries = try objects("rich-u8.pcraft", rich: true)
    var accessed = Set<String>()
    _ = try PcraftProject.read { path, _ in
      accessed.insert(path)
      return try XCTUnwrap(entries[path])
    }
    XCTAssertTrue(accessed.allSatisfy { $0 == "manifest.json" || $0.hasPrefix("tiles/") || $0.hasPrefix("blobs/") })
  }
  func testCancellationBeforeLoadingDoesNotFetch() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PcraftProject.read { _, _ in
        XCTFail("Cancelled work must not fetch."); return Data()
      }.layerIDs.count
    }
    do { _ = try await task.value; XCTFail("Expected cancellation.") }
    catch is CancellationError {} catch { XCTFail("\(error)") }
  }
}
