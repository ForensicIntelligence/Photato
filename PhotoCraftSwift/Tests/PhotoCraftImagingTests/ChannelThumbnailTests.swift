import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class ChannelThumbnailTests: XCTestCase {
  func testIndependentComponentsAtEveryDepthPreserveSourceSamplesAndAlpha() throws {
    for depth in PixelDepth.allCases {
      var source = try Surface(width: 3, height: 2, depth: depth)
      source.setPixel(x: 0, y: 0, Pixel(0.2, 0.6, 0.9, 0.4))
      source.setPixel(x: 1, y: 1, Pixel(1, 0, 0.5, 1))
      let before = source
      let thumbnails = try Renderer.channelThumbnails(source, maximumSize: 64)
      XCTAssertEqual(thumbnails.count, 4)
      XCTAssertEqual(thumbnails[0], source)
      for y in 0..<2 {
        for x in 0..<3 {
          let pixel = source.pixel(x: x, y: y)
          for (index, value) in [pixel.r, pixel.g, pixel.b].enumerated() {
            XCTAssertEqual(
              thumbnails[index + 1].pixel(x: x, y: y), Pixel(value, value, value, pixel.a))
            XCTAssertEqual(thumbnails[index + 1].depth, depth)
          }
        }
      }
      XCTAssertEqual(source, before)
    }
  }

  func testPremultipliedAreaReductionRetainsFineContentWithoutHiddenColorBleed() throws {
    var source = try Surface(width: 100, height: 2, depth: .f32, fill: Pixel(0, 1, 0, 0))
    source.setPixel(x: 47, y: 0, Pixel(1, 0.25, 0.5, 1))
    let thumbnails = try Renderer.channelThumbnails(source, maximumSize: 1)
    let expected = [
      Pixel(1, 0.25, 0.5, 0.005), Pixel(1, 1, 1, 0.005),
      Pixel(0.25, 0.25, 0.25, 0.005), Pixel(0.5, 0.5, 0.5, 0.005),
    ]
    for (thumbnail, pixel) in zip(thumbnails, expected) {
      XCTAssertEqual(thumbnail.width, 1)
      XCTAssertEqual(thumbnail.height, 1)
      XCTAssertEqual(thumbnail.pixel(x: 0, y: 0), pixel)
    }
  }

  func testWideAndTallImagesStayBoundedAndTransparentDefaultsRemainTransparent() throws {
    for (w, h) in [(30000, 1), (1, 30000)] {
      let source = try Surface(width: w, height: h, fill: .clear)
      let thumbnails = try Renderer.channelThumbnails(source, maximumSize: 82)
      for thumbnail in thumbnails {
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), 82)
        XCTAssertEqual(min(thumbnail.width, thumbnail.height), 1)
        XCTAssertNil(try thumbnail.contentBounds())
      }
    }
  }

  func testCompositeReflectsLayerVisibilityOpacityAndMasks() throws {
    var document = try ChannelCompositeFixture.document()
    let source = try Renderer.composite(document)
    let thumbnails = try Renderer.channelThumbnails(source, maximumSize: 2)
    XCTAssertEqual(thumbnails[0], source)
    let p = source.pixel(x: 0, y: 0)
    XCTAssertEqual(thumbnails[1].pixel(x: 0, y: 0), Pixel(p.r, p.r, p.r, p.a))
    document.layers[1].visible = false
    XCTAssertNotEqual(
      try Renderer.channelThumbnails(Renderer.composite(document), maximumSize: 2), thumbnails)
  }

  func testInvalidSizesRejected() throws {
    let source = try Surface(width: 2, height: 2)
    for size in [Int.min, -1, 0, 513, Int.max] {
      XCTAssertThrowsError(try Renderer.channelThumbnails(source, maximumSize: size))
    }
  }

  func testCancelledRequestStopsBeforeSampling() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try Renderer.channelThumbnails(Surface(width: 1200, height: 800), maximumSize: 82)
    }
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}

private enum ChannelCompositeFixture {
  static func document() throws -> CraftDocument {
    var document = try CraftDocument(width: 2, height: 1)
    document.layers = [
      Layer(
        name: "Base", content: .raster(try Surface(width: 2, height: 1, fill: Pixel(0.1, 0.2, 0.4)))
      )
    ]
    var top = Layer(
      name: "Top", content: .raster(try Surface(width: 2, height: 1, fill: Pixel(0.8, 0.4, 0.2))))
    top.opacity = 0.5
    var mask = try Surface(width: 2, height: 1, fill: .white)
    mask.setPixel(x: 1, y: 0, .black)
    top.mask = mask
    document.layers.append(top)
    document.activeLayerID = top.id
    return document
  }
}
