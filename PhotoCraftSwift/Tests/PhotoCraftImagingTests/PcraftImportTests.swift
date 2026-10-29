import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PcraftImportTests: XCTestCase {
  func fixture(_ name: String = "source-u8.pcraft", folder: String = "Pcraft") throws -> Data {
    let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: root.appendingPathComponent(folder).appendingPathComponent(name))
  }
  func source(_ data: Data, mutate: (inout [String: Any]) -> Void) throws -> PcraftProject {
    let zip = try PcraftZIP(data)
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: zip.read("manifest.json")) as? [String: Any])
    var doc = try XCTUnwrap(root["document"] as? [String: Any])
    mutate(&doc); root["document"] = doc
    let manifest = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    return try PcraftProject.read { name, limit in name == "manifest.json" ? manifest : try zip.read(name, limit: limit) }
  }
  func convert(_ project: PcraftProject) throws -> CraftDocument {
    try PcraftImport.convert(project, rasterByteLimit: 1_073_741_824)
  }
  func testExplicitEmptySourceSelectionRejectsWithoutBroadeningEdits() throws {
    let project = try source(fixture()) { document in
      document["selection"] = ["format": ["mode": "Grayscale", "sample": "U8", "alpha": false],
        "default": "00", "tiles": []] as [String: Any]
    }
    XCTAssertThrowsError(try convert(project))
  }
  func testSourceLabelsHighDepthMasksAndPathsRetainEditableProperties() throws {
    for bits in ["u8", "u16", "f32"] {
      let input = try fixture("editable-\(bits).pcraft", folder: "PcraftEditable")
      let model = try PcraftImport.read(input)
      XCTAssertEqual(model.layers.count, 4)
      let layer = model.layers[1]
      XCTAssertEqual(layer.name, "Offcanvas and masks")
      XCTAssertEqual(layer.colorLabel, .violet)
      XCTAssertEqual(layer.parentID, model.layers[2].id)
      XCTAssertEqual(model.layers[2].parentID, model.layers[3].id)
      XCTAssertEqual(model.layers[0].protection, .all)
      let mask = try XCTUnwrap(layer.mask)
      XCTAssertEqual(mask.depth, model.depth)
      XCTAssertFalse(layer.effectiveMaskProperties.enabled)
      XCTAssertFalse(layer.effectiveMaskProperties.linked)
      XCTAssertEqual(layer.effectiveMaskProperties.density, 0.5)
      XCTAssertEqual(layer.effectiveMaskProperties.feather, 2.25)
      XCTAssertEqual(layer.effectiveMaskProperties.outside,
        bits == "u8" ? 64.0 / 255 : bits == "u16" ? 16384.0 / 65535 : 0.25)
      XCTAssertEqual(mask.pixel(x: 253, y: 251).r,
        bits == "u8" ? 191.0 / 255 : bits == "u16" ? 49151.0 / 65535 : 0.75)
      XCTAssertEqual(layer.maskCoordinateTransform, .translation(-256, -256))
      let vector = try XCTUnwrap(layer.vectorMask)
      XCTAssertFalse(vector.linked); XCTAssertEqual(vector.density, 0.75)
      XCTAssertEqual(vector.path.components[0].knots[0].anchor, PathPoint(1.125, 2.25))
      XCTAssertEqual(model.paths?.count, 2)
      XCTAssertEqual(model.paths?.first?.name, "Source Bézier")
      XCTAssertEqual(model.paths?.last?.isWorkPath, true)
      XCTAssertEqual(model.selection, IntRect(x: 1, y: 2, width: 7, height: 4))
      XCTAssertEqual(model.selectionMask?.bytes[2 * 12 + 1], 51)
      if bits == "f32" {
        guard case .raster(let surface) = layer.content else { return XCTFail("Editable pixels") }
        let hidden = surface.linearPixel(x: 256, y: 256)
        XCTAssertEqual(hidden.r.bitPattern, Float(-0.0).bitPattern)
        XCTAssertEqual(hidden.b, 2.5); XCTAssertEqual(hidden.a, 0)
      }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(model)), model)
    }
  }
  func testOriginalRustProjectsRetainEveryAllocatedSampleBitAndEditableProperties() throws {
    for bits in ["u8", "u16", "f32"] {
      let input = try fixture("source-\(bits).pcraft")
      let project = try PcraftProject.read(input), model = try PcraftImport.read(input)
      XCTAssertEqual(model.width, 271); XCTAssertEqual(model.height, 259)
      XCTAssertEqual(model.pixelsPerInch, 144)
      XCTAssertEqual(model.name, "Original PhotoCraft Ω")
      XCTAssertEqual(model.layers.map(\.name), ["Background", "Pixels Ω", "Group"])
      XCTAssertEqual(model.layers[1].parentID, model.layers[2].id)
      XCTAssertEqual(model.layers[0].protection, [.transparency, .position])
      XCTAssertEqual(model.layers[1].opacity, 0.8)
      XCTAssertEqual(model.layers[1].blendMode, .multiply)
      XCTAssertEqual(model.layers[1].x, -256); XCTAssertEqual(model.layers[1].y, -256)
      XCTAssertEqual(model.layers[1].effectiveMaskProperties.outside, 1)
      XCTAssertEqual(model.layers[1].effectiveMaskProperties.density, 0.75)
      XCTAssertEqual(model.layers[1].effectiveMaskProperties.feather, 1.25)
      XCTAssertEqual(model.layers[1].maskCoordinateTransform, .identity)
      guard case .group(let group) = model.layers[2].content else { return XCTFail("Editable group") }
      XCTAssertTrue(group.passThrough); XCTAssertTrue(group.expanded)
      XCTAssertEqual(model.sourceMetadata?["pcraft.manifest"], project.rawManifest)
      let roles = [("/document/layers/0/content/surface", 0, false),
        ("/document/layers/1/content/children/0/content/surface", 1, false),
        ("/document/layers/1/content/children/0/mask/surface", 1, true)]
      for (path, index, isMask) in roles {
        let original = try XCTUnwrap(project.surfaces[path]), layer = model.layers[index]
        let surface: Surface
        if isMask { surface = try XCTUnwrap(layer.mask) }
        else if case .raster(let value) = layer.content { surface = value }
        else { return XCTFail("Editable raster") }
        XCTAssertEqual(surface.colorEncoding, bits == "f32" && !isMask ? .linearRGB : .sRGB)
        for (coordinate, bytes) in original.tiles {
          var roundTrip = Data(); roundTrip.reserveCapacity(bytes.count)
          for y in 0..<256 { for x in 0..<256 {
            let dx = Int(coordinate.x) * 256 + x - (isMask ? 0 : layer.x)
            let dy = Int(coordinate.y) * 256 + y - (isMask ? 0 : layer.y)
            let pixel = surface.colorEncoding == .linearRGB
              ? surface.linearPixel(x: dx, y: dy) : surface.pixel(x: dx, y: dy)
            let channels = isMask ? [pixel.r] : [pixel.r, pixel.g, pixel.b, pixel.a]
            for value in channels {
              switch surface.depth {
              case .u8: roundTrip.append(UInt8((value * 255).rounded()))
              case .u16:
                var v = UInt16((value * 65535).rounded()).littleEndian
                withUnsafeBytes(of: &v) { roundTrip.append(contentsOf: $0) }
              case .f32:
                var v = value.bitPattern.littleEndian
                withUnsafeBytes(of: &v) { roundTrip.append(contentsOf: $0) }
              }
            }
          } }
          XCTAssertEqual(roundTrip, bytes, "\(bits) \(path) \(coordinate)")
        }
      }
      let saved = try NativeArchive.encodeChunked(model)
      XCTAssertEqual(try NativeArchive.decode(saved), model)
      var session = EditorSession(document: model)
      try session.execute(.renameLayer(model.layers[1].id, "Editable source layer"))
      XCTAssertEqual(session.document.layers[1].name, "Editable source layer")
      try session.undo(); XCTAssertEqual(session.document, model)
      try session.redo(); XCTAssertEqual(session.document.layers[1].name, "Editable source layer")
    }
  }
  func testZIPAndDirectoryImportsMatchAndDoNotWriteTheSource() throws {
    let bytes = try fixture(), zip = try PcraftZIP(bytes)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("photato153-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("renamed.png")
    try bytes.write(to: file)
    let directory = root.appendingPathComponent("project.pcraft")
    for name in zip.entries.keys {
      let path = directory.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      try zip.read(name).write(to: path)
    }
    XCTAssertTrue(PcraftImport.recognizes(bytes)); XCTAssertTrue(PcraftImport.recognizes(file))
    XCTAssertTrue(PcraftImport.recognizes(directory)); XCTAssertFalse(PcraftImport.recognizes(Data("PKwrong".utf8)))
    let expected = try PcraftImport.read(bytes)
    XCTAssertEqual(try PcraftImport.read(file), expected)
    XCTAssertEqual(try PcraftImport.read(directory), expected)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    for name in zip.entries.keys { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), try zip.read(name)) }
  }
  func testLargeSourceIDsStayDistinctAndDeterministic() throws {
    let zip = try PcraftZIP(fixture())
    var manifest = String(decoding: try zip.read("manifest.json"), as: UTF8.self)
    for (old, new) in [(1, "18446744073709551615"), (2, "9007199254740992"), (3, "9007199254740993"), (4, "9007199254740995")] {
      manifest = manifest.replacingOccurrences(of: "\"id\": \(old),", with: "\"id\": \(new),")
      manifest = manifest.replacingOccurrences(of: "\"id\":\(old),", with: "\"id\":\(new),")
    }
    let bytes = Data(manifest.utf8)
    let project = try PcraftProject.read { name, limit in name == "manifest.json" ? bytes : try zip.read(name, limit: limit) }
    XCTAssertEqual(project.manifest["document"]?["id"]?.uint, UInt64.max)
    let first = try convert(project), second = try convert(project)
    XCTAssertEqual(first, second)
    XCTAssertEqual(Set(first.layers.map(\.id)).count, 3)
  }
  func testUnsupportedFeaturesAndUnknownFieldsRejectInsteadOfFlattening() throws {
    let input = try fixture()
    let documentCases: [(String, Any)] = [("channels", [1]), ("guides", ["horizontal": [12], "vertical": []]),
      ("unrecognizedFeature", true), ("timeline", [String: Any]()), ("patterns", [1])]
    for (key, value) in documentCases {
      XCTAssertThrowsError(try convert(source(input) { $0[key] = value }), key)
    }
    let layerCases: [(String, Any)] = [("fill_opacity", 0.5), ("label", "Unknown"),
      ("link_group", 7), ("excluded_channels", 1), ("unrecognizedLayerFeature", false)]
    for (key, value) in layerCases {
      XCTAssertThrowsError(try convert(source(input) { doc in
        var layers = doc["layers"] as! [[String: Any]]; layers[0][key] = value; doc["layers"] = layers
      }), key)
    }
    for bits in ["u8", "u16", "f32"] {
      XCTAssertThrowsError(try PcraftImport.read(fixture("rich-\(bits).pcraft", folder: "PcraftProjects")))
    }
    XCTAssertThrowsError(try PcraftImport.read(input, rasterByteLimit: 1))
    XCTAssertThrowsError(try PcraftImport.read(input, rasterByteLimit: -1))
  }
  func testOriginalRustPathGeometryRemainsEditableWithoutCaches() throws {
    let rich = try PcraftProject.read(fixture("rich-u8.pcraft", folder: "PcraftProjects"))
    let richJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: rich.rawManifest) as? [String: Any])
    let richDoc = try XCTUnwrap(richJSON["document"] as? [String: Any])
    var paths = try XCTUnwrap(richDoc["paths"] as? [[String: Any]])
    for i in paths.indices { paths[i]["psd_raw"] = NSNull() }
    let project = try source(fixture()) { doc in doc["paths"] = paths; doc["work_path"] = richDoc["work_path"] }
    let model = try convert(project)
    XCTAssertFalse(try XCTUnwrap(model.paths).isEmpty)
    XCTAssertTrue(try XCTUnwrap(model.paths).contains(where: \.isWorkPath))
    for (actual, raw) in zip(model.paths!.filter { !$0.isWorkPath }, project.manifest["document"]!["paths"]!.array!) {
      XCTAssertEqual(actual.name, raw["name"]?.string)
      let subpaths = try XCTUnwrap(raw["path"]?["subpaths"]?.array)
      XCTAssertEqual(actual.path.components.count, subpaths.count)
      for (component, reference) in zip(actual.path.components, subpaths) {
        XCTAssertEqual(component.closed, reference["closed"]?.bool)
        XCTAssertEqual(component.operation.rawValue, reference["op"]?.string ?? "Combine")
        let knots = try XCTUnwrap(reference["knots"]?.array)
        XCTAssertEqual(component.knots.count, knots.count)
        for (knot, expected) in zip(component.knots, knots) {
          for (point, field) in [(knot.anchor, "anchor"), (knot.incoming, "in_ctrl"), (knot.outgoing, "out_ctrl")] {
            XCTAssertEqual(point.x, try PcraftNode(expected[field]!["x"]!, path: "reference").double())
            XCTAssertEqual(point.y, try PcraftNode(expected[field]!["y"]!, path: "reference").double())
          }
        }
      }
    }
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(model)), model)
  }
  func testCancellationBeforeConversionPublishesNothing() async throws {
    let bytes = try fixture()
    let task = Task { while !Task.isCancelled { await Task.yield() }; return try PcraftImport.read(bytes) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled import succeeded") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
  func testUnboundedDefaultsNonFiniteSamplesAndExtremeCoordinatesReject() throws {
    func bytes(_ samples: [Float]) -> Data {
      var result = Data()
      for sample in samples {
        var bits = sample.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
      }
      return result
    }
    for values: [Float] in [[1, 0, 0, 0], [0, 0, 0, 1], [.nan, 0, 0, 0],
      [.infinity, 0, 0, 0], [0, 0, 0, -1], [0, 0, 0, 2]] {
      let source = PcraftProject.Surface(mode: "Rgb", sample: "F32", alpha: true,
        bytesPerPixel: 16, defaultPixel: bytes(values), tiles: [:])
      var budget = 1_073_741_824
      XCTAssertThrowsError(try PcraftSamples.placed(source, mask: false, budget: &budget))
    }
    let zeroTile = Data(repeating: 0, count: 256 * 256 * 16)
    let source = PcraftProject.Surface(mode: "Rgb", sample: "F32", alpha: true,
      bytesPerPixel: 16, defaultPixel: bytes([0, 0, 0, 0]),
      tiles: [.init(x: Int32.max, y: Int32.min): zeroTile])
    var budget = 1_073_741_824
    XCTAssertThrowsError(try PcraftSamples.placed(source, mask: false, budget: &budget))
    let mask = PcraftProject.Surface(mode: "Grayscale", sample: "U8", alpha: false,
      bytesPerPixel: 1, defaultPixel: Data([255]), tiles: [:])
    XCTAssertThrowsError(try PcraftSamples.selection(mask, width: 1, height: 1, budget: &budget))
    let offCanvas = PcraftProject.Surface(mode: "Grayscale", sample: "U8", alpha: false,
      bytesPerPixel: 1, defaultPixel: Data([0]),
      tiles: [.init(x: -1, y: 0): Data([1]) + Data(repeating: 0, count: 65535)])
    XCTAssertThrowsError(try PcraftSamples.selection(offCanvas, width: 1, height: 1, budget: &budget))
  }
}
