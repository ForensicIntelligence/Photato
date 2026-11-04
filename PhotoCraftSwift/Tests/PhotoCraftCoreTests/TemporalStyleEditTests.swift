import Foundation
import XCTest
@testable import PhotoCraftCore

final class TemporalStyleEditTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 6, height: 4, depth: depth)
    let layer = Layer(name: "Owned square", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: Pixel(1, 0, 0))))
    document.layers = [layer]; document.activeLayerID = layer.id
    return document
  }
  var blue: LayerStyle {
    var effect = LayerEffect(.colorOverlay); effect.color = Pixel(0, 0, 1)
    return LayerStyle(effects: [effect])
  }
  func testDirectVideoStyleCaptureReplacesKeysWithoutLosingIdentityOrInterpolation() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      var document = try fixture(depth); let id = document.layers[0].id
      try Command.video(.create(frameRate: 4, durationFrames: 9)).apply(to: &document)
      try Command.video(.keyframe(.enable(id, .style))).apply(to: &document)
      try document.selectVideoFrame(8)
      try LayerStyleEdit(layerIDs: [id], style: blue).apply(to: &document)
      let keys = try XCTUnwrap(document.layers[0].videoKeyframes)
      XCTAssertEqual(keys.map(\.time), [0, 2]); XCTAssertNil(keys[0].style); XCTAssertEqual(keys[1].style, blue)
      try Command.video(.keyframe(.interpolation(id, keys[1].id, .hold))).apply(to: &document)
      try LayerStyleEdit(layerIDs: [id], style: nil).apply(to: &document)
      XCTAssertEqual(document.layers[0].videoKeyframes?.map(\.id), keys.map(\.id))
      XCTAssertEqual(document.layers[0].videoKeyframes?.last?.interpolation, .hold)
      XCTAssertNil(document.layers[0].style); try document.validate()
      try LayerStyleEdit(layerIDs: [id], style: blue).apply(to: &document)
      try document.selectVideoFrame(4)
      XCTAssertEqual(document.layers[0].style?.effects.first?.opacity, 0.5)
      try document.selectVideoFrame(0); XCTAssertNil(document.layers[0].style)
      try document.selectVideoFrame(8); XCTAssertEqual(document.layers[0].style, blue)
    }
  }
  func testFrameAnimationStyleTransactionsKeepOtherFramesAndOneUndo() throws {
    for depth in [PixelDepth.u8, .u16, .f32] {
      for modern in [false, true] {
        var document = try fixture(depth)
        try Command.animation(.create).apply(to: &document)
        try Command.animation(.duplicate).apply(to: &document)
        let original = document, id = document.layers[0].id
        var session = EditorSession(document: document)
        let command: Command = modern ? .layerStyles(LayerStyleEdit(layerIDs: [id], style: blue)) : .layerStyle([id], blue)
        try session.execute(command)
        let changed = session.document, frames = try XCTUnwrap(changed.animation?.frames)
        XCTAssertNil(frames[0].layers[0].style); XCTAssertEqual(frames[1].layers[0].style, blue)
        XCTAssertEqual(session.undoStack.count, 1)
        try session.undo(); XCTAssertEqual(session.document, original)
        try session.redo(); XCTAssertEqual(session.document, changed)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(changed)), changed)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)), changed)
        try session.selectAnimationFrame(frames[0].id); XCTAssertNil(session.document.layers[0].style)
        try session.selectAnimationFrame(frames[1].id); XCTAssertEqual(session.document.layers[0].style, blue)
      }
    }
  }
  func testInvalidMultiTargetStyleEditKeepsDocumentAndTemporalStateAtomic() throws {
    var document = try fixture()
    document.layers[0].id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var second = document.layers[0]; second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    document.layers.append(second); document.activeLayerID = document.layers[0].id
    let ids = Set(document.layers.map(\.id))
    try Command.video(.create(frameRate: 4, durationFrames: 9)).apply(to: &document)
    for id in ids { try Command.video(.keyframe(.enable(id, .style))).apply(to: &document) }
    try document.selectVideoFrame(8)
    document.layers[1].locked = true
    let original = document
    var invalid = blue; invalid.effects[0].opacity = 2
    let edits = [LayerStyleEdit(layerIDs: ids, style: blue),
      LayerStyleEdit(layerIDs: [document.layers[0].id, UUID()], style: blue),
      LayerStyleEdit(layerIDs: [document.layers[0].id], style: invalid),
      LayerStyleEdit(layerIDs: [document.layers[0].id], style: blue, globalLight: GlobalLight(angle: .nan, altitude: 30))]
    for edit in edits {
      XCTAssertThrowsError(try edit.apply(to: &document)); XCTAssertEqual(document, original); try document.validate()
    }
  }
  func testMalformedTemporalSourceRejectsBeforeCapture() throws {
    var frames = try fixture(); try Command.animation(.create).apply(to: &frames)
    var empty = frames; empty.animation!.frames = []
    var missingSelection = frames; missingSelection.animation!.selectedFrameID = UUID()
    var staleFrame = frames; staleFrame.layers[0].style = blue
    var video = try fixture(); let id = video.layers[0].id
    try Command.video(.create(frameRate: 4, durationFrames: 9)).apply(to: &video)
    try Command.video(.keyframe(.enable(id, .style))).apply(to: &video)
    var staleKey = video; staleKey.layers[0].style = blue
    var duplicateKeys = video; duplicateKeys.layers[0].videoKeyframes! += video.layers[0].videoKeyframes!
    for original in [empty, missingSelection, staleFrame, staleKey, duplicateKeys] {
      var document = original
      XCTAssertThrowsError(try LayerStyleEdit(layerIDs: [original.layers[0].id], style: blue).apply(to: &document))
      XCTAssertEqual(document, original)
    }
  }
}
