import PhotoCraftCore
import PhotoCraftImaging
import XCTest

final class IncrementalMaskBrushRendererTests: XCTestCase {
  func testAllDepthsCroppedAndTransformedMasksMatchCompletePrefixAndFinalRenders() throws {
    for depth in PixelDepth.allCases { for target in 0..<3 { for cropped in [false, true] {
      var source = try CraftDocument(width: 72, height: 48, depth: depth)
      var pixels = try Surface(width: 72, height: 48, depth: depth)
      pixels.mapPixels { x, y, _ in Pixel(Float(x + 1) / 74, Float(y + 1) / 50, 0.4, 0.8) }
      source.layers[0].content = .raster(pixels)
      if target == 1 {
        let layer = Layer(name: "Colour", content: .adjustment(AdjustmentBrushKind.colorVibrance.initial))
        source.layers.append(layer); source.activeLayerID = layer.id
      }
      let index = source.layers.count - 1, id = source.layers[index].id
      if target != 2 {
        source.layers[index].mask = try Surface(width: cropped ? 22 : 72, height: cropped ? 18 : 48,
          depth: depth, fill: target == 0 ? .white : .black)
        if cropped {
          source.layers[index].maskProperties = .init()
          source.layers[index].maskProperties?.transform = .translation(19, 12) * .rotation(7)
        }
      }
      source.selection = .init(x: 6, y: 6, width: 58, height: 34)
      var brush = Brush(); brush.settings = .init(); brush.settings?.seed = 123
      brush.settings?.flow = 0.63; brush.settings?.smoothing.amount = 0.8
      brush.size = 9; brush.opacity = 0.7; brush.color = .black
      let newID = UUID()
      func command(_ points: [StrokePoint]) -> Command {
        if target == 0 { return .maskStroke(id, points, brush) }
        return .adjustmentBrush(.init(layerID: target == 1 ? id : nil, newLayerID: newID,
          adjustment: AdjustmentBrushKind.colorVibrance.initial, points: points, brush: brush))
      }
      let points: [StrokePoint] = [.init(x: 12, y: 20, pressure: 0.5, time: 0),
        .init(x: 27, y: 25, pressure: 0.8, time: 12), .init(x: 42, y: 18, time: 24),
        .init(x: 59, y: 31, pressure: 0.6, time: 36)]
      let renderer = try IncrementalMaskBrushRenderer(document: source, command: command([]))
      var previous: RenderSnapshot?, retained: [RenderSnapshot] = [], canonical: [CraftDocument] = []
      for point in points {
        let count = renderer.sampleCount + 1
        var expected = source; try command(Array(points.prefix(count))).apply(to: &expected)
        let snapshot = try renderer.append([point], reusing: previous)
        XCTAssertEqual(snapshot.document, expected)
        XCTAssertEqual(snapshot.surface, try Renderer.composite(expected))
        retained.append(snapshot); canonical.append(expected); previous = snapshot
        for (old, document) in zip(retained, canonical) {
          XCTAssertEqual(old.document, document)
          XCTAssertEqual(old.surface, try Renderer.composite(document))
        }
      }
      var session = EditorSession(document: source)
      try session.executePrepared(renderer.prepareEdit(points: points))
      XCTAssertEqual(session.document, canonical.last); XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, source)
      try session.redo(); XCTAssertEqual(session.document, canonical.last)
    } } }
  }

  func testMaskLightPauseOnlyChangesPresentationAndCommitRestoresFullParameters() throws {
    for adjustment in [false, true] {
      var source = try LightEditingPreviewTests().fixture(.u16)
      let target = source.layers[0].id
      source.layers[0].mask = try Surface(width: source.width, height: source.height, depth: .u16, fill: .white)
      var brush = Brush(); brush.settings = .init(); brush.settings?.seed = 42
      brush.color = .black; brush.size = 12; brush.settings?.smoothing.amount = 0
      let points: [StrokePoint] = [.init(x: 35, y: 40), .init(x: 90, y: 60)]
      let command: Command
      if adjustment {
        var colour = Layer(name: "Colour", content: .adjustment(AdjustmentBrushKind.colorVibrance.initial))
        colour.mask = try Surface(width: source.width, height: source.height, depth: .u16, fill: .black)
        source.layers.insert(colour, at: 1)
        command = .adjustmentBrush(.init(layerID: colour.id,
          adjustment: AdjustmentBrushKind.colorVibrance.initial, points: points, brush: brush))
      } else { command = .maskStroke(target, points, brush) }
      let renderer = try IncrementalMaskBrushRenderer(document: source, command: command, pausingLightWhileEditing: !adjustment)
      let snapshot = try renderer.append(points, reusing: nil)
      var expected = source; try command.apply(to: &expected)
      let presentation = adjustment ? expected : LightEditingPreview(document: source, editingLayers: [target]).project(expected)
      XCTAssertEqual(snapshot.document, presentation)
      XCTAssertEqual(snapshot.surface, try Renderer.composite(presentation))
      if !adjustment { XCTAssertNotEqual(snapshot.document.layers[1], expected.layers[1]) }
      var session = EditorSession(document: source)
      try session.executePrepared(renderer.prepareEdit(points: points))
      XCTAssertEqual(session.document, expected)
      XCTAssertEqual(try Renderer.composite(session.document), try Renderer.composite(expected))
    }
  }
}
