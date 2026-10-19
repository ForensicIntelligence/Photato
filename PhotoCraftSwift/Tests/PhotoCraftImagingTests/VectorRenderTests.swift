import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class VectorRenderTests: XCTestCase {
  func rect(
    _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ operation: PathOperation = .combine
  ) -> PathComponent {
    PathComponent(
      knots: [
        PathPoint(x, y), PathPoint(x + w, y), PathPoint(x + w, y + h),
        PathPoint(x, y + h),
      ].map { PathKnot($0) }, closed: true, operation: operation)
  }
  func testBooleanCoverageAndJoinedWindingHoles() throws {
    for operation in [PathOperation.combine, .subtract, .intersect, .exclude] {
      let path = VectorPath(components: [rect(2, 2, 8, 8), rect(6, 6, 8, 8, operation)])
      let mask = try VectorRasterizer.coverage(path, width: 16, height: 16)
      XCTAssertEqual(mask.coverage(x: 3, y: 3), operation == .intersect ? 0 : 1)
      XCTAssertEqual(mask.coverage(x: 7, y: 7), [.combine, .intersect].contains(operation) ? 1 : 0)
      XCTAssertEqual(mask.coverage(x: 12, y: 12), [.combine, .exclude].contains(operation) ? 1 : 0)
    }
    var hole = rect(4, 4, 4, 4, .join)
    hole.knots.reverse()
    var path = VectorPath(components: [rect(2, 2, 12, 12), hole])
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 6, y: 6), 0)
    path.components[1].knots.reverse()
    path.fillRule = .evenOdd
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 6, y: 6), 0)
    path.inverted = true
    XCTAssertEqual(
      try VectorRasterizer.coverage(path, width: 16, height: 16).coverage(x: 0, y: 0), 1)
  }
  func testPixelAndVectorMasksMultiplyAtEveryDepthIncludingGroups() throws {
    for depth in PixelDepth.allCases {
      for group in [false, true] {
        var d = try CraftDocument(width: 16, height: 16, depth: depth)
        var masked = Layer(name: "Masked", content: group ? .group(GroupContent()) : .fill(.white))
        masked.vectorMask = VectorMask(path: VectorPath(components: [rect(2, 2, 8, 8)]))
        masked.vectorMask!.density = 0.75
        masked.mask = try Surface(width: 16, height: 16, depth: .f32, fill: Pixel(0.4, 0.4, 0.4))
        var child = Layer(name: "White", content: .fill(.white))
        child.parentID = masked.id
        d.layers = group ? [child, masked] : [masked]
        d.activeLayerID = masked.id
        let image = try Renderer.composite(d)
        XCTAssertEqual(image.pixel(x: 3, y: 3).a, 0.4, accuracy: 1e-6)
        XCTAssertEqual(image.pixel(x: 13, y: 13).a, 0.1, accuracy: 1e-6)
        d.layers[d.layers.count - 1].vectorMask!.enabled = false
        XCTAssertEqual(try Renderer.composite(d).pixel(x: 13, y: 13).a, 0.4, accuracy: 1e-6)
      }
    }
  }
  func testEmptyMaskRevealsAllAndFeatherDoesNotClipAtCanvasEdge() throws {
    var d = try CraftDocument(width: 20, height: 16)
    d.layers[0].vectorMask = VectorMask()
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).a, 1)
    d.layers[0].vectorMask!.path.inverted = true
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).a, 0)
    d.layers[0].vectorMask = VectorMask(path: VectorPath(components: [rect(-40, -40, 48, 100)]))
    d.layers[0].vectorMask!.feather = 1.5
    let image = try Renderer.composite(d)
    XCTAssertEqual(image.pixel(x: 0, y: 0).a, 1, accuracy: 0.001)
    XCTAssertGreaterThan(image.pixel(x: 8, y: 5).a, 0.3)
    XCTAssertLessThan(image.pixel(x: 8, y: 5).a, 0.5)
  }
  func testPSDPathFixedPointRoundTripAndMalformedRecords() throws {
    var path = VectorPath(components: [
      rect(-3.125, 4.25, 20.5, 13.75), rect(5, 8, 4, 4, .subtract),
    ])
    path.components[0].knots[0].outgoing = PathPoint(4, -12)
    path.components[0].knots[0].smooth = true
    let data = try PSDPaths.write(path, width: 128, height: 64)
    XCTAssertEqual(try PSDPaths.read(data, width: 128, height: 64), path)
    XCTAssertThrowsError(try PSDPaths.read(data.dropLast(), width: 128, height: 64))
    var truncated = data
    truncated[54] = 0
    truncated[55] = 255
    XCTAssertThrowsError(try PSDPaths.read(truncated, width: 128, height: 64))
    for empty in [false, true] {
      for inverted in [false, true] {
        var mask = VectorMask(path: empty ? VectorPath() : path)
        mask.path.inverted = inverted
        mask.enabled = false
        mask.linked = false
        XCTAssertEqual(
          try PSDPaths.readMask(
            PSDPaths.writeMask(mask, width: 128, height: 64),
            width: 128, height: 64), mask)
      }
    }
    path.components[0].knots[0].anchor.x = 20_000
    XCTAssertThrowsError(try PSDPaths.write(path, width: 16, height: 16))
  }
  func assertPath(
    _ a: VectorPath, _ b: VectorPath, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(a.components.count, b.components.count, file: file, line: line)
    XCTAssertEqual(a.inverted, b.inverted, file: file, line: line)
    for (a, b) in zip(a.components, b.components) {
      XCTAssertEqual(a.operation, b.operation, file: file, line: line)
      XCTAssertEqual(a.closed, b.closed, file: file, line: line)
      XCTAssertEqual(a.knots.count, b.knots.count, file: file, line: line)
      for (a, b) in zip(a.knots, b.knots) {
        XCTAssertEqual(a.smooth, b.smooth, file: file, line: line)
        for (a, b) in zip([a.anchor, a.incoming, a.outgoing], [b.anchor, b.incoming, b.outgoing]) {
          XCTAssertEqual(a.x, b.x, accuracy: 0.00001, file: file, line: line)
          XCTAssertEqual(a.y, b.y, accuracy: 0.00001, file: file, line: line)
        }
      }
    }
  }
  func testPhotoshopVectorMasksAndPathsMatchSavedComposite() throws {
    for depth in [8, 16, 32] { try comparePhotoshopVector(depth) }
  }
  func comparePhotoshopVector(_ depth: Int) throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-vector-\(depth)", withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let d = try PSDCodec.read(data)
    let original = try fixture(depth: d.depth)
    XCTAssertEqual(d.layers.filter { $0.vectorMask != nil }.count, 2)
    XCTAssertEqual(d.layers.filter { $0.mask != nil }.count, 1)
    XCTAssertEqual(d.paths?.count, 2)
    for (a, b) in zip(original.layers, d.layers) {
      if let a = a.vectorMask, let b = b.vectorMask {
        assertPath(a.path, b.path)
        XCTAssertEqual(a.density, b.density, accuracy: 1 / 255)
        XCTAssertEqual(a.feather, b.feather)
      }
    }
    let native = try Renderer.composite(d)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let reference = try RasterIO.surface(image, depth: d.depth)
    var maximum: Float = 0
    var encodedMaximum: Float = 0
    var worst = ""
    for y in 0..<d.height {
      for x in 0..<d.width {
        var a = native.pixel(x: x, y: y)
        var b = reference.pixel(x: x, y: y)
        encodedMaximum = max(encodedMaximum, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
        if d.depth == .f32 {
          a = SRGBTransfer.linear(a)
          b = SRGBTransfer.linear(b)
        }
        let delta = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
        if delta > maximum {
          maximum = delta
          worst = "\(x),\(y): \(a) vs \(b)"
        }
      }
    }
    print(
      "Photoshop vector RGB/\(depth): max working-space channel difference \(maximum), encoded sRGB \(encodedMaximum) at \(worst)"
    )
    // Current Core Graphics edge rasterization/CPU feather is not pixel-identical to Photoshop.
    // Keep the measured tolerance explicit; do not relax the high-depth pixel/channel tests.
    XCTAssertLessThanOrEqual(maximum, 4 / 255)
  }
  func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 128, height: 96, depth: depth, name: "Editable vector masks")
    var path = VectorPath(components: [rect(12, 12, 84, 64), rect(38, 30, 28, 24, .subtract)])
    path.components[0].knots[0].outgoing = PathPoint(32, -4)
    path.components[0].knots[1].incoming = PathPoint(80, 36)
    d.paths = [
      NamedPath(name: "Cutout", path: path, isWorkPath: false),
      NamedPath(path: VectorPath(components: [rect(5, 5, 7, 7)])),
    ]
    var layer = Layer(
      name: "Blue curved cutout",
      content: .raster(
        try Surface(
          width: 128, height: 96,
          depth: depth, fill: Pixel(0.1, 0.4, 0.9))))
    layer.vectorMask = VectorMask(path: path)
    layer.vectorMask!.feather = 1.5
    layer.vectorMask!.density = 0.8
    layer.mask = try Surface(width: 128, height: 96, depth: depth, fill: Pixel(0.7, 0.7, 0.7))
    d.layers.append(layer)
    var vectorOnly = Layer(
      name: "Vector only",
      content: .raster(
        try Surface(
          width: 128, height: 96,
          depth: depth, fill: Pixel(0.9, 0.2, 0.1))))
    vectorOnly.vectorMask = VectorMask(path: VectorPath(components: [rect(98, 10, 16, 30)]))
    vectorOnly.vectorMask!.density = 0.75
    vectorOnly.vectorMask!.feather = 2
    d.layers.append(vectorOnly)
    d.activeLayerID = layer.id
    return d
  }
  func testPSDVectorMetadataAndSavedPathsRoundTripAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth: depth)
      let bytes = try PSDCodec.writeRasterLayers(source)
      let decoded = try PSDCodec.read(bytes)
      for (a, b) in zip(source.layers, decoded.layers) {
        if let a = a.vectorMask?.path, let b = b.vectorMask?.path {
          assertPath(a, b)
        } else {
          XCTAssertEqual(a.vectorMask == nil, b.vectorMask == nil)
        }
        XCTAssertEqual(a.vectorMask?.feather, b.vectorMask?.feather)
        XCTAssertEqual(a.vectorMask?.enabled, b.vectorMask?.enabled)
        if let a = a.vectorMask, let b = b.vectorMask {
          XCTAssertEqual(a.density, b.density, accuracy: 1 / 255)
        }
        XCTAssertEqual(a.mask != nil, b.mask != nil)
      }
      for (a, b) in zip(source.paths ?? [], decoded.paths ?? []) { assertPath(a.path, b.path) }
      XCTAssertEqual(source.paths?.map(\.isWorkPath), decoded.paths?.map(\.isWorkPath))
      let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("artifacts/native-vector-\(depth.rawValue).psd")
      try bytes.write(to: output)
      let native = try Renderer.composite(source)
      let restored = try Renderer.composite(decoded)
      for y in 0..<96 {
        for x in 0..<128 {
          let a = native.pixel(x: x, y: y)
          let b = restored.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: 0.003)
          XCTAssertEqual(a.b, b.b, accuracy: 0.003)
        }
      }
    }
  }
}
