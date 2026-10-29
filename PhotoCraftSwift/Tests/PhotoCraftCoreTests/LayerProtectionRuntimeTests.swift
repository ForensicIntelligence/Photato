import Foundation
import XCTest
@testable import PhotoCraftCore

final class LayerProtectionRuntimeTests: XCTestCase {
  func fixture(_ protection: LayerProtection = []) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 1)
    var s = try Surface(width: 4, height: 1)
    for (x, a) in ([0, 64 / 255, 128 / 255, 1] as [Float]).enumerated() {
      s.setPixel(x: x, y: 0, Pixel(0.25, 0.5, 0.75, a))
    }
    d.layers[0].content = .raster(s)
    d.layers[0].protection = protection
    return d
  }
  func pixels(_ d: CraftDocument) throws -> Surface {
    guard case .raster(let s) = d.layers[0].content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func testLegacyBoolAndExplicitBitsArchiveHistory() throws {
    for raw in UInt32(0)...15 {
      for high: UInt32 in [0, 0x8000_0000] {
        let flags = LayerProtection(rawValue: raw | high)
        let d = try fixture(flags)
        XCTAssertEqual(d.layers[0].protection, flags)
        let legacy = try NativeArchive.encode(d)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: legacy, format: nil) as? [String: Any])
        XCTAssertEqual(plist["version"] as? Int, d.requiresPartialProtectionArchive ? 12 : 10)
        XCTAssertEqual(try NativeArchive.decode(legacy), d)
        let chunked = try NativeArchive.encodeChunked(d)
        XCTAssertEqual(chunked[8], d.requiresPartialProtectionArchive ? 12 : 11)
        XCTAssertEqual(try NativeArchive.decode(chunked), d)
        var session = EditorSession(document: try fixture())
        let before = session.document
        try session.execute(.protection([before.layers[0].id: flags]))
        XCTAssertEqual(session.document.layers[0].protection, flags)
        if !flags.isEmpty {
          try session.undo(); XCTAssertEqual(session.document, before)
          try session.redo(); XCTAssertEqual(session.document.layers[0].protection, flags)
        }
      }
    }
    var d = try fixture(); d.layers[0].locked = true
    d.layers[0].sourceTags = ["lspf": Data([0, 0, 0, 1])]
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)).layers[0].protection, .fullyLocked)
  }
  func testOperationSpecificLocksAreAtomicAndInherited() throws {
    var d = try fixture(.image)
    let id = d.layers[0].id
    var session = EditorSession(document: d)
    for command: Command in [.fill(id, .black), .clear(id), .applyAdjustment(id, .invert)] {
      XCTAssertThrowsError(try session.execute(command)); XCTAssertEqual(session.document, d)
    }
    try session.execute(.move(id, 1, 2))
    try session.execute(.opacity(id, 0.5))
    d.layers[0].protection = .position; session = EditorSession(document: d)
    XCTAssertThrowsError(try session.execute(.move(id, 1, 2)))
    try session.execute(.fill(id, .black))
    var group = Layer(name: "Group", content: .group(GroupContent()))
    group.protection = [.position, .image]
    d.layers[0].parentID = group.id; d.layers.append(group)
    session = EditorSession(document: d)
    XCTAssertThrowsError(try session.execute(.fill(id, .black)))
    XCTAssertThrowsError(try session.execute(.move(group.id, 2, 2)))
    XCTAssertEqual(session.document, d)
    try session.execute(.protection([group.id: .fullyLocked]))
    try session.execute(.renameLayer(id, "Renamed While Locked"))
    XCTAssertEqual(session.document.layers[0].name, "Renamed While Locked")
    let before = session.document
    XCTAssertThrowsError(try session.execute(.protection([id: [], UUID(): .position])))
    XCTAssertEqual(session.document, before)
  }
  func testProtectedFillBrushAndEraserPreserveAlphaButClearErases() throws {
    let d = try fixture(.transparency), id = d.layers[0].id
    let original = try pixels(d)
    var brush = Brush(); brush.size = 20; brush.hardness = 1; brush.color = .black
    var eraser = brush; eraser.erase = true; eraser.backgroundColor = Pixel(1, 0, 0)
    let point = [StrokePoint(x: 2, y: 0.5)]
    for command: Command in [.fill(id, .black), .stroke(id, point, brush), .stroke(id, point, eraser)] {
      var session = EditorSession(document: d); try session.execute(command)
      let result = try pixels(session.document)
      for x in 0..<4 { XCTAssertEqual(result.pixel(x: x, y: 0).a, original.pixel(x: x, y: 0).a) }
      XCTAssertEqual(result.pixel(x: 0, y: 0), original.pixel(x: 0, y: 0))
      XCTAssertNotEqual(result.pixel(x: 3, y: 0), original.pixel(x: 3, y: 0))
      try session.undo(); XCTAssertEqual(session.document, d)
    }
    var session = EditorSession(document: d)
    try session.execute(.selection(IntRect(x: 0, y: 0, width: 4, height: 1)))
    try session.execute(.clear(id))
    let cleared = try pixels(session.document)
    for x in 0..<4 { XCTAssertEqual(cleared.pixel(x: x, y: 0).a, 0) }
    XCTAssertEqual(session.document.layers[0].protection, .transparency)
    // A Fill must not create higher-precision RGB samples in an integer surface.
    // Include a sparse default and an untouched pixel outside the selection.
    for depth: PixelDepth in [.u8, .u16] {
      var model = try CraftDocument(width: 2, height: 1, depth: depth)
      let source = try Surface(width: 2, height: 1, depth: depth,
        fill: Pixel(0.1, 0.2, 0.3, 0.4))
      model.layers[0].content = .raster(source)
      model.layers[0].protection = .transparency
      var fill = EditorSession(document: model)
      try fill.execute(.selection(IntRect(x: 0, y: 0, width: 1, height: 1)))
      let beforeFill = fill.document
      try fill.execute(.fill(model.layers[0].id, Pixel(0.3, 0.5, 0.7, 0.2)))
      let actual = try pixels(fill.document)
      let changed = actual.pixel(x: 0, y: 0)
      XCTAssertEqual(changed, changed.quantized(depth), "Integer storage invariant")
      XCTAssertEqual(changed.a, source.pixel(x: 0, y: 0).a)
      XCTAssertEqual(actual.pixel(x: 1, y: 0), source.pixel(x: 1, y: 0))
      try fill.undo(); XCTAssertEqual(fill.document, beforeFill)
    }
  }
  func testEveryRetouchFamilyPreservesProtectedAlphaAndBounds() throws {
    for depth: PixelDepth in [.u8, .u16, .f32] {
      var d = try CraftDocument(width: 12, height: 12, depth: depth)
      var surface = try Surface(width: 4, height: 4, depth: depth)
      for y in 0..<4 { for x in 0..<4 {
        surface.setPixel(x: x, y: y, Pixel(Float(x)/4, Float(y)/4, 0.5, Float(x)/3))
      } }
      d.layers[0].content = .raster(surface); d.layers[0].protection = .transparency
      let id = d.layers[0].id
      let sample = CloneSample(surface: try Surface(width: 12, height: 12, depth: depth, fill: .white))
      var brush = CloneBrush(); brush.size = 8; brush.opacity = 1; brush.flow = 1
      let points = [StrokePoint(x: 2, y: 2), StrokePoint(x: 7, y: 7)]
      let clone = CloneStroke(source: sample, mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: brush, points: points)
      let gradient = GradientStroke(gradient: .init(colors: [.init(0, .rgb(.black)), .init(1, .rgb(.white))]), start: .init(0, 0), end: .init(10, 10))
      var commands: [Command] = [.cloneStamp(id, clone), .healingBrush(id, .init(stroke: clone)),
        .paintBucket(id, .init(source: sample, seed: .init(2, 2), color: .black)),
        .paintGradient(id, gradient)]
      commands += FocusTool.allCases.map { .focus(id, .init(tool: $0, brush: brush, points: points)) }
      commands += ToningTool.allCases.map { .toning(id, .init(tool: $0, brush: brush, points: points)) }
      commands += SpotHealingType.allCases.map { .spotHealing(id, .init(sample: sample, brush: brush, points: points, kind: $0)) }
      for command in commands {
        var session = EditorSession(document: d); try session.execute(command)
        let result = try pixels(session.document)
        XCTAssertEqual(result.width, surface.width, command.label)
        XCTAssertEqual(result.height, surface.height, command.label)
        for y in 0..<4 { for x in 0..<4 {
          XCTAssertEqual(result.pixel(x: x, y: y).a, surface.pixel(x: x, y: y).a, command.label)
          if x == 0 { XCTAssertEqual(result.pixel(x: x, y: y), surface.pixel(x: x, y: y), command.label) }
        } }
        if session.document != d { try session.undo(); XCTAssertEqual(session.document, d) }
      }
    }
  }

}
