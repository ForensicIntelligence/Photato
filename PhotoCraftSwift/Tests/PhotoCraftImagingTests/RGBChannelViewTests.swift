import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class RGBChannelViewTests: XCTestCase {
  // Independent Photoshop27.2 observations: steps100/101, original RGB probe.
  func testEyeVisibilityDoesNotChangePreviewAndCannotHideLastComponent() {
    var view = RGBChannelView()
    view.setVisible(.blue, false)
    XCTAssertEqual(view.preview, .composite)
    XCTAssertEqual(view.visible, [.red, .green])
    XCTAssertFalse(view.isVisible(.composite))
    view.setVisible(.green, false)
    XCTAssertEqual(view.visible, [.red])
    let before = view
    view.setVisible(.red, false)
    view.setVisible(.composite, false)
    XCTAssertEqual(view, before)
    view.setVisible(.composite, true)
    XCTAssertTrue(view.isVisible(.composite))
  }

  func testRowSelectionPreservesCustomVisibleTargetButIsolatesHiddenTarget() {
    var view = RGBChannelView()
    view.selectPreview(.red)
    XCTAssertEqual(view.visible, [.red])
    view.setVisible(.green, true)
    view.selectPreview(.red)
    XCTAssertEqual(view.visible, [.red, .green])
    view.selectPreview(.green)
    XCTAssertEqual(view.preview, .green)
    XCTAssertEqual(view.visible, [.red, .green])
    view.selectPreview(.blue)
    XCTAssertEqual(view.visible, [.blue])
    view.setVisible(.composite, true)
    view.selectPreview(.green)
    XCTAssertEqual(view.visible, RGBChannelView.components)
    view.selectPreview(.composite)
    view.selectPreview(.green)
    XCTAssertEqual(view.visible, [.green])
  }

  func testAllSevenVisibilityCombinationsAtEveryDepthPreserveStoredSourceAndAlpha() throws {
    for depth in PixelDepth.allCases {
      var source = try Surface(width: 3, height: 2, depth: depth, fill: Pixel(0.2, 0.4, 0.8, 0.6))
      source.setPixel(x: 1, y: 1, depth == .f32 ? Pixel(-0.25, 2, 8, 0.5) : Pixel(0.1, 0.7, 0.3, 0))
      let before = source
      for mask in 1...7 {
        var view = RGBChannelView()
        for (bit, component) in [RGBChannelPreview.red, .green, .blue].enumerated() {
          view.setVisible(component, mask & (1 << bit) != 0)
        }
        let output = try view.applying(to: source)
        for y in 0..<2 {
          for x in 0..<3 {
            let p = source.pixel(x: x, y: y)
            let values = [p.r, p.g, p.b]
            let selected = (0..<3).filter { mask & (1 << $0) != 0 }
            let expected: Pixel
            if selected.count == 1 {
              let v = values[selected[0]]
              expected = Pixel(v, v, v, p.a)
            } else {
              expected = Pixel(
                mask & 1 != 0 ? p.r : 0, mask & 2 != 0 ? p.g : 0, mask & 4 != 0 ? p.b : 0, p.a)
            }
            XCTAssertEqual(output.pixel(x: x, y: y), expected, "depth \(depth), mask \(mask)")
          }
        }
        XCTAssertEqual(output.depth, depth)
        XCTAssertEqual(source, before)
      }
    }
  }

  func testCancelledDisplayDoesNotProduceAnImage() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try RGBChannelView(preview: .red).applying(to: Surface(width: 3, height: 2))
    }
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}
