import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientPaintTests: XCTestCase {
  private func pixels(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  private var blackWhite: GradientDefinition {
    var gradient = GradientDefinition.blackToWhite
    gradient.method = .classic
    gradient.smoothness = 0
    return gradient
  }
  func testOriginalRustClassicToolGeometryBitForBit() throws {
    var reader = try PatternOracleTests.Reader("gradient-tool-oracle")
    var count = 0
    while reader.offset < reader.data.count {
      let style = GradientStyle.allCases[Int(reader.u())]
      let start = PathPoint(Double(reader.f()), Double(reader.f()))
      let end = PathPoint(Double(reader.f()), Double(reader.f()))
      let x = reader.f()
      let y = reader.f()
      let expected = reader.f()
      let field = try GradientToolField(style: style, start: start, end: end)
      XCTAssertEqual(
        field.parameter(x: x, y: y).bitPattern, expected.bitPattern,
        "Rust gradient geometry sample \(count), \(style)")
      count += 1
    }
    XCTAssertEqual(count, 12_920)
    print("Classic Gradient geometry: \(count) bit-identical Rust Float32 samples")
  }
  func testPixelCenterPhaseDepthArchiveAndOneUndo() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 8, height: 3, depth: depth)
      doc.layers[0].content = .raster(try Surface(width: 8, height: 3, depth: depth))
      var stroke = GradientStroke(gradient: blackWhite, start: .init(0, 0), end: .init(8, 0))
      stroke.dither = false
      var session = EditorSession(document: doc)
      try session.execute(.paintGradient(doc.layers[0].id, stroke))
      let raster = try pixels(session.document.layers[0])
      for y in 0..<3 {
        for x in 0..<8 {
          let gray = Float(2 * x + 1) / 16
          XCTAssertTrue(
            raster.pixel(x: x, y: y).hasSameBits(as: Pixel(gray, gray, gray).quantized(depth)))
        }
      }
      let result = session.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
      XCTAssertEqual(session.undoStack.count, 1)
      session.undo()
      XCTAssertEqual(session.document, doc)
      session.redo()
      XCTAssertEqual(session.document, result)
    }
  }
  func testSelectionOpacityTransparencyReverseDitherAndBlend() throws {
    for depth in PixelDepth.allCases {
      let old = Pixel(0.2, 0.4, 0.6, 0.8).quantized(depth)
      var layer = Layer(
        name: "Pixels", content: .raster(try Surface(width: 4, height: 1, depth: depth, fill: old)))
      var gradient = blackWhite
      gradient.opacity = [.init(0, 1), .init(1, 0)]
      var stroke = GradientStroke(gradient: gradient, start: .init(0, 0), end: .init(4, 0))
      stroke.opacity = 0.5
      stroke.dither = false
      stroke.reverse = true
      let selection = try SelectionMask(width: 4, height: 1, bytes: [0, 128, 255, 255])
      for mode in [BlendMode.normal, .multiply, .screen] {
        stroke.mode = mode
        for transparent in [true, false] {
          stroke.transparency = transparent
          var result = layer
          try GradientPainter.paint(
            stroke, on: &result, canvasWidth: 4, canvasHeight: 1,
            selection: .init(x: 0, y: 0, width: 3, height: 1), selectionMask: selection)
          let raster = try pixels(result)
          XCTAssertEqual(raster.pixel(x: 0, y: 0), old)
          XCTAssertEqual(raster.pixel(x: 3, y: 0), old)
          for x in 1...2 {
            let gray = 1 - Float(2 * x + 1) / 8
            let source = Pixel(gray, gray, gray, transparent ? 1 - gray : 1)
            let linear = depth == .f32
            let blend = mode.composite(
              backdrop: linear ? SRGBTransfer.linear(old) : old,
              source: linear ? SRGBTransfer.linear(source) : source,
              opacity: 0.5 * Float(selection.bytes[x]) / 255, x: x, y: 0)
            let expected = (linear ? SRGBTransfer.encoded(blend) : blend).quantized(depth)
            XCTAssertTrue(raster.pixel(x: x, y: 0).hasSameBits(as: expected))
          }
        }
      }
      stroke.mode = .normal
      stroke.opacity = 1
      stroke.transparency = false
      stroke.dither = true
      try GradientPainter.paint(stroke, on: &layer, canvasWidth: 4, canvasHeight: 1)
      for x in 0..<4 {
        let gray = 1 - Float(2 * x + 1) / 8
        let expected = GradientRamp.dither(Pixel(gray, gray, gray), x: x, y: 0).quantized(depth)
        XCTAssertEqual(try pixels(layer).pixel(x: x, y: 0), expected)
      }
    }
  }
  func testCroppedRasterExpansionAndMaskCoordinatesArePreserved() throws {
    var layer = Layer(
      name: "Cropped", content: .raster(try Surface(width: 2, height: 2, fill: .white)))
    layer.x = 2
    layer.y = 1
    layer.mask = try Surface(width: 2, height: 2, fill: .white)
    let maskTransform = layer.maskCoordinateTransform
    var stroke = GradientStroke(gradient: blackWhite, start: .init(0, 0), end: .init(6, 0))
    stroke.dither = false
    try GradientPainter.paint(stroke, on: &layer, canvasWidth: 6, canvasHeight: 4)
    XCTAssertEqual(layer.maskCoordinateTransform, maskTransform)
    XCTAssertEqual(layer.x, 0)
    XCTAssertEqual(layer.y, 0)
    XCTAssertEqual(try pixels(layer).width, 6)
    XCTAssertEqual(try pixels(layer).height, 4)
    for x in 0..<6 {
      let gray = Float(2 * x + 1) / 12
      XCTAssertEqual(try pixels(layer).pixel(x: x, y: 2), Pixel(gray, gray, gray).quantized(.u8))
    }
    stroke.mask = true
    let content = layer.content
    try GradientPainter.paint(stroke, on: &layer, canvasWidth: 6, canvasHeight: 4)
    XCTAssertEqual(layer.content, content)
    XCTAssertEqual(layer.maskCoordinateTransform, .identity)
    XCTAssertEqual(layer.mask?.width, 6)
    for x in 0..<6 {
      let gray = Float(2 * x + 1) / 12
      XCTAssertEqual(layer.mask?.pixel(x: x, y: 1).r, Pixel(gray, gray, gray).quantized(.u8).r)
      XCTAssertEqual(layer.mask?.pixel(x: x, y: 1).a, 1)
    }
  }
  func testAllStylesMethodsAndDepthsRespectSelectedBounds() throws {
    for depth in PixelDepth.allCases {
      for style in GradientStyle.allCases {
        for method in GradientMethod.allCases {
          var gradient = blackWhite
          gradient.method = method
          var stroke = GradientStroke(gradient: gradient, start: .init(1, 2), end: .init(8, 6))
          stroke.style = style
          var layer = Layer(
            name: "Shapes", content: .raster(try Surface(width: 11, height: 9, depth: depth)))
          try GradientPainter.paint(
            stroke, on: &layer, canvasWidth: 11, canvasHeight: 9,
            selection: .init(x: 2, y: 1, width: 7, height: 6))
          let raster = try pixels(layer)
          XCTAssertEqual(raster.pixel(x: 0, y: 0), .clear)
          XCTAssertEqual(raster.pixel(x: 9, y: 3), .clear)
          XCTAssertEqual(raster.pixel(x: 5, y: 4).a, 1)
          XCTAssertTrue(raster.pixel(x: 5, y: 4).isFinite)
        }
      }
    }
  }
  func testValidationLocksZeroOpacityAndCancellationAreAtomic() async throws {
    var doc = try CraftDocument(width: 8, height: 8)
    var stroke = GradientStroke(gradient: blackWhite, start: .init(0, 0), end: .init(8, 0))
    stroke.opacity = 0
    var session = EditorSession(document: doc)
    try session.execute(.paintGradient(doc.layers[0].id, stroke))
    XCTAssertEqual(session.document, doc)
    XCTAssertTrue(session.undoStack.isEmpty)
    stroke.opacity = .nan
    XCTAssertThrowsError(try session.execute(.paintGradient(doc.layers[0].id, stroke)))
    XCTAssertEqual(session.document, doc)
    stroke.opacity = 1
    stroke.start.x = .infinity
    XCTAssertThrowsError(try session.execute(.paintGradient(doc.layers[0].id, stroke)))
    stroke.start.x = 0
    stroke.gradient = .foregroundToBackground
    XCTAssertThrowsError(try session.execute(.paintGradient(doc.layers[0].id, stroke)))
    stroke.gradient = blackWhite
    doc.layers[0].locked = true
    session = EditorSession(document: doc)
    XCTAssertThrowsError(try session.execute(.paintGradient(doc.layers[0].id, stroke)))
    doc.layers[0].locked = false
    let before = doc
    let captured = stroke
    await Task.detached {
      var copy = before
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try Command.paintGradient(copy.layers[0].id, captured).apply(to: &copy)
        XCTFail()
      } catch is CancellationError {} catch { XCTFail("\(error)") }
      XCTAssertEqual(copy, before)
    }.value
  }
}
