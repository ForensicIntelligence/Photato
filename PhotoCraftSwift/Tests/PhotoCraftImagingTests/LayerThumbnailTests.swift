import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerThumbnailTests: XCTestCase {
  func assertPixels(
    _ actual: Surface, _ expected: Surface, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.width, expected.width, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, file: file, line: line)
    XCTAssertEqual(actual.depth, expected.depth, file: file, line: line)
    for y in 0..<expected.height {
      for x in 0..<expected.width {
        XCTAssertEqual(
          actual.pixel(x: x, y: y), expected.pixel(x: x, y: y), "Pixel \(x),\(y)", file: file,
          line: line)
      }
    }
  }
  func testDocumentCoordinatesAndOccupiedBoundsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let document = try CraftDocument(width: 8, height: 4, depth: depth)
      var source = try Surface(width: 4, height: 3, depth: depth)
      source.setPixel(x: 1, y: 1, .white)
      source.setPixel(x: 2, y: 1, .black)
      var layer = Layer(name: "Offset", content: .raster(source))
      layer.x = 2
      layer.y = 1
      let canvas = try XCTUnwrap(
        Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 8))
      XCTAssertEqual(canvas.width, 8)
      XCTAssertEqual(canvas.height, 4)
      XCTAssertEqual(canvas.depth, depth)
      for y in 0..<4 {
        for x in 0..<8 {
          XCTAssertEqual(
            canvas.pixel(x: x, y: y), y == 2 && x == 3 ? .white : y == 2 && x == 4 ? .black : .clear
          )
        }
      }
      let cropped = try XCTUnwrap(
        Renderer.layerThumbnail(layer, in: document, framing: .layerBounds, maximumSize: 2))
      XCTAssertEqual(cropped.width, 2)
      XCTAssertEqual(cropped.height, 1)
      XCTAssertEqual(cropped.pixel(x: 0, y: 0), .white)
      XCTAssertEqual(cropped.pixel(x: 1, y: 0), .black)
      XCTAssertEqual(cropped.depth, depth)
    }
  }

  func testRotatedAndOffCanvasContentUsesTransformedBounds() throws {
    let document = try CraftDocument(width: 4, height: 4)
    var source = try Surface(width: 2, height: 1)
    source.setPixel(x: 0, y: 0, .white)
    source.setPixel(x: 1, y: 0, .black)
    var layer = Layer(name: "Rotated", content: .raster(source))
    layer.affine = .translation(-3, -4) * .rotation(90)
    let cropped = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .layerBounds, maximumSize: 2))
    XCTAssertEqual(cropped.width, 1)
    XCTAssertEqual(cropped.height, 2)
    XCTAssertEqual(cropped.pixel(x: 0, y: 0), .white)
    XCTAssertEqual(cropped.pixel(x: 0, y: 1), .black)
    XCTAssertNil(
      try Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 4)?
        .contentBounds())
  }

  func testPreviewIgnoresVisibilityOpacityAndMasksWithoutEditingLayer() throws {
    let document = try CraftDocument(width: 4, height: 2)
    var layer = Layer(
      name: "Hidden", content: .raster(try Surface(width: 4, height: 2, fill: .white)))
    layer.visible = false
    layer.opacity = 0
    layer.mask = try Surface(width: 4, height: 2, fill: .black)
    layer.vectorMask = VectorMask()
    let before = layer
    let preview = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 4))
    assertPixels(preview, try Surface(width: 4, height: 2, fill: .white))
    XCTAssertEqual(layer, before)
  }

  func testEmptyHiddenRGBAndWideCanvasStayBounded() throws {
    let document = try CraftDocument(width: 30000, height: 1)
    let layer = Layer(
      name: "Empty", content: .raster(try Surface(width: 1, height: 1, fill: Pixel(1, 0, 1, 0))))
    for framing in ThumbnailFraming.allCases {
      let preview = try XCTUnwrap(
        Renderer.layerThumbnail(layer, in: document, framing: framing, maximumSize: 64))
      XCTAssertEqual(preview.width, 64)
      XCTAssertEqual(preview.height, 1)
      XCTAssertNil(try preview.contentBounds())
    }
  }

  func testCanvasFillsAreNotTransformedTwice() throws {
    let document = try CraftDocument(width: 8, height: 4)
    for content in [LayerContent.fill(.white), .gradientFill(GradientFill(dither: false))] {
      var layer = Layer(name: "Fill", content: content)
      layer.affine = .translation(100, 100)
      let source = try Renderer.layerSurface(layer, in: document)
      for framing in ThumbnailFraming.allCases {
        assertPixels(
          try XCTUnwrap(
            Renderer.layerThumbnail(layer, in: document, framing: framing, maximumSize: 8)), source)
      }
    }
  }

  func testInvalidSizesAndSingularTransformsAreRejected() throws {
    let document = try CraftDocument(width: 2, height: 2)
    var layer = document.layers[0]
    for size in [Int.min, 0, 513, Int.max] {
      XCTAssertThrowsError(
        try Renderer.layerThumbnail(layer, in: document, framing: .layerBounds, maximumSize: size))
    }
    layer.affine = .scale(0, 1)
    XCTAssertThrowsError(
      try Renderer.layerThumbnail(layer, in: document, framing: .layerBounds, maximumSize: 2))
    XCTAssertNil(
      try Renderer.layerThumbnail(
        Layer(name: "Group", content: .group(.init())), in: document, framing: .entireDocument,
        maximumSize: 2))
  }

  func testCancelledPreviewStopsBeforeRasterization() async throws {
    let document = try CraftDocument(width: 2, height: 2)
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try Renderer.layerThumbnail(
        document.layers[0], in: document, framing: .entireDocument, maximumSize: 2)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled work must throw")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
}
