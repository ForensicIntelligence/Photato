import XCTest
import CryptoKit
@testable import PhotoCraftCore

final class RetainedMaskStrokeTests: XCTestCase {
  struct Case {
    let id: String
    let original: CraftDocument
    let target: String
    let layerID: UUID
    let newLayerID: UUID
    let brush: Brush
    let subtract: Bool
    let adjustment: Adjustment
    let points: [StrokePoint]
    func command(_ points: [StrokePoint], released: Bool) -> Command {
      var value = brush
      if target == "mask" {
        if !released { value.settings?.smoothing.catchUpOnEnd = false }
        return .maskStroke(layerID, points, value)
      }
      return .adjustmentBrush(.init(layerID: target == "existing" ? layerID : nil,
        newLayerID: newLayerID, adjustment: adjustment, points: points, brush: value, subtract: subtract))
    }
    var paintedID: UUID { target == "new" ? newLayerID : layerID }
  }
  struct Reference: Codable, Equatable {
    let id: String
    let samples: Int
    let released: Bool
    let metadataSHA256: String
    let maskSHA256: String?
    let maskWidth: Int?
    let maskHeight: Int?
    let maskDepth: PixelDepth?
    let maskEncoding: SurfaceColorEncoding?
  }
  struct Book: Codable {
    let sourceBuild: Int
    let sourceCommit: String
    let references: [Reference]
  }
  static let sourceCommit = "84de39282cd28c42a181f79563c7c1f1deabfc5f"
  func cases() throws -> [Case] {
    var cases: [Case] = []
    for depth in PixelDepth.allCases { for variant in 0..<7 { for target in ["mask", "existing", "new"] {
      var d = try CraftDocument(width: 96, height: 72, depth: depth)
      d.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
      d.layers[0].id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
      var raster = try Surface(width: 96, height: 72, depth: depth)
      raster.mapPixels { x,y,_ in Pixel(Float(x + 1) / 98, Float(y + 1) / 74, 0.4, 0.8) }
      d.layers[0].content = .raster(raster); d.activeLayerID = d.layers[0].id
      if variant % 2 == 1 {
        let values = (0..<(96 * 72)).map { i -> UInt8 in
          let x = i % 96, y = i / 96
          return x >= 8 && x < 88 && y >= 4 && y < 66 ? UInt8(30 + (x + y) % 200) : 0
        }
        d.setCoverageSelection(try SelectionMask(width: 96, height: 72, bytes: values))
      }
      var modern = ModernAdjustment(.colorVibrance)
      modern.values["temperature"] = 17; modern.values["tint"] = -23
      modern.values["vibrance"] = 37; modern.values["saturation"] = -19
      let adjustment = Adjustment.modern(modern)
      var index = 0
      if target == "existing" {
        var layer = Layer(name: "Existing adjustment", content: .adjustment(AdjustmentBrushKind.colorVibrance.initial))
        layer.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        layer.opacity = 0.63; layer.blendMode = .screen
        d.layers.append(layer); index = 1; d.activeLayerID = layer.id
      }
      if target != "new" {
        let cropped = variant % 2 == 1
        let maskDepth: PixelDepth = variant == 2 ? .f32 : depth
        d.layers[index].mask = try Surface(width: cropped ? 20 : 96, height: cropped ? 18 : 72,
          depth: maskDepth, fill: target == "mask" ? .white : .black)
        var properties = MaskProperties()
        if cropped {
          properties.transform = .translation(14, 9) * .rotation(8)
          properties.outside = 0.25; properties.linked = false
          properties.density = 0.73; properties.feather = 1.2
        }
        if variant == 4 { properties.inverted = true; properties.density = 0.5; properties.feather = 1 }
        d.layers[index].maskProperties = properties
      }
      var brush = Brush(); brush.settings = .init(); brush.settings!.seed = UInt64(42 + variant)
      brush.size = 12; brush.hardness = 0.7; brush.opacity = 0.65
      brush.color = Pixel(0.2, 0.6, 0.4, 0.8); brush.backgroundColor = Pixel(0.8, 0.1, 0.3)
      brush.settings!.flow = 0.4
      switch variant {
      case 1: brush.settings!.smoothing.amount = 0.65; brush.settings!.smoothing.catchUpOnEnd = true
      case 2: brush.settings!.colorDynamics.enabled = true; brush.settings!.colorDynamics.hue = 0.45
      case 3: brush.settings!.texture.enabled = true; brush.settings!.texture.eachTip = true; brush.settings!.noise = true
      case 4: brush.erase = true; brush.settings!.mode = .multiply
      case 5:
        brush.settings!.scattering.enabled = true; brush.settings!.scattering.amount.jitter = 0.7
        brush.settings!.scattering.count = 2; brush.settings!.shape.enabled = true
        brush.settings!.shape.size.control = .penPressure; brush.settings!.shape.angle.control = .direction
      case 6: brush.opacity = 0
      default: break
      }
      var points: [StrokePoint] = []
      for i in 0..<8 {
        let x = 8.0 + Double(i) * 7.0, y = 30.0 + sin(Double(i)) * 9.0
        let pressure = Float(i % 4 + 1) / 4.0, time = Double(i) * 40.0
        points.append(StrokePoint(x: x, y: y, pressure: pressure, time: time))
      }
      try d.validate()
      cases.append(Case(id: "\(depth)-\(variant)-\(target)", original: d, target: target,
        layerID: d.layers[index].id, newLayerID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        brush: brush, subtract: target == "existing" && variant % 2 == 1, adjustment: adjustment, points: points))
    } } }
    return cases
  }
  func reference(_ document: CraftDocument, for value: Case, samples: Int, released: Bool) throws -> Reference {
    let mask = document.layers.first { $0.id == value.paintedID }?.mask
    var metadata = document
    for i in metadata.layers.indices {
      metadata.layers[i].mask = nil
      if case .raster = metadata.layers[i].content { metadata.layers[i].content = .fill(.clear) }
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    return Reference(id: value.id, samples: samples, released: released,
      metadataSHA256: hash(try encoder.encode(metadata)), maskSHA256: try mask.map { hash(try $0.rgbaData(depth: .f32)) },
      maskWidth: mask?.width, maskHeight: mask?.height, maskDepth: mask?.depth, maskEncoding: mask?.colorEncoding)
  }
  func testCanonicalMaskCommandsMatchCheckpoint522() throws {
    var actual: [Reference] = []
    for value in try cases() { for count in [1, 2, 4, 8] { for released in [false, true] {
      var result = value.original
      try value.command(Array(value.points.prefix(count)), released: released).apply(to: &result)
      actual.append(try reference(result, for: value, samples: count, released: released))
      XCTAssertEqual(result.layers[0].content, value.original.layers[0].content)
    } } }
    XCTAssertEqual(actual.count, 504)
    let url = try XCTUnwrap(Bundle.module.url(forResource: "canonical-522", withExtension: "json", subdirectory: "Fixtures/RetainedMask523"))
    let book = try JSONDecoder().decode(Book.self, from: Data(contentsOf: url))
    XCTAssertEqual(book.sourceBuild, 522); XCTAssertEqual(book.sourceCommit, Self.sourceCommit)
    XCTAssertEqual(actual.count, book.references.count)
    for (found, expected) in zip(actual, book.references) {
      guard found == expected else {
        return XCTFail("Canonical output changed from checkpoint522: \(found) expected \(expected)")
      }
    }
  }

  func testRetainedEveryPrefixAndPublishedSnapshotsMatchCanonicalWordsAndMetadata() throws {
    for value in try cases() { for released in [false, true] {
      let owner = try DocumentMaskStrokeSession(document: value.original, command: value.command([], released: true))
      var snapshots: [(CraftDocument, Reference)] = []
      for i in value.points.indices {
        let prefix = Array(value.points.prefix(i + 1))
        // Native Adjustment Brush previews keep their complete tail; ordinary mask
        // held previews omit it. The reference's released flag records that policy.
        let actual = try owner.append([value.points[i]], includingReleaseTail: released || value.target != "mask")
        var expected = value.original; try value.command(prefix, released: released).apply(to: &expected)
        let found = try reference(actual, for: value, samples: prefix.count, released: released)
        let wanted = try reference(expected, for: value, samples: prefix.count, released: released)
        guard actual == expected, found == wanted else { return XCTFail("\(value.id) prefix\(i + 1) released\(released): \(found) expected \(wanted)") }
        XCTAssertEqual(owner.sampleCount, prefix.count)
        snapshots.append((actual, found))
      }
      for (snapshot, before) in snapshots {
        XCTAssertEqual(try reference(snapshot, for: value, samples: before.samples, released: released), before,
          "Later appends mutated an already published snapshot")
      }
    } }
  }
  func testExplicitAdjustmentTailOmissionMatchesCanonicalBrushWithCatchUpDisabled() throws {
    for value in try cases() where value.target != "mask" && value.brush.settings?.smoothing.amount ?? 0 > 0 {
      let owner = try DocumentMaskStrokeSession(document: value.original, command: value.command([], released: true))
      for i in value.points.indices {
        let points = Array(value.points.prefix(i + 1))
        guard case .adjustmentBrush(var request) = value.command(points, released: true) else { return XCTFail("Expected adjustment") }
        request.brush.settings?.smoothing.catchUpOnEnd = false
        var expected = value.original; try Command.adjustmentBrush(request).apply(to: &expected)
        let actual = try owner.append([value.points[i]], includingReleaseTail: false)
        XCTAssertTrue(actual == expected, "\(value.id) held prefix\(i + 1)")
        XCTAssertEqual(try reference(actual, for: value, samples: points.count, released: false),
          try reference(expected, for: value, samples: points.count, released: false))
      }
    }
  }
  func testPreparedCommitRetainsCommandMetadataNoOpsAndUndoRedo() throws {
    for value in try cases() {
      let owner = try DocumentMaskStrokeSession(document: value.original, command: value.command([], released: true))
      _ = try owner.append(Array(value.points.prefix(4)), includingReleaseTail: false)
      let prepared = try owner.prepareEdit(points: value.points)
      var expected = value.original; try value.command(value.points, released: true).apply(to: &expected)
      var session = EditorSession(document: value.original); try session.executePrepared(prepared)
      XCTAssertTrue(session.document == expected, value.id)
      XCTAssertEqual(try reference(session.document, for: value, samples: 8, released: true),
        try reference(expected, for: value, samples: 8, released: true))
      let changed = expected != value.original
      XCTAssertEqual(session.undoStack.count, changed ? 1 : 0)
      if changed {
        try session.undo(); XCTAssertTrue(session.document == value.original)
        try session.redo(); XCTAssertTrue(session.document == expected)
      }
      if value.target != "mask" { XCTAssertEqual(prepared.adjustmentBrushTarget, value.paintedID) }
      XCTAssertThrowsError(try owner.prepareEdit(points: value.points))
      XCTAssertThrowsError(try owner.append([]))
    }
  }
  func testFailurePoisonsOwnerWithoutMutatingSourceOrPublishedMask() throws {
    let value = try XCTUnwrap(cases().first { $0.target == "mask" })
    let owner = try DocumentMaskStrokeSession(document: value.original, command: value.command([], released: true))
    let first = try owner.append([StrokePoint(x: 20, y: 20, time: 10)])
    let before = try reference(first, for: value, samples: 1, released: true)
    XCTAssertThrowsError(try owner.append([StrokePoint(x: 30, y: 20, time: 5)]))
    XCTAssertThrowsError(try owner.append([StrokePoint(x: 30, y: 20, time: 20)]))
    XCTAssertEqual(try reference(first, for: value, samples: 1, released: true), before)
    XCTAssertEqual(value.original.layers[0].mask?.defaultPixel, .white)
  }
  func testFallbackAndDisabledAdjustmentMaskRetainCanonicalAdmission() throws {
    let values = try cases()
    let ordinary = try XCTUnwrap(values.first { $0.target == "mask" })
    var brush = ordinary.brush; brush.settings!.dual.enabled = true
    let dual = Command.maskStroke(ordinary.layerID, ordinary.points, brush)
    XCTAssertFalse(DocumentMaskStrokeSession.supports(document: ordinary.original, command: dual))
    XCTAssertThrowsError(try DocumentMaskStrokeSession(document: ordinary.original, command: dual))
    var source = ordinary.original; source.layers[0].mask = nil
    XCTAssertFalse(DocumentMaskStrokeSession.supports(document: source, command: ordinary.command([], released: true)))
    let adjustment = try XCTUnwrap(values.first { $0.target == "existing" })
    var disabled = adjustment.original; disabled.layers[1].maskProperties?.enabled = false
    let command = adjustment.command(adjustment.points, released: true)
    XCTAssertThrowsError(try DocumentMaskStrokeSession(document: disabled, command: command))
    XCTAssertThrowsError(try command.apply(to: &disabled))
    var opacity = ordinary.brush; opacity.color = Pixel(.infinity, 0, 0)
    XCTAssertThrowsError(try DocumentMaskStrokeSession(document: ordinary.original,
      command: .maskStroke(ordinary.layerID, [], opacity)))
  }
  func testCancelledAppendCannotPublishOrCommit() async throws {
    let value = try XCTUnwrap(cases().first { $0.target == "new" })
    let document = value.original, command = value.command([], released: true), point = value.points[0]
    let task = Task.detached { () throws -> CraftDocument in
      let owner = try DocumentMaskStrokeSession(document: document, command: command)
      withUnsafeCurrentTask { $0?.cancel() }
      return try owner.append([point])
    }
    do { _ = try await task.value; XCTFail("Cancelled stroke published") }
    catch is CancellationError { }
    XCTAssertEqual(document.layers.count, 1)
  }
}
